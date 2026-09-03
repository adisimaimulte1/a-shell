# A cloud placeholder is not a junction. Query metadata without opening its data
# or following a name-surrogate reparse point.
if(!('AShellFileTags' -as [type])){Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class AShellFileTags {
 [StructLayout(LayoutKind.Sequential)] struct TagInfo { public uint Attributes, Tag; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandleEx(SafeFileHandle file,int kind,out TagInfo info,uint size);
 public static uint Read(string path) {
  using(var file=CreateFile(path,0,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero)) {
   if(file.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error(),"Cannot inspect desktop path: "+path);
   TagInfo info;if(!GetFileInformationByHandleEx(file,9,out info,8))throw new Win32Exception(Marshal.GetLastWin32Error(),"Cannot inspect reparse tag: "+path);
   return (info.Attributes&0x400)!=0?info.Tag:0;
  }
 }
 public static bool IsCloud(uint tag) {return (tag&0xffff0fffU)==0x9000001aU;}
}
'@}
function Get-AShellReparseTag([string]$Path) {[AShellFileTags]::Read($Path)}
function Assert-AShellMovablePath([string]$Path) {
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
 if(!$item){return}
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
  $tag=Get-AShellReparseTag $item.FullName
  if(![AShellFileTags]::IsCloud($tag)){
   throw ('Cannot archive a junction, symbolic link or unsupported reparse point: {0} (tag 0x{1:X8}). No link target will be moved.' -f $item.FullName,$tag)
  }
 }
}
