$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MatrixProbe {
 public delegate bool EnumProc(IntPtr hwnd,IntPtr param);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc fn,IntPtr param);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent,EnumProc fn,IntPtr param);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd,StringBuilder cls,int count);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
 [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr process,uint flags);
 public static IntPtr FindLayer(uint processId) {
  IntPtr found=IntPtr.Zero;
  EnumProc child=(h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);var cls=new StringBuilder(128);GetClassName(h,cls,128);if(owner==processId && cls.ToString()=="MatrixDesktopLayer")found=h;return true;};
  EnumWindows((h,p)=>{EnumChildWindows(h,child,IntPtr.Zero);return true;},IntPtr.Zero);
  return found;
 }
 public static void Send(IntPtr hwnd,uint msg) {IntPtr result;if(SendMessageTimeout(hwnd,msg,IntPtr.Zero,IntPtr.Zero,2,2000,out result)==IntPtr.Zero)throw new Exception("Renderer message timed out");}
}
'@
$renderer=Get-Process MatrixDesktop
if(@($renderer).Count -ne 1){throw 'Expected exactly one Matrix renderer.'}
$controller=[MatrixProbe]::FindWindow('MatrixDesktopController',$null)
[uint32]$owner=0
[void][MatrixProbe]::GetWindowThreadProcessId($controller,[ref]$owner)
if($owner -ne $renderer.Id){throw 'Controller does not belong to the renderer.'}
$layer=[MatrixProbe]::FindLayer($renderer.Id)
if($layer -eq [IntPtr]::Zero){throw 'Renderer layer is not attached.'}
$gdiBefore=[MatrixProbe]::GetGuiResources($renderer.Handle,0)
for($i=0;$i -lt 5;$i++){[MatrixProbe]::Send($controller,0x7e)}
Start-Sleep -Milliseconds 500
if([MatrixProbe]::FindLayer($renderer.Id) -ne $layer){throw 'Repeated display notifications recreated the layer.'}
# Destroy only A-Shell's own drawing child, simulating loss of its desktop host.
for($i=0;$i -lt 3;$i++) {
 $layer=[MatrixProbe]::FindLayer($renderer.Id)
 [MatrixProbe]::Send($layer,0x10)
 Start-Sleep -Milliseconds 500
 if([MatrixProbe]::FindLayer($renderer.Id) -eq [IntPtr]::Zero){throw 'Renderer did not reattach.'}
}
$gdiAfter=[MatrixProbe]::GetGuiResources($renderer.Handle,0)
if($gdiAfter -gt $gdiBefore+1){throw 'GDI resources increased across reattachments.'}
$duplicate=Start-Process (Join-Path $root 'bin\MatrixDesktop.exe') -WindowStyle Hidden -Wait -PassThru
if($duplicate.ExitCode -ne 0 -or @(Get-Process MatrixDesktop).Count -ne 1){throw 'Single-instance guard failed.'}
$entries=@(Get-Content (Join-Path $root 'bin\MatrixDesktop.log') | Where-Object {$_ -match "pid=$($renderer.Id) .*Desktop attached"})
$counts=@($entries | ForEach-Object {if($_ -match 'resets=(\d+)'){$Matches[1]}} | Select-Object -Last 3 -Unique)
if($counts.Count -ne 1){throw 'Animation reset during desktop reattachment.'}
"PASS: repeated display notifications preserve the layer; three reattachments preserve animation; single instance; GDI objects $gdiBefore -> $gdiAfter."
