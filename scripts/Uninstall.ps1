param([switch]$Confirmed,[switch]$ElevatedWorker,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Desktop.Support.ps1')
. (Join-Path $PSScriptRoot 'Console.Helpers.ps1')
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
function Write-AShellFarewell {
 Write-Host ''
 Write-AShellAccent '⠀⢀⣴⣾⣿⣿⣿⣷⣦⡄⠀⣴⣾⣿⣿⣿⣿⣶⣄⠀⠀'
 Write-AShellAccent '⣰⣿⣿⣿⣿⣿⣿⣿⠋⢠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀'
 Write-AShellAccent '⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣌⠛⣿⣿⣿⣿⣿⣿⣿⣿⡆'
 Write-AShellAccent '⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⢁⣼⣿⣿⣿⣿⣿⣿⣿⣿⠁'
 Write-AShellAccent '⠸⣿⣿⣿⣿⣿⣿⣿⡟⢀⣾⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀'
 Write-AShellAccent '⠀⠙⣿⣿⣿⣿⣿⣿⣄⠻⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀⠀'
 Write-AShellAccent '⠀⠀⠈⠻⣿⣿⣿⣿⣿⣧⡈⢿⣿⣿⣿⣿⡟⠁⠀⠀⠀'
 Write-AShellAccent '⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⡇⢸⣿⣿⠟⠉⠀⠀⠀⠀⠀'
 Write-AShellAccent '⠀⠀⠀⠀⠀⠀⠈⠙⢿⡿⠀⡿⠛⠁⠀⠀⠀⠀⠀⠀⠀' -NoNewline
 Write-Host '  A-Shell has left the desktop.' -ForegroundColor White
}
if(!$Confirmed){
 Write-AShellHeading 'UNINSTALL'
 Write-AShellLine '[INFO] Restore Windows and Desktop content, then remove A-Shell.'
 $answer=Read-Host '  Uninstall A-Shell completely? [Y/N]'
 if($answer -notmatch '^(?i:y|yes)$'){Write-AShellLine '[SKIP] Uninstall cancelled.';exit 0}
 $Confirmed=$true
}
$admin=Test-AShellAdministrator
if(!$admin){
 Write-AShellLine '[WORKING] Requesting administrator access...'
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters @{Confirmed=$true;ElevatedWorker=$true;ExpectedSid=$ExpectedSid} -Title 'A-Shell Uninstall - Administrator'
 if($exitCode){throw "Uninstall restore failed (exit $exitCode). A-Shell files were kept so recovery remains possible. See state\setup.log."}
 Write-AShellFarewell
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched to another Windows account.'}
if(!(Test-Path -LiteralPath (Join-Path $root 'state\\before-setup.clixml'))){throw 'The original A-Shell recovery state is missing. Refusing to delete the program before Windows can be restored.'}
# If A-Shell is active, run the full installer-grade restore. If it is already
# stopped, do not replay wallpaper/theme/taskbar transitions just to uninstall;
# validate/recover any legacy Desktop archive and continue with integration cleanup.
$wasActive=Test-AShellRuntimeActive $root
if($wasActive){
 Write-AShellLine '[WORKING] Restoring the active A-Shell appearance...'
 & (Join-Path $PSScriptRoot 'Setup.ps1') -Action Restore -ExpectedSid $ExpectedSid
}else{
 Write-AShellLine '[SKIP] A-Shell is already stopped; appearance restore is already complete.'
}
# This exhaustive pass intentionally restores *every* leftover item from old
# original_desktop implementations (files, folders, shortcuts and links), then
# deletes the archive. Conflicts are preserved under a safe restored name.
Restore-AShellLegacyDesktopArchive $root
try {& (Join-Path $PSScriptRoot 'Manage.ps1') -Action Remove}catch{}
try {& (Join-Path $PSScriptRoot 'Terminal.ps1') -Action Restore}catch{}
try {Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'A-Shell') -Recurse -Force -ErrorAction SilentlyContinue}catch{}
# Cursor assets and any legacy lock-image staging live in ProgramData so
# Winlogon can use the cursors before the user profile loads. Remove them only
# after the installer-grade restore above has succeeded.
try {Remove-Item -LiteralPath (Join-Path $env:ProgramData 'A-Shell') -Recurse -Force -ErrorAction SilentlyContinue}catch{}
try {
 $wh64=Join-Path $env:ProgramData 'Windhawk\Engine\Mods\64'
 $whsrc=Join-Path $env:ProgramData 'Windhawk\ModsSource'
 foreach($pattern in @('ashell-lockscreen-clear-background_*.dll','ashell-signin-clear-background_*.dll')){
  foreach($file in @(Get-ChildItem -LiteralPath $wh64 -Filter $pattern -File -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue}
 }
 foreach($file in @('windows-11-taskbar-styler_1.9_ashell_identity1.dll')){Remove-Item -LiteralPath (Join-Path $wh64 $file) -Force -ErrorAction SilentlyContinue}
 foreach($file in @('ashell-lockscreen-clear-background.wh.cpp','ashell-signin-clear-background.wh.cpp')){Remove-Item -LiteralPath (Join-Path $whsrc $file) -Force -ErrorAction SilentlyContinue}
}catch{}
# Delete the install tree after this PowerShell process exits, so scripts are never
# removed out from underneath their own restore transaction.
$cleanup=Join-Path $env:TEMP ('ashell-uninstall-'+[guid]::NewGuid().ToString('N')+'.ps1')
$escaped=$root.Replace("'","''")
$body=@"
`$target='$escaped'
Start-Sleep -Seconds 6
`$matrix=Join-Path `$target 'bin\MatrixDesktop.exe'
for(`$i=0;`$i -lt 150;`$i++){
 `$ours=@(Get-Process MatrixDesktop -ErrorAction SilentlyContinue | Where-Object {try{[IO.Path]::GetFullPath(`$_.Path) -eq [IO.Path]::GetFullPath(`$matrix)}catch{`$false}})
 if(!`$ours.Count){break}
 Start-Sleep -Milliseconds 400
}
`$ours=@(Get-Process MatrixDesktop -ErrorAction SilentlyContinue | Where-Object {try{[IO.Path]::GetFullPath(`$_.Path) -eq [IO.Path]::GetFullPath(`$matrix)}catch{`$false}})
if(`$ours.Count){`$ours | Stop-Process -Force -ErrorAction SilentlyContinue;Start-Sleep -Milliseconds 300}
for(`$i=0;`$i -lt 30 -and (Test-Path -LiteralPath `$target);`$i++){
 try {Remove-Item -LiteralPath `$target -Recurse -Force -ErrorAction Stop}catch{Start-Sleep -Milliseconds 400}
}
Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
"@
[IO.File]::WriteAllText($cleanup,$body,[Text.UTF8Encoding]::new($false))
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$cleanup+'"')) | Out-Null
if(!$ElevatedWorker){Write-AShellFarewell}
exit 0
