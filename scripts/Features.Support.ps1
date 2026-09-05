$ErrorActionPreference='Stop'

function Get-AShellFeatureConfigPath([string]$Root) { Join-Path $Root 'state\features.json' }
function Get-AShellRuntimeStatePath([string]$Root) { Join-Path $Root 'state\runtime-state.json' }
function Get-AShellFeatureConfig([string]$Root) {
 $defaults=[ordered]@{version=4;screens=$true;signInHook=$false;taskbarTransparency=$true;icons=$true;rain=$true}
 $path=Get-AShellFeatureConfigPath $Root
 if(Test-Path -LiteralPath $path) {
  try {
   $data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
   if($null -ne $data.screens){$defaults.screens=[bool]$data.screens}
   if($null -ne $data.signInHook){$defaults.signInHook=[bool]$data.signInHook}
   if($null -ne $data.taskbarTransparency){$defaults.taskbarTransparency=[bool]$data.taskbarTransparency}
   if($null -ne $data.icons){$defaults.icons=[bool]$data.icons}
   if($null -ne $data.rain){$defaults.rain=[bool]$data.rain}
  } catch {Write-Warning 'The saved component configuration was invalid. A-Shell is using safe defaults until it is rewritten.'}
 }
 return [pscustomobject]$defaults
}
function Save-AShellFeatureConfig([string]$Root,$Config) {
 $path=Get-AShellFeatureConfigPath $Root
 New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
 $normalized=[ordered]@{
  version=4
  screens=[bool]$Config.screens
  signInHook=$(if($null -ne $Config.signInHook){[bool]$Config.signInHook}else{$false})
  taskbarTransparency=[bool]$Config.taskbarTransparency
  icons=[bool]$Config.icons
  rain=$(if($null -ne $Config.rain){[bool]$Config.rain}else{$true})
 }
 $json=$normalized | ConvertTo-Json -Depth 3
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
 if(Test-Path -LiteralPath $path){Move-Item -LiteralPath $tmp -Destination $path -Force}else{Move-Item -LiteralPath $tmp -Destination $path}
}

