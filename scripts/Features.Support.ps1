$ErrorActionPreference='Stop'

function Get-AShellFeatureConfigPath([string]$Root) { Join-Path $Root 'state\features.json' }
function Get-AShellRuntimeStatePath([string]$Root) { Join-Path $Root 'state\runtime-state.json' }
function Get-AShellFeatureConfig([string]$Root) {
 $defaults=[ordered]@{version=2;screens=$true;taskbarTransparency=$true;icons=$true}
 $path=Get-AShellFeatureConfigPath $Root
 if(Test-Path -LiteralPath $path) {
  try {
   $data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
   if($null -ne $data.screens){$defaults.screens=[bool]$data.screens}
   if($null -ne $data.taskbarTransparency){$defaults.taskbarTransparency=[bool]$data.taskbarTransparency}
   if($null -ne $data.icons){$defaults.icons=[bool]$data.icons}
  } catch {Write-Warning 'The saved component configuration was invalid. A-Shell is using safe defaults until it is rewritten.'}
 }
 return [pscustomobject]$defaults
}
function Save-AShellFeatureConfig([string]$Root,$Config) {
 $path=Get-AShellFeatureConfigPath $Root
 New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
 $normalized=[ordered]@{
  version=2
  screens=[bool]$Config.screens
  taskbarTransparency=[bool]$Config.taskbarTransparency
  icons=[bool]$Config.icons
 }
 $json=$normalized | ConvertTo-Json -Depth 3
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
 if(Test-Path -LiteralPath $path){Move-Item -LiteralPath $tmp -Destination $path -Force}else{Move-Item -LiteralPath $tmp -Destination $path}
}
function Set-AShellRuntimeState([string]$Root,[bool]$Active,[string]$Reason='') {
 $path=Get-AShellRuntimeStatePath $Root
 New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
 [ordered]@{version=1;active=$Active;changed=(Get-Date -Format o);reason=$Reason} | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
}
function Test-AShellRuntimeActive([string]$Root) {
 $path=Get-AShellRuntimeStatePath $Root
 if(Test-Path -LiteralPath $path){try{return [bool]((Get-Content -LiteralPath $path -Raw|ConvertFrom-Json).active)}catch{}}
 # v1.6 and earlier didn't have a runtime-state file. A successful setup means active.
 return (Test-Path -LiteralPath (Join-Path $Root 'state\applied.txt'))
}
function Get-AShellDesiredBackground([string]$Root) {
 $path=Join-Path $Root 'state\desired-background.txt'
 if(Test-Path -LiteralPath $path){$value=(Get-Content -LiteralPath $path -Raw).Trim();if($value){return $value}}
 return (Join-Path $Root 'assets\LockScreenPicture.png')
}
function Set-AShellDesiredBackground([string]$Root,[string]$Value) {
 $path=Join-Path $Root 'state\desired-background.txt';New-Item -ItemType Directory -Path (Split-Path $path) -Force|Out-Null
 Set-Content -LiteralPath $path -Value $Value -Encoding UTF8
}
function Get-AShellDesiredAccent([string]$Root) {
 $path=Join-Path $Root 'state\desired-accent.txt'
 if(Test-Path -LiteralPath $path){$value=(Get-Content -LiteralPath $path -Raw).Trim();if($value -match '^[0-9A-Fa-f]{6}$'){return $value.ToUpperInvariant()}}
 return 'D65A00'
}
function Set-AShellDesiredAccent([string]$Root,[string]$Value) {
 $path=Join-Path $Root 'state\desired-accent.txt';New-Item -ItemType Directory -Path (Split-Path $path) -Force|Out-Null
 Set-Content -LiteralPath $path -Value $Value.ToUpperInvariant() -Encoding ascii
}
function Get-AShellBeforeSetup([string]$Root) {
 $path=Join-Path $Root 'state\before-setup.clixml'
 if(!(Test-Path -LiteralPath $path)){throw 'This installation has no original appearance backup. Run the A-Shell Setup EXE once before using start/stop.'}
 $before=Import-Clixml -LiteralPath $path
 if($before.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'The original appearance backup belongs to another Windows account.'}
 return $before
}
function Get-AShellCoreRuntimeValues {
 @(
  @('HKCU:\Control Panel\Desktop','WallpaperStyle','String','10'),
  @('HKCU:\Control Panel\Desktop','TileWallpaper','String','0'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','AppsUseLightTheme','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','SystemUsesLightTheme','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency','DWord',1),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','ColorPrevalence','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarAl','DWord',1),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','ShowTaskViewButton','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode','DWord',1),
  @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableAutomaticRestartSignOn','DWord',1)
 )
}
function Get-AShellScreenRuntimeValues {
 @(
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsSystemCurationEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338387Enabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','DetailedStatusApp','String',''),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh','DisableWidgetsOnLockScreen','DWord',1),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','DisableAcrylicBackgroundOnLogon','DWord',1)
 )
}
function Write-AShellRuntimeValues($Values) {
 foreach($v in $Values){Write-RegistryValue @{Path=$v[0];Name=$v[1];Kind=$v[2];Value=$v[3];Exists=$true}}
}
function Restore-AShellOriginalSetupValues([string]$Root) {
 $before=Get-AShellBeforeSetup $Root
 foreach($value in @($before.Values)){Write-RegistryValue $value}
 if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
}
function Get-AShellOriginalDesktopImage([string]$Root) {
 # The baseline checkpoint is captured before ANY A-Shell mutation and is the
 # authoritative fallback across upgrades. Prefer it over legacy desktop-before.img.
 $baseline=Join-Path $Root 'state\baseline\desktop.img'
 if(Test-Path -LiteralPath $baseline){return $baseline}
 $before=Get-AShellBeforeSetup $Root
 if($before.Wallpaper -and (Test-Path -LiteralPath $before.Wallpaper)){return [string]$before.Wallpaper}
 $cached=Join-Path $Root 'state\desktop-before.img'
 if(Test-Path -LiteralPath $cached){return $cached}
 return ''
}
function Get-AShellOriginalLockImage([string]$Root) {
 $baseline=Join-Path $Root 'state\baseline\lock.img'
 if(Test-Path -LiteralPath $baseline){return $baseline}
 $path=Join-Path $Root 'state\lock-before.img'
 if(Test-Path -LiteralPath $path){return $path}
 return $null
}
function Resolve-AShellRuntimeBackground([string]$Root,[switch]$OriginalDesktop) {
 $desired=Get-AShellDesiredBackground $Root
 if($desired -eq 'original' -or $OriginalDesktop){return Get-AShellOriginalDesktopImage $Root}
 if(Test-Path -LiteralPath $desired -PathType Leaf){return $desired}
 $fallback=Join-Path $Root 'assets\LockScreenPicture.png'
 if(Test-Path -LiteralPath $fallback){return $fallback}
 throw 'The saved A-Shell background no longer exists and the bundled default image is missing.'
}

