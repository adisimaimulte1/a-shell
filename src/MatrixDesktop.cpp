#define _WIN32_WINNT 0x0A00
#define WINVER 0x0A00
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wtsapi32.h>
#include <vector>
#include <string>
#include <cstdio>
#include <cstdint>
#include <algorithm>
#include <cmath>
#include <limits>

static std::wstring AShellRootPath() {
 wchar_t path[32768]{};
 DWORD count=GetModuleFileNameW(nullptr,path,static_cast<DWORD>(_countof(path)));
 if(!count || count>=_countof(path))return L"";
 std::wstring value(path,count);
 auto binSlash=value.find_last_of(L"\\/");
 if(binSlash==std::wstring::npos)return L"";
 value.resize(binSlash); // ...\\A-Shell\\bin
 auto rootSlash=value.find_last_of(L"\\/");
 if(rootSlash==std::wstring::npos)return L"";
 value.resize(rootSlash); // ...\\A-Shell
 return value;
}
static bool AShellFileExists(const std::wstring& path) {
 DWORD attrs=GetFileAttributesW(path.c_str());
 return attrs!=INVALID_FILE_ATTRIBUTES && !(attrs&FILE_ATTRIBUTE_DIRECTORY);
}
static std::string AShellReadSmallFile(const std::wstring& path) {
 HANDLE file=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
                         nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(file==INVALID_HANDLE_VALUE)return {};
 LARGE_INTEGER size{};
 if(!GetFileSizeEx(file,&size) || size.QuadPart<0 || size.QuadPart>1024*1024){CloseHandle(file);return {};}
 std::string bytes(static_cast<size_t>(size.QuadPart),'\0');
 DWORD read=0;
 if(!bytes.empty() && !ReadFile(file,bytes.data(),static_cast<DWORD>(bytes.size()),&read,nullptr)){CloseHandle(file);return {};}
 CloseHandle(file);bytes.resize(read);return bytes;
}
static bool AShellReadJsonBool(const std::string& json,const char* key,bool fallback) {
 std::string token="\""+std::string(key)+"\"";
 auto pos=json.find(token);if(pos==std::string::npos)return fallback;
 pos=json.find(':',pos+token.size());if(pos==std::string::npos)return fallback;
 ++pos;while(pos<json.size() && (json[pos]==' '||json[pos]=='\t'||json[pos]=='\r'||json[pos]=='\n'))++pos;
 if(json.compare(pos,4,"true")==0)return true;
 if(json.compare(pos,5,"false")==0)return false;
 return fallback;
}
static bool AShellShouldAutoStartRain() {
 const auto root=AShellRootPath();if(root.empty())return false;
 const auto runtime=root+L"\\state\\runtime-state.json";
 bool active=false;
 if(AShellFileExists(runtime))active=AShellReadJsonBool(AShellReadSmallFile(runtime),"active",false);
 else active=AShellFileExists(root+L"\\state\\applied.txt"); // legacy installs
 if(!active)return false;
 const auto features=root+L"\\state\\features.json";
 if(!AShellFileExists(features))return true; // v1/v2 default
 return AShellReadJsonBool(AShellReadSmallFile(features),"rain",true);
}

static HWND control, wall, parent, icons;
static HDC dc;
static HBITMAP bitmap, previous;
static uint32_t* pixels;
static int width, height, cell;
static bool locked=false, resetPending=false, desktopAvailable=true;
static bool disconnected=false, suspended=false;
static bool layoutPending=false, notificationsRegistered=false;
static UINT timerInterval=0;
static ULONGLONG lastFrame=0, nextDesktopCheck=0, nextAttach=0, nextRegistration=0;
static unsigned resetCount=0, attachCount=0;
static bool draining=false;
static ULONGLONG started;
static std::vector<double> drops;


