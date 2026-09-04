param([switch]$Confirmed,[switch]$ElevatedWorker,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
function Write-AShellFarewell {
 Write-Host ''
 $heart=@'
⠀⢀⣴⣾⣿⣿⣿⣷⣦⡄⠀⣴⣾⣿⣿⣿⣿⣶⣄⠀⠀
⣰⣿⣿⣿⣿⣿⣿⣿⠋⢠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣌⠛⣿⣿⣿⣿⣿⣿⣿⣿⡆
⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⢁⣼⣿⣿⣿⣿⣿⣿⣿⣿⠁
⠸⣿⣿⣿⣿⣿⣿⣿⡟⢀⣾⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀
⠀⠙⣿⣿⣿⣿⣿⣿⣄⠻⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀⠀
⠀⠀⠈⠻⣿⣿⣿⣿⣿⣧⡈⢿⣿⣿⣿⣿⡟⠁⠀⠀⠀
⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⡇⢸⣿⣿⠟⠉⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⠙⢿⡿⠀⡿⠛⠁⠀⠀⠀⠀⠀⠀⠀
'@
 Write-Host $heart -ForegroundColor DarkRed
 Write-Host '              A-Shell has left the desktop.' -ForegroundColor DarkYellow
 Write-Host ''
}
if(!$Confirmed){
 Write-Host ''
 Write-Host '  A-SHELL  UNINSTALL' -ForegroundColor DarkYellow
 Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
 Write-Host '  Restore Windows, remove startup/terminal integration, then delete A-Shell.' -ForegroundColor Gray
 $answer=Read-Host '  Uninstall A-Shell completely? [Y/N]'
 if($answer -notmatch '^(?i:y|yes)$'){Write-Host '  Cancelled.' -ForegroundColor Gray;exit 0}
 $Confirmed=$true
}
$admin=Test-AShellAdministrator
if(!$admin){
 Write-Host '  WORKING  Requesting administrator access to restore Windows in this terminal...' -ForegroundColor Yellow
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters @{Confirmed=$true;ElevatedWorker=$true;ExpectedSid=$ExpectedSid} -Title 'A-Shell Uninstall - Administrator'
 if($exitCode){throw "Uninstall restore failed (exit $exitCode). A-Shell files were kept so recovery remains possible. See state\setup.log."}
 Write-AShellFarewell
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched to another Windows account.'}
if(!(Test-Path -LiteralPath (Join-Path $root 'state\\before-setup.clixml'))){throw 'The original A-Shell recovery state is missing. Refusing to delete the program before Windows can be restored.'}
# Comprehensive installer-grade restore first. If this fails, keep files intact.
& (Join-Path $PSScriptRoot 'Setup.ps1') -Action Restore -ExpectedSid $ExpectedSid
try {& (Join-Path $PSScriptRoot 'Manage.ps1') -Action Remove}catch{}
try {& (Join-Path $PSScriptRoot 'Terminal.ps1') -Action Restore}catch{}
try {Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'A-Shell') -Recurse -Force -ErrorAction SilentlyContinue}catch{}
try {
 $wh64=Join-Path $env:ProgramData 'Windhawk\Engine\Mods\64'
 $whsrc=Join-Path $env:ProgramData 'Windhawk\ModsSource'
 foreach($file in @('ashell-lockscreen-clear-background_1.9.dll','ashell-lockscreen-clear-background_1.8.dll','ashell-signin-clear-background_1.0.dll','windows-11-taskbar-styler_1.9_ashell_identity1.dll')){Remove-Item -LiteralPath (Join-Path $wh64 $file) -Force -ErrorAction SilentlyContinue}
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
