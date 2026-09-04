param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if(!$Worker){$p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker') -Wait -PassThru;exit $p.ExitCode}
$log=Join-Path $root 'state\optional-controls-test.txt'
Start-Transcript -Path $log -Force | Out-Null
$icon=Join-Path $root 'assets\icons\icons8-chrome-96.png'
$backup=Join-Path $root 'state\live-tests\chrome-icon-before.png'
Copy-Item -LiteralPath $icon -Destination $backup -Force
try {
 $key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler\Settings'
 $before=Get-ItemProperty $key
 Copy-Item -LiteralPath (Join-Path $root 'assets\icons\icons-a-shell-96.png') -Destination $icon -Force
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Icons.ps1') -Action refresh
 if($LASTEXITCODE){throw 'Changed icon refresh failed'}
 $after=Get-ItemProperty $key;$changed=@()
 foreach($p in $before.PSObject.Properties | Where-Object Name -Like 'controlStyles*') {if([string]$after.($p.Name) -ne [string]$p.Value){$changed+=$p.Name}}
 if($changed.Count -ne 1 -or $changed[0] -notlike '*.styles[[]0[]]'){throw "Expected one changed image-source setting, got $($changed -join ', ')"}
 Write-Output 'PASS: replacing one live mapped image changed exactly one taskbar source setting.'
 Copy-Item -LiteralPath $backup -Destination $icon -Force
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Icons.ps1') -Action refresh
 if($LASTEXITCODE){throw 'Original icon restore failed'}
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $photoKey='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\'+$sid
 $current=Get-ItemProperty $photoKey
 foreach($restore in @($true,$false)) {
  $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\Profile-Picture.ps1'))
  if($restore){$arguments+='-Restore'}
  & powershell.exe @arguments
  if($LASTEXITCODE){throw 'Optional photo command failed'}
  if($restore){$saved=Import-Clixml (Join-Path $env:ProgramData ('A-Shell\AccountPictures\'+$sid+'\before.clixml'));$now=Get-ItemProperty $photoKey;foreach($entry in $saved){if($now.($entry.Name) -ne $entry.Value){throw 'Photo restore mismatch'}}}
 }
 $now=Get-ItemProperty $photoKey
 foreach($p in $current.PSObject.Properties | Where-Object Name -Match '^Image\d+$'){if($now.($p.Name) -ne $p.Value){throw 'Photo did not return to its pre-test selection'}}
 if(Get-ScheduledTask -TaskName 'A-Shell Profile Picture Maintenance' -ErrorAction SilentlyContinue){throw 'Temporary photo task was not removed'}
 Write-Output 'PASS: optional photo restore/apply, exact path readback, original pre-test selection restored and maintenance task cleaned up.'
} catch {Write-Output ('FAIL: '+$_);exit 1}
finally {
 Copy-Item -LiteralPath $backup -Destination $icon -Force
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Icons.ps1') -Action refresh
 Stop-Transcript | Out-Null
}