function Set-AShellRainPreference([string]$Root,[bool]$Enabled) {
 $cfg=Get-AShellFeatureConfig $Root
 Save-AShellFeatureConfig $Root ([pscustomobject]@{
  version=4
  screens=[bool]$cfg.screens
  signInHook=[bool]$cfg.signInHook
  taskbarTransparency=[bool]$cfg.taskbarTransparency
  icons=[bool]$cfg.icons
  rain=$Enabled
 })
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
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','ColorPrevalence','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarAl','DWord',1),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','ShowTaskViewButton','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode','DWord',1),
  @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableAutomaticRestartSignOn','DWord',1)
 )
}
function Get-AShellScreenRuntimeValues {
 @(
  # Use Windows' supported machine policy for a clear sign-in background.
  # Do not disable the user's global Transparency Effects just to alter LogonUI;
  # A-Shell's XAML guard handles any remaining full-screen dim/scrim surface.
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsSystemCurationEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338387Enabled','DWord',0),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','DetailedStatusApp','String',''),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh','DisableWidgetsOnLockScreen','DWord',1),
  # This is Windows' supported "Prevent lock screen background motion" policy.
  # It drives the static/zoom-disabled lock-logon image path without disabling
  # authentication animations or the user's system-wide animation preference.
  @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization','AnimateLockScreenBackground','DWord',1),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','DisableAcrylicBackgroundOnLogon','DWord',1)
 )
}
function Write-AShellRuntimeValues($Values) {
 foreach($v in $Values){Write-RegistryValue @{Path=$v[0];Name=$v[1];Kind=$v[2];Value=$v[3];Exists=$true}}
}
function Test-AShellRuntimeValuesApplied($Values) {
 foreach($v in $Values) {
  $actual=Read-RegistryValue $v[0] $v[1]
  if(!$actual.Exists -or [string]$actual.Value -ne [string]$v[3]){return $false}
 }
 return $true
}
function Test-AShellScreenRuntimeApplied([string]$Root) {
 if(!(Test-AShellRuntimeValuesApplied (Get-AShellScreenRuntimeValues))){return $false}
 $cfg=Get-AShellFeatureConfig $Root
 # Essentials/Core profiles intentionally use only the native Windows lock/sign-in
 # settings and do not install Windhawk. Treat that as a valid applied state.
 if(!$cfg.signInHook){return $true}
 $caps=Get-AShellCapabilities
 if(!$caps.SignInOverlay){return $false}

 # LogonUI is handled only by the narrow verified backdrop hook. It must never
 # share LogonUI with the broader LockApp styling module.
 $signInMod='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-signin-clear-background'
 if(!(Test-Path -LiteralPath $signInMod)){return $false}
 $signInConfig=Get-ItemProperty -LiteralPath $signInMod -ErrorAction SilentlyContinue
 if(!$signInConfig -or [int]$signInConfig.Disabled -ne 0 -or [string]$signInConfig.Version -ne '1.0'){return $false}
 if([string]$signInConfig.Include -notmatch '(?i)LogonUI\.exe'){return $false}
 try {$signInPayload=Get-AShellSignInPayloadInfo $Root}catch{return $false}
 if([string]$signInConfig.LibraryFileName -ne [string]$signInPayload.LibraryFileName){return $false}
 $signInInstalled=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$signInPayload.LibraryFileName)
 if(!(Test-Path -LiteralPath $signInInstalled -PathType Leaf)){return $false}
 if((Get-FileHash -LiteralPath $signInInstalled).Hash -ne (Get-FileHash -LiteralPath $signInPayload.SourcePath).Hash){return $false}

 if(!$caps.Windows11){return $true}
 $mod='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-lockscreen-clear-background'
 if(!(Test-Path -LiteralPath $mod)){return $false}
 $config=Get-ItemProperty -LiteralPath $mod -ErrorAction SilentlyContinue
 if(!$config -or [int]$config.Disabled -ne 0 -or [string]$config.Version -ne '1.7'){return $false}
 $payload=Join-Path $Root 'assets\windhawk\ashell-lockscreen-clear-background_1.7.dll'
 if(!(Test-Path -LiteralPath $payload -PathType Leaf)){return $false}
 $payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()
 $expectedLibrary='ashell-lockscreen-clear-background_1.7_'+$payloadHash.Substring(0,12)+'.dll'
 if([string]$config.LibraryFileName -ne $expectedLibrary){return $false}
 $installed=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$expectedLibrary)
 if(!(Test-Path -LiteralPath $installed -PathType Leaf)){return $false}
 if((Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $payload).Hash){return $false}
 $include=[string]$config.Include
 if($include -notmatch '(?i)LockApp\.exe' -or $include -match '(?i)LogonUI\.exe'){return $false}
 return $true
}
function Test-AShellTaskbarRuntimeApplied([string]$Root,[bool]$Transparency,[bool]$Icons) {
 if(!$Transparency -and !$Icons){return $true}
 $mod='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
 if(!(Test-Path -LiteralPath $mod)){return $false}
 $config=Get-ItemProperty -LiteralPath $mod -ErrorAction SilentlyContinue
 if(!$config -or [int]$config.Disabled -ne 0){return $false}
 if($Transparency) {
  $base=Get-Content -LiteralPath (Join-Path $Root 'assets\taskbar-base.json') -Raw | ConvertFrom-Json
  foreach($property in $base.PSObject.Properties) {
   $actual=Read-RegistryValue ($mod+'\Settings') $property.Name
   if(!$actual.Exists -or [string]$actual.Value -ne [string]$property.Value){return $false}
  }
 }
 if($Icons -and (Test-Path -LiteralPath (Join-Path $Root 'state\icons-refresh.pending'))){return $false}
 return $true
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
 # Rain preference lives in features.json; the scheduled task is only the optional
 # sign-in launcher. Do not enable/install/disable that task here, otherwise a
 # global start/stop silently changes the user's saved startup choice.
 if($Enabled){
  [void](Install-AShellPendingMatrixUpdate $Root)
  & (Join-Path $PSScriptRoot 'Manage.ps1') -Action Start
 } else {
  & (Join-Path $PSScriptRoot 'Manage.ps1') -Action Stop
 }
}
function Restart-AShellWindhawkRuntime {
 $windhawk=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if(Test-Path -LiteralPath $windhawk){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden | Out-Null}
}
function Test-AShellTaskbarModuleLoaded([string]$LibraryFileName) {
 if(!$LibraryFileName){return $false}
 foreach($process in @(Get-Process explorer -ErrorAction SilentlyContinue)) {
  try {
   foreach($module in @($process.Modules)) {
    if([string]::Equals([IO.Path]::GetFileName([string]$module.FileName),$LibraryFileName,[StringComparison]::OrdinalIgnoreCase)){return $true}
   }
  } catch {}
 }
 return $false
}
function Ensure-AShellTaskbarRuntimeLoaded([string]$Root,[int]$WaitMilliseconds=1200) {
 $mod='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
 if(!(Test-Path -LiteralPath $mod)){return}
 $config=Get-ItemProperty -LiteralPath $mod -ErrorAction SilentlyContinue
 if(!$config -or [int]$config.Disabled -ne 0){return}
 $library=[string]$config.LibraryFileName
 if(!$library){return}
 $deadline=(Get-Date).AddMilliseconds($WaitMilliseconds)
 do {
  if(Test-AShellTaskbarModuleLoaded $library){Write-Output '[OK] Taskbar styling hot-applied without restarting Windhawk.';return}
  Start-Sleep -Milliseconds 100
 } while((Get-Date) -lt $deadline)
 # SettingsChangeTime is the normal zero-flicker path. Restart only as a fallback
 # when the module genuinely failed to load (for example immediately after a
 # first Windhawk install), and do it before Matrix rain starts.
 Write-Output '[WORKING] Windhawk taskbar module did not hot-load; performing one fallback engine reload before rain starts...'
 Restart-AShellWindhawkRuntime
 $deadline=(Get-Date).AddMilliseconds(1800)
 do {
  if(Test-AShellTaskbarModuleLoaded $library){Write-Output '[OK] Windhawk taskbar module loaded.';return}
  Start-Sleep -Milliseconds 120
 } while((Get-Date) -lt $deadline)
 Write-Warning 'Windhawk taskbar styling is configured but its module could not be confirmed in Explorer. The next Explorer/sign-in start can load it normally.'
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
 if($Icons){Update-AShellIcons $Root -SkipTaskbarBase -PreserveUnlisted -DeferApply}
 # Commit transparency + icon changes as one Windhawk settings transaction. The
 # old path could notify once from Update-AShellIcons and immediately notify again
 # here, forcing two taskbar-style reinitializations.
 $current=Read-RegistryValue $mod 'SettingsChangeTime'
 $stamp=[uint32]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
 if($current.Exists -and [uint32]$current.Value -ge $stamp){$stamp=[uint32]$current.Value+1}
 Write-RegistryValue @{Path=$mod;Name='SettingsChangeTime';Kind='DWord';Value=$stamp;Exists=$true}
 $pending=Join-Path $Root 'state\icons-refresh.pending'
 if($Icons -and (Test-Path -LiteralPath $pending)){Remove-Item -LiteralPath $pending -Force}
 if(!$NoRestart){Restart-AShellWindhawkRuntime}
 Write-Output ('[OK] Taskbar components: transparency={0}; icon replacement={1}.' -f $(if($Transparency){'on'}else{'off'}),$(if($Icons){'on'}else{'off'}))
}
function Test-AShellScreenSetting([string]$Path,[string]$Name) {
 $id=(Get-AShellRegistrySettingId $Path $Name)
 return $id -in @(
  'hkcu:\software\microsoft\windows\currentversion\themes\personalize|enabletransparency',
  'hkcu:\software\microsoft\windows\currentversion\themes\personalize|enabledblurbehind',
  'registry::hkey_users\.default\software\microsoft\windows\currentversion\themes\personalize|enabletransparency',
  'registry::hkey_users\.default\software\microsoft\windows\currentversion\themes\personalize|enabledblurbehind',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|lockscreenwidgetsenabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|lockscreenwidgetssystemcurationenabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|slideshowenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|rotatinglockscreenenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|rotatinglockscreenoverlayenabled',
  'hkcu:\software\microsoft\windows\currentversion\contentdeliverymanager|subscribedcontent-338387enabled',
  'hkcu:\software\microsoft\windows\currentversion\lock screen|detailedstatusapp',
  'hklm:\software\policies\microsoft\dsh|disablewidgetsonlockscreen',
  'hklm:\software\policies\microsoft\windows\personalization|animatelockscreenbackground',
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
function Restore-AShellLegacyScreenMaterialOverrides([string]$Root) {
 # r4 and earlier temporarily forced global Transparency Effects off as a
 # workaround for LogonUI. r6 and later no longer own that user preference: restore the
 # exact pre-A-Shell values once, if an older active install left them changed.
 $before=Get-AShellBeforeSetup $Root
 $wanted=@(
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnabledBlurBehind'),
  @('Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency'),
  @('Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnabledBlurBehind')
 )
 $changed=$false
 foreach($item in $wanted) {
  $saved=@($before.Values | Where-Object {$_.Path -eq $item[0] -and $_.Name -eq $item[1]}) | Select-Object -First 1
  if(!$saved){continue}
  $current=Read-RegistryValue $saved.Path $saved.Name
  $different=($current.Exists -ne [bool]$saved.Exists)
  if(!$different -and $saved.Exists){$different=([string]$current.Value -ne [string]$saved.Value)}
  if($different){Write-RegistryValue $saved;$changed=$true}
 }
 if($changed -and (Get-Command Send-AShellMaterialPreferenceChange -ErrorAction SilentlyContinue)){Send-AShellMaterialPreferenceChange}
 return $changed
}
function Restore-AShellScreenBaseline([string]$Root,[switch]$NoRestart) {
 # Disable/restore screen mods first, migrate any old machine image pin,
 # then release blockers so the supported LockScreen API can restore the original.
 $screenSnapshot=Join-Path $Root 'state\signin-backdrop-before.clixml'
 if(Test-Path -LiteralPath $screenSnapshot){& (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Restore -NoRestart}
 [void](Restore-AShellLegacyMachineLockScreenPin $Root)
 [void](Release-AShellLockScreenPolicyBlockers)
 $lock=Get-AShellOriginalLockImage $Root
 if($lock){Set-LockImage $lock}
 $before=Get-AShellBeforeSetup $Root
 $savedTransparency=@($before.Values | Where-Object {$_.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -and $_.Name -eq 'EnableTransparency'}) | Select-Object -First 1
 $materialChanged=$false
 if($savedTransparency){
  $currentTransparency=Read-RegistryValue $savedTransparency.Path $savedTransparency.Name
  $materialChanged=($currentTransparency.Exists -ne [bool]$savedTransparency.Exists -or [string]$currentTransparency.Value -ne [string]$savedTransparency.Value)
 }
 foreach($value in @($before.Values)){if(Test-AShellScreenSetting $value.Path $value.Name){Write-RegistryValue $value}}
 if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
 if(!$NoRestart){Restart-AShellWindhawkRuntime}
 Write-Output '[OK] Lock screen + sign-in styling: off. Original Windows appearance restored.'
}
function Set-AShellScreenRuntime([string]$Root,[bool]$Enabled,[switch]$NoRestart) {
 if(!$Enabled){Restore-AShellScreenBaseline $Root -NoRestart:$NoRestart;return}
 $target=Resolve-AShellRuntimeBackground $Root
 if($target -eq ''){throw 'A-Shell lock-screen styling cannot use an empty image. Choose a background or use the bundled default.'}
 [void](Restore-AShellLegacyMachineLockScreenPin $Root)
 $handoff=Get-AShellLockScreenPolicyHandoff
 if(@($handoff.Entries).Count){
  if(!(Test-AShellLockScreenOverrideConsent $Root)){throw 'Windows lock-screen policy is blocking A-Shell. Run the Setup EXE again and approve the explicit lock-screen policy override.'}
  foreach($entry in @(Get-AShellLockScreenOverrideValues $handoff $target)){Write-RegistryValue $entry}
 }
 $legacyMaterialRestored=Restore-AShellLegacyScreenMaterialOverrides $Root
 $screenValues=Get-AShellScreenRuntimeValues
 $settingsAlreadyApplied=Test-AShellRuntimeValuesApplied $screenValues
 Write-AShellRuntimeValues $screenValues
 $clearLogonPolicy=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon'
 if(!$clearLogonPolicy.Exists -or [string]$clearLogonPolicy.Value -ne '1'){throw 'Windows clear-logon policy write could not be verified.'}
 # DisableAcrylicBackgroundOnLogon is a machine policy. The old runtime path
 # wrote the value but didn't always broadcast a Policy change, so an already
 # running shell/logon stack could keep the previous acrylic/smoke decision.
 # Re-notify only when the screen values or a consented policy handoff changed.
 if(!$settingsAlreadyApplied -or @($handoff.Entries).Count -gt 0) {
  if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
 }
 Set-LockImage $target
 $cfg=Get-AShellFeatureConfig $Root
 if($cfg.signInHook){
  & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Apply -NoRestart -RuntimeOnly | Out-Null
  if(!$NoRestart){Restart-AShellWindhawkRuntime}
  Write-Output '[OK] Lock screen + sign-in styling: on (narrow LogonUI backdrop hook active).'
 } else {
  Write-Output '[OK] Lock screen + sign-in styling: on (native Windows path; Essentials profile).'
 }
}
function Write-AShellComponentStatus([string]$Root) {
 $cfg=Get-AShellFeatureConfig $Root
 $state='stopped'
 if(Test-AShellRuntimeActive $Root){$state='started'}
 $lockState='off';if([bool]$cfg.screens){$lockState='on'}
 $taskbarState='off';if([bool]$cfg.taskbarTransparency){$taskbarState='on'}
 $iconState='off';if([bool]$cfg.icons){$iconState='on'}
 $rainState='off';if([bool]$cfg.rain){$rainState='on'}
 $background='custom'
 $desiredBackground=Get-AShellDesiredBackground $Root
 if($desiredBackground -eq 'original'){$background='original'}
 else {
  $bundled=Join-Path $Root 'assets\LockScreenPicture.png'
  try {
   if((Test-Path -LiteralPath $desiredBackground -PathType Leaf) -and (Test-Path -LiteralPath $bundled -PathType Leaf) -and (Get-FileHash -LiteralPath $desiredBackground).Hash -eq (Get-FileHash -LiteralPath $bundled).Hash){$background='default'}
  } catch {}
 }
 Write-Output ('[STATUS] State: '+$state)
 Write-Output ('[STATUS] Lock screen: '+$lockState)
 Write-Output ('[STATUS] Taskbar: '+$taskbarState)
 Write-Output ('[STATUS] Icons: '+$iconState)
 Write-Output ('[STATUS] Rain: '+$rainState)
 Write-Output ('[STATUS] Background: '+$background)
 Write-Output ('[STATUS] Accent: #'+(Get-AShellDesiredAccent $Root))
 if($state -eq 'stopped'){Write-Output '[INFO] Saved switches will be restored on the next ashell start.'}
}