function Install-AShellPendingMatrixUpdate([string]$Root) {
 $pending=Join-Path $Root 'bin\MatrixDesktop.exe.pending'
 if(!(Test-Path -LiteralPath $pending)){return $false}
 $exe=Join-Path $Root 'bin\MatrixDesktop.exe'
 $running=@((Get-Process MatrixDesktop -ErrorAction SilentlyContinue) | Where-Object {try{[IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($exe)}catch{$false}})
 if($running.Count){return $false}
 Move-Item -LiteralPath $pending -Destination $exe -Force
 Write-Output '[OK] Pending Matrix executable update applied before rain startup.'
 return $true
}

function Set-AShellRainRuntime([string]$Root,[bool]$Enabled) {
 $taskName='Matrix Desktop - Instant Rain';$exe=Join-Path $Root 'bin\MatrixDesktop.exe'
 $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 if($Enabled){
  [void](Install-AShellPendingMatrixUpdate $Root)
  if(!$task){& (Join-Path $PSScriptRoot 'Manage.ps1') -Action Install;return}
  if($task.Actions.Execute -notcontains $exe){throw 'The Matrix startup task belongs to another A-Shell copy. Repair this installation with the Setup EXE.'}
  Enable-ScheduledTask -TaskName $taskName | Out-Null
  & (Join-Path $PSScriptRoot 'Manage.ps1') -Action Start
 } else {
  if($task -and $task.Actions.Execute -contains $exe){Disable-ScheduledTask -TaskName $taskName | Out-Null}
  $running=@(Get-Process MatrixDesktop -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $exe})
  if($running.Count){& (Join-Path $PSScriptRoot 'Manage.ps1') -Action Stop}
  else {Write-Output '[OK] Rain is already stopped. Automatic A-Shell rain startup is disabled until ashell start.'}
 }
}
function Restart-AShellWindhawkRuntime {
 $windhawk=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if(Test-Path -LiteralPath $windhawk){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden | Out-Null}
}
function Restore-AShellTaskbarBaseline([string]$Root) {
 $baseline=Join-Path $Root 'state\baseline\checkpoint.clixml'
 if(!(Test-Path -LiteralPath $baseline)){
  $before=Get-AShellBeforeSetup $Root
  $key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
  if(Test-Path -LiteralPath $key){Remove-Item -LiteralPath $key -Recurse -Force}
  if($before.HadMod -and (Test-Path -LiteralPath (Join-Path $Root 'state\taskbar-before.reg'))){& reg.exe import (Join-Path $Root 'state\taskbar-before.reg')|Out-Null}
  return
 }
 $saved=Import-Clixml -LiteralPath $baseline
 $tree=@($saved.Trees | Where-Object {$_.Path -eq 'HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'}) | Select-Object -First 1
 if($tree){Restore-AShellTree $tree}
}
function Set-AShellTaskbarRuntime([string]$Root,[bool]$Transparency,[bool]$Icons,[switch]$NoRestart) {
 Restore-AShellTaskbarBaseline $Root
 if(!$Transparency -and !$Icons){if(!$NoRestart){Restart-AShellWindhawkRuntime};Write-Output '[OK] Taskbar styling restored to its pre-A-Shell configuration.';return}
 $meta=Get-Content -LiteralPath (Join-Path $Root 'assets\windhawk\mod.json') -Raw|ConvertFrom-Json
 $mod='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
 $dll=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$meta.LibraryFileName)
 if(!(Test-Path -LiteralPath $dll)){throw 'The installed A-Shell taskbar Windhawk payload is missing. Run the Setup EXE to repair program integrations.'}
 foreach($entry in @{LibraryFileName=$meta.LibraryFileName;Version=$meta.Version;Include='explorer.exe';Exclude='';Architecture='x86-64'}.GetEnumerator()){
  Write-RegistryValue @{Path=$mod;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
 }
 Write-RegistryValue @{Path=$mod;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
 if($Transparency){
  $base=Get-Content -LiteralPath (Join-Path $Root 'assets\taskbar-base.json') -Raw|ConvertFrom-Json
  foreach($p in $base.PSObject.Properties){Write-RegistryValue @{Path="$mod\Settings";Name=$p.Name;Kind='String';Value=[string]$p.Value;Exists=$true}}
 }
 if($Icons){Update-AShellIcons $Root -SkipTaskbarBase -PreserveUnlisted}
 $stamp=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
 Write-RegistryValue @{Path=$mod;Name='SettingsChangeTime';Kind='DWord';Value=$stamp;Exists=$true}
 if(!$NoRestart){Restart-AShellWindhawkRuntime}
 Write-Output ('[OK] Taskbar components: transparency={0}; icon replacement={1}.' -f $(if($Transparency){'on'}else{'off'}),$(if($Icons){'on'}else{'off'}))
}
function Test-AShellScreenSetting([string]$Path,[string]$Name) {
 $id=(Get-AShellRegistrySettingId $Path $Name)
 return $id -in @(
  'hkcu:\software\microsoft\windows\currentversion\lock screen|lockscreenwidgetsenabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|lockscreenwidgetssystemcurationenabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|slideshowenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|rotatinglockscreenenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|rotatinglockscreenoverlayenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|subscribedcontent-338387enabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|detailedstatusapp',
  'hklm:\software\policies\microsoft\dsh|disablewidgetsonlockscreen',
  'hklm:\software\policies\microsoft\windows\system|disableacrylicbackgroundonlogon',
  'hklm:\software\policies\microsoft\windows\system|disablelogonbackgroundimage',
  'hklm:\software\policies\microsoft\windows\personalization|nochanginglockscreen',
  'hklm:\software\policies\microsoft\windows\personalization|nolockscreen',
  'hklm:\software\policies\microsoft\windows\personalization|nolockscreenslideshow',
  'hklm:\software\policies\microsoft\windows\personalization|lockscreenimage',
  'hklm:\software\microsoft\windows\currentversion\personalizationcsp|lockscreenimagepath',
  'hklm:\software\microsoft\windows\currentversion\personalizationcsp|lockscreenimageurl'
 )
}
function Restore-AShellScreenBaseline([string]$Root,[switch]$NoRestart) {
 # Disable/restore visual-tree mods first, then release A-Shell's forced image long
 # enough for the supported LockScreen API to put the original image back.
 $screenSnapshot=Join-Path $Root 'state\signin-backdrop-before.clixml'
 if(Test-Path -LiteralPath $screenSnapshot){& (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Restore -NoRestart}
 [void](Release-AShellLockScreenPolicyBlockers)
 $lock=Get-AShellOriginalLockImage $Root
 if($lock){Set-LockImage $lock}
 $before=Get-AShellBeforeSetup $Root
 foreach($value in @($before.Values)){if(Test-AShellScreenSetting $value.Path $value.Name){Write-RegistryValue $value}}
 if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
 if(!$NoRestart){Restart-AShellWindhawkRuntime}
 Write-Output '[OK] Lock/sign-in image, shading, acrylic and saved personalization policy values restored.'
}
function Set-AShellScreenRuntime([string]$Root,[bool]$Enabled,[switch]$NoRestart) {
 if(!$Enabled){Restore-AShellScreenBaseline $Root -NoRestart:$NoRestart;return}
 $target=Resolve-AShellRuntimeBackground $Root
 if($target -eq ''){throw 'A-Shell screens cannot use an empty image. Choose a background or use the bundled default.'}
 $handoff=Get-AShellLockScreenPolicyHandoff
 if(@($handoff.Entries).Count){
  if(!(Test-AShellLockScreenOverrideConsent $Root)){throw 'Windows lock-screen policy is blocking A-Shell. Run the Setup EXE again and approve the explicit lock-screen policy override.'}
  foreach($entry in @(Get-AShellLockScreenOverrideValues $handoff $target)){Write-RegistryValue $entry}
  if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
 }
 Write-AShellRuntimeValues (Get-AShellScreenRuntimeValues)
 Set-LockImage $target
 & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Apply -NoRestart -RuntimeOnly
 if(!$NoRestart){Restart-AShellWindhawkRuntime}
 Write-Output '[OK] Lock + sign-in screen customization enabled, including the dim/black overlay removal rules.'
}
function Write-AShellComponentStatus([string]$Root) {
 $cfg=Get-AShellFeatureConfig $Root
 Write-Output ('[STATUS] A-Shell overall: '+$(if(Test-AShellRuntimeActive $Root){'started'}else{'stopped'}))
 Write-Output ('[STATUS] screen: '+$(if($cfg.screens){'on  (A-Shell image, filters removed)'}else{'off (original Windows image/effects)'}))
 Write-Output ('[STATUS] taskbar: '+$(if($cfg.taskbarTransparency){'on'}else{'off'}))
 Write-Output ('[STATUS] icons: '+$(if($cfg.icons){'on'}else{'off'})+'  (taskbar/start/search/app replacements)')
 Write-Output '[STATUS] desktop: hidden while A-Shell is started  (fixed A-Shell design)'
}
