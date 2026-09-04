param([ValidateSet('Apply','Restore','Check')][string]$Action='Apply',[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),[switch]$Core,[switch]$OverrideLockScreenPolicy,[switch]$DoNotOverrideLockScreenPolicy)
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
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode','DWord',1),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','LockScreenWidgetsSystemCurationEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338387Enabled','DWord',0),
 @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','DetailedStatusApp','String',''),
 @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh','DisableWidgetsOnLockScreen','DWord',1),
 @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','DisableAcrylicBackgroundOnLogon','DWord',1),
 @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableAutomaticRestartSignOn','DWord',1)
)
. (Join-Path $PSScriptRoot 'Setup.Support.ps1')
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
$capabilities=Get-AShellCapabilities
$useFullAppearance=(!$Core -and $capabilities.Windows11)
if($Action -eq 'Apply') {
 $desiredBackgroundPath=Join-Path $root 'state\desired-background.txt'
 if(Test-Path -LiteralPath $desiredBackgroundPath){
  $savedBackground=(Get-Content -LiteralPath $desiredBackgroundPath -Raw).Trim()
  if($savedBackground -and $savedBackground -ne 'original' -and (Test-Path -LiteralPath $savedBackground -PathType Leaf)){$image=$savedBackground}
  elseif($savedBackground -eq 'original' -and (Test-Path -LiteralPath (Join-Path $root 'state\baseline\desktop.img'))){$image=Join-Path $root 'state\baseline\desktop.img'}
 }
}
if($Action -in @('Apply','Check')) {Assert-AShellPackage $root -RequireCompatible}
if($Action -eq 'Check') {
 Write-Output ''
 Write-Output 'Lock-screen policy diagnostics:'
 Write-AShellLockScreenPolicyHandoffStatus (Get-AShellLockScreenPolicyHandoff) -DiagnosticOnly
 & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Check
 Write-Output 'Check completed without changing appearance settings.'
 exit 0
}
if($Action -eq 'Apply') {
 $preflightHandoff=Get-AShellLockScreenPolicyHandoff
 $consentPath=Get-AShellLockScreenOverrideConsentPath $root
 if($DoNotOverrideLockScreenPolicy){$OverrideLockScreenPolicy=$false}
 elseif(Test-Path -LiteralPath $consentPath){$OverrideLockScreenPolicy=$true}
 if(@($preflightHandoff.Entries).Count -and !$OverrideLockScreenPolicy -and !$DoNotOverrideLockScreenPolicy) {
  Write-Output ''
  Write-Warning 'Windows lock-screen personalization policy is active. A-Shell can temporarily override only the listed lock/sign-in personalization values, then restore their exact original values on ashell stop.'
  if($preflightHandoff.ExternallyManaged){Write-Warning ('Windows also reports device management: '+(@($preflightHandoff.ManagementReasons) -join ', ')+'. This consent does NOT remove MDM/enrollment or change unrelated policies. Management software may reapply these values later.')}
  foreach($entry in @($preflightHandoff.Entries)){Write-Output ('  - '+$entry.Name+': '+$entry.Meaning)}
  $answer=Read-Host 'Allow A-Shell to temporarily override these lock-screen personalization policies? [Y/N]'
  if($answer -match '^(?i:y|yes)$'){$OverrideLockScreenPolicy=$true}
 }
}
if(!(Test-AShellAdministrator)) {
 Write-Output "[WORKING] Requesting administrator access for A-Shell $($Action.ToLowerInvariant()) in this terminal..."
 $parameters=@{Action=$Action;ExpectedSid=$ExpectedSid}
 if($Core){$parameters.Core=$true}
 if($OverrideLockScreenPolicy){$parameters.OverrideLockScreenPolicy=$true}elseif($DoNotOverrideLockScreenPolicy){$parameters.DoNotOverrideLockScreenPolicy=$true}
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title 'A-Shell Setup - Administrator'
 if($exitCode -ne 0){Write-Error 'Setup did not finish. See state\setup.log.'}
 else {Write-Output "[OK] A-Shell $Action completed. Original backups are preserved. Full details: $stateDir\setup.log"}
 exit $exitCode
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Run setup from the account being customized; elevation switched to a different account.'}
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$checkpoint=$null
$appearanceStarted=$false
Start-Transcript -Path (Join-Path $stateDir 'setup.log') -Append | Out-Null
function Write-AShellSetupStep([int]$Number,[int]$Total,[string]$Title,[string]$Detail='') {
 $script:AShellCurrentSetupStep=('STEP {0} OF {1} | {2}' -f $Number,$Total,$Title)
 Write-Host ''
 Write-Host '  ================================================================' -ForegroundColor DarkYellow
 Write-Host (('  >>> STEP {0} OF {1}  |  {2}' -f $Number,$Total,$Title.ToUpperInvariant())) -ForegroundColor DarkYellow
 Write-Host '  ================================================================' -ForegroundColor DarkYellow
 if($Detail){Write-Host ('      '+$Detail) -ForegroundColor Gray}
}
try {
 . (Join-Path $PSScriptRoot 'Desktop.Support.ps1')
 . (Join-Path $PSScriptRoot 'Icons.Support.ps1')
 # A previous tweak/local policy can lock the Personalization page or pin a
 # different image. Discover it before the checkpoint so rollback and Undo know
 # the exact original value. Managed-device personalization can also be temporarily
 # overridden, but only after the user grants the dedicated consent switch/prompt.
 $lockPolicyHandoff=$null
 if($Action -eq 'Apply') {
  $lockPolicyHandoff=Get-AShellLockScreenPolicyHandoff
  if($OverrideLockScreenPolicy) {
   foreach($entry in @(Get-AShellLockScreenOverrideValues $lockPolicyHandoff $image)) {
    $desired += ,@($entry.Path,$entry.Name,$entry.Kind,$entry.Value,$entry.Exists)
   }
  }
 }
 Enter-AShellOperation
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $checkpoint=Join-Path $stateDir ('runs\'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
 if($Action -eq 'Apply'){Write-AShellSetupStep 1 8 'Save recovery state' 'Capturing wallpaper, lock screen, desktop layout, cursor and integration state before changing anything.'}
 else {Write-AShellSetupStep 1 6 'Load recovery state' 'Preparing the saved pre-A-Shell appearance and desktop layout.'}
 Save-AShellCheckpoint $checkpoint $desired $root
 if($Action -eq 'Apply'){
  # Capture the cursor registry/task baseline before any theme, pointer or shell mutation.
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Capture
  Save-AShellDesktop $root
 }
 # Capture every component together, before wallpaper/theme changes can also
 # change derived accent settings. Never replace an existing original backup.
 if($Action -eq 'Apply' -and !(Test-Path $snapshot) -and !(Test-Path (Join-Path $stateDir 'baseline\checkpoint.clixml'))) {
  $baseline=Join-Path $stateDir 'baseline'
  New-Item -ItemType Directory $baseline -Force | Out-Null
  Get-ChildItem -LiteralPath $checkpoint -File | Where-Object {$_.Name -ne 'checkpoint.clixml'} | Copy-Item -Destination $baseline
  Copy-Item -LiteralPath (Join-Path $checkpoint 'checkpoint.clixml') -Destination $baseline
 }
 if($Action -eq 'Apply'){Repair-AShellLegacyImageBaseline $root;Update-AShellBaselineForNewValues (Join-Path $stateDir 'baseline') $desired}
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
   $tasks=@(foreach($name in @('Matrix Desktop - Instant Rain','A-Shell Session Repair','A-Shell Cursor Session Repair','Codex Early Lively Wallpaper','Lively Wallpaper - Adi')) {
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
  Write-AShellSetupStep 2 8 'Hide desktop icons' 'The Explorer desktop view is hidden immediately; Desktop and OneDrive files are not moved.'
  Hide-AShellDesktopIconsNow $root
  Write-AShellSetupStep 3 8 'Prepare integrations' $(if($useFullAppearance){'Checking Windhawk and the bundled A-Shell mod payloads.'}else{'Essentials mode does not install or change Windhawk mods.'})
  if($useFullAppearance){Ensure-Windhawk $root}
  elseif($Core){Write-Output 'Essentials mode: skipping Windhawk taskbar/LockApp visual mods.'}
  else {Write-Output 'Windows 10 compatibility profile: applying supported A-Shell features; Windows 11-only Windhawk styling is skipped.'}
  Write-AShellSetupStep 4 8 'Apply Windows appearance' 'Applying theme preferences, temporarily overriding consented lock-screen personalization blockers, then setting desktop and lock images.'
  Write-AShellLockScreenPolicyHandoffStatus $lockPolicyHandoff -OverridePolicy:$OverrideLockScreenPolicy
  $themeRefreshRequired=$false
  foreach($v in $desired){
   $expectedExists=if($v.Count -ge 5){[bool]$v[4]}else{$true}
   if($v[0] -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -and $v[1] -in @('AppsUseLightTheme','SystemUsesLightTheme')){
    $current=Read-RegistryValue $v[0] $v[1]
    if(!$current.Exists -or [string]$current.Value -ne [string]$v[3]){$themeRefreshRequired=$true}
   }
   Write-RegistryValue @{Path=$v[0];Name=$v[1];Kind=$v[2];Value=$v[3];Exists=$expectedExists}
  }
  # Tell Settings/Explorer that policy-backed personalization changed before
  # invoking the supported lock-screen image API. A full WM_THEMECHANGED is only
  # useful when the actual Windows app/system light-dark values changed; replaying
  # it on repair/setup when they're already correct visibly repaints the taskbar.
  Send-AShellPolicyChange
  if($themeRefreshRequired){Send-AShellThemeChange}else{Write-Output '[SKIP] Windows light/dark theme already matches A-Shell; no taskbar theme refresh was sent.'}
  Set-DesktopImage $image
  Set-LockImage $image
  Show-AShellSignInBackgroundStatus
  & (Join-Path $PSScriptRoot 'Color.ps1') -Color default
  Write-AShellSetupStep 5 8 'Apply icons and screen styling' $(if($useFullAppearance){'Installing automatic taskbar icon matching plus supported LockApp/sign-in styling.'}else{'Skipping Windhawk visual styling in Essentials/Windows 10 compatibility mode.'})
  if($useFullAppearance) {
  $payloadUpdateRequired=Test-AShellWindhawkPayloadUpdateRequired $root
  if($payloadUpdateRequired){Prepare-AShellWindhawkForFileUpdate $root}
  else {Write-Output '[SKIP] Windhawk binary payloads already match this build; keeping the live taskbar module loaded.'}
  foreach($path in @($modDestination,$sourceDestination)){New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null}
  # Avoid replacing a loaded DLL when this exact version already exists.
  $payload=Join-Path $root ('assets\windhawk\'+$meta.LibraryFileName)
  if(!(Test-Path $modDestination) -or (Get-FileHash $payload).Hash -ne (Get-FileHash $modDestination).Hash){Copy-AShellWindhawkPayload -Source $payload -Destination $modDestination}
  Copy-Item (Join-Path $root 'assets\windhawk\windows-11-taskbar-styler.wh.cpp') $sourceDestination -Force
  foreach($entry in @{LibraryFileName=$meta.LibraryFileName;Version=$meta.Version;Include='explorer.exe';Exclude='';Architecture='x86-64'}.GetEnumerator()) {
   Write-RegistryValue @{Path=$modKey;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
  }
  Write-RegistryValue @{Path=$modKey;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
  . (Join-Path $PSScriptRoot 'Icon.Selection.ps1')
  Add-AShellAutomaticIcons $root
  Update-AShellIcons $root
  & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Apply -NoRestart
  Ensure-AShellTaskbarRuntimeLoaded $root
  }
  Write-AShellSetupStep 6 8 'Install Matrix and commands' 'Installing instant rain startup plus the A-Shell terminal commands.'
  & (Join-Path $PSScriptRoot 'Manage.ps1') -Action Install
  & (Join-Path $PSScriptRoot 'Terminal.ps1') -Action Install
  # The real Windows theme transition already happened in step 4. Do not send a
  # second WM_THEMECHANGED after Matrix starts: the taskbar is already correct and
  # that redundant replay is visible as a light/dark + Windhawk flicker.
  Write-AShellSetupStep 7 8 'Apply cursor pack' 'Applying the cursor scheme last without replaying the Windows theme.'
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Apply
  Write-AShellSetupStep 8 8 'Verify installation' 'Checking required appearance settings, desktop visibility, selected mod payloads, cursor selection and Matrix startup.'
  Assert-AShellInstalled $root $desired -Core:(!$useFullAppearance) -PolicyOverride:$OverrideLockScreenPolicy
  # Taskbar/icon settings were committed live before rain started. Avoid an
  # unconditional Windhawk restart here; it unloads/reloads an already-correct mod.
  Set-Content (Join-Path $stateDir 'applied.txt') (Get-Date -Format o)
  if($OverrideLockScreenPolicy){Set-Content -LiteralPath (Get-AShellLockScreenOverrideConsentPath $root) -Value ('consented '+(Get-Date -Format o)) -Encoding ascii}
  elseif($DoNotOverrideLockScreenPolicy){Remove-Item -LiteralPath (Get-AShellLockScreenOverrideConsentPath $root) -Force -ErrorAction SilentlyContinue}
  # Setup is the one-time install/repair transaction. Runtime start/stop reuses
  # these installed assets and backups without rebuilding or recopying them.
  Save-AShellFeatureConfig $root ([pscustomobject]@{version=2;screens=$true;taskbarTransparency=[bool]$useFullAppearance;icons=[bool]$useFullAppearance})
  Set-AShellDesiredBackground $root $image
  if(!(Test-Path -LiteralPath (Join-Path $stateDir 'desired-accent.txt'))){Set-AShellDesiredAccent $root 'D65A00'}
  Set-AShellRuntimeState $root $true 'Setup EXE completed'
  Set-AShellDesktopHidden $root
  Write-Output 'A-Shell installed and started. Future toggles use ashell start / ashell stop; Setup is only for install, upgrade or repair.'
 } else {
  if(!(Test-Path $snapshot)){throw 'No saved pre-setup settings exist in this package.'}
  $before=Import-Clixml $snapshot
  if($before.Sid -ne $sid){throw 'The backup belongs to another Windows account.'}
  $appearanceStarted=$true
  Write-AShellSetupStep 2 6 'Rain state' 'Stopping active rain once; an already-stopped A-Shell is left untouched.'
  if(Test-AShellRuntimeActive $root){Stop-AShellRendererForRestore $root -PauseStartup}
  else {Write-Output '[SKIP] A-Shell is already stopped. Rain was not drained or stopped again.'}
  Write-AShellSetupStep 3 6 'Restore backgrounds and colors' 'Restoring desktop, lock screen and saved Windows appearance preferences.'
  Restore-AShellBackground (Join-Path $stateDir 'background-before')
  Write-AShellSetupStep 4 6 'Restore cursors and integrations' 'Unloading A-Shell Windhawk mods, restoring original binaries/settings, then restoring the original cursor scheme.'
  Prepare-AShellWindhawkForFileUpdate $root -ForRestore
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Restore
  & (Join-Path $PSScriptRoot 'Color.ps1') -Action Restore
  foreach($value in $before.Values){Write-RegistryValue $value}
  $baselineDesktop=Join-Path $stateDir 'baseline\desktop.img'
  if(Test-Path -LiteralPath $baselineDesktop){Set-DesktopImage $baselineDesktop}
  elseif($before.Wallpaper -and (Test-Path -LiteralPath $before.Wallpaper)){Set-DesktopImage $before.Wallpaper}
  elseif(Test-Path (Join-Path $stateDir 'desktop-before.img')){Set-DesktopImage (Join-Path $stateDir 'desktop-before.img')}
  else {Set-DesktopImage ''}
  # A-Shell may currently be forcing its image through LockScreenImage policy.
  # Release active blockers before asking the supported API to restore the old image.
  [void](Release-AShellLockScreenPolicyBlockers)
  $baselineLock=Join-Path $stateDir 'baseline\lock.img'
  if(Test-Path -LiteralPath $baselineLock){Set-LockImage $baselineLock}else{Set-LockImage (Join-Path $stateDir 'lock-before.img')}
  # SetImageFileAsync can change personalization preferences; restore them last.
  foreach($value in $before.Values){Write-RegistryValue $value}
  foreach($file in $before.Files) {
   if($file.Exists){Restore-AShellSavedFile -Source $file.Saved -Destination $file.Path -Root $root | Out-Null}
   # Files which did not exist before A-Shell can remain unreferenced; deleting a loaded DLL is unnecessary.
  }
  if(Test-Path (Join-Path $stateDir 'signin-backdrop-before.clixml')) {
   & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Restore -NoRestart
  }
  if(Test-Path $modKey){Remove-Item -LiteralPath $modKey -Recurse -Force}
  if($before.HadMod){ & reg.exe import (Join-Path $stateDir 'taskbar-before.reg') | Out-Null; if($LASTEXITCODE){throw 'Taskbar restore failed.'} }
  foreach($task in $before.Tasks) {
   if($task.Exists){Register-ScheduledTask -TaskName $task.Name -Xml $task.Xml -Force | Out-Null; if($task.Running){Start-ScheduledTask -TaskName $task.Name}}
   elseif(Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false}
  }
  if(Test-Path (Join-Path $stateDir 'baseline\checkpoint.clixml')) {
   Restore-AShellCheckpoint (Join-Path $stateDir 'baseline') $root
  }
  Send-AShellPolicyChange
  Write-AShellSetupStep 5 6 'Restore desktop and terminal' 'Restoring desktop visibility/layout and removing the A-Shell command path entry.'
  & (Join-Path $PSScriptRoot 'Terminal.ps1') -Action Restore
  Restore-AShellDesktop $root
  Send-AShellThemeChange
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action SessionApply
  Write-AShellSetupStep 6 6 'Finish restore' 'Refreshing Explorer-facing appearance and restarting Windhawk when no deferred DLL replacement is waiting for reboot.'
  if((Test-Path $windhawk) -and !$script:AShellWindhawkRestorePendingReboot){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
  if($script:AShellWindhawkRestorePendingReboot){Write-Warning 'One or more previous Windhawk DLLs were still locked after unload/retry. Their exact replacements are queued for the next reboot; A-Shell restore otherwise completed.'}
  Remove-Item -LiteralPath (Get-AShellLockScreenOverrideConsentPath $root) -Force -ErrorAction SilentlyContinue
  Set-AShellRuntimeState $root $false 'full restore completed'
  Write-Output 'Previous appearance and startup settings restored. Sign out and back in to fully refresh. Saved backups are retained.'
  if(!$before.HadWindhawk -and (Test-Path $windhawk)){Write-Output 'Windhawk is retained so other mods are not disrupted. You can uninstall it from Installed apps if it is no longer needed.'}
 }
} catch {
 if($script:AShellCurrentSetupStep){Write-Output ('[ERROR] Setup stopped during '+$script:AShellCurrentSetupStep+'.')}
 Write-Output ('FAILED: '+$_)
 if($appearanceStarted -and $checkpoint -and (Test-Path (Join-Path $checkpoint 'checkpoint.clixml'))) {
  try {Restore-AShellCheckpoint $checkpoint $root -RestoreTerminal;Write-Output 'Appearance rolled back to the state immediately before this run.'}
  catch {Write-Output ('Automatic rollback needs attention: '+$_+'; checkpoint: '+$checkpoint)}
 }
 Write-Output 'The original backup and this run checkpoint are preserved. See state\setup.log.'
 exit 1
} finally {Exit-AShellOperation;Stop-Transcript | Out-Null}
