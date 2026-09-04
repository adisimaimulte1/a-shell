param([ValidateSet('Apply','Restore','Check')][string]$Action='Apply',[switch]$NoRestart,[switch]$RuntimeOnly,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
$state=Join-Path $root 'state'
$snapshot=Join-Path $state 'signin-backdrop-before.clixml'
$key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-signin-clear-background'
$engine='HKLM:\SOFTWARE\Windhawk\Engine\Settings'
$target='%SystemRoot%\System32\LogonUI.exe'
$lockTarget='%SystemRoot%\SystemApps\Microsoft.LockApp_cw5n1h2txyewy\LockApp.exe'
$lockKey='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-lockscreen-clear-background'
$lockLibrary='ashell-lockscreen-clear-background_1.9.dll'
$library='ashell-signin-clear-background_1.0.dll'
$payload=Join-Path $root ('assets\windhawk\'+$library)
$expected='51B3AA2B50944111F039C0DE035F9C8951A3FD7A65EDA7380AD30ECE5C2565BF'
$logonDll="$env:SystemRoot\System32\Windows.UI.Logon.dll"
$actualHash=if(Test-Path -LiteralPath $logonDll){(Get-FileHash -LiteralPath $logonDll).Hash}else{''}
$signInSupported=($actualHash -eq $expected)
if($Action -eq 'Check') {
 Write-Output "Lock/sign-in visual-tree mod: available on Windows 11"
 Write-Output "Exact 45% LogonUI overlay hook supported on this build: $signInSupported"
 if(!$signInSupported){Write-Output "Windows.UI.Logon.dll SHA-256: $actualHash"}
 Get-ItemProperty $key -ErrorAction SilentlyContinue | Select-Object Disabled,LibraryFileName,Include
 Get-ItemProperty $lockKey -ErrorAction SilentlyContinue | Select-Object Disabled,LibraryFileName,Include
 Get-ItemProperty 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable\ashell-signin-clear-background\LocalStorage' -ErrorAction SilentlyContinue | Format-List
 Get-ItemProperty 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable\ashell-lockscreen-clear-background\LocalStorage' -ErrorAction SilentlyContinue | Format-List
 exit 0
}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$admin){
 Write-Output "[WORKING] Requesting administrator access for lock/sign-in $($Action.ToLowerInvariant()) in this terminal..."
 $parameters=@{Action=$Action;ExpectedSid=$ExpectedSid};if($RuntimeOnly){$parameters.RuntimeOnly=$true};if($NoRestart){$parameters.NoRestart=$true}
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title 'A-Shell Screen Styling - Administrator'
 if($exitCode -ne 0){throw "Sign-in backdrop action failed ($exitCode). See state\signin-backdrop.log."}
 Write-Output "[OK] Lock/sign-in shading $Action completed. Check it at the next lock/sign-in."
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched to another Windows account.'}
New-Item -ItemType Directory $state -Force | Out-Null
Start-Transcript (Join-Path $state 'signin-backdrop.log') -Append | Out-Null
try {
 . (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
 . (Join-Path $PSScriptRoot 'Setup.Support.ps1')
 if($Action -eq 'Apply') {
  $lockPayload=Join-Path $root ('assets\windhawk\'+$lockLibrary)
  if(!(Test-Path $lockPayload)){throw 'The lock-screen mod binary is missing.'}
  if($signInSupported -and !(Test-Path $payload)){throw 'The sign-in mod binary is missing.'}
  if(!(Test-Path $engine)){throw 'Install Windhawk first.'}
  if(!(Test-Path $snapshot)) {
   @{Include=Read-RegistryValue $engine 'Include';Acrylic=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon';Trees=@((Read-AShellTree $key),(Read-AShellTree $lockKey))} | Export-Clixml $snapshot
  }
  $before=Import-Clixml $snapshot
  $sourceDir=Join-Path $env:ProgramData 'Windhawk\ModsSource'
  New-Item -ItemType Directory $sourceDir -Force | Out-Null

  # LockApp and LogonUI styling is XAML visual-tree based and doesn't depend on
  # the private Windows.UI.Logon.dll function offset. Keep it enabled across Windows 11 builds.
  $lockDestination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$lockLibrary)
  New-Item -ItemType Directory (Split-Path $lockDestination) -Force | Out-Null
  if($RuntimeOnly) {
   if(!(Test-Path -LiteralPath $lockDestination)){throw 'The installed lock/sign-in Windhawk payload is missing. Run the Setup EXE to repair A-Shell.'}
  } else {
   if(!(Test-Path $lockDestination) -or (Get-FileHash $lockPayload).Hash -ne (Get-FileHash $lockDestination).Hash){Copy-AShellWindhawkPayload -Source $lockPayload -Destination $lockDestination}
   Copy-Item (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') (Join-Path $sourceDir 'ashell-lockscreen-clear-background.wh.cpp') -Force
  }
  foreach($entry in @{LibraryFileName=$lockLibrary;Version='1.9';Include=($lockTarget+'|'+$target);Exclude='';Architecture='x86-64'}.GetEnumerator()) {
   Write-RegistryValue @{Path=$lockKey;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
  }
  Write-RegistryValue @{Path="$lockKey\Settings";Name='disableNewStartMenuLayout';Kind='String';Value='default';Exists=$true}
  $index=0
  foreach($name in @('DimmingOverlayPassword','DimmingOverlayNoPassword')) {
   $selector=(@('Rectangle','Grid','Border','Canvas') | ForEach-Object {$_+'#'+$name}) -join ', '
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].target";Kind='String';Value=$selector;Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=0';Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[1]";Kind='String';Value='Visibility=Collapsed';Exists=$true}
   $index++
  }
  # Windows 11 25H2/26200 can build the credential-screen dimmer without the
  # older DimmingOverlayPassword/NoPassword x:Name. The original verified
  # LogonUI hook identified the unwanted surface as a black brush at ~45%
  # opacity. The visual-tree engine supports exact primitive-property selectors,
  # so catch the version-tolerant Rectangle form without hiding generic Grid/
  # Border containers (which could contain credential controls).
  # LogonUI adds its own scrim/tint above the chosen image. Earlier A-Shell
  # registered this mod for LogonUI but the DLL itself rejected LogonUI.exe,
  # so those rules never ran there. v1.9 keeps both processes attached and adds stricter raw-image cleanup.
  $opacitySelector='Rectangle[Opacity=0.35], Rectangle[Opacity=0.4], Rectangle[Opacity=0.45], Rectangle[Opacity=0.5], Border[Opacity=0.4], Border[Opacity=0.45]'
  Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].target";Kind='String';Value=$opacitySelector;Exists=$true}
  Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=0';Exists=$true}
  Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[1]";Kind='String';Value='IsHitTestVisible=False';Exists=$true}
  $index++
  foreach($name in @('DimmingOverlay','BackgroundDimmingOverlay','ScreenDimmingOverlay','LogonDimmingOverlay','CredentialDimmingOverlay','CredentialBackgroundOverlay','BackgroundOverlay','LogonBackgroundOverlay','LockScreenOverlay','BlackOverlay','DarkOverlay','ColorOverlay','ColorTint','DimmingLayer','DimmingRect','BackgroundDimmer','BackgroundShade','BackgroundTint','TintOverlay','ShadeOverlay','ImageOverlay','WallpaperOverlay','BackgroundMask','ContentOverlay','Scrim','ScrimLayer','BackgroundScrim','CredentialScrim','LockScreenScrim','LogonScrim','AcrylicOverlay','BlurOverlay')) {
   $selector=(@('Rectangle','Border','Grid','Canvas')|ForEach-Object {$_+'#'+$name}) -join ', '
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].target";Kind='String';Value=$selector;Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=0';Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[1]";Kind='String';Value='IsHitTestVisible=False';Exists=$true}
   $index++
  }
  # Keep the actual wallpaper/image surface unfiltered. This doesn't touch the
  # user tile/profile image; it only targets common background-image names.
  foreach($name in @('BackgroundImage','LockScreenImage','LogonBackgroundImage','BackgroundImageControl','LockScreenBackgroundImage','WallpaperImage','BackgroundPhoto','LockScreenWallpaper','LogonWallpaper','UserBackgroundImage')) {
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].target";Kind='String';Value=('Image#'+$name);Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=1';Exists=$true}
   $index++
  }
  foreach($name in @('BackgroundRoot','BackgroundHost','BackgroundPanel','BackgroundPresenter','BackgroundContainer','LockScreenBackground','LockScreenBackgroundRoot','LockScreenBackgroundHost','LogonBackground','LogonBackgroundRoot','LogonBackgroundHost','WallpaperHost','WallpaperPresenter','ImageHost','ImagePresenter')) {
   $selector=(@('Grid','Border','Canvas','ContentControl')|ForEach-Object {$_+'#'+$name}) -join ', '
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].target";Kind='String';Value=$selector;Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=1';Exists=$true}
   # Some builds put the tint directly in Background on the named host rather
   # than in a separate dimming Rectangle. Make that host transparent while
   # leaving its child wallpaper Image at full opacity.
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[1]";Kind='String';Value='Background=Transparent';Exists=$true}
   $index++
  }
  Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
  Write-RegistryValue @{Path=$lockKey;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}

  # The documented policy removes acrylic blur on both Windows 10 and 11.
  Write-RegistryValue @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';Name='DisableAcrylicBackgroundOnLogon';Kind='DWord';Value=1;Exists=$true}

  if($signInSupported) {
   $destination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$library)
   New-Item -ItemType Directory (Split-Path $destination) -Force | Out-Null
   if($RuntimeOnly) {
    if(!(Test-Path -LiteralPath $destination)){throw 'The installed legacy sign-in Windhawk payload is missing. Run the Setup EXE to repair A-Shell.'}
   } else {
    if(!(Test-Path $destination) -or (Get-FileHash $payload).Hash -ne (Get-FileHash $destination).Hash){Copy-AShellWindhawkPayload -Source $payload -Destination $destination}
    Copy-Item (Join-Path $root 'src\signin-clear-background.wh.cpp') (Join-Path $sourceDir 'ashell-signin-clear-background.wh.cpp') -Force
   }
   foreach($entry in @{LibraryFileName=$library;Version='1.0';Include=$target;Exclude='';Architecture='x86-64'}.GetEnumerator()) {
    Write-RegistryValue @{Path=$key;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
   }
   Write-RegistryValue @{Path=$key;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
   Write-RegistryValue @{Path=$key;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
  } else {
   # An old verified build may have been updated in-place. Disable the stale
   # binary hook rather than injecting an offset-based patch into a new LogonUI.
   if(Test-Path $key){Write-RegistryValue @{Path=$key;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
   Write-Output '[INFO] This Windows build does not use A-Shell''s legacy byte-offset LogonUI hook. Named LogonUI/LockApp XAML overlays are styled by the version-tolerant visual-tree mod instead.'
  }

  $current=[string](Get-ItemProperty $engine).Include
  $entries=@($current -split '\|' | Where-Object {$_})
  $oldEntries=@(([string]$before.Include.Value) -split '\|' | Where-Object {$_})
  if($entries -notcontains $lockTarget){$entries+= $lockTarget}
  # The visual-tree mod targets both LockApp and LogonUI on every supported Windows 11 build.
  if($entries -notcontains $target){$entries+= $target}
  Write-RegistryValue @{Path=$engine;Name='Include';Kind='String';Value=($entries -join '|');Exists=$true}
  Write-Output $(if($signInSupported){'Installed visual-tree lock/sign-in styling plus the validated legacy LogonUI fallback.'}else{'Installed version-tolerant visual-tree lock/sign-in styling and clear-logon policy.'})
 } else {
  if(!(Test-Path $snapshot)){Write-Output 'No sign-in backdrop backup; nothing to restore.';exit 0}
  if(Test-Path $key){Write-RegistryValue @{Path=$key;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
  if(Test-Path $lockKey){Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
  $before=Import-Clixml $snapshot
  if($before.ContainsKey('Trees')){foreach($tree in $before.Trees){Restore-AShellTree $tree}}
  $current=[string](Get-ItemProperty $engine).Include
  $oldEntries=@(([string]$before.Include.Value) -split '\|' | Where-Object {$_})
  $addedTargets=@(@($target,$lockTarget) | Where-Object {$oldEntries -notcontains $_})
  if($addedTargets.Count){
   $remaining=@($current -split '\|' | Where-Object {$_ -and $addedTargets -notcontains $_}) -join '|'
   if($remaining -eq [string]$before.Include.Value){Write-RegistryValue $before.Include}
   else {Write-RegistryValue @{Path=$engine;Name='Include';Kind='String';Value=$remaining;Exists=$true}}
  }
  Write-RegistryValue $before.Acrylic
  Write-Output 'Previous screen-mod settings restored. Lock and unlock to refresh the views.'
 }
 if(!$NoRestart){Start-Process (Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe') -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
} finally {Stop-Transcript | Out-Null}
