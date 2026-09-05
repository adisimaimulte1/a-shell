param([ValidateSet('Apply','Restore','Check','SessionApply','Capture','RepairTask','Migrate')][string]$Action='Check',[ValidateRange(0,30000)][int]$DelayMilliseconds=0)
$ErrorActionPreference='Stop'
$cursorRoot=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
$cursorSource=Join-Path $cursorRoot 'assets\cursors'
$cursorState=Join-Path $cursorRoot 'state\cursors-before.clixml'
$cursorKey='HKCU:\Control Panel\Cursors'
$defaultCursorKey='Registry::HKEY_USERS\.DEFAULT\Control Panel\Cursors'
$themeKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
$schemeName='Material Design Pure Dark v2 by Jepri Creations (A-Shell)'
$legacyRepairTaskName='A-Shell Cursor Session Repair'
$guardTaskName='A-Shell Cursor Session Guard'
$guardExe=Join-Path $cursorRoot 'bin\CursorSessionGuard.exe'
$cursorMap=[ordered]@{Arrow='pointer.cur';Help='help.cur';AppStarting='working.ani';Wait='busy.ani';Crosshair='precision.cur';IBeam='beam.cur';NWPen='handwriting.cur';No='unavailable.cur';SizeNS='vert.cur';SizeWE='horz.cur';SizeNWSE='dgn1.cur';SizeNESW='dgn2.cur';SizeAll='move.cur';UpArrow='alternate.cur';Hand='link.cur';Person='person.cur';Pin='pin.cur'}
$cursorIds=[ordered]@{Arrow=32512;IBeam=32513;Wait=32514;Crosshair=32515;UpArrow=32516;SizeNWSE=32642;SizeNESW=32643;SizeWE=32644;SizeNS=32645;SizeAll=32646;No=32648;Hand=32649;AppStarting=32650}
$optionalCursorIds=[ordered]@{NWPen=32631;Help=32651;Pin=32671;Person=32672}

