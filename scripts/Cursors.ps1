param([ValidateSet('Apply','Restore','Check','SessionApply','Capture','RepairTask')][string]$Action='Check',[ValidateRange(0,30000)][int]$DelayMilliseconds=0)
$ErrorActionPreference='Stop'
$cursorRoot=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
$cursorSource=Join-Path $cursorRoot 'assets\cursors'
$cursorState=Join-Path $cursorRoot 'state\cursors-before.clixml'
$cursorKey='HKCU:\Control Panel\Cursors'
$schemeName='Material Design Pure Dark v2 by Jepri Creations (A-Shell)'
$repairTaskName='A-Shell Cursor Session Repair'
$repairLauncher=Join-Path $PSScriptRoot 'CursorSessionRepair.vbs'
$cursorMap=[ordered]@{Arrow='pointer.cur';Help='help.cur';AppStarting='working.ani';Wait='busy.ani';Crosshair='precision.cur';IBeam='beam.cur';NWPen='handwriting.cur';No='unavailable.cur';SizeNS='vert.cur';SizeWE='horz.cur';SizeNWSE='dgn1.cur';SizeNESW='dgn2.cur';SizeAll='move.cur';UpArrow='alternate.cur';Hand='link.cur';Person='person.cur';Pin='pin.cur'}
# SetSystemCursor officially documents the core system IDs below. The newer/legacy
# extras are attempted too, but never make an otherwise successful install fail.
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
 if($optionalFailures.Count){Write-Warning ('Some optional pointer roles could not be directly refreshed and will rely on the saved Windows scheme: '+($optionalFailures -join '; '))}
 if($failures.Count) {
  $message='Could not directly activate core cursor roles for this session: '+($failures -join '; ')
  if($Strict){throw $message}
  Write-Warning $message
  return $false
 }
 return $true
}
function Install-AShellCursorRepairTask {
 if(!(Test-Path -LiteralPath $repairLauncher -PathType Leaf)){throw 'Windowless cursor-session launcher is missing. Re-extract the complete A-Shell package.'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $wscript=Join-Path $env:SystemRoot 'System32\wscript.exe'
 # Task Scheduler starts InteractiveToken processes on the visible desktop. A
 # direct powershell.exe action can therefore flash before -WindowStyle Hidden is
 # processed. wscript.exe is a GUI host and creates the PowerShell child hidden
 # from the beginning, while SessionApply still runs in the interactive session.
 $arguments='//B //NoLogo "'+$repairLauncher+'" "'+$PSCommandPath+'"'
 $action=New-ScheduledTaskAction -Execute $wscript -Argument $arguments -WorkingDirectory $PSScriptRoot
 $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
 $principal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
 Register-ScheduledTask -TaskName $repairTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Re-applies the selected A-Shell cursor handles after Windows initializes the user theme, using a windowless launcher.' -Force | Out-Null
}
function Restore-AShellCursorRepairTask($Saved) {
 $taskState=$Saved.Task
 if($taskState -and $taskState.Exists) {
  Register-ScheduledTask -TaskName $repairTaskName -Xml $taskState.Xml -Force | Out-Null
  if($taskState.Running){Start-ScheduledTask -TaskName $repairTaskName}
 } else {
  $task=Get-ScheduledTask -TaskName $repairTaskName -ErrorAction SilentlyContinue
  if($task){Unregister-ScheduledTask -TaskName $repairTaskName -Confirm:$false}
 }
}
function Save-AShellCursorBaseline {
 if(Test-Path -LiteralPath $cursorState){return}
 $values=@(foreach($name in @($cursorMap.Keys)+@('','Scheme Source')){Read-RegistryValue $cursorKey $name})
 $values+=Read-RegistryValue "$cursorKey\Schemes" $schemeName
 $task=Get-ScheduledTask -TaskName $repairTaskName -ErrorAction SilentlyContinue
 $taskState=@{Exists=($null -ne $task);Xml=$(if($task){Export-ScheduledTask -TaskName $repairTaskName});Running=($task -and $task.State -eq 'Running')}
 New-Item -ItemType Directory (Split-Path $cursorState) -Force | Out-Null
 @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Values=$values;Task=$taskState} | Export-Clixml $cursorState
}
if($Action -eq 'Capture'){Save-AShellCursorBaseline;Write-Output 'Cursors: Capture complete.';exit 0}
if($Action -eq 'RepairTask'){Install-AShellCursorRepairTask;Write-Output '[OK] Cursor session repair now uses the windowless launcher.';exit 0}
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
if($Action -eq 'SessionApply') {
 # Let Explorer/theme initialization finish when this action comes from the logon task.
 if($DelayMilliseconds){Start-Sleep -Milliseconds $DelayMilliseconds}
 # Windows 11 updates can reject SPI_SETCURSORS even while the registry scheme is valid.
 # Re-load each standard cursor handle directly after the user theme/session starts.
 [void](Update-SystemCursors -BestEffort)
 [void](Set-AShellCursorSession)
 return
}
if($Action -eq 'Apply') {
 Save-AShellCursorBaseline
 $saved=Import-Clixml $cursorState
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
 $destination=Join-Path $env:LOCALAPPDATA 'A-Shell\Cursors\MaterialPureDarkV2'
 New-Item -ItemType Directory $destination -Force | Out-Null
 foreach($entry in $cursorMap.GetEnumerator()) {
  $file=Join-Path $destination $entry.Value
  if(!(Test-Path $file) -or (Get-FileHash $file).Hash -ne (Get-FileHash (Join-Path $cursorSource $entry.Value)).Hash){Copy-Item -LiteralPath (Join-Path $cursorSource $entry.Value) -Destination $file -Force}
  Write-RegistryValue @{Path=$cursorKey;Name=$entry.Key;Kind='ExpandString';Value=$file;Exists=$true}
 }
 $scheme=(@($cursorMap.Values | ForEach-Object {Join-Path $destination $_}) -join ',')
 Write-RegistryValue @{Path="$cursorKey\Schemes";Name=$schemeName;Kind='String';Value=$scheme;Exists=$true}
 Write-RegistryValue @{Path=$cursorKey;Name='';Kind='String';Value=$schemeName;Exists=$true}
 Write-RegistryValue @{Path=$cursorKey;Name='Scheme Source';Kind='DWord';Value=1;Exists=$true}
 Install-AShellCursorRepairTask
 [void](Update-SystemCursors -BestEffort)
 [void](Set-AShellCursorSession -Strict)
} else {
 if(!(Test-Path $cursorState)){return}
 $saved=Import-Clixml $cursorState
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
 foreach($value in $saved.Values){Write-RegistryValue $value}
 Restore-AShellCursorRepairTask $saved
 [void](Update-SystemCursors -BestEffort)
 [void](Set-AShellCursorSession)
}
Write-Output "Cursors: $Action complete."
