// Desktop positions through documented shell interfaces; no Explorer memory access.
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <shlobj.h>
#include <exdisp.h>
#include <shlguid.h>
#include <shlwapi.h>
#include <cstdio>
#include <string>
#include <vector>
#include <stdexcept>
#include <io.h>
#include <fcntl.h>
#include <share.h>
#include <sys/stat.h>
template<class T> struct Ptr {
 T* p=nullptr; ~Ptr(){if(p)p->Release();}
 T** out(){return &p;} T* operator->(){return p;}
};
static void Check(HRESULT hr){if(FAILED(hr)){char text[96];snprintf(text,sizeof(text),"Desktop shell operation failed (HRESULT 0x%08lX)",(unsigned long)hr);throw std::runtime_error(text);}}
struct Entry {std::wstring name;POINT point;};
int wmain(int argc,wchar_t** argv) {
 if(argc!=3 || (wcscmp(argv[1],L"save") && wcscmp(argv[1],L"restore") && wcscmp(argv[1],L"hide")))return 2;
 bool save=!wcscmp(argv[1],L"save");
 HRESULT init=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);if(FAILED(init))return 3;
 int result=0;
 try {
  Ptr<IShellWindows> windows;Check(CoCreateInstance(CLSID_ShellWindows,nullptr,CLSCTX_ALL,IID_PPV_ARGS(windows.out())));
  VARIANT location{},root{};location.vt=VT_I4;location.lVal=CSIDL_DESKTOP;
  long handle=0;Ptr<IDispatch> dispatch;
  Check(windows->FindWindowSW(&location,&root,SWC_DESKTOP,&handle,SWFO_NEEDDISPATCH,dispatch.out()));
  if(!dispatch.p)throw std::runtime_error("Explorer desktop is unavailable");
  Ptr<IServiceProvider> provider;Check(dispatch->QueryInterface(IID_PPV_ARGS(provider.out())));
  Ptr<IShellBrowser> browser;Check(provider->QueryService(SID_STopLevelBrowser,IID_PPV_ARGS(browser.out())));
  Ptr<IShellView> shellView;Check(browser->QueryActiveShellView(shellView.out()));
  Ptr<IFolderView2> view;Check(shellView->QueryInterface(IID_PPV_ARGS(view.out())));
  Ptr<IShellFolder> folder;Check(view->GetFolder(IID_PPV_ARGS(folder.out())));
  std::vector<Entry> entries;DWORD flags=0;
  if(!wcscmp(argv[1],L"hide")) {
   Check(view->SetCurrentFolderFlags(FWF_NOICONS,FWF_NOICONS));
  } else if(save) {
   Check(view->GetCurrentFolderFlags(&flags));
   int count=0;Check(view->ItemCount(SVGIO_ALLVIEW,&count));
   for(int i=0;i<count;i++) {
    PITEMID_CHILD pidl=nullptr;Check(view->Item(i,&pidl));
    POINT pt{};STRRET name{};PWSTR text=nullptr;
    HRESULT hr=view->GetItemPosition(pidl,&pt);
    if(SUCCEEDED(hr))hr=folder->GetDisplayNameOf(pidl,SHGDN_FORPARSING,&name);
    if(SUCCEEDED(hr))hr=StrRetToStrW(&name,pidl,&text);
    if(SUCCEEDED(hr))entries.push_back({text,pt});
    CoTaskMemFree(text);CoTaskMemFree(pidl);Check(hr);
   }
   int fd=-1;
   if(_wsopen_s(&fd,argv[2],_O_CREAT|_O_EXCL|_O_BINARY|_O_WRONLY,_SH_DENYRW,_S_IREAD|_S_IWRITE))throw std::runtime_error("Cannot create new layout backup");
   FILE* f=_wfdopen(fd,L"wb");if(!f){_close(fd);throw std::runtime_error("Cannot open layout backup stream");}
   const DWORD header[]={0x41534C31,flags,(DWORD)entries.size()};bool ok=fwrite(header,sizeof(header),1,f)==1;
   for(auto& e:entries){DWORD length=(DWORD)e.name.size();ok=ok&&fwrite(&length,4,1,f)==1&&fwrite(e.name.data(),sizeof(wchar_t),length,f)==length&&fwrite(&e.point,sizeof(POINT),1,f)==1;}
   if(fclose(f))ok=false;if(!ok)throw std::runtime_error("Layout backup write failed");
   printf("Saved %zu desktop positions.\n",entries.size());
  } else {
   FILE* f=_wfopen(argv[2],L"rb");if(!f)throw std::runtime_error("Layout backup missing");
   DWORD header[3]{};bool ok=fread(header,sizeof(header),1,f)==1&&header[0]==0x41534C31&&header[2]<100000;
   flags=header[1];
   for(DWORD i=0;ok&&i<header[2];i++) {
    DWORD n=0;ok=fread(&n,4,1,f)==1&&n>0&&n<32768;if(!ok)break;
    Entry e;e.name.resize(n);ok=fread(&e.name[0],sizeof(wchar_t),n,f)==n&&fread(&e.point,sizeof(POINT),1,f)==1;entries.push_back(e);
   }
   fclose(f);if(!ok)throw std::runtime_error("Invalid layout backup");
   DWORD currentFlags=0;Check(view->GetCurrentFolderFlags(&currentFlags));
   Check(view->SetCurrentFolderFlags(FWF_AUTOARRANGE|FWF_SNAPTOGRID,0));
   size_t restored=0;
   HRESULT positionResult=S_OK;
   std::vector<PCUITEMID_CHILD> children;
   std::vector<POINT> points;
   // Use the desktop view's own child IDs. Parsing an absolute filesystem path
   // can produce a different shell ID (notably for redirected/OneDrive Desktop).
   int count=0;Check(view->ItemCount(SVGIO_ALLVIEW,&count));
   for(int i=0;i<count;i++) {
    PITEMID_CHILD pidl=nullptr;Check(view->Item(i,&pidl));
    STRRET name{};PWSTR text=nullptr;bool matched=false;
    if(SUCCEEDED(folder->GetDisplayNameOf(pidl,SHGDN_FORPARSING,&name)) &&
       SUCCEEDED(StrRetToStrW(&name,pidl,&text))) {
     for(auto& e:entries)if(!_wcsicmp(text,e.name.c_str())){
      children.push_back(pidl);points.push_back(e.point);matched=true;break;
     }
    }
    CoTaskMemFree(text);if(!matched)CoTaskMemFree(pidl);
   }
   if(!children.empty())positionResult=view->SelectAndPositionItems((UINT)children.size(),children.data(),points.data(),SVSI_POSITIONITEM);
   HRESULT flagsResult=view->SetCurrentFolderFlags(FWF_AUTOARRANGE|FWF_SNAPTOGRID|FWF_NOICONS,flags&(FWF_AUTOARRANGE|FWF_SNAPTOGRID|FWF_NOICONS));
   for(size_t i=0;i<children.size();i++){
    POINT actual{};
    // Explorer can apply a positioning request asynchronously.
    for(int attempt=0;attempt<10;attempt++) {
     if(SUCCEEDED(view->GetItemPosition(children[i],&actual)) &&
        ((flags&FWF_AUTOARRANGE) || (actual.x==points[i].x && actual.y==points[i].y))){restored++;break;}
     Sleep(25);
    }
    if(!(flags&FWF_AUTOARRANGE) && (actual.x!=points[i].x || actual.y!=points[i].y))
     printf("Position pending: expected (%ld,%ld), observed (%ld,%ld).\n",points[i].x,points[i].y,actual.x,actual.y);
    CoTaskMemFree((void*)children[i]);
   }
   Check(positionResult);Check(flagsResult);
   printf("Restored and verified %zu/%zu desktop positions%s.\n",restored,entries.size(),(flags&FWF_AUTOARRANGE)?" (saved auto-arrange enabled)":"");
   if(restored!=entries.size())result=2; // Caller may retry pending enumeration.
  }
 } catch(const std::exception& e){fprintf(stderr,"%s\n",e.what());result=1;}
 CoUninitialize();return result;
}
