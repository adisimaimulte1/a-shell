$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.System.UserProfile.LockScreen,Windows.System.UserProfile,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
if(!('AShellLockStream' -as [type])){Add-Type @'
using System; using System.IO; using System.Runtime.InteropServices; using System.Runtime.InteropServices.ComTypes;
public static class AShellLockStream {
 [DllImport("shcore.dll", PreserveSig=true)] static extern int CreateStreamOverRandomAccessStream([MarshalAs(UnmanagedType.IUnknown)] object source, ref Guid iid, out IStream stream);
 public static void Save(object source, string path) {
  Guid iid=new Guid("0000000c-0000-0000-C000-000000000046"); IStream stream;
  Marshal.ThrowExceptionForHR(CreateStreamOverRandomAccessStream(source,ref iid,out stream));
  IntPtr count=Marshal.AllocCoTaskMem(4);
  try {using(var file=File.Create(path)){byte[] buffer=new byte[65536];for(;;){stream.Read(buffer,buffer.Length,count);int n=Marshal.ReadInt32(count);if(n==0)break;file.Write(buffer,0,n);}}}
  finally {Marshal.FreeCoTaskMem(count);Marshal.ReleaseComObject(stream);}
 }
}
'@}
$script:awaitOperation=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$script:awaitAction=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and !$_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
function Save-LockImage([string]$Path) {
 $random=[Windows.System.UserProfile.LockScreen]::GetImageStream()
 # Use Windows' stream bridge even when PowerShell sees an unprojected COM object.
 [AShellLockStream]::Save($random,$Path)
}
function Get-AShellLockSource {
 $uri=[Windows.System.UserProfile.LockScreen]::OriginalImageFile
 if($uri -and $uri.IsFile -and (Test-Path -LiteralPath $uri.LocalPath)){return $uri.LocalPath}
 return $null
}
function Set-LockImage([string]$Path) {
 $operation=[Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)
 $task=$script:awaitOperation.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null,@($operation))
 $task.GetAwaiter().GetResult() | Out-Null
 $action=[Windows.System.UserProfile.LockScreen]::SetImageFileAsync($task.Result)
 $script:awaitAction.Invoke($null,@($action)).GetAwaiter().GetResult() | Out-Null
}
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class ShellAppearance {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool SystemParametersInfo(uint action,uint param,string value,uint flags);
 [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)] public static extern bool SystemParametersInfoPointer(uint action,uint param,IntPtr value,uint flags);
}
'@
function Set-DesktopImage([string]$Path) {
 if(![ShellAppearance]::SystemParametersInfo(20,0,$Path,3)) {throw 'Windows rejected the desktop image.'}
}
function Update-SystemCursors {
 if(![ShellAppearance]::SystemParametersInfoPointer(0x57,0,[IntPtr]::Zero,0)) {
  throw "Windows could not refresh the cursor scheme (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
 }
}
function Read-RegistryValue([string]$Path,[string]$Name) {
 $key=Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
 if($key -and $key.GetValueNames() -contains $Name) {
  return @{Path=$Path;Name=$Name;Exists=$true;Kind=$key.GetValueKind($Name).ToString();Value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
 }
 return @{Path=$Path;Name=$Name;Exists=$false;Kind='DWord';Value=$null}
}
function Write-RegistryValue($Item) {
 if($script:AShellWidgetsBlocked -and $Item.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -and $Item.Name -eq 'TaskbarDa'){return}
 $current=Read-RegistryValue $Item.Path $Item.Name
 if($current.Exists -and $Item.Exists -ne $false -and $current.Kind -eq $Item.Kind -and [string]$current.Value -eq [string]$Item.Value){return}
 if($Item.Exists -eq $false) {
  if(Test-Path -LiteralPath $Item.Path){
   if($Item.Name -eq ''){
    $writable=(Get-Item -LiteralPath $Item.Path).OpenSubKey('', $true)
    try {$writable.DeleteValue('', $false)} finally {$writable.Dispose()}
   }
   else {Remove-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue}
  }
  return
 }
 if(!(Test-Path -LiteralPath $Item.Path)){New-Item -Path $Item.Path -Force | Out-Null}
 if($Item.Name -eq '') {
  $defaultKey=Get-Item -LiteralPath $Item.Path
  [Microsoft.Win32.Registry]::SetValue($defaultKey.Name, '', $Item.Value, [Enum]::Parse([Microsoft.Win32.RegistryValueKind], $Item.Kind))
  return
 }
 try { New-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Item.Value -PropertyType $Item.Kind -Force | Out-Null }
 catch {
  # Windows can protect the optional Widgets toggle even for administrators.
  # Do not undo unrelated wallpaper/accent/mod restoration when it rejects it.
  $denied=$false;$cause=$_.Exception
  while($cause){if($cause -is [UnauthorizedAccessException] -or $cause -is [Security.SecurityException]){$denied=$true};$cause=$cause.InnerException}
  if($denied -and $Item.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -and $Item.Name -eq 'TaskbarDa'){
   $script:AShellWidgetsBlocked=$true
   Write-Warning 'Windows blocked the optional Widgets taskbar toggle. It was left unchanged; other appearance changes continue. Change Widgets in Windows Taskbar settings if available.'
   return
  }
  throw "Cannot set $($Item.Path) / $($Item.Name): $_"
 }
}
