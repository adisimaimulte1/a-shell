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
 try {$uri=[Windows.System.UserProfile.LockScreen]::OriginalImageFile}
 catch {return $null} # Stream-set/Spotlight images can have no original file URI.
 if($uri -and $uri.IsFile -and (Test-Path -LiteralPath $uri.LocalPath)){return $uri.LocalPath}
 return $null
}
function Test-AShellLockImage([string]$Path) {
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
 $expected=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
 $source=Get-AShellLockSource
 if($source -and (Test-Path -LiteralPath $source -PathType Leaf)) {
  try {if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -eq $expected){return $true}} catch {}
 }
 $probe=Join-Path ([IO.Path]::GetTempPath()) ('ashell-lock-'+[guid]::NewGuid().ToString('N')+'.img')
 try {
  Save-LockImage $probe
  return ((Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash -eq $expected)
 } catch {return $false}
 finally {Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue}
}
function Set-LockImage([string]$Path) {
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Lock-screen image does not exist: $Path"}
 $operation=[Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)
 $task=$script:awaitOperation.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null,@($operation))
 $task.GetAwaiter().GetResult() | Out-Null
 for($attempt=0;$attempt -lt 2;$attempt++) {
  $action=[Windows.System.UserProfile.LockScreen]::SetImageFileAsync($task.Result)
  $script:awaitAction.Invoke($null,@($action)).GetAwaiter().GetResult() | Out-Null
  if(Test-AShellLockImage $Path){return}
  Start-Sleep -Milliseconds 150
 }
 throw 'Windows accepted the lock-screen request but did not make the requested image active.'
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
function Update-SystemCursors([switch]$BestEffort) {
 if(![ShellAppearance]::SystemParametersInfoPointer(0x57,0,[IntPtr]::Zero,0)) {
  $message="Windows could not refresh the cursor scheme through SPI_SETCURSORS (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
  if($BestEffort){Write-Warning ($message+' A-Shell will use the direct per-session cursor fallback.');return $false}
  throw $message
 }
 return $true
}
function Read-RegistryValue([string]$Path,[string]$Name) {
 $key=Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
 if($key -and $key.GetValueNames() -contains $Name) {
  return @{Path=$Path;Name=$Name;Exists=$true;Kind=$key.GetValueKind($Name).ToString();Value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
 }
 return @{Path=$Path;Name=$Name;Exists=$false;Kind='DWord';Value=$null}
}
function Get-AShellRegistrySettingId([string]$Path,[string]$Name) { return ($Path+'|'+$Name).ToLowerInvariant() }
function Test-AShellProtectedPreferencePath([string]$Path) {
 return $Path -like 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\*'
}
function Test-AShellOptionalRegistrySetting([string]$Path,[string]$Name) {
 $id=Get-AShellRegistrySettingId $Path $Name
 $optional=@(
  'hkcu:\software\microsoft\windows\currentversion\explorer\advanced|taskbaral',
  'hkcu:\software\microsoft\windows\currentversion\explorer\advanced|showtaskviewbutton',
  'hkcu:\software\microsoft\windows\currentversion\explorer\advanced|taskbarda',
  'hkcu:\software\microsoft\windows\currentversion\search|searchboxtaskbarmode',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|lockscreenwidgetsenabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|lockscreenwidgetssystemcurationenabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|slideshowenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|rotatinglockscreenenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|rotatinglockscreenoverlayenabled',
  'hklm:\software\policies\microsoft\windows\system|disableacrylicbackgroundonlogon',
  'hklm:\software\policies\microsoft\windows\system|disablelogonbackgroundimage',
  'hklm:\software\policies\microsoft\dsh|disablewidgetsonlockscreen',
  'hklm:\software\microsoft\windows\currentversion\policies\system|disableautomaticrestartsignon'
 )
 return $optional -contains $id
}
function Test-AShellAccessDeniedError($ErrorRecord) {
 # PowerShell 5.1's Registry provider can wrap the same access denial several
 # different ways depending on the Windows build/provider code path.
 $exception=if($ErrorRecord -is [Management.Automation.ErrorRecord]){$ErrorRecord.Exception}else{$ErrorRecord}
 $cause=$exception
 while($cause){
  if($cause -is [UnauthorizedAccessException] -or $cause -is [Security.SecurityException]){return $true}
  $cause=$cause.InnerException
 }
 if($ErrorRecord -is [Management.Automation.ErrorRecord]) {
  $category=[string]$ErrorRecord.CategoryInfo.Category
  if($category -in @('PermissionDenied','SecurityError')){return $true}
 }
 $message=[string]$ErrorRecord
 return ($message -match '(?i)unauthori[sz]ed|access.{0,40}(denied|not allowed)|registry access is not allowed')
}
function Write-AShellOptionalRegistryWarning([string]$Path,[string]$Name) {
 if(!$script:AShellSkippedRegistrySettings){$script:AShellSkippedRegistrySettings=@{}}
 $id=Get-AShellRegistrySettingId $Path $Name
 $script:AShellSkippedRegistrySettings[$id]=$true
 if(!$script:AShellWarnedRegistrySettings){$script:AShellWarnedRegistrySettings=@{}}
 if(!$script:AShellWarnedRegistrySettings.ContainsKey($id)){
  $script:AShellWarnedRegistrySettings[$id]=$true
  Write-Warning "Windows or device policy protects the optional setting '$Name'. A-Shell left it unchanged and will continue."
 }
}
function Write-RegistryValue($Item) {
 # SystemProtectedUserData contains broker-owned per-user preferences. Newer
 # Windows 11 builds can expose these values for reading while rejecting writes
 # even from an elevated administrator. Never take ownership or run as SYSTEM
 # merely to change them; stale checkpoints from older A-Shell builds are ignored.
 if(Test-AShellProtectedPreferencePath $Item.Path) {
  if(!$script:AShellProtectedPreferenceWarningShown){
   $script:AShellProtectedPreferenceWarningShown=$true
   Write-Warning 'A protected Windows per-user personalization value from an older A-Shell backup was skipped. Windows keeps ownership of SystemProtectedUserData.'
  }
  return
 }
 $current=Read-RegistryValue $Item.Path $Item.Name
 if($current.Exists -and $Item.Exists -ne $false -and $current.Kind -eq $Item.Kind -and [string]$current.Value -eq [string]$Item.Value){return}
 try {
  if($Item.Exists -eq $false) {
   if(!$current.Exists){return}
   if(Test-Path -LiteralPath $Item.Path){
    if($Item.Name -eq ''){
     $writable=(Get-Item -LiteralPath $Item.Path).OpenSubKey('', $true)
     try {$writable.DeleteValue('', $false)} finally {$writable.Dispose()}
    }
    else {Remove-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction Stop}
   }
   return
  }
  if(!(Test-Path -LiteralPath $Item.Path)){New-Item -Path $Item.Path -Force -ErrorAction Stop | Out-Null}
  if($Item.Name -eq '') {
   $defaultKey=Get-Item -LiteralPath $Item.Path
   [Microsoft.Win32.Registry]::SetValue($defaultKey.Name, '', $Item.Value, [Enum]::Parse([Microsoft.Win32.RegistryValueKind], $Item.Kind))
   return
  }
  New-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Item.Value -PropertyType $Item.Kind -Force -ErrorAction Stop | Out-Null
 } catch {
  if((Test-AShellAccessDeniedError $_) -and (Test-AShellOptionalRegistrySetting $Item.Path $Item.Name)){
   Write-AShellOptionalRegistryWarning $Item.Path $Item.Name
   return
  }
  throw "Cannot set $($Item.Path) / $($Item.Name): $_"
 }
}
