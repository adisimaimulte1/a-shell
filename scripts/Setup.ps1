param([ValidateSet('Apply','Restore','Check')][string]$Action='Apply',[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),[switch]$Core)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$stateDir=Join-Path $root 'state'
$snapshot=Join-Path $stateDir 'before-setup.clixml'
$modKey='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
$modNative='HKLM\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
$image=Join-Path $root 'assets\LockScreenPicture.png'
$exe=Join-Path $root 'bin\MatrixDesktop.exe'
$windhawk=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
$desired=@(
 @('HKCU:\Control Panel\Desktop','WallpaperStyle','String','10'),
 @('HKCU:\Control Panel\Desktop','TileWallpaper','String','0'),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','AppsUseLightTheme','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','SystemUsesLightTheme','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency','DWord',1),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','ColorPrevalence','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarAl','DWord',1),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','ShowTaskViewButton','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarDa','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode','DWord',1),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsSystemCurationEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled','DWord',0),
 @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','DisableAcrylicBackgroundOnLogon','DWord',1),
 @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableLogonBackgroundImage','DWord',0),
 @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableAutomaticRestartSignOn','DWord',1)
)
. (Join-Path $PSScriptRoot 'Setup.Support.ps1')
$useFullAppearance=(!( $Core ) -and (Get-AShellCapabilities).Full)
if($Action -in @('Apply','Check')) {Assert-AShellPackage $root -RequireCompatible}
if($Action -eq 'Check') {Write-Output 'Check completed without changing appearance settings.';exit 0}
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
 Write-Output "[WORKING] A-Shell $Action. Approve the administrator prompt; progress is saved in state\setup.log."
 $coreArgument=if($Core){' -Core'}else{''}
 $p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$Action+' -ExpectedSid '+$ExpectedSid+$coreArgument) -Wait -PassThru
 if($p.ExitCode -ne 0){Write-Error 'Setup did not finish. See state\setup.log.'}
 else {Write-Output "[OK] A-Shell $Action completed. Original backups are preserved. Full details: $stateDir\setup.log"}
 exit $p.ExitCode
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Run setup from the account being customized; elevation switched to a different account.'}
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$checkpoint=$null
$appearanceStarted=$false
Start-Transcript -Path (Join-Path $stateDir 'setup.log') -Append | Out-Null
try {
 . (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
 . (Join-Path $PSScriptRoot 'Desktop.Support.ps1')
 . (Join-Path $PSScriptRoot 'Background.Support.ps1')
 . (Join-Path $PSScriptRoot 'Icons.Support.ps1')
 Enter-AShellOperation
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $checkpoint=Join-Path $stateDir ('runs\'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
 Save-AShellCheckpoint $checkpoint $desired
 if($Action -eq 'Apply'){Save-AShellDesktop $root}
 # Capture every component together, before wallpaper/theme changes can also
 # change derived accent settings. Never replace an existing original backup.
 if($Action -eq 'Apply' -and !(Test-Path $snapshot) -and !(Test-Path (Join-Path $stateDir 'baseline\checkpoint.clixml'))) {
  $baseline=Join-Path $stateDir 'baseline'
  New-Item -ItemType Directory $baseline -Force | Out-Null
  Get-ChildItem -LiteralPath $checkpoint -File | Where-Object {$_.Name -ne 'checkpoint.clixml'} | Copy-Item -Destination $baseline
  Copy-Item -LiteralPath (Join-Path $checkpoint 'checkpoint.clixml') -Destination $baseline
 }
 if($Action -eq 'Apply') {
  if(!(Test-Path $image)){throw 'LockScreenPicture.png is missing.'}
  $meta=Get-Content (Join-Path $root 'assets\windhawk\mod.json') -Raw | ConvertFrom-Json
  $modDestination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$meta.LibraryFileName)
  $sourceDestination=Join-Path $env:ProgramData 'Windhawk\ModsSource\windows-11-taskbar-styler.wh.cpp'
  if(!(Test-Path $snapshot)) {
   $values=@(foreach($v in $desired){Read-RegistryValue $v[0] $v[1]})
   # The wallpaper cache is needed when the old source has been moved/deleted.
   $wallpaper=(Get-ItemProperty 'HKCU:\Control Panel\Desktop').Wallpaper
   $cached=Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
   if($wallpaper -and (Test-Path -LiteralPath $wallpaper)){Copy-Item -LiteralPath $wallpaper -Destination (Join-Path $stateDir 'desktop-before.img')}
   elseif(Test-Path $cached){Copy-Item $cached (Join-Path $stateDir 'desktop-before.img')}
   Save-LockImage (Join-Path $stateDir 'lock-before.img')
   $tasks=@(foreach($name in @('Matrix Desktop - Instant Rain','Codex Early Lively Wallpaper','Lively Wallpaper - Adi')) {
    $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    @{Name=$name;Exists=($null -ne $task);Xml=$(if($task){Export-ScheduledTask -TaskName $name});Running=($task.State -eq 'Running')}
   })
   $hadMod=Test-Path $modKey
   if($hadMod){ & reg.exe export $modNative (Join-Path $stateDir 'taskbar-before.reg') /y | Out-Null; if($LASTEXITCODE){throw 'Cannot back up taskbar settings.'} }
   $files=@(foreach($path in @($modDestination,$sourceDestination)) {
    $exists=Test-Path -LiteralPath $path; $saved=Join-Path $stateDir ([IO.Path]::GetFileName($path)+'.before')
    if($exists){Copy-Item -LiteralPath $path -Destination $saved}
    @{Path=$path;Exists=$exists;Saved=$saved}
   })
   @{Sid=$sid;Values=$values;Wallpaper=$wallpaper;Tasks=$tasks;HadMod=$hadMod;HadWindhawk=(Test-Path $windhawk);Files=$files} | Export-Clixml -LiteralPath $snapshot
  }
  $before=Import-Clixml $snapshot
  if($before.Sid -ne $sid){throw 'This backup belongs to another Windows account. Use a fresh package copy.'}
  $appearanceStarted=$true
  if($useFullAppearance){Ensure-Windhawk $root}
  else {Write-Output 'Applying the core appearance. Windows 11-only mods and binary patches are not installed in this mode.'}
  foreach($v in $desired){Write-RegistryValue @{Path=$v[0];Name=$v[1];Kind=$v[2];Value=$v[3];Exists=$true}}
  Set-DesktopImage $image
  Set-LockImage $image
  & (Join-Path $PSScriptRoot 'Color.ps1') -Color default
  if($useFullAppearance) {
  foreach($path in @($modDestination,$sourceDestination)){New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null}
  # Avoid replacing a loaded DLL when this exact version already exists.
  $payload=Join-Path $root ('assets\windhawk\'+$meta.LibraryFileName)
  if(!(Test-Path $modDestination) -or (Get-FileHash $payload).Hash -ne (Get-FileHash $modDestination).Hash){Copy-Item $payload $modDestination -Force}
  Copy-Item (Join-Path $root 'assets\windhawk\windows-11-taskbar-styler.wh.cpp') $sourceDestination -Force
  foreach($entry in @{LibraryFileName=$meta.LibraryFileName;Version=$meta.Version;Include='explorer.exe';Exclude='';Architecture='x86-64'}.GetEnumerator()) {
   Write-RegistryValue @{Path=$modKey;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
  }
  Write-RegistryValue @{Path=$modKey;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
  . (Join-Path $PSScriptRoot 'Icon.Selection.ps1')
  Add-AShellAutomaticIcons $root
  Update-AShellIcons $root
  }
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Apply
  & (Join-Path $PSScriptRoot 'Manage.ps1') -Action Install
  if($useFullAppearance){& (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Apply -NoRestart}
  & (Join-Path $PSScriptRoot 'Terminal.ps1') -Action Install
  Assert-AShellInstalled $root $desired -Core:(!$useFullAppearance)
  Send-AShellThemeChange
  if($useFullAppearance){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
  Set-Content (Join-Path $stateDir 'applied.txt') (Get-Date -Format o)
  Set-AShellDesktopArchived $root
  Write-Output 'A-Shell applied. Sign out and back in to fully refresh taskbar styling. Restart to check the lock-screen transition.'
 } else {
  if(!(Test-Path $snapshot)){throw 'No saved pre-setup settings exist in this package.'}
  $before=Import-Clixml $snapshot
  if($before.Sid -ne $sid){throw 'The backup belongs to another Windows account.'}
  $appearanceStarted=$true
  Stop-AShellRendererForRestore $root -PauseStartup
  Restore-AShellBackground (Join-Path $stateDir 'background-before')
  if(Test-Path (Join-Path $stateDir 'signin-backdrop-before.clixml')) {
   & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Restore -NoRestart
  }
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Restore
  & (Join-Path $PSScriptRoot 'Color.ps1') -Action Restore
  foreach($value in $before.Values){Write-RegistryValue $value}
  if($before.Wallpaper -and (Test-Path -LiteralPath $before.Wallpaper)){Set-DesktopImage $before.Wallpaper}
  elseif(Test-Path (Join-Path $stateDir 'desktop-before.img')){Set-DesktopImage (Join-Path $stateDir 'desktop-before.img')}
  else {Set-DesktopImage ''}
  Set-LockImage (Join-Path $stateDir 'lock-before.img')
  # SetImageFileAsync can change personalization preferences; restore them last.
  foreach($value in $before.Values){Write-RegistryValue $value}
  if(Test-Path $modKey){Remove-Item -LiteralPath $modKey -Recurse -Force}
  if($before.HadMod){ & reg.exe import (Join-Path $stateDir 'taskbar-before.reg') | Out-Null; if($LASTEXITCODE){throw 'Taskbar restore failed.'} }
  foreach($file in $before.Files) {
   if($file.Exists -and ((Get-FileHash $file.Path -ErrorAction SilentlyContinue).Hash -ne (Get-FileHash $file.Saved).Hash)){Copy-Item -LiteralPath $file.Saved -Destination $file.Path -Force}
   # Unreferenced mod payloads can remain harmlessly; do not delete a loaded DLL.
  }
  foreach($task in $before.Tasks) {
   if($task.Exists){Register-ScheduledTask -TaskName $task.Name -Xml $task.Xml -Force | Out-Null; if($task.Running){Start-ScheduledTask -TaskName $task.Name}}
   elseif(Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false}
  }
  if(Test-Path (Join-Path $stateDir 'baseline\checkpoint.clixml')) {
   Restore-AShellCheckpoint (Join-Path $stateDir 'baseline') $root
  }
  & (Join-Path $PSScriptRoot 'Terminal.ps1') -Action Restore
  Restore-AShellDesktop $root
  Send-AShellThemeChange
  if(Test-Path $windhawk){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
  Write-Output 'Previous appearance and startup settings restored. Sign out and back in to fully refresh. Saved backups are retained.'
  if(!$before.HadWindhawk -and (Test-Path $windhawk)){Write-Output 'Windhawk is retained so other mods are not disrupted. You can uninstall it from Installed apps if it is no longer needed.'}
 }
} catch {
 Write-Output ('FAILED: '+$_)
 if($appearanceStarted -and $checkpoint -and (Test-Path (Join-Path $checkpoint 'checkpoint.clixml'))) {
  try {Restore-AShellCheckpoint $checkpoint $root -RestoreTerminal;Write-Output 'Appearance rolled back to the state immediately before this run.'}
  catch {Write-Output ('Automatic rollback needs attention: '+$_+'; checkpoint: '+$checkpoint)}
 }
 Write-Output 'The original backup and this run checkpoint are preserved. See state\setup.log.'
 exit 1
} finally {Exit-AShellOperation;Stop-Transcript | Out-Null}
