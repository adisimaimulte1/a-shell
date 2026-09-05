// Native regression tests. Includes the actual renderer and event handlers.
#include "../src/MatrixDesktop.cpp"
#include <cassert>
#include <iostream>

static void CheckActiveList() {
 std::vector<uint32_t> sorted=activePixels;
 std::sort(sorted.begin(),sorted.end());
 assert(std::adjacent_find(sorted.begin(),sorted.end())==sorted.end());
 for(auto index:sorted)assert(index<size_t(width)*height && pixels[index]);
 size_t lit=0; for(size_t i=0;i<size_t(width)*height;i++)if(pixels[i])++lit;
 assert(lit==sorted.size());
}
int main() {
 started=GetTickCount64();
 uint32_t parsed=123;
 assert(ParseAccent(L"00AaFf",parsed) && parsed==0x00AAFF);
 assert(!ParseAccent(L"12GG34",parsed) && parsed==0x00AAFF);
 assert(!ParseAccent(L"1234567",parsed));
 assert(EnsureSurface(280,140,14));


 // Compare incremental restoration against full reference composition per pixel.
 // Exercise image/solid wallpaper, glyph clears, expiration and accent changes.
 std::vector<uint32_t> composed(size_t(width)*height);
 displayPixels=composed.data();
 for(bool solid : {false,true}) {
  wallpaperSolid=solid;wallpaperColor=0xff18345a;
  wallpaperPixels.resize(composed.size());
  for(size_t i=0;i<composed.size();++i)wallpaperPixels[i]=0xff000000|((i*7919)&0xffffff);
  ResetAnimation(L"Incremental composition test");CompositeRain(true);
  for(int frame=0;frame<250;++frame) {
   if(frame==90)accent=0x33bbff;
   if(frame==120)draining=true;
   Advance(50);CompositeRain();
   for(size_t i=0;i<composed.size();++i)
    assert(displayPixels[i]==BlendWallpaper(pixels[i],WallpaperPixel(uint32_t(i))));
  }
  draining=false;
 }
 displayPixels=nullptr;wallpaperPixels.clear();wallpaperSolid=false;
 accent=0xD65A00;ResetAnimation(L"Composition test complete");

 // Exhaust all opacity/channel inputs against the original integer formula.
 for(unsigned a=0;a<256;++a)for(unsigned c=0;c<256;++c) {
  uint32_t foreground=(a<<24)|((214*a/255)<<16)|((90*a/255)<<8)|(17*a/255);
  uint32_t background=0xff000000|(c<<16)|((255-c)<<8)|((c*73)&255);
  unsigned inv=255-a;
  uint32_t reference=0xff000000|
   (((foreground>>16&255)+(background>>16&255)*inv/255)<<16)|
   (((foreground>>8&255)+(background>>8&255)*inv/255)<<8)|
   ((foreground&255)+(background&255)*inv/255);
  assert(BlendWallpaper(foreground,background)==reference);
 }
 // Fading blends into the wallpaper, including white and saturated images.
 assert(BlendWallpaper(0,0xffabcdef)==0xffabcdef);
 assert(BlendWallpaper(0xffd65a00,0xffffffff)==0xffd65a00);
 auto fading=BlendWallpaper(0x40351600,0xffffffff);
 assert(((fading>>16)&255)>=191 && ((fading>>8)&255)>=191 && (fading&255)>=191);
  for(unsigned a=0;a<256;a++) {
  uint32_t p=(a<<24)|((214*a/255)<<16)|((90*a/255)<<8);
  uint32_t bg=BlendWallpaper(a<<24,0xff070706)&0xffffff;
  assert((0xff000000|((p&0xffffff)+bg))==BlendWallpaper(p,0xff070706));
 }
 accent=0x0000FF;Advance(50);Advance(50);
 assert(!activePixels.empty());
 for(auto index:activePixels)assert((pixels[index]&255)>0 && !(pixels[index]&0x00ffff00));
 Advance(62.5);CheckActiveList();
 accent=0xD65A00;ResetAnimation(L"Test reset after blue");
 Advance(50);Advance(50); assert(!activePixels.empty());
 for(int i=0;i<120;i++){Advance(62.5);CheckActiveList();}
 const auto savedDrops=drops;
 const auto savedBitmap=bitmap;
 const auto savedReset=resetCount;
 assert(EnsureSurface(280,140,14));


 assert(bitmap==savedBitmap && drops==savedDrops && resetCount==savedReset);

 // A stalled frame draws just the next row, as the original interval does.
 ResetAnimation(L"Test timing");
 drops.assign(drops.size(),0);
 Advance(0);
 Advance(250);
 for(auto row:drops)assert(row==1);
 for(int y=28;y<height;y++)for(int x=0;x<width;x++)assert(!pixels[size_t(y)*width+x]);
 CheckActiveList();
 Advance(3600000); CheckActiveList(); // Long sleep remains bounded and valid.
 for(auto row:drops)assert(row==2); // No rephasing or time jump after a stall.

 // Replay the supplied script.js draw/increment/random-reset ordering with
 // an identical RNG stream, including random glyph picks off-screen.
 ResetAnimation(L"Original script replay");
 auto expected=drops;uint32_t referenceRng=rng;
 auto referenceRandom=[&](){referenceRng^=referenceRng<<13;referenceRng^=referenceRng>>17;referenceRng^=referenceRng<<5;return referenceRng;};
 for(int frame=0;frame<500;frame++) {
  for(auto& row:expected) {
   referenceRandom(); // script.js picks one character for every column.
   ++row;
   if(row*cell>height && double(referenceRandom())/4294967296.0>0.975)row=0;
  }
  Advance(frame%7==0?700:50);
  assert(drops==expected && rng==referenceRng);CheckActiveList();
 }
 // Columns remain scattered rather than cycling as a band.
 ResetAnimation(L"Original generation distribution");
 for(int i=0;i<800;i++)Advance(50);
 auto scattered=drops;std::sort(scattered.begin(),scattered.end());
 assert(std::unique(scattered.begin(),scattered.end())-scattered.begin()>drops.size()/2);
 // Draining never restarts streams and eventually clears every trail pixel.
 draining=true;Advance(50);
 const auto resumeDrops=drops;const auto resumePixels=activePixels;
 const auto resumeResets=resetCount;
 std::vector<uint32_t> resumeBitmap(pixels,pixels+size_t(width)*height);
 ControlProc(nullptr,WM_APP+11,0,0);
 assert(!draining && drops==resumeDrops && activePixels==resumePixels && resetCount==resumeResets);
 assert(std::equal(resumeBitmap.begin(),resumeBitmap.end(),pixels));
 draining=true;
 for(int i=0;i<1000;i++)Advance(50);
 assert(activePixels.empty());
 for(auto row:drops)assert(row*cell>height);
 draining=false;ResetAnimation(L"Drain test completed");
 // Hidden local windows exercise session and display notifications safely.
 WNDCLASSW cls{};cls.hInstance=GetModuleHandleW(nullptr);cls.lpfnWndProc=DefWindowProcW;cls.lpszClassName=L"AShellMatrixTest";
 RegisterClassW(&cls);
 control=CreateWindowW(cls.lpszClassName,L"",WS_POPUP,0,0,1,1,nullptr,nullptr,cls.hInstance,nullptr);
 parent=control;
 wall=CreateWindowW(cls.lpszClassName,L"",WS_CHILD,0,0,1,1,parent,nullptr,cls.hInstance,nullptr);
 assert(control && wall);
 notificationsRegistered=true;desktopAvailable=true;nextDesktopCheck=GetTickCount64()+60000;
 const auto promptResets=resetCount;const auto promptDrops=drops;
 desktopAvailable=false;Tick();
 assert(drops==promptDrops && !resetPending && resetCount==promptResets);
 desktopAvailable=true;lastFrame=GetTickCount64()-50;Tick();
 assert(drops!=promptDrops && resetCount==promptResets && timerInterval==50);
 SessionChanged(WTS_CONSOLE_DISCONNECT);Tick();
 SessionChanged(WTS_CONSOLE_CONNECT);nextDesktopCheck=GetTickCount64()+60000;Tick();
 ControlProc(control,WM_POWERBROADCAST,PBT_APMSUSPEND,0);Tick();
 lastFrame=GetTickCount64()-3600000;
 ControlProc(control,WM_POWERBROADCAST,PBT_APMRESUMEAUTOMATIC,0);nextDesktopCheck=GetTickCount64()+60000;Tick();
 assert(GetTickCount64()-lastFrame<100);
 assert(!resetPending && resetCount==promptResets);
 const auto beforeLock=resetCount;
 SessionChanged(WTS_SESSION_LOCK);
 const auto preparedDrops=drops;
 Tick(); assert(locked && drops==preparedDrops && !resetPending && timerInterval==250);
 assert(resetCount==beforeLock+1 && activePixels.empty());
 for(auto row:drops)assert(row<1);
 SessionChanged(WTS_SESSION_UNLOCK);
 nextDesktopCheck=GetTickCount64()+60000;
 
 const auto beforeUnlock=resetCount;
 Tick(); assert(!locked && !resetPending && resetCount==beforeUnlock && activePixels.empty());
 for(auto row:drops)assert(row<1);
 SessionChanged(WTS_SESSION_UNLOCK);
 nextDesktopCheck=GetTickCount64()+60000;
 Tick(); assert(resetCount==beforeUnlock); // Duplicate unlock is harmless.
 
 HWND progman=FindWindowW(L"Progman",nullptr);
 assert(EnsureSurface(GetSystemMetrics(SM_CXVIRTUALSCREEN),GetSystemMetrics(SM_CYVIRTUALSCREEN),std::max(14,MulDiv(14,GetDpiForWindow(parent),96))));
 const auto displayBitmap=bitmap;const auto displayResets=resetCount;
 for(int i=0;i<5;i++) {ControlProc(control,WM_DISPLAYCHANGE,32,0);Tick();}
 assert(bitmap==displayBitmap && resetCount==displayResets);
 assert(IsWindow(wall));
 assert(EnsureSurface(width+28,height+28,cell));
 assert(resetCount==displayResets);CheckActiveList();
 // Host recreation must be able to reuse the same backing frame.
 DestroyWindow(wall);wall=nullptr;
 assert(EnsureSurface(width,height,cell));
 assert(resetCount==displayResets);
 KillTimer(control,1);DestroyWindow(control);control=parent=wall=nullptr;
 FreeSurface();
 std::cout << "PASS: colors, sparse pixels, stalls, display/resize preservation, secure-desktop pause, sleep/reconnect preservation, lock/unlock reset.\n";
}
