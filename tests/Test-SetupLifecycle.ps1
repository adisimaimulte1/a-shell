param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if(!$Worker) {
 $p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker') -Wait -PassThru
 exit $p.ExitCode
}
$log=Join-Path $root 'state\lifecycle-test.txt'
function Invoke-Setup([string]$Action) {
 $stdout=Join-Path $root 'state\test-stdout.txt'
 $stderr=Join-Path $root 'state\test-stderr.txt'
 $process=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'scripts\Setup.ps1')+'" -Action '+$Action) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 Get-Content $stdout,$stderr | Out-File $log -Append -Encoding utf8
 if($process.ExitCode){throw "Setup $Action failed (exit $($process.ExitCode)); see $log"}
}
function Assert-Values($Values) {
 foreach($value in $Values) {
  $now=Read-RegistryValue $value.Path $value.Name
  if($now.Exists -ne $value.Exists -or ($value.Exists -and ($now.Kind -ne $value.Kind -or [string]$now.Value -ne [string]$value.Value))){throw "Restore mismatch: $($value.Path) / $($value.Name)"}
 }
}
try {
 'Starting full setup / repeat setup / restore / setup test.' | Set-Content $log -Encoding utf8
 Invoke-Setup 'Apply'
 $baseline=(Get-FileHash (Join-Path $root 'state\before-setup.clixml')).Hash
 $cursorBaseline=(Get-FileHash (Join-Path $root 'state\cursors-before.clixml')).Hash
 Invoke-Setup 'Apply'
 if((Get-FileHash (Join-Path $root 'state\before-setup.clixml')).Hash -ne $baseline -or (Get-FileHash (Join-Path $root 'state\cursors-before.clixml')).Hash -ne $cursorBaseline){throw 'Repeat setup changed the first-run backups.'}
 Invoke-Setup 'Restore'
 . (Join-Path $root 'scripts\Appearance.Helpers.ps1')
 Assert-Values (Import-Clixml (Join-Path $root 'state\before-setup.clixml')).Values
 Assert-Values (Import-Clixml (Join-Path $root 'state\cursors-before.clixml')).Values
 Assert-Values (Import-Clixml (Join-Path $root 'state\accent-before.clixml')).Values
 Assert-Values @((Import-Clixml (Join-Path $root 'state\terminal-before.clixml')).Path)
 Invoke-Setup 'Apply'
 'PASS: Apply, repeat Apply, Restore, Apply; original backups stable; saved appearance, accent and cursor values restored exactly.' | Add-Content $log
} catch {
 ('FAILED: '+$_) | Add-Content $log
 # Leave the requested A-Shell appearance enabled if verification encountered an error.
 try {Invoke-Setup 'Apply'} catch {('Recovery: '+$_) | Add-Content $log}
 exit 1
}