if(!('AShellCursorSession' -as [type])){Add-Type @'
using System;using System.Runtime.InteropServices;
public static class AShellCursorSession {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr LoadCursorFromFile(string path);
 [DllImport("user32.dll",SetLastError=true)] public static extern bool SetSystemCursor(IntPtr cursor,uint id);
 [DllImport("user32.dll",SetLastError=true)] public static extern bool DestroyCursor(IntPtr cursor);
}
'@}

function Get-AShellCursorRegistryValues([string]$Path) {
 $result=@(foreach($name in @($cursorMap.Keys)+@('','Scheme Source')){Read-RegistryValue $Path $name})
 $result+=Read-RegistryValue "$Path\Schemes" $schemeName
 return @($result)
}
function Get-AShellCursorGuardTaskState {
 $task=Get-ScheduledTask -TaskName $guardTaskName -ErrorAction SilentlyContinue
 return @{Exists=($null -ne $task);Xml=$(if($task){Export-ScheduledTask -TaskName $guardTaskName});Running=($task -and $task.State -eq 'Running')}
}
function Remove-AShellLegacyCursorRepairTask {
 $task=Get-ScheduledTask -TaskName $legacyRepairTaskName -ErrorAction SilentlyContinue
 if($task){Unregister-ScheduledTask -TaskName $legacyRepairTaskName -Confirm:$false;Write-Output '[OK] Removed obsolete delayed cursor PowerShell repair task.'}
}
function Stop-AShellCursorGuardProcess {
 foreach($process in @(Get-Process CursorSessionGuard -ErrorAction SilentlyContinue)){
  try {if([IO.Path]::GetFullPath($process.Path) -eq [IO.Path]::GetFullPath($guardExe)){$process | Stop-Process -Force -ErrorAction SilentlyContinue}}catch{}
 }
}
function Remove-AShellCursorGuardTask {
 Stop-AShellCursorGuardProcess
 $task=Get-ScheduledTask -TaskName $guardTaskName -ErrorAction SilentlyContinue
 if($task){Unregister-ScheduledTask -TaskName $guardTaskName -Confirm:$false}
}
function Install-AShellCursorGuardTask {
 if(!(Test-Path -LiteralPath $guardExe -PathType Leaf)){throw 'The native CursorSessionGuard.exe is missing. Run scripts\Build.ps1 or rebuild the Setup EXE.'}
 Remove-AShellLegacyCursorRepairTask
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
 # Run as early as Task Scheduler permits after the interactive token exists.
 # The helper itself is a GUI-subsystem process, so there is no PowerShell/CMD flash.
 $settings.Priority=0
 Register-ScheduledTask -TaskName $guardTaskName -Action (New-ScheduledTaskAction -Execute $guardExe -Argument '--guard' -WorkingDirectory (Split-Path $guardExe)) -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $identity.Name) -Principal (New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited) -Settings $settings -Description 'A-Shell: windowless session cursor guard for Windows/theme/startup-app cursor resets.' -Force | Out-Null
}
function Restore-AShellCursorGuardTask($TaskState) {
 Remove-AShellCursorGuardTask
 if($TaskState -and $TaskState.Exists){
  Register-ScheduledTask -TaskName $guardTaskName -Xml $TaskState.Xml -Force | Out-Null
  if($TaskState.Running){Start-ScheduledTask -TaskName $guardTaskName}
 }
}
function Save-AShellCursorBaseline {
 New-Item -ItemType Directory (Split-Path $cursorState) -Force | Out-Null
 if(Test-Path -LiteralPath $cursorState) {
  # Upgrade the old baseline only with values A-Shell has never changed before.
  # This keeps the true pre-A-Shell setting available for stop/uninstall.
  $saved=Import-Clixml -LiteralPath $cursorState
  if([string]$saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
  $defaultValues=if($null -ne $saved.DefaultValues){@($saved.DefaultValues)}else{@(Get-AShellCursorRegistryValues $defaultCursorKey)}
  $themeValue=if($null -ne $saved.ThemeChangesMousePointers){$saved.ThemeChangesMousePointers}else{Read-RegistryValue $themeKey 'ThemeChangesMousePointers'}
  $guardTask=if($null -ne $saved.GuardTask){$saved.GuardTask}else{Get-AShellCursorGuardTaskState}
  @{Version=3;Sid=[string]$saved.Sid;Values=@($saved.Values);DefaultValues=$defaultValues;ThemeChangesMousePointers=$themeValue;GuardTask=$guardTask} | Export-Clixml -LiteralPath $cursorState
  return
 }
 @{Version=3;Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Values=@(Get-AShellCursorRegistryValues $cursorKey);DefaultValues=@(Get-AShellCursorRegistryValues $defaultCursorKey);ThemeChangesMousePointers=(Read-RegistryValue $themeKey 'ThemeChangesMousePointers');GuardTask=(Get-AShellCursorGuardTaskState)} | Export-Clixml -LiteralPath $cursorState
}
function Set-AShellCursorRegistry([string]$Path,[string]$Destination) {
 foreach($entry in $cursorMap.GetEnumerator()) {
  $file=Join-Path $Destination $entry.Value
  Write-RegistryValue @{Path=$Path;Name=$entry.Key;Kind='ExpandString';Value=$file;Exists=$true}
 }
 $scheme=(@($cursorMap.Values | ForEach-Object {Join-Path $Destination $_}) -join ',')
 Write-RegistryValue @{Path="$Path\Schemes";Name=$schemeName;Kind='String';Value=$scheme;Exists=$true}
 Write-RegistryValue @{Path=$Path;Name='';Kind='String';Value=$schemeName;Exists=$true}
 Write-RegistryValue @{Path=$Path;Name='Scheme Source';Kind='DWord';Value=1;Exists=$true}
}
function Install-AShellPersistentCursorRegistry {
 Save-AShellCursorBaseline
 Remove-AShellLegacyCursorRepairTask
 $destination=Join-Path $env:ProgramData 'A-Shell\Cursors\MaterialPureDarkV2'
 New-Item -ItemType Directory $destination -Force | Out-Null
 foreach($entry in $cursorMap.GetEnumerator()) {
  $file=Join-Path $destination $entry.Value
  if(!(Test-Path $file) -or (Get-FileHash $file).Hash -ne (Get-FileHash (Join-Path $cursorSource $entry.Value)).Hash){Copy-Item -LiteralPath (Join-Path $cursorSource $entry.Value) -Destination $file -Force}
 }
 # Winlogon/.DEFAULT and the actual user profile resolve to the same immutable
 # ProgramData files. Also stop Windows theme activation from swapping the saved
 # pointer scheme during Explorer/theme initialization.
 Set-AShellCursorRegistry $defaultCursorKey $destination
 Set-AShellCursorRegistry $cursorKey $destination
 Write-RegistryValue @{Path=$themeKey;Name='ThemeChangesMousePointers';Kind='DWord';Value=0;Exists=$true}
 return $destination
}
function Set-AShellCursorSession([switch]$Strict) {
 $failures=@();$optionalFailures=@()
 foreach($set in @(@{Map=$cursorIds;Required=$true},@{Map=$optionalCursorIds;Required=$false})) {
  foreach($entry in $set.Map.GetEnumerator()) {
   $raw=(Read-RegistryValue $cursorKey $entry.Key).Value
   $path=if($raw){[Environment]::ExpandEnvironmentVariables([string]$raw)}else{''}
   if(!$path -or !(Test-Path -LiteralPath $path -PathType Leaf)) {
    if($Strict -and $set.Required){$failures+="$($entry.Key): cursor file is missing ($raw)"}
    continue
   }
   $handle=[AShellCursorSession]::LoadCursorFromFile($path)
   if($handle -eq [IntPtr]::Zero) {
    $message="$($entry.Key): LoadCursorFromFile failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    if($set.Required){$failures+=$message}else{$optionalFailures+=$message}
    continue
   }
   if(![AShellCursorSession]::SetSystemCursor($handle,[uint32]$entry.Value)) {
    $error=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
    [void][AShellCursorSession]::DestroyCursor($handle)
    $message="$($entry.Key): SetSystemCursor failed ($error)"
    if($set.Required){$failures+=$message}else{$optionalFailures+=$message}
   }
  }
 }
 if($optionalFailures.Count){Write-Warning ('Some optional pointer roles could not be directly refreshed: '+($optionalFailures -join '; '))}
 if($failures.Count) {
  $message='Could not directly activate core cursor roles for this session: '+($failures -join '; ')
  if($Strict){throw $message}
  Write-Warning $message
  return $false
 }
 return $true
}

if($Action -in @('Apply','Check')) {
 foreach($file in $cursorMap.Values) {
  $path=Join-Path $cursorSource $file
  if(!(Test-Path -LiteralPath $path)){throw "Missing cursor: $file"}
  $bytes=[IO.File]::ReadAllBytes($path)
  if($file.EndsWith('.cur')) {
   if($bytes.Length -lt 22 -or [BitConverter]::ToUInt16($bytes,0) -ne 0 -or [BitConverter]::ToUInt16($bytes,2) -ne 2){throw "Invalid cursor file: $file"}
  } elseif($bytes.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'RIFF' -or [Text.Encoding]::ASCII.GetString($bytes,8,4) -ne 'ACON'){throw "Invalid animated cursor: $file"}
 }
}
if($Action -eq 'Check'){Write-Output 'All 17 cursor files validated.';return}
if($Action -eq 'Capture'){Save-AShellCursorBaseline;Remove-AShellLegacyCursorRepairTask;Write-Output 'Cursors: Capture complete.';exit 0}
if($Action -eq 'RepairTask'){
 [void](Install-AShellPersistentCursorRegistry);Install-AShellCursorGuardTask
 Write-Output '[OK] Native/windowless cursor sign-in guard repaired.';exit 0
}
if($Action -eq 'Migrate') {
 [void](Install-AShellPersistentCursorRegistry)
 Install-AShellCursorGuardTask
 # The updater may briefly pause CursorSessionGuard.exe because Windows locks a
 # running executable against replacement. Restart only the windowless guard when
 # A-Shell is active; do not reload the live cursor table or any visual settings.
 if(Test-AShellRuntimeActive $cursorRoot){Start-ScheduledTask -TaskName $guardTaskName -ErrorAction SilentlyContinue}
 Write-Output '[OK] Cursor persistence migrated; the current cursor appearance was left untouched.'
 exit 0
}
if($Action -eq 'SessionApply') {
 # Compatibility endpoint for obsolete PowerShell tasks from prior builds.
 Remove-AShellLegacyCursorRepairTask
 return
}
if($Action -eq 'Apply') {
 [void](Install-AShellPersistentCursorRegistry)
 Install-AShellCursorGuardTask
 $saved=Import-Clixml $cursorState
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
 # On affected 2026 Windows builds SPI_SETCURSORS can fail or briefly reload the
 # stock scheme. Go directly through SetSystemCursor so start/setup never inserts
 # an unnecessary default-cursor transition.
 [void](Set-AShellCursorSession -Strict)
 # The AtLogOn trigger protects future sessions. Start the same native/windowless
 # guard now as well so an app/theme reset later in this already-open session
 # cannot win after `ashell start` or Setup. The helper mutex makes this idempotent.
 Start-ScheduledTask -TaskName $guardTaskName -ErrorAction SilentlyContinue
} else {
 Remove-AShellLegacyCursorRepairTask
 Remove-AShellCursorGuardTask
 if(!(Test-Path $cursorState)){return}
 $saved=Import-Clixml $cursorState
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
 if($null -ne $saved.DefaultValues){foreach($value in @($saved.DefaultValues)){Write-RegistryValue $value}}
 foreach($value in @($saved.Values)){Write-RegistryValue $value}
 if($null -ne $saved.ThemeChangesMousePointers){Write-RegistryValue $saved.ThemeChangesMousePointers}
 Restore-AShellCursorGuardTask $saved.GuardTask
 # Restoring the user's original scheme may use the normal SPI path on builds
 # where it works, then direct-load the exact saved files as a deterministic fallback.
 [void](Update-SystemCursors -BestEffort)
 [void](Set-AShellCursorSession)
}
Write-Output "Cursors: $Action complete."