static std::vector<uint32_t> activePixels;
static std::vector<std::vector<unsigned char>> masks;
static uint32_t rng=1;
static uint32_t accent=0xD65A00;
static UINT accentMessage=0;
static bool ParseAccent(const wchar_t* text,uint32_t& result) {
 if(!text || wcslen(text)!=6)return false;
 uint32_t value=0;
 for(int i=0;i<6;i++) {
  wchar_t c=text[i]; unsigned digit;
  if(c>=L'0' && c<=L'9')digit=c-L'0';
  else if(c>=L'a' && c<=L'f')digit=c-L'a'+10;
  else if(c>=L'A' && c<=L'F')digit=c-L'A'+10;
  else return false;
  value=(value<<4)|digit;
 }
 result=value; return true;
}
static void Log(const wchar_t* message);
#include "Wallpaper.h"
static void ReadAccent() {
 wchar_t path[MAX_PATH]{};GetModuleFileNameW(nullptr,path,MAX_PATH);
 auto slash=wcsrchr(path,L'\\');if(slash)wcscpy(slash+1,L"..\\state\\accent-color.txt");
 uint32_t next=0xD65A00;
 FILE* file=_wfopen(path,L"rb");
 if(file) {
  char bytes[8]{};size_t count=fread(bytes,1,sizeof(bytes),file);fclose(file);
  if(count==6){wchar_t value[7]{};for(int i=0;i<6;i++)value[i]=static_cast<unsigned char>(bytes[i]);ParseAccent(value,next);}
 }
 if(next==accent)return;
 accent=next;GdiFlush();
 wchar_t report[64];swprintf(report,64,L"Live accent: #%06X",accent);Log(report);
 // Recolor existing trails without changing stream positions or their opacity.
 for(auto index:activePixels) {
  unsigned a=pixels[index]>>24;
  pixels[index]=(a<<24)|((((accent>>16)&255)*a/255)<<16)|((((accent>>8)&255)*a/255)<<8)|((accent&255)*a/255);
 }
 CompositeRain(true); if(IsWindow(wall)){InvalidateRect(wall,nullptr,FALSE);UpdateWindow(wall);}
}
static unsigned Random() { rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; return rng; }
static void Log(const wchar_t* message) {
 wchar_t path[MAX_PATH]; GetModuleFileNameW(nullptr,path,MAX_PATH);
 auto slash=wcsrchr(path,L'\\'); if(slash) wcscpy(slash+1,L"MatrixDesktop.log");
 WIN32_FILE_ATTRIBUTE_DATA info{};
 if(GetFileAttributesExW(path,GetFileExInfoStandard,&info) && (info.nFileSizeHigh || info.nFileSizeLow>262144)) DeleteFileW(path);
 FILE* f=_wfopen(path,L"a"); if(!f)return;
 SYSTEMTIME t; GetLocalTime(&t);
 fwprintf(f,L"%04d-%02d-%02d %02d:%02d:%02d.%03d pid=%lu +%llu ms %ls\n",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond,t.wMilliseconds,GetCurrentProcessId(),GetTickCount64()-started,message); fclose(f);
}
static bool DesktopReady() {
 HDESK desk=OpenInputDesktop(0,FALSE,DESKTOP_READOBJECTS);
 if(!desk)return false;
 wchar_t name[128]{}; DWORD needed;
 bool ready=GetUserObjectInformationW(desk,UOI_NAME,name,sizeof(name),&needed)&&!wcscmp(name,L"Default");
 CloseDesktop(desk); return ready;
}
static BOOL CALLBACK FindLegacy(HWND hwnd,LPARAM result) {
 if(FindWindowExW(hwnd,nullptr,L"SHELLDLL_DefView",nullptr)) {
  *(HWND*)result=FindWindowExW(nullptr,hwnd,L"WorkerW",nullptr);
  return FALSE;
 } return TRUE;
}
static void FreeSurface() {
 GdiFlush();
 FreeWallpaper();
 if(dc) { SelectObject(dc,previous); DeleteObject(bitmap); DeleteDC(dc); }
 dc=nullptr; bitmap=nullptr; pixels=nullptr;
 activePixels.clear();
}
static void ResetAnimation(const wchar_t* reason) {
 GdiFlush();
 if(pixels)memset(pixels,0,size_t(width)*height*4);
 activePixels.clear();
 drops.resize((width+cell-1)/cell);
 // Preserve the explicitly requested random opening.
 // The per-frame generation below follows the supplied script.js.
 for(auto& row:drops)row=-int(Random()%std::max(1,height/cell));
 for(size_t i=0;i<std::min(size_t(8),drops.size());i++)
  drops[Random()%drops.size()]=0;
 CompositeRain(true);
 // Publish the clean wallpaper now: clearing the DIB alone leaves DWM's last
 // presented rain frame visible when Windows uncovers the desktop at unlock.
 if(IsWindow(wall)){InvalidateRect(wall,nullptr,FALSE);UpdateWindow(wall);GdiFlush();}
 lastFrame=GetTickCount64(); ++resetCount; Log(reason);
}
static bool EnsureSurface(int newWidth,int newHeight,int newCell) {
 if(pixels && width==newWidth && height==newHeight && cell==newCell)return true;
 if(newWidth<=0 || newHeight<=0 || uint64_t(newWidth)*newHeight>64000000)return false;
 const bool preserve=pixels!=nullptr;
 const int oldWidth=width,oldHeight=height,oldCell=cell;
 const auto oldDrops=drops;
 std::vector<uint32_t> oldPixels;
 if(preserve){GdiFlush();oldPixels.assign(pixels,pixels+size_t(width)*height);}
 FreeSurface();
 width=newWidth; height=newHeight; cell=newCell;
 BITMAPINFO bi{}; bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
 bi.bmiHeader.biWidth=width; bi.bmiHeader.biHeight=-height;
 bi.bmiHeader.biPlanes=1; bi.bmiHeader.biBitCount=32; bi.bmiHeader.biCompression=BI_RGB;
 dc=CreateCompatibleDC(nullptr);
 bitmap=CreateDIBSection(dc,&bi,DIB_RGB_COLORS,(void**)&pixels,nullptr,0);
 if(!dc || !bitmap) { Log(L"DIB allocation failed"); FreeSurface(); return false; }
 previous=(HBITMAP)SelectObject(dc,bitmap);
 memset(pixels,0,size_t(width)*height*4);
 // Rasterize the glyphs once; animation only blends cached masks.
 HDC fontDC=CreateCompatibleDC(nullptr); uint32_t* glyphPixels;
 bi.bmiHeader.biWidth=cell; bi.bmiHeader.biHeight=-cell;
 HBITMAP glyphBitmap=CreateDIBSection(fontDC,&bi,DIB_RGB_COLORS,(void**)&glyphPixels,nullptr,0);
 if(!fontDC || !glyphBitmap) { if(glyphBitmap)DeleteObject(glyphBitmap); if(fontDC)DeleteDC(fontDC); FreeSurface(); return false; }
 auto oldBitmap=SelectObject(fontDC,glyphBitmap);
 HFONT font=CreateFontW(-cell,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Arial");
 auto oldFont=SelectObject(fontDC,font); SetTextColor(fontDC,RGB(255,255,255)); SetBkColor(fontDC,0);
 const wchar_t* chars=L"゠アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレワヰヱヲンヺ・ーヽヿ0123456789";
 masks.clear();
 for(const wchar_t* c=chars;*c;c++) {
  memset(glyphPixels,0,cell*cell*4); SetTextAlign(fontDC,TA_LEFT|TA_BASELINE); TextOutW(fontDC,0,cell,c,1); GdiFlush();
  std::vector<unsigned char> mask(cell*cell);
  for(int i=0;i<cell*cell;i++) mask[i]=(unsigned char)(glyphPixels[i]&255);
  masks.push_back(std::move(mask));
 }
 SelectObject(fontDC,oldFont); DeleteObject(font); SelectObject(fontDC,oldBitmap); DeleteObject(glyphBitmap); DeleteDC(fontDC);
 activePixels.reserve(size_t(width)*height/8);
 if(!preserve)ResetAnimation(L"Animation initialized for new surface");
 else {
  drops.resize((width+cell-1)/cell);
  for(size_t col=0;col<drops.size();col++) {
   size_t oldCol=col*cell/oldCell;
   drops[col]=oldCol<oldDrops.size()?oldDrops[oldCol]*oldCell/cell:-(int)(Random()%std::max(1,height/cell));
  }
  for(int y=0;y<std::min(height,oldHeight);y++)for(int x=0;x<std::min(width,oldWidth);x++) {
   uint32_t p=oldPixels[size_t(y)*oldWidth+x];
   if(p){uint32_t index=uint32_t(size_t(y)*width+x);pixels[index]=p;activePixels.push_back(index);}
  }
  lastFrame=GetTickCount64();Log(L"Surface resized; existing rain preserved");
 }
 return true;
}
static void Advance(double elapsedMs) {
 if(!pixels || elapsedMs<=0)return;
 // Original frame loop: fade once, draw, increment, then random reset.
 // Rebuild color tables only when the accent changes, not every frame.
 static uint32_t cachedAccent=~uint32_t(0), fade[256], ink[256];
 if(cachedAccent!=accent) {
  for(unsigned i=0;i<256;++i) {
   ink[i]=(i<<24)|((((accent>>16)&255)*i/255)<<16)|
          ((((accent>>8)&255)*i/255)<<8)|((accent&255)*i/255);
   unsigned a=static_cast<unsigned>(i*0.95);
   fade[i]=a<3?0:((a<<24)|((((accent>>16)&255)*a/255)<<16)|
             ((((accent>>8)&255)*a/255)<<8)|((accent&255)*a/255));
  }
  cachedAccent=accent;
 }
 size_t kept=0;
 for(uint32_t index:activePixels) {
  uint32_t p=pixels[index];
  pixels[index]=fade[p>>24];
  if(pixels[index])activePixels[kept++]=index;
  else if(displayPixels)displayPixels[index]=WallpaperPixel(index);
 }
 activePixels.resize(kept);
 for(size_t col=0;col<drops.size();col++) {
  int row=static_cast<int>(drops[col]);
  int x=int(col)*cell;
  // Original clears the cell below the alphabetic glyph baseline.
  // Clear to transparent rather than painting its opaque dark rectangle.
  for(int yy=std::max(0,row*cell);yy<std::min(height,(row+1)*cell);yy++)
   for(int xx=x;xx<std::min(width,x+cell);xx++) {
    const auto index=size_t(yy)*width+xx;
    if(pixels[index] && displayPixels)displayPixels[index]=WallpaperPixel(uint32_t(index));
    pixels[index]=0;
   }
  auto& mask=masks[Random()%masks.size()];
  int y=(row-1)*cell;
  if(y>=0 && y<height) {

   for(int yy=0;yy<cell && y+yy<height;yy++) for(int xx=0;xx<cell && x+xx<width;xx++) {
    unsigned a=mask[yy*cell+xx]; if(!a)continue;
    const uint32_t index=uint32_t(size_t(y+yy)*width+x+xx);
    auto& p=pixels[index]; unsigned inv=255-a;
    if(!p){activePixels.push_back(index);p=ink[a];continue;}
    unsigned oa=a+((p>>24)*inv)/255;
    unsigned r=(((accent>>16)&255)*a+((p>>16)&255)*inv)/255;
    unsigned g=(((accent>>8)&255)*a+((p>>8)&255)*inv)/255;
    unsigned b=((accent&255)*a+(p&255)*inv)/255;
    p=(oa<<24)|(r<<16)|(g<<8)|b;
   }
  }
  ++drops[col];
  if(!draining && drops[col]*cell>height && double(Random())/4294967296.0>0.975)drops[col]=0;
 }
 activePixels.erase(std::remove_if(activePixels.begin(),activePixels.end(),[](uint32_t i){return !pixels[i];}),activePixels.end());
 if(draining && activePixels.empty())PostMessageW(control,WM_CLOSE,0,0);
}
static void Draw() {
 if(!pixels || !wall)return;
 const ULONGLONG now=GetTickCount64();
 const ULONGLONG elapsed=lastFrame?now-lastFrame:0;
 lastFrame=now;
 // Complete any batched GDI reads before modifying the DIB on this thread.
 GdiFlush();
 if(wallpaperPending || !displayDC)ReloadWallpaper();
 Advance(static_cast<double>(elapsed)); CompositeRain();
 InvalidateRect(wall,nullptr,FALSE); UpdateWindow(wall);
 static ULONGLONG nextReport=0, maximumGap=0, frameCount=0;
 maximumGap=std::max(maximumGap,elapsed); ++frameCount;
 if(now>=nextReport) {
  wchar_t status[200]; swprintf(status,200,L"Rendering: frames=%llu activePixels=%llu maxGap=%llu ms attaches=%u resets=%u",frameCount,(unsigned long long)activePixels.size(),maximumGap,attachCount,resetCount); Log(status);
  nextReport=now+60000; maximumGap=0; frameCount=0;
 }
}
static LRESULT CALLBACK WallProc(HWND hwnd,UINT msg,WPARAM w,LPARAM l) {
 if(msg==WM_PAINT) { PAINTSTRUCT ps; HDC target=BeginPaint(hwnd,&ps); if(displayDC)BitBlt(target,ps.rcPaint.left,ps.rcPaint.top,ps.rcPaint.right-ps.rcPaint.left,ps.rcPaint.bottom-ps.rcPaint.top,displayDC,ps.rcPaint.left,ps.rcPaint.top,SRCCOPY); EndPaint(hwnd,&ps); return 0; }
 if(msg==WM_DESTROY && hwnd==wall)wall=nullptr;
 if(msg==WM_NCHITTEST)return HTTRANSPARENT;
 if(msg==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
 if(msg==WM_ERASEBKGND)return 1;
 return DefWindowProcW(hwnd,msg,w,l);
}
static bool Attach() {
 if(!DesktopReady())return false;
 HWND progman=FindWindowW(L"Progman",nullptr); if(!progman)return false;
 DWORD_PTR ignored;
 SendMessageTimeoutW(progman,0x052C,0xD,1,SMTO_ABORTIFHUNG,200,&ignored);
 icons=FindWindowExW(progman,nullptr,L"SHELLDLL_DefView",nullptr);
 bool raised=(GetWindowLongPtrW(progman,GWL_EXSTYLE)&WS_EX_NOREDIRECTIONBITMAP)!=0;
 if(raised) { if(!icons)return false; parent=progman; }
 else { parent=nullptr; EnumWindows(FindLegacy,(LPARAM)&parent); if(!parent)return false; }
 if(!EnsureSurface(GetSystemMetrics(SM_CXVIRTUALSCREEN),GetSystemMetrics(SM_CYVIRTUALSCREEN),std::max(14,MulDiv(14,GetDpiForWindow(progman),96))))return false;
 POINT origin{GetSystemMetrics(SM_XVIRTUALSCREEN),GetSystemMetrics(SM_YVIRTUALSCREEN)};
 ScreenToClient(parent,&origin);
 // Never create a visible or decorated top-level wallpaper window.
 wall=CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,L"MatrixDesktopLayer",L"Matrix Desktop",WS_CHILD,origin.x,origin.y,width,height,parent,nullptr,GetModuleHandleW(nullptr),nullptr);
 if(!wall) { Log(L"Desktop child creation failed"); return false; }
 // The cached wallpaper makes this surface fully composed and opaque.
 // A color key would force an unnecessary full-screen transparency scan.
 SetLayeredWindowAttributes(wall,0,255,LWA_ALPHA);
 ++attachCount;
 lastFrame=GetTickCount64(); Draw();
 SetWindowPos(wall,raised?icons:HWND_TOP,origin.x,origin.y,width,height,SWP_NOACTIVATE|SWP_SHOWWINDOW);
 wchar_t message[180]; swprintf(message,180,L"Desktop attached; child=%p parent=%p cell=%d size=%dx%d attaches=%u resets=%u",wall,parent,cell,width,height,attachCount,resetCount); Log(message);
 return true;
}
static void SetInterval(UINT interval) {
 if(timerInterval!=interval) {SetTimer(control,1,interval,nullptr); timerInterval=interval;}
}
static void SessionChanged(WPARAM event) {
 if(event==WTS_SESSION_LOCK) {
  locked=true;
  // Prepare the new sequence while the secure desktop is covering us. Resetting
  // after UNLOCK lets one or two frames of the old rain escape before the reset.
  if(pixels) {
   ResetAnimation(L"Fresh animation prepared while session locked");
   resetPending=false;
  } else resetPending=true;
  SetInterval(250); Log(L"Session paused; fresh rain prepared for unlock");
 } else if(event==WTS_SESSION_UNLOCK) {
  // A missing surface is the only case that still needs the timer fallback.
  if(resetPending && pixels) {
   ResetAnimation(L"Fresh animation prepared before session unlock");
   resetPending=false;
  }
  locked=false; nextDesktopCheck=0; SetInterval(50);
 } else if(event==WTS_CONSOLE_DISCONNECT || event==WTS_REMOTE_DISCONNECT) {
  disconnected=true;SetInterval(250);
 } else if(event==WTS_CONSOLE_CONNECT || event==WTS_REMOTE_CONNECT) {
  disconnected=false;lastFrame=GetTickCount64();nextDesktopCheck=0;SetInterval(50);
 }
}
static void Tick() {
 const ULONGLONG now=GetTickCount64();
 PollWallpaper(now);
 if(!notificationsRegistered && now>=nextRegistration) {
  notificationsRegistered=WTSRegisterSessionNotification(control,NOTIFY_FOR_THIS_SESSION)!=FALSE;
  nextRegistration=now+1000;
 }
 if(now>=nextDesktopCheck) {
  bool ready=DesktopReady();
  if(!desktopAvailable && ready)lastFrame=now;
  desktopAvailable=ready;
  nextDesktopCheck=now+250;
 }
 if(locked || disconnected || suspended || !desktopAvailable) {if(draining)PostMessageW(control,WM_CLOSE,0,0);lastFrame=now; SetInterval(250); return;}
 if(resetPending && pixels) {
  ResetAnimation(L"Fresh animation after surface recovery"); resetPending=false;
  // Clear the previous frame even if a full-screen window currently covers it.
  if(IsWindow(wall)){InvalidateRect(wall,nullptr,FALSE); UpdateWindow(wall);}
 }
 if(!IsWindow(wall) || !IsWindow(parent)) {
  wall=nullptr;
  if(now>=nextAttach){Attach(); nextAttach=now+100;}
  SetInterval(100); return;
 }
 if(layoutPending) {
  const int newCell=std::max(14,MulDiv(14,GetDpiForWindow(parent),96));
  if(!EnsureSurface(GetSystemMetrics(SM_CXVIRTUALSCREEN),GetSystemMetrics(SM_CYVIRTUALSCREEN),newCell))return;
  POINT origin{GetSystemMetrics(SM_XVIRTUALSCREEN),GetSystemMetrics(SM_YVIRTUALSCREEN)}; ScreenToClient(parent,&origin);
  SetWindowPos(wall,nullptr,origin.x,origin.y,width,height,SWP_NOACTIVATE|SWP_NOZORDER);
  layoutPending=false;
 }
 SetInterval(50); Draw();
}
static LRESULT CALLBACK ControlProc(HWND hwnd,UINT msg,WPARAM w,LPARAM l) {
 if(accentMessage && msg==accentMessage) {ReadAccent();return static_cast<LRESULT>(accent+1);}
 switch(msg) {
 case WM_SETTINGCHANGE: ReadAccent(); if(w==SPI_SETDESKWALLPAPER || !l || !wcscmp((const wchar_t*)l,L"Control Panel\\Desktop"))wallpaperPending=true;return 0;
 case WM_THEMECHANGED: nextWallpaperPoll=0;return 0;
 case WM_APP+10:
  draining=true;
  for(auto& row:drops)if(row<=0)row=height/cell+2;
  if(locked || disconnected || suspended || !desktopAvailable || !pixels)PostMessageW(hwnd,WM_CLOSE,0,0);
  Log(L"Finishing existing rain; new streams disabled");return 0;
  case WM_APP+11:
   // Keep the bitmap and every in-flight column. Off-screen columns restart
   // through the original random reset rule on subsequent frames.
   if(draining){draining=false;Log(L"Rain resumed; existing streams and trails preserved");}return 0;
 case WM_TIMER:
  if(w==1)Tick();
  return 0;
 case WM_WTSSESSION_CHANGE: SessionChanged(w); return 0;
 case WM_DISPLAYCHANGE:
 case WM_DPICHANGED:
  layoutPending=true; wallpaperPending=true;return 0;
 case WM_POWERBROADCAST:
  if(w==PBT_APMSUSPEND) {suspended=true;SetInterval(250);}
  if(w==PBT_APMRESUMEAUTOMATIC || w==PBT_APMRESUMESUSPEND) {suspended=false;lastFrame=GetTickCount64();nextDesktopCheck=0;}
  return TRUE;
 case WM_CLOSE: DestroyWindow(hwnd); return 0;
 case WM_DESTROY:
  KillTimer(hwnd,1);
  if(IsWindow(wall))DestroyWindow(wall); FreeSurface(); PostQuitMessage(0); return 0;
 }
 return DefWindowProcW(hwnd,msg,w,l);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR args,int) {
 started=GetTickCount64(); CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 // Scheduled sign-in startup is state-aware. The task may remain installed while
 // A-Shell or rain is off; in that case exit before creating any desktop/window.
 if(wcsstr(args,L"--autostart") && !AShellShouldAutoStartRain())return 0;
 if(wcsstr(args,L"--drain")) { HWND other=FindWindowW(L"MatrixDesktopController",nullptr); if(other)PostMessageW(other,WM_APP+10,0,0); return 0; }
 if(wcsstr(args,L"--resume")) { HWND other=FindWindowW(L"MatrixDesktopController",nullptr); if(other)PostMessageW(other,WM_APP+11,0,0); return 0; }
 if(wcsstr(args,L"--stop")) { HWND other=FindWindowW(L"MatrixDesktopController",nullptr); if(other)PostMessageW(other,WM_CLOSE,0,0); return 0; }
 HANDLE mutex=CreateMutexW(nullptr,TRUE,L"Local\\MatrixDesktopStandalone");
 if(!mutex)return 1;
 if(GetLastError()==ERROR_ALREADY_EXISTS){CloseHandle(mutex);return 0;}
 // A wallpaper must not compete with foreground applications at startup.
 SetPriorityClass(GetCurrentProcess(),NORMAL_PRIORITY_CLASS);
 SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
 rng=GetTickCount()|1; Log(L"Process entered");
 accentMessage=RegisterWindowMessageW(L"A-Shell.AccentChanged.v1"); ReadAccent();
 WNDCLASSW cls{}; cls.hInstance=instance; cls.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));cls.lpfnWndProc=WallProc; cls.lpszClassName=L"MatrixDesktopLayer"; RegisterClassW(&cls);
 cls.lpfnWndProc=ControlProc; cls.lpszClassName=L"MatrixDesktopController"; RegisterClassW(&cls);
 control=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,cls.lpszClassName,L"",WS_POPUP,0,0,0,0,nullptr,nullptr,instance,nullptr);
 if(!control){CloseHandle(mutex);return 1;}
 notificationsRegistered=WTSRegisterSessionNotification(control,NOTIFY_FOR_THIS_SESSION)!=FALSE;
 desktopAvailable=DesktopReady();
 if(desktopAvailable)Attach(); SetInterval(50);
 MSG msg; while(GetMessageW(&msg,nullptr,0,0)>0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
 if(notificationsRegistered)WTSUnRegisterSessionNotification(control); CloseHandle(mutex); return 0;
}
