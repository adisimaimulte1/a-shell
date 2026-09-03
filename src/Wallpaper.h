// Cached wallpaper composition uses the proven GDI desktop child. Only the
// current/previously lit pixels are recomposited; images decode on changes only.
#include <shobjidl.h>
#include <gdiplus.h>
static HDC displayDC;
static HBITMAP displayBitmap, displayPrevious;
static uint32_t* displayPixels;
static std::vector<uint32_t> wallpaperPixels;
static bool wallpaperSolid=false;
static uint32_t wallpaperColor=0xff000000;
static bool wallpaperPending=true;
static ULONG_PTR gdiplusToken;
static ULONGLONG nextWallpaperPoll=0;
static std::wstring observedWallpaper;
static FILETIME observedWriteTime{};
static bool wallpaperObserved=false;
static void PollWallpaper(ULONGLONG now) {
 if(now<nextWallpaperPoll)return;
 nextWallpaperPoll=now+2000;
 wchar_t path[32768]{};
 if(!SystemParametersInfoW(SPI_GETDESKWALLPAPER,32768,path,0))return;
 WIN32_FILE_ATTRIBUTE_DATA data{};GetFileAttributesExW(path,GetFileExInfoStandard,&data);
 if(wallpaperObserved && (observedWallpaper!=path || CompareFileTime(&observedWriteTime,&data.ftLastWriteTime)!=0))wallpaperPending=true;
 observedWallpaper=path;observedWriteTime=data.ftLastWriteTime;wallpaperObserved=true;
}
static uint32_t BlendWallpaper(uint32_t foreground,uint32_t background) {
 unsigned inv=255-(foreground>>24);
 unsigned r=((foreground>>16)&255)+((background>>16)&255)*inv/255;
 unsigned g=((foreground>>8)&255)+((background>>8)&255)*inv/255;
 unsigned b=(foreground&255)+(background&255)*inv/255;
 return 0xff000000|(r<<16)|(g<<8)|b;
}
static uint32_t WallpaperPixel(uint32_t index){return wallpaperSolid?wallpaperColor:wallpaperPixels[index];}
static void CompositeRain(bool clear=false) {
 if(!displayPixels || (!wallpaperSolid && wallpaperPixels.size()!=size_t(width)*height))return;
 if(clear){if(wallpaperSolid)std::fill(displayPixels,displayPixels+size_t(width)*height,wallpaperColor);else memcpy(displayPixels,wallpaperPixels.data(),wallpaperPixels.size()*4);}
 if(wallpaperSolid) {
  // One background contribution per opacity, not three divisions per pixel.
  uint32_t background[256];
  for(unsigned a=0;a<256;a++)background[a]=BlendWallpaper(a<<24,wallpaperColor)&0xffffff;
  for(auto index:activePixels){uint32_t p=pixels[index];displayPixels[index]=0xff000000|((p&0xffffff)+background[p>>24]);}
 } else for(auto index:activePixels)displayPixels[index]=BlendWallpaper(pixels[index],wallpaperPixels[index]);
}
static void FreeWallpaper() {
 if(displayDC){SelectObject(displayDC,displayPrevious);DeleteObject(displayBitmap);DeleteDC(displayDC);}
 displayDC=nullptr;displayBitmap=nullptr;displayPixels=nullptr;wallpaperPixels.clear();wallpaperSolid=false;
}
static void PaintWallpaperImage(Gdiplus::Graphics& g,const wchar_t* path,RECT r,DESKTOP_WALLPAPER_POSITION mode) {
 if(!path || !*path)return;
 Gdiplus::Bitmap image(path);
 if(image.GetLastStatus()!=Gdiplus::Ok || !image.GetWidth() || !image.GetHeight()){Log(L"Wallpaper image unavailable; using desktop color");return;}
 const float iw=float(image.GetWidth()),ih=float(image.GetHeight());
 float rw=float(r.right-r.left),rh=float(r.bottom-r.top),dw=iw,dh=ih;
 auto state=g.Save();g.SetClip(Gdiplus::Rect(r.left,r.top,int(rw),int(rh)));
 if(mode==DWPOS_TILE){
  for(int y=r.top;y<r.bottom;y+=int(ih))for(int x=r.left;x<r.right;x+=int(iw))g.DrawImage(&image,x,y,int(iw),int(ih));
 } else {
  if(mode==DWPOS_STRETCH){dw=rw;dh=rh;}
  else if(mode==DWPOS_FIT || mode==DWPOS_FILL || mode==DWPOS_SPAN){float scale=mode==DWPOS_FIT?std::min(rw/iw,rh/ih):std::max(rw/iw,rh/ih);dw=iw*scale;dh=ih*scale;}
  Gdiplus::ImageAttributes attributes;attributes.SetWrapMode(Gdiplus::WrapModeTileFlipXY);
  g.DrawImage(&image,Gdiplus::RectF(r.left+(rw-dw)/2,r.top+(rh-dh)/2,dw,dh),0,0,iw,ih,Gdiplus::UnitPixel,&attributes);
 }
 g.Restore(state);
}
static bool ReloadWallpaper() {
 if(!width || !height)return false;
 if(!gdiplusToken){Gdiplus::GdiplusStartupInput input;if(Gdiplus::GdiplusStartup(&gdiplusToken,&input,nullptr)!=Gdiplus::Ok)return false;}
 if(!displayDC){
  BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=width;info.bmiHeader.biHeight=-height;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
  displayDC=CreateCompatibleDC(nullptr);displayBitmap=CreateDIBSection(displayDC,&info,DIB_RGB_COLORS,(void**)&displayPixels,nullptr,0);
  if(!displayDC || !displayBitmap){FreeWallpaper();return false;}
  displayPrevious=(HBITMAP)SelectObject(displayDC,displayBitmap);
 }
 IDesktopWallpaper* manager=nullptr;
 HRESULT hr=CoCreateInstance(CLSID_DesktopWallpaper,nullptr,CLSCTX_ALL,IID_PPV_ARGS(&manager));
 COLORREF color=GetSysColor(COLOR_DESKTOP);DESKTOP_WALLPAPER_POSITION mode=DWPOS_FILL;
 if(SUCCEEDED(hr)){manager->GetBackgroundColor(&color);manager->GetPosition(&mode);}
 {
  Gdiplus::Graphics g(displayDC);g.Clear(Gdiplus::Color(255,GetRValue(color),GetGValue(color),GetBValue(color)));
  g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
  UINT count=0;if(manager)manager->GetMonitorDevicePathCount(&count);
  if(count){
   for(UINT i=0;i<count;i++){
    LPWSTR id=nullptr,path=nullptr;RECT r{};
    if(SUCCEEDED(manager->GetMonitorDevicePathAt(i,&id)) && manager->GetMonitorRECT(id,&r)==S_OK && SUCCEEDED(manager->GetWallpaper(id,&path))){
     OffsetRect(&r,-GetSystemMetrics(SM_XVIRTUALSCREEN),-GetSystemMetrics(SM_YVIRTUALSCREEN));
     if(mode==DWPOS_SPAN)r={0,0,width,height};
     PaintWallpaperImage(g,path,r,mode);
    }
    CoTaskMemFree(id);CoTaskMemFree(path);if(mode==DWPOS_SPAN)break;
   }
  } else {
   wchar_t path[32768]{};SystemParametersInfoW(SPI_GETDESKWALLPAPER,32768,path,0);
   PaintWallpaperImage(g,path,RECT{0,0,width,height},mode);
  }
 }
 if(manager)manager->Release();GdiFlush();
 wallpaperColor=displayPixels[0]|0xff000000;
 wallpaperSolid=std::all_of(displayPixels,displayPixels+size_t(width)*height,[](uint32_t p){return (p|0xff000000)==wallpaperColor;});
 if(wallpaperSolid){wallpaperPixels.clear();wallpaperPixels.shrink_to_fit();}
 else {wallpaperPixels.assign(displayPixels,displayPixels+size_t(width)*height);for(auto& p:wallpaperPixels)p|=0xff000000;}
 CompositeRain(true);wallpaperPending=false;Log(L"Wallpaper cache refreshed; rain preserved");return true;
}
