param(
 [ValidateSet('Apply','Restore','Check')][string]$Action='Apply',
 [switch]$NoRestart,
 [switch]$RuntimeOnly,
 [string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Setup.Support.ps1')

$state=Join-Path $root 'state'
$snapshot=Join-Path $state 'signin-backdrop-before.clixml'
$engine='HKLM:\SOFTWARE\Windhawk\Engine\Settings'
$target='%SystemRoot%\System32\LogonUI.exe'
$lockTarget='%SystemRoot%\SystemApps\Microsoft.LockApp_cw5n1h2txyewy\LockApp.exe'
$signInKey='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-signin-clear-background'
$lockKey='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-lockscreen-clear-background'
$caps=Get-AShellCapabilities
$signInSupported=[bool]$caps.SignInOverlay
$lockSupported=[bool]$caps.LockScreenBackdrop

if($Action -eq 'Check') {
 $policy=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon'
 $motion=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'AnimateLockScreenBackground'
 $signInConfig=Get-ItemProperty -LiteralPath $signInKey -ErrorAction SilentlyContinue
 $signInStorage='HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable\ashell-signin-clear-background\LocalStorage'
 $removed=Read-RegistryValue $signInStorage 'OverlayRemoved'
 $hookInstalled=Read-RegistryValue $signInStorage 'HookInstalled'
 $zoomHookInstalled=Read-RegistryValue $signInStorage 'ZoomHookInstalled'
 $zoomDisabled=Read-RegistryValue $signInStorage 'ZoomDisabled'
 $policyOn=($policy.Exists -and [string]$policy.Value -eq '1')
 if($policyOn){Write-Output '[OK] Clear-logon acrylic policy: enabled.'}else{Write-Output '[INFO] Clear-logon acrylic policy: not enabled.'}
 if($motion.Exists -and [string]$motion.Value -eq '1'){Write-Output '[OK] Static lock/sign-in image policy: enabled.'}else{Write-Output '[INFO] Static lock/sign-in image policy: not enabled.'}
 if($signInSupported){
  if($signInConfig -and [int]$signInConfig.Disabled -eq 0){Write-Output '[OK] Narrow LogonUI 45% backdrop hook: enabled.'}else{Write-Output '[INFO] Narrow LogonUI backdrop hook: not enabled.'}
  if($hookInstalled.Exists -and [int]$hookInstalled.Value -eq 1){Write-Output '[OK] Verified sign-in backdrop hook initialized inside LogonUI.'}
  if($zoomHookInstalled.Exists -and [int]$zoomHookInstalled.Value -eq 1){Write-Output '[OK] Verified sign-in framing hook initialized inside LogonUI.'}
  if($zoomDisabled.Exists -and [int]$zoomDisabled.Value -eq 1){Write-Output '[OK] Sign-in background zoom: disabled.'}else{Write-Output '[INFO] Sign-in zoom suppression has not yet been observed.'}
  if($removed.Exists -and [int]$removed.Value -eq 1){Write-Output '[OK] 45% black sign-in backdrop: removed.'}else{Write-Output '[INFO] Backdrop removal has not been observed; this Windows.UI.Logon.dll may not match the verified build.'}
 } else {Write-Output '[INFO] Sign-in backdrop hook is unavailable on this unsupported A-Shell platform.'}
 if($lockSupported){
  $lockConfig=Get-ItemProperty -LiteralPath $lockKey -ErrorAction SilentlyContinue
  $lockStorage='HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable\ashell-lockscreen-clear-background\LocalStorage'
  $lockRemoved=Read-RegistryValue $lockStorage 'OverlayRemoved'
  if($lockConfig -and [int]$lockConfig.Disabled -eq 0){Write-Output '[OK] Windows 11 LockApp support module: enabled.'}else{Write-Output '[INFO] Windows 11 LockApp support module: not enabled.'}
  if($lockRemoved.Exists -and [int]$lockRemoved.Value -eq 1){Write-Output '[OK] LockApp credential dimmer cleanup: observed.'}
 }
 exit 0
}

$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$admin){
 Write-Output "[WORKING] Requesting administrator access for lock/sign-in $($Action.ToLowerInvariant()) in this terminal..."
 $parameters=@{Action=$Action;ExpectedSid=$ExpectedSid}
 if($RuntimeOnly){$parameters.RuntimeOnly=$true}
 if($NoRestart){$parameters.NoRestart=$true}
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title 'A-Shell Screen Styling - Administrator'
 if($exitCode -ne 0){throw "Sign-in backdrop action failed ($exitCode). See state\signin-backdrop.log."}
 Write-Output "[OK] Lock/sign-in shading $Action completed. Check it at the next lock/sign-in."
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched to another Windows account.'}

New-Item -ItemType Directory $state -Force | Out-Null
Start-Transcript (Join-Path $state 'signin-backdrop.log') -Append | Out-Null
try {
 if($Action -eq 'Apply') {
  if(!(Test-Path -LiteralPath $engine)){throw 'Install Windhawk first.'}
  if(!$signInSupported){throw 'This Windows platform is outside A-Shell sign-in hook support.'}

  # A legacy build used a process-wide XAML brush detour in LogonUI. If it is
  # still configured, disable it and restart Windhawk before installing the narrow
  # hook. This prevents the old DLL from remaining injected until the next reboot.
  $existingSignIn=Get-ItemProperty -LiteralPath $signInKey -ErrorAction SilentlyContinue
  if($existingSignIn -and [string]$existingSignIn.Version -eq '2.0' -and [int]$existingSignIn.Disabled -eq 0){
   Write-RegistryValue @{Path=$signInKey;Name='Disabled';Kind='DWord';Value=1;Exists=$true}
   Write-RegistryValue @{Path=$signInKey;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
   $windhawkExe=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
   if(Test-Path -LiteralPath $windhawkExe){
    Start-Process $windhawkExe -ArgumentList '-restart','-tray-only' -WindowStyle Hidden -Wait
    Start-Sleep -Milliseconds 500
   }
   Write-Output '[OK] Removed the unsafe legacy live LogonUI hook before continuing.'
  }

  # A legacy experiment tried to suppress the lock->sign-in zoom with LogonUI\AnimationDisabled.
  # That value only changes authentication animation behavior; on some builds it
  # leaves the background in the scaled transition state and can produce a black
  # screen when cancelling sign-in back to LockApp. Undo that one-time experiment
  # before applying the stable screen path.
  $legacyAnimationLog=Join-Path $state 'signin-backdrop.log'
  $legacyAnimationWasApplied=$false
  $legacyAnimationSnapshot=$null
  if(Test-Path -LiteralPath $snapshot){
   try {
    $candidate=Import-Clixml -LiteralPath $snapshot
    if($candidate.PSObject.Properties.Name -contains 'AnimationDisabled'){
     $legacyAnimationSnapshot=$candidate.AnimationDisabled
     $legacyAnimationWasApplied=$true
    }
   } catch {}
  }
  if(Test-Path -LiteralPath $legacyAnimationLog){
   try {$legacyAnimationWasApplied=$legacyAnimationWasApplied -or [bool](Select-String -LiteralPath $legacyAnimationLog -SimpleMatch 'authentication-animation suppression enabled' -Quiet)}catch{}
  }
  if($legacyAnimationWasApplied){
   $restoredLegacyAnimation=$false
   if($legacyAnimationSnapshot){
    Write-RegistryValue $legacyAnimationSnapshot
    $restoredLegacyAnimation=$true
   }
   if(!$restoredLegacyAnimation){
    # Older A-Shell snapshots predate this setting, so there is no saved value to
    # restore. The legacy experiment created/forced DWORD 1; remove it instead of
    # pinning an animation policy that A-Shell no longer owns.
    $currentAnimation=Read-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI' 'AnimationDisabled'
    if($currentAnimation.Exists -and [string]$currentAnimation.Value -eq '1'){
     Write-RegistryValue @{Path=$currentAnimation.Path;Name=$currentAnimation.Name;Kind=$currentAnimation.Kind;Value=$null;Exists=$false}
    }
   }
   Write-Output '[OK] Removed the obsolete LogonUI animation override.'
  }

  if(!(Test-Path -LiteralPath $snapshot)) {
   @{
    Include=Read-RegistryValue $engine 'Include'
    Acrylic=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon'
    Motion=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'AnimateLockScreenBackground'
    Trees=@((Read-AShellTree $signInKey),(Read-AShellTree $lockKey))
   } | Export-Clixml -LiteralPath $snapshot
  }
  $sourceDir=Join-Path $env:ProgramData 'Windhawk\ModsSource'
  New-Item -ItemType Directory $sourceDir -Force | Out-Null

  # Windows 11 LockApp keeps the narrow credential-dimmer support module.
  # It must stay OUT of LogonUI; the dedicated narrow hook owns LogonUI.
  $lockLibrary=''
  if($lockSupported){
   $lockPayloadInfo=Get-AShellLockScreenPayloadInfo $root
   $lockLibrary=[string]$lockPayloadInfo.LibraryFileName
   $lockPayload=[string]$lockPayloadInfo.SourcePath
   $lockDestination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$lockLibrary)
   if(!(Test-Path -LiteralPath $lockDestination) -or (Get-FileHash -LiteralPath $lockPayload).Hash -ne (Get-FileHash -LiteralPath $lockDestination).Hash){
    Copy-AShellWindhawkPayload -Source $lockPayload -Destination $lockDestination
   }
   if(!$RuntimeOnly){
    Copy-Item -LiteralPath (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') -Destination (Join-Path $sourceDir 'ashell-lockscreen-clear-background.wh.cpp') -Force
   }
   foreach($entry in @{LibraryFileName=$lockLibrary;Version=[string]$lockPayloadInfo.Version;Include=$lockTarget;Exclude='';Architecture='x86-64'}.GetEnumerator()){
    Write-RegistryValue @{Path=$lockKey;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
   }
   $lockSettings="$lockKey\Settings"
   if(Test-Path -LiteralPath $lockSettings){Remove-Item -LiteralPath $lockSettings -Recurse -Force}
   Write-RegistryValue @{Path=$lockSettings;Name='disableNewStartMenuLayout';Kind='String';Value='default';Exists=$true}
   $index=0
   # LockApp's clock/photo page has a dedicated LockScreenOverlay element. Target
   # it explicitly instead of relying only on the visual-tree heuristic. This is
   # the dark photo veil on the lock screen; the time/date/content containers are
   # separate and remain untouched.
   foreach($name in @('LockScreenOverlay','DimmingOverlayPassword','DimmingOverlayNoPassword')){
    $selector=(@('Rectangle','Grid','Border','Canvas','ContentPresenter') | ForEach-Object {$_+'#'+$name}) -join ', '
    Write-RegistryValue @{Path=$lockSettings;Name="controlStyles[$index].target";Kind='String';Value=$selector;Exists=$true}
    Write-RegistryValue @{Path=$lockSettings;Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=0';Exists=$true}
    Write-RegistryValue @{Path=$lockSettings;Name="controlStyles[$index].styles[1]";Kind='String';Value='Visibility=Collapsed';Exists=$true}
    $index++
    foreach($paint in @(@{Target='Rectangle#'+$name;Property='Fill'},@{Target='Grid#'+$name+', Border#'+$name+', Canvas#'+$name;Property='Background'})){
     Write-RegistryValue @{Path=$lockSettings;Name="controlStyles[$index].target";Kind='String';Value=$paint.Target;Exists=$true}
     Write-RegistryValue @{Path=$lockSettings;Name="controlStyles[$index].styles[0]";Kind='String';Value=($paint.Property+':=<SolidColorBrush Color="Transparent" />');Exists=$true}
     $index++
    }
   }
   Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
   Write-RegistryValue @{Path=$lockKey;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
  } elseif(Test-Path -LiteralPath $lockKey) {
   Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=1;Exists=$true}
  }

  # Blur: use Windows' documented clear-logon policy and verify the write.
  Write-RegistryValue @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization';Name='AnimateLockScreenBackground';Kind='DWord';Value=1;Exists=$true}
  $staticImagePolicy=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'AnimateLockScreenBackground'
  if(!$staticImagePolicy.Exists -or [string]$staticImagePolicy.Value -ne '1'){throw 'Windows static lock/sign-in image policy write could not be verified.'}
  Write-RegistryValue @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';Name='DisableAcrylicBackgroundOnLogon';Kind='DWord';Value=1;Exists=$true}
  $clearLogonPolicy=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon'
  if(!$clearLogonPolicy.Exists -or [string]$clearLogonPolicy.Value -ne '1'){throw 'Windows clear-logon policy write could not be verified.'}
  if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}

  # 40-45% sign-in overlay: use the narrow, previously verified hook only.
  # It targets one getter/brush and fails closed on unknown Windows.UI.Logon.dll builds.
  $signInPayloadInfo=Get-AShellSignInPayloadInfo $root
  $signInLibrary=[string]$signInPayloadInfo.LibraryFileName
  $signInPayload=[string]$signInPayloadInfo.SourcePath
  $signInDestination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$signInLibrary)
  if(!(Test-Path -LiteralPath $signInDestination) -or (Get-FileHash -LiteralPath $signInPayload).Hash -ne (Get-FileHash -LiteralPath $signInDestination).Hash){
   Copy-AShellWindhawkPayload -Source $signInPayload -Destination $signInDestination
  }
  if(!$RuntimeOnly){Copy-Item -LiteralPath (Join-Path $root 'src\signin-clear-background.wh.cpp') -Destination (Join-Path $sourceDir 'ashell-signin-clear-background.wh.cpp') -Force}
  foreach($entry in @{LibraryFileName=$signInLibrary;Version=[string]$signInPayloadInfo.Version;Include=$target;Exclude='';Architecture='x86-64'}.GetEnumerator()){
   Write-RegistryValue @{Path=$signInKey;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
  }
  Write-RegistryValue @{Path=$signInKey;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
  Write-RegistryValue @{Path=$signInKey;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
  Remove-AShellStaleSignInPayloads -KeepLibrary $signInLibrary
  Write-Output ('[OK] Narrow verified LogonUI backdrop hook enabled with '+$signInLibrary+'.')

  $current=[string](Get-ItemProperty $engine).Include
  $entries=@($current -split '\|' | Where-Object {$_})
  if($lockSupported -and $entries -notcontains $lockTarget){$entries+=$lockTarget}
  if($entries -notcontains $target){$entries+=$target}
  Write-RegistryValue @{Path=$engine;Name='Include';Kind='String';Value=($entries -join '|');Exists=$true}
  if($lockSupported){Remove-AShellStaleLockScreenPayloads -KeepLibrary $lockLibrary}
  Write-Output '[OK] Lock/sign-in blur, raw LockApp photo overlay removal and narrow sign-in backdrop handling enabled.'
 } else {
  if(!(Test-Path -LiteralPath $snapshot)){Write-Output 'No sign-in backdrop backup; nothing to restore.';exit 0}
  if(Test-Path -LiteralPath $signInKey){Write-RegistryValue @{Path=$signInKey;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
  if(Test-Path -LiteralPath $lockKey){Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
  $before=Import-Clixml -LiteralPath $snapshot
  if($before.ContainsKey('Trees')){foreach($tree in $before.Trees){Restore-AShellTree $tree}}
  $current=[string](Get-ItemProperty $engine).Include
  $oldEntries=@(([string]$before.Include.Value) -split '\|' | Where-Object {$_})
  $addedTargets=@(@($target,$lockTarget) | Where-Object {$oldEntries -notcontains $_})
  if($addedTargets.Count){
   $remaining=@($current -split '\|' | Where-Object {$_ -and $addedTargets -notcontains $_}) -join '|'
   if($remaining -eq [string]$before.Include.Value){Write-RegistryValue $before.Include}
   else{Write-RegistryValue @{Path=$engine;Name='Include';Kind='String';Value=$remaining;Exists=$true}}
  }
  Write-RegistryValue $before.Acrylic
  if($before.ContainsKey('Motion')){Write-RegistryValue $before.Motion}
  Write-Output 'Previous screen-mod settings restored. Lock and unlock to refresh the views.'
 }
 if(!$NoRestart){Start-Process (Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe') -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
} finally {Stop-Transcript | Out-Null}
