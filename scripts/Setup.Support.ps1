$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
function Get-AShellCapabilities([int]$Build=[Environment]::OSVersion.Version.Build,[string]$Architecture=[Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE','Machine')) {
 # A-Shell's current native helpers are x64, so the package baseline remains
 # Windows 10 22H2+ / Windows 11 x64. The sign-in overlay hook deliberately
 # resolves the installed Windows.UI.Logon.dll through matching Microsoft symbols.
 $core=($Build -ge 19045 -and $Architecture -eq 'AMD64' -and [Environment]::Is64BitProcess)
 $windows11=($core -and $Build -ge 22000)
 $signInOverlay=$core
 return @{Core=$core;Windows11=$windows11;Full=$windows11;TaskbarStyling=$windows11;LockScreenBackdrop=$windows11;SignInOverlay=$signInOverlay}
}
function Get-AShellLockScreenPayloadInfo([string]$Root) {
 $source=Join-Path $Root 'assets\windhawk\ashell-lockscreen-clear-background_1.7.dll'
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw 'The bundled LockApp support DLL is missing.'}
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $library=('ashell-lockscreen-clear-background_1.7_'+$hash.Substring(0,12)+'.dll')
 return [pscustomobject]@{SourcePath=$source;Sha256=$hash;LibraryFileName=$library;Version='1.7'}
}
function Get-AShellSignInPayloadInfo([string]$Root) {
 $source=Join-Path $Root 'assets\windhawk\ashell-signin-clear-background_1.0.dll'
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw 'The verified narrow LogonUI backdrop DLL is missing.'}
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $library=('ashell-signin-clear-background_1.0_'+$hash.Substring(0,12)+'.dll')
 return [pscustomobject]@{SourcePath=$source;Sha256=$hash;LibraryFileName=$library;Version='1.0'}
}
function Remove-AShellStaleLockScreenPayloads([string]$KeepLibrary='') {
 $folder=Join-Path $env:ProgramData 'Windhawk\Engine\Mods\64'
 if(!(Test-Path -LiteralPath $folder -PathType Container)){return}
 foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter 'ashell-lockscreen-clear-background_*.dll' -File -ErrorAction SilentlyContinue)) {
  if($KeepLibrary -and $file.Name -eq $KeepLibrary){continue}
  try {Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop}catch{}
 }
}
function Remove-AShellStaleSignInPayloads([string]$KeepLibrary='') {
 $folder=Join-Path $env:ProgramData 'Windhawk\Engine\Mods\64'
 if(!(Test-Path -LiteralPath $folder -PathType Container)){return}
 foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter 'ashell-signin-clear-background_*.dll' -File -ErrorAction SilentlyContinue)) {
  if($KeepLibrary -and $file.Name -eq $KeepLibrary){continue}
  try {Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop}catch{}
 }
}
function Assert-AShellPackage([string]$Root,[switch]$RequireCompatible) {
 $manifest=Join-Path $Root 'assets\package-manifest.json'
 if(!(Test-Path $manifest)){throw 'Package manifest is missing. Extract the complete ZIP.'}
 $data=Get-Content $manifest -Raw | ConvertFrom-Json
 $versionFile=Join-Path $Root 'VERSION'
 if(!(Test-Path -LiteralPath $versionFile -PathType Leaf)){throw 'Canonical VERSION file is missing.'}
 $productVersion=(Get-Content -LiteralPath $versionFile -Raw).Trim()
 if($productVersion -notmatch '^\d+\.\d+\.\d+$' -or [string]$data.version -ne $productVersion){throw 'VERSION and package-manifest.json do not identify the same A-Shell release.'}
 $prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 foreach($item in $data.files) {
  $full=[IO.Path]::GetFullPath((Join-Path $Root $item.path))
  if(!$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid package manifest path.'}
  $editable=$item.path -match '^assets/icons/[^/]+\.png$' -or $item.path -eq 'assets/icon-map.json'
  if(!$editable -and (!(Test-Path -LiteralPath $full) -or (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $item.sha256)){throw "Missing or modified package file: $($item.path). Re-extract the ZIP, or rebuild its manifest after intentional edits."}
 }
 foreach($file in Get-ChildItem (Join-Path $Root 'scripts') -Filter '*.ps1') {
  $tokens=$null
  $errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors -and $errors.Count -gt 0){
   $details=@($errors | ForEach-Object {"line $($_.Extent.StartLineNumber), column $($_.Extent.StartColumnNumber): $($_.Message)"}) -join '; '
   throw "Invalid PowerShell script: $($file.Name) - $details"
  }
 }
 $cursorGuardSource=Join-Path $Root 'src\CursorSessionGuard.cpp'
 $cursorGuardBinary=Join-Path $Root 'bin\CursorSessionGuard.exe'
 if(!(Test-Path -LiteralPath $cursorGuardSource) -or !(Test-Path -LiteralPath $cursorGuardBinary)){throw 'The native cursor session guard is missing. Run scripts\Build.ps1 before building a package or installer.'}
 $screenSource=Join-Path $Root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp'
 $screenBinary=Join-Path $Root 'assets\windhawk\ashell-lockscreen-clear-background_1.7.dll'
 $screenBuild=Join-Path $Root 'assets\windhawk\ashell-lockscreen-clear-background.build.json'
 if(!(Test-Path -LiteralPath $screenSource) -or !(Test-Path -LiteralPath $screenBinary) -or !(Test-Path -LiteralPath $screenBuild)){throw 'The compiled LockApp screen mod is missing. Run scripts\Build.ps1 before building a package or installer.'}
 $screenMeta=Get-Content -LiteralPath $screenBuild -Raw | ConvertFrom-Json
 if((Get-FileHash -LiteralPath $screenSource -Algorithm SHA256).Hash -ne [string]$screenMeta.sourceSha256 -or (Get-FileHash -LiteralPath $screenBinary -Algorithm SHA256).Hash -ne [string]$screenMeta.binarySha256){throw 'The bundled LockApp Windhawk DLL is stale relative to its source. Run scripts\Build.ps1, then build the package again.'}
 $signInSource=Join-Path $Root 'src\signin-clear-background.wh.cpp'
 $signInBinary=Join-Path $Root 'assets\windhawk\ashell-signin-clear-background_1.0.dll'
 $signInBuild=Join-Path $Root 'assets\windhawk\ashell-signin-clear-background_1.0.build.json'
 if(!(Test-Path -LiteralPath $signInSource -PathType Leaf) -or !(Test-Path -LiteralPath $signInBinary -PathType Leaf) -or !(Test-Path -LiteralPath $signInBuild -PathType Leaf)){throw 'The verified narrow sign-in backdrop hook or its build metadata is missing.'}
 $signInMeta=Get-Content -LiteralPath $signInBuild -Raw | ConvertFrom-Json
 if((Get-FileHash -LiteralPath $signInSource -Algorithm SHA256).Hash -ne [string]$signInMeta.sourceSha256 -or (Get-FileHash -LiteralPath $signInBinary -Algorithm SHA256).Hash -ne [string]$signInMeta.binarySha256){throw 'The bundled LogonUI Windhawk DLL is stale relative to its source. Run scripts\Build.ps1, then build the package again.'}
 . (Join-Path $PSScriptRoot 'Icons.Support.ps1')
 $iconPlan=Get-AShellIconPlan $Root
 $cursorCheck=@(& (Join-Path $Root 'scripts\Cursors.ps1') -Action Check)
 $caps=Get-AShellCapabilities
 Write-Output '[OK] Package: verified.'
 Write-Output '[OK] Cursors: 17 / 17 valid.'
 if($RequireCompatible -and !$caps.Core){throw 'Setup requires Windows 10 22H2 or Windows 11, x64. No appearance settings were changed.'}
 if($caps.Windows11){Write-Output '[OK] Windows 11 lock/sign-in styling: supported.'}
 else{Write-Output '[OK] Windows 10 sign-in backdrop hook: supported. Windows 11-only taskbar/LockApp styling is skipped.'}
}

function Ensure-Windhawk([string]$Root) {
 $exe=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if(Test-Path $exe){
  $version=(Get-Item $exe).VersionInfo.FileVersion -replace ',','.'
  if([version]$version -lt [version]'1.7.3'){throw 'Windhawk 1.7.3 or newer is required. Update Windhawk, then rerun Setup.'}
  Write-Output "Using installed Windhawk $version"
  return
 }
 $dep=(Get-Content (Join-Path $Root 'assets\dependencies.json') -Raw | ConvertFrom-Json).windhawk
 $cache=Join-Path $Root 'state\downloads';New-Item -ItemType Directory $cache -Force | Out-Null
 $installer=Join-Path $cache 'windhawk_setup.exe'
 if(!(Test-Path $installer) -or (Get-FileHash $installer).Hash -ne $dep.sha256) {
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $partial=$installer+'.partial'
  for($attempt=1;$attempt -le 3;$attempt++) {
   try {Invoke-WebRequest -UseBasicParsing -Uri $dep.url -OutFile $partial -TimeoutSec 180;break}
   catch {if($attempt -eq 3){throw 'Windhawk download failed. Check the internet connection and rerun Setup.'};Start-Sleep -Seconds 2}
  }
  if((Get-FileHash $partial).Hash -ne $dep.sha256){throw 'Windhawk installer checksum mismatch; it was not executed.'}
  Move-Item -LiteralPath $partial -Destination $installer -Force
 }
 Write-Output "Installing official Windhawk $($dep.version). Its installer may download additional components."
 $process=Start-Process -FilePath $installer -ArgumentList '/S','/STANDARD' -PassThru -Wait -WindowStyle Hidden
 if($process.ExitCode -notin @(0,3010) -or !(Test-Path $exe)){throw "Windhawk installation failed (exit $($process.ExitCode)). Rerun Setup after resolving the installer/network issue."}
}

function Test-AShellLockScreenOverrideSetting([string]$Path,[string]$Name) {
 $id=(Get-AShellRegistrySettingId $Path $Name)
 return $id -in @(
  'hklm:\software\policies\microsoft\windows\personalization|nochanginglockscreen',
  'hklm:\software\policies\microsoft\windows\personalization|nolockscreen',
  'hklm:\software\policies\microsoft\windows\personalization|nolockscreenslideshow',
  'hklm:\software\policies\microsoft\windows\personalization|lockscreenimage',
  'hklm:\software\microsoft\windows\currentversion\personalizationcsp|lockscreenimagepath',
  'hklm:\software\microsoft\windows\currentversion\personalizationcsp|lockscreenimageurl',
  'hklm:\software\policies\microsoft\windows\system|disablelogonbackgroundimage'
 )
}
function Assert-AShellInstalled([string]$Root,$Desired,[switch]$Core,[switch]$PolicyOverride) {
 foreach($entry in $Desired) {
  $actual=Read-RegistryValue $entry[0] $entry[1]
  $expectedExists=if($entry.Count -ge 5){[bool]$entry[4]}else{$true}
  $matches=if($expectedExists){$actual.Exists -and [string]$actual.Value -eq [string]$entry[3]}else{!$actual.Exists}
  if(!$matches -and $PolicyOverride -and (Test-AShellLockScreenOverrideSetting $entry[0] $entry[1])) {
   # A management refresh can race the setup transaction once. Explicit consent
   # allows A-Shell to reassert only its lock/sign-in personalization override.
   for($retry=1;$retry -le 3 -and !$matches;$retry++) {
    Write-Warning "Windows reapplied lock-screen policy '$($entry[1])' during setup. Reasserting the consented A-Shell value ($retry/3)."
    Write-RegistryValue @{Path=$entry[0];Name=$entry[1];Kind=$entry[2];Value=$entry[3];Exists=$expectedExists}
    if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
    Start-Sleep -Milliseconds 350
    $actual=Read-RegistryValue $entry[0] $entry[1]
    $matches=if($expectedExists){$actual.Exists -and [string]$actual.Value -eq [string]$entry[3]}else{!$actual.Exists}
   }
  }
  if(!$matches){
   if(Test-AShellOptionalRegistrySetting $entry[0] $entry[1]){
    Write-Warning "Optional Windows setting '$($entry[1])' is unavailable, protected or overridden on this device. Required A-Shell verification continues."
    continue
   }
   throw "Appearance verification failed: $($entry[1])"
  }
 }
 $caps=Get-AShellCapabilities
 $requiredMods=@()
 if(!$Core){
  if($caps.Windows11){$requiredMods+=@('windows-11-taskbar-styler','ashell-lockscreen-clear-background')}
  if($caps.SignInOverlay){$requiredMods+='ashell-signin-clear-background'}
 }
 foreach($id in $requiredMods) {
  $config=Get-ItemProperty ('HKLM:\SOFTWARE\Windhawk\Engine\Mods\'+$id)
  if($config.Disabled -ne 0){throw "Mod is disabled: $id"}
  $installed=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$config.LibraryFileName)
  if($id -eq 'ashell-lockscreen-clear-background') {
   $payloadInfo=Get-AShellLockScreenPayloadInfo $Root
   $original=$payloadInfo.SourcePath
   if([string]$config.LibraryFileName -ne [string]$payloadInfo.LibraryFileName){throw 'LockApp support mod points at a stale Windhawk payload.'}
  } elseif($id -eq 'ashell-signin-clear-background') {
   $payloadInfo=Get-AShellSignInPayloadInfo $Root
   $original=$payloadInfo.SourcePath
   if([string]$config.LibraryFileName -ne [string]$payloadInfo.LibraryFileName){throw 'Portable sign-in backdrop mod points at a stale Windhawk payload.'}
  } else {
   $original=Join-Path $Root ('assets\windhawk\'+$config.LibraryFileName)
  }
  if(!(Test-Path -LiteralPath $installed -PathType Leaf) -or (Get-FileHash $installed).Hash -ne (Get-FileHash $original).Hash){throw "Mod verification failed: $id"}
  if($id -eq 'ashell-lockscreen-clear-background') {
   $include=[string]$config.Include
   if($include -notmatch '(?i)LockApp\.exe' -or $include -match '(?i)LogonUI\.exe'){throw 'Lock-screen support mod must be LockApp-only; LogonUI belongs to the dedicated backdrop hook.'}
  } elseif($id -eq 'ashell-signin-clear-background') {
   if([string]$config.Include -notmatch '(?i)LogonUI\.exe'){throw 'Portable sign-in backdrop mod is not configured for LogonUI.'}
  }
 }
 $task=Get-ScheduledTask -TaskName 'Matrix Desktop - Instant Rain'
 if($task.Actions[0].Execute -ne (Join-Path $Root 'bin\MatrixDesktop.exe')){throw 'Matrix startup points at the wrong folder.'}
 if([string]$task.Actions[0].Arguments -notmatch '(?i)(^|\s)--autostart($|\s)'){throw 'Matrix sign-in startup is not state-aware. Run the Setup EXE again.'}
 $deadline=(Get-Date).AddSeconds(8)
 while(!(Get-Process MatrixDesktop -ErrorAction SilentlyContinue)) {if((Get-Date) -gt $deadline){throw 'Matrix did not start.'};Start-Sleep -Milliseconds 200}
 $cursorPath=(Get-ItemProperty 'HKCU:\Control Panel\Cursors').Arrow
 if(!(Test-Path $cursorPath) -or (Get-FileHash $cursorPath).Hash -ne (Get-FileHash (Join-Path $Root 'assets\cursors\pointer.cur')).Hash){throw 'Cursor installation verification failed.'}
 $defaultCursor=(Read-RegistryValue 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Cursors' 'Arrow')
 if(!$defaultCursor.Exists -or !(Test-Path -LiteralPath ([string]$defaultCursor.Value)) -or (Get-FileHash -LiteralPath ([string]$defaultCursor.Value)).Hash -ne (Get-FileHash (Join-Path $Root 'assets\cursors\pointer.cur')).Hash){throw 'Pre-logon cursor persistence verification failed.'}
 $cursorTheme=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' 'ThemeChangesMousePointers'
 if(!$cursorTheme.Exists -or [string]$cursorTheme.Value -ne '0'){throw 'Windows themes are still allowed to replace the active A-Shell cursor scheme.'}
 $cursorGuardTask=Get-ScheduledTask -TaskName 'A-Shell Cursor Session Guard' -ErrorAction SilentlyContinue
 if(!$cursorGuardTask -or $cursorGuardTask.Actions[0].Execute -ne (Join-Path $Root 'bin\CursorSessionGuard.exe')){throw 'Native cursor sign-in guard installation verification failed.'}
 if(Get-Command Test-AShellLegacyMachineLockScreenPath -ErrorAction SilentlyContinue){
  foreach($machineValue in @(Get-AShellMachineLockScreenRegistryValues)){
   if($machineValue.Exists -and (Test-AShellLegacyMachineLockScreenPath ([string]$machineValue.Value))){throw 'Legacy A-Shell machine lock-screen pin is still active. Rerun Setup to migrate it.'}
  }
 }
 if(!$Core){$service=Get-Service Windhawk;if($service.Status -ne 'Running'){Start-Service Windhawk}}
 if((Read-RegistryValue 'HKCU:\Software\A-Shell' 'AccentColor').Value -ne 'D65A00'){throw 'Setup accent color verification failed.'}
 $desktopIcons=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
 if(!$desktopIcons.Exists -or [int]$desktopIcons.Value -ne 1){throw 'Desktop icon visibility verification failed.'}
 Send-AShellColorChange
 Write-Output 'Verified appearance settings, native lock/sign-in image path, native cursor startup guard, hidden desktop view, selected mod payloads, shared accent and state-aware Matrix startup.'
}

function Read-AShellTree([string]$Path) {
 if(!(Test-Path -LiteralPath $Path)){return @{Path=$Path;Exists=$false;Keys=@();Values=@()}}
 $keys=@((Get-Item -LiteralPath $Path))+@(Get-ChildItem -LiteralPath $Path -Recurse)
 $values=@(foreach($key in $keys){foreach($name in $key.GetValueNames()){Read-RegistryValue $key.PSPath $name}})
 return @{Path=$Path;Exists=$true;Keys=@($keys | ForEach-Object {$_.PSPath});Values=$values}
}
function Restore-AShellTree($Tree) {
 # Only installer-owned appearance locations may be replaced.
 if($Tree.Path -notmatch '^HKLM:\\SOFTWARE\\Windhawk\\Engine\\Mods\\(windows-11-taskbar-styler|ashell-signin-clear-background|ashell-lockscreen-clear-background)$' -and $Tree.Path -notin @('HKCU:\Control Panel\Cursors','Registry::HKEY_USERS\.DEFAULT\Control Panel\Cursors')){throw 'Unrecognized registry checkpoint path.'}
 if(Test-Path -LiteralPath $Tree.Path){Remove-Item -LiteralPath $Tree.Path -Recurse -Force}
 if($Tree.Exists){foreach($path in $Tree.Keys){New-Item -Path $path -Force | Out-Null};foreach($value in $Tree.Values){Write-RegistryValue $value}}
}
function Save-AShellCheckpoint([string]$Folder,$Desired,[string]$Root) {
 New-Item -ItemType Directory $Folder -Force | Out-Null
 # Capture the active desktop shell-view flags/positions for per-run rollback.
 # This matters because A-Shell hides icons immediately through IFolderView2 as
 # well as the persistent registry setting.
 $desktopLayout=Join-Path $Folder 'desktop-layout.bin'
 & (Join-Path $Root 'bin\DesktopLayout.exe') save $desktopLayout
 if($LASTEXITCODE){throw 'Could not capture the current desktop view for rollback.'}
 $trees=@(foreach($path in @('HKCU:\Control Panel\Cursors','Registry::HKEY_USERS\.DEFAULT\Control Panel\Cursors','HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler','HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-signin-clear-background','HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-lockscreen-clear-background')){Read-AShellTree $path})
 $values=@(foreach($v in $Desired){Read-RegistryValue $v[0] $v[1]})
 $values+=Read-RegistryValue 'HKLM:\SOFTWARE\Windhawk\Engine\Settings' 'Include'
 $values+=Get-AShellColorValues
 $values+=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
 $values+=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' 'ThemeChangesMousePointers'
 if(Get-Command Get-AShellMachineLockScreenRegistryValues -ErrorAction SilentlyContinue){$values+=Get-AShellMachineLockScreenRegistryValues}
 $wallpaper=(Get-ItemProperty 'HKCU:\Control Panel\Desktop').Wallpaper
 $cached=Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
 $desktopCopy=Join-Path $Folder 'desktop.img'
 if($wallpaper -and (Test-Path -LiteralPath $wallpaper)){Copy-Item -LiteralPath $wallpaper -Destination $desktopCopy}
 elseif(Test-Path $cached){Copy-Item -LiteralPath $cached -Destination $desktopCopy}
 Save-LockImage (Join-Path $Folder 'lock.img')
 $lockSource=Get-AShellLockSource;$lockOriginal=$null
 if($lockSource) {
  $lockOriginal='lock-original'+[IO.Path]::GetExtension($lockSource)
  Copy-Item -LiteralPath $lockSource -Destination (Join-Path $Folder $lockOriginal)
 }
 $tasks=@(foreach($name in @('Matrix Desktop - Instant Rain','A-Shell Cursor Session Guard','A-Shell Cursor Session Repair','A-Shell Session Repair','Codex Early Lively Wallpaper','Lively Wallpaper - Adi')){
  $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  @{Name=$name;Exists=($null -ne $task);Running=($task.State -eq 'Running');Xml=$(if($task){Export-ScheduledTask -TaskName $name})}
 })
 $files=@();$fileIndex=0
 foreach($tree in $trees | Where-Object {$_.Path -like 'HKLM:*'}) {
  $id=Split-Path $tree.Path -Leaf
  $paths=@((Join-Path $env:ProgramData ('Windhawk\ModsSource\'+$id+'.wh.cpp')))
  $config=Get-ItemProperty $tree.Path -ErrorAction SilentlyContinue
  if($config.LibraryFileName -and [IO.Path]::GetFileName($config.LibraryFileName) -eq $config.LibraryFileName){$paths+=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$config.LibraryFileName)}
  foreach($path in $paths){if(Test-Path -LiteralPath $path){$name='saved-file-'+$fileIndex+'.bin';Copy-Item -LiteralPath $path -Destination (Join-Path $Folder $name);$files+=@{Path=$path;Saved=$name};$fileIndex++}}
 }
 @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Trees=$trees;Values=$values;Wallpaper=$wallpaper;LockSource=$lockSource;LockOriginal=$lockOriginal;Tasks=$tasks;Files=$files;TerminalPath=(Read-RegistryValue 'HKCU:\Environment' 'Path')} | Export-Clixml (Join-Path $Folder 'checkpoint.clixml')
}
function Repair-AShellLegacyImageBaseline([string]$Root) {
 # v1.9 captures the immutable baseline before the desktop is hidden or any
 # wallpaper/theme/cursor mutation occurs. For an in-place upgrade, keep that
 # baseline unless it is byte-for-byte the bundled A-Shell image and an older
 # dedicated pre-A-Shell copy proves that a different original image existed.
 # This repairs the historical "original became the black A-Shell image" case
 # without guessing based on color or replacing legitimate custom wallpapers.
 $baseline=Join-Path $Root 'state\baseline'
 $bundled=Join-Path $Root 'assets\LockScreenPicture.png'
 if(!(Test-Path -LiteralPath $baseline) -or !(Test-Path -LiteralPath $bundled)){return}
 $bundleHash=(Get-FileHash -LiteralPath $bundled -Algorithm SHA256).Hash

 $desktop=Join-Path $baseline 'desktop.img'
 if((Test-Path -LiteralPath $desktop) -and (Get-FileHash -LiteralPath $desktop -Algorithm SHA256).Hash -eq $bundleHash) {
  $candidates=New-Object System.Collections.Generic.List[string]
  $legacy=Join-Path $Root 'state\desktop-before.img'
  if(Test-Path -LiteralPath $legacy){$candidates.Add($legacy)}
  $beforePath=Join-Path $Root 'state\before-setup.clixml'
  if(Test-Path -LiteralPath $beforePath) {
   try {
    $before=Import-Clixml -LiteralPath $beforePath
    if($before.Wallpaper -and (Test-Path -LiteralPath ([string]$before.Wallpaper))){$candidates.Add([string]$before.Wallpaper)}
   } catch {}
  }
  foreach($candidate in $candidates) {
   if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne $bundleHash) {
    Copy-Item -LiteralPath $candidate -Destination $desktop -Force
    Write-Output '[REPAIR] Recovered the original desktop wallpaper from the older pre-A-Shell backup; the legacy baseline had captured the bundled A-Shell image.'
    break
   }
  }
 }

 $lock=Join-Path $baseline 'lock.img'
 $legacyLock=Join-Path $Root 'state\lock-before.img'
 if((Test-Path -LiteralPath $lock) -and (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash -eq $bundleHash -and (Test-Path -LiteralPath $legacyLock) -and (Get-FileHash -LiteralPath $legacyLock -Algorithm SHA256).Hash -ne $bundleHash) {
  Copy-Item -LiteralPath $legacyLock -Destination $lock -Force
  Write-Output '[REPAIR] Recovered the original lock-screen image from the older pre-A-Shell backup.'
 }
}

function Update-AShellBaselineForNewValues([string]$Folder,$Desired) {
 $path=Join-Path $Folder 'checkpoint.clixml'
 if(!(Test-Path -LiteralPath $path)){return}
 $saved=Import-Clixml -LiteralPath $path
 Assert-AShellAccount $saved
 $values=@($saved.Values | Where-Object {$_.Path -notlike 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\*'})
 foreach($entry in $Desired) {
  $exists=@($values | Where-Object {$_.Path -eq $entry[0] -and $_.Name -eq $entry[1]}).Count -gt 0
  if(!$exists){$values+=Read-RegistryValue $entry[0] $entry[1]}
 }
 if(Get-Command Get-AShellMachineLockScreenRegistryValues -ErrorAction SilentlyContinue){
  foreach($value in @(Get-AShellMachineLockScreenRegistryValues)){
   $exists=@($values | Where-Object {$_.Path -eq $value.Path -and $_.Name -eq $value.Name}).Count -gt 0
   if(!$exists){$values+=$value}
  }
 }
 $saved.Values=$values
 $saved | Export-Clixml -LiteralPath $path
}
function Stop-AShellRendererForRestore([string]$Root,[switch]$PauseStartup) {
 $exe=Join-Path $Root 'bin\MatrixDesktop.exe'
 $session=(Get-Process -Id $PID).SessionId
 $running=@(Get-Process MatrixDesktop -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session})
 if($running|Where-Object {$_.Path -ne $exe}){throw 'Another A-Shell copy is running in this session. Stop that copy before restoring.'}
 if($PauseStartup){
  $task=Get-ScheduledTask -TaskName 'Matrix Desktop - Instant Rain' -ErrorAction SilentlyContinue
  if($task -and $task.Actions.Execute -contains $exe){Disable-ScheduledTask -TaskName $task.TaskName|Out-Null}
 }
 if($running.Count){
  Write-Output '[WORKING] Rain is draining naturally while the desktop is restored in parallel...'
  # --drain is a short control command; the existing renderer owns the visual fade.
  Start-Process $exe -ArgumentList '--drain' -WindowStyle Hidden -Wait
 }
 Write-Output '[OK] Rain drain started. Restoring wallpaper, colors and desktop now without waiting for the final trails.'
}
function Test-AShellWindhawkPayloadUpdateRequired([string]$Root) {
 # The taskbar payload keeps its upstream-compatible fixed filename, so it must
 # be unloaded before replacement. Both A-Shell lock/sign-in payloads are
 # content-addressed and are installed side-by-side by SignIn-Backdrop.ps1.
 $meta=Get-Content -LiteralPath (Join-Path $Root 'assets\windhawk\mod.json') -Raw | ConvertFrom-Json
 $source=Join-Path $Root ('assets\windhawk\'+[string]$meta.LibraryFileName)
 $destination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+[string]$meta.LibraryFileName)
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){return $false}
 if(!(Test-Path -LiteralPath $destination -PathType Leaf)){return $true}
 try {
  $sourceHash=(Get-FileHash -LiteralPath $source).Hash
  $destinationHash=(Get-FileHash -LiteralPath $destination).Hash
  return $sourceHash -ne $destinationHash
 } catch {return $true}
}
function Prepare-AShellWindhawkForFileUpdate([string]$Root,[switch]$ForRestore) {
 $ids=if($ForRestore){@('windows-11-taskbar-styler','ashell-signin-clear-background','ashell-lockscreen-clear-background')}else{@('windows-11-taskbar-styler')}
 $changed=$false
 foreach($id in $ids) {
  $path='HKLM:\SOFTWARE\Windhawk\Engine\Mods\'+$id
  if(Test-Path -LiteralPath $path) {
   try {
    Write-RegistryValue @{Path=$path;Name='Disabled';Kind='DWord';Value=1;Exists=$true}
    Write-RegistryValue @{Path=$path;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
    $changed=$true
   } catch {Write-Warning "Could not pre-disable Windhawk mod '$id': $($_.Exception.Message)"}
  }
 }
 $windhawk=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if($changed -and (Test-Path -LiteralPath $windhawk)) {
  try {Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden -ErrorAction Stop | Out-Null}catch{}
  Start-Sleep -Milliseconds $(if($ForRestore){1200}else{700})
 }
}
function Copy-AShellWindhawkPayload([string]$Source,[string]$Destination) {
 if(!(Test-Path -LiteralPath $Source -PathType Leaf)){throw "Windhawk payload is missing: $Source"}
 New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
 try {if((Test-Path -LiteralPath $Destination) -and (Get-FileHash -LiteralPath $Destination).Hash -eq (Get-FileHash -LiteralPath $Source).Hash){return}}catch{}
 $last=$null
 for($attempt=1;$attempt -le 24;$attempt++){
  try {Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop;return}
  catch {$last=$_;Start-Sleep -Milliseconds 250}
 }
 if([IO.Path]::GetFileName($Destination) -like 'windows-11-taskbar-styler*.dll') {
  Restart-AShellExplorerForWindhawkRelease
  for($attempt=1;$attempt -le 20;$attempt++){
   try {Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop;Write-Output '[OK] Updated taskbar Windhawk DLL after the Explorer refresh.';return}
   catch {$last=$_;Start-Sleep -Milliseconds 200}
  }
 }
 throw "Windhawk still has '$([IO.Path]::GetFileName($Destination))' loaded after unload/retry. Lock/unlock or restart Windows, then rerun setup. Last copy error: $last"
}
function Initialize-AShellMoveFileNative {
 if(!('AShellPendingFileReplace' -as [type])){Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AShellPendingFileReplace {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern bool MoveFileEx(string existingName, string newName, int flags);
}
'@}
}
function Restart-AShellExplorerForWindhawkRelease {
 Write-Warning 'Explorer still has the A-Shell taskbar DLL mapped. Restarting Explorer once so the original Windhawk file can be restored without waiting for a reboot.'
 $old=@(Get-Process explorer -ErrorAction SilentlyContinue)
 $oldIds=@($old | ForEach-Object {$_.Id})
 try {if($old.Count){$old | Stop-Process -Force -ErrorAction Stop}} catch {Write-Warning "Explorer restart request reported: $($_.Exception.Message)"}
 $deadline=(Get-Date).AddSeconds(8)
 do {
  $stillOld=@(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object {$oldIds -contains $_.Id})
  if(!$stillOld.Count){break}
  Start-Sleep -Milliseconds 120
 } while((Get-Date) -lt $deadline)
 if(!(Get-Process explorer -ErrorAction SilentlyContinue)){
  try {Start-Process explorer.exe -ErrorAction Stop | Out-Null}catch{Write-Warning "Explorer will be started by Windows automatically: $($_.Exception.Message)"}
 }
 Start-Sleep -Milliseconds 900
}
function Restore-AShellSavedFile([string]$Source,[string]$Destination,[string]$Root) {
 if(!(Test-Path -LiteralPath $Source -PathType Leaf)){throw "Saved Windhawk file is missing: $Source"}
 New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
 try {
  if((Test-Path -LiteralPath $Destination) -and (Get-FileHash -LiteralPath $Destination).Hash -eq (Get-FileHash -LiteralPath $Source).Hash){return $true}
 } catch {}
 $last=$null
 for($attempt=1;$attempt -le 24;$attempt++) {
  try {Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop;return $true}
  catch {$last=$_;Start-Sleep -Milliseconds 250}
 }
 # explorer.exe is the process that maps the taskbar-styler payload. Windhawk can
 # take a little while to detach it after a settings restart, so perform one
 # controlled Explorer restart before falling back to a reboot-time replacement.
 if([IO.Path]::GetFileName($Destination) -like 'windows-11-taskbar-styler*.dll') {
  Restart-AShellExplorerForWindhawkRelease
  for($attempt=1;$attempt -le 20;$attempt++) {
   try {Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop;Write-Output '[OK] Original taskbar Windhawk DLL restored after the Explorer refresh.';return $true}
   catch {$last=$_;Start-Sleep -Milliseconds 200}
  }
 }
 # A loaded injected DLL can remain mapped briefly even after Windhawk disables
 # the mod. Never fail the whole restore for that race: queue the exact previous
 # bytes for boot-time replacement, where no target process can keep the file open.
 Initialize-AShellMoveFileNative
 $pendingDir=Join-Path $Root 'state\pending-windhawk-restore';New-Item -ItemType Directory -Path $pendingDir -Force | Out-Null
 $pending=Join-Path $pendingDir (([IO.Path]::GetFileName($Destination))+'.'+[guid]::NewGuid().ToString('N')+'.pending')
 Copy-Item -LiteralPath $Source -Destination $pending -Force
 $flags=0x1 -bor 0x4 # MOVEFILE_REPLACE_EXISTING | MOVEFILE_DELAY_UNTIL_REBOOT
 if(![AShellPendingFileReplace]::MoveFileEx($pending,$Destination,$flags)){
  Remove-Item -LiteralPath $pending -Force -ErrorAction SilentlyContinue
  throw "Windhawk kept '$Destination' locked and Windows could not queue a reboot-time replacement. Last copy error: $last"
 }
 $script:AShellWindhawkRestorePendingReboot=$true
 Write-Warning "Windhawk still had '$([IO.Path]::GetFileName($Destination))' loaded after unload/retry. Its exact previous bytes are queued for replacement at the next reboot; restore will continue."
 return $false
}
function Restore-AShellCheckpoint([string]$Folder,[string]$Root,[switch]$RestoreTerminal) {
 $saved=Import-Clixml (Join-Path $Folder 'checkpoint.clixml')
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Checkpoint belongs to another account.'}
 Stop-AShellRendererForRestore $Root -PauseStartup
 if($saved.Wallpaper -and (Test-Path -LiteralPath $saved.Wallpaper) -and (Get-FileHash $saved.Wallpaper).Hash -eq (Get-FileHash (Join-Path $Folder 'desktop.img')).Hash){Set-DesktopImage $saved.Wallpaper}
 elseif(Test-Path (Join-Path $Folder 'desktop.img')){Set-DesktopImage (Join-Path $Folder 'desktop.img')}
 else {Set-DesktopImage ''}
 # Migrate any legacy machine-level image pin away before restoring through the
 # normal per-user LockScreen API. The checkpoint's exact policy values are restored below.
 if(Get-Command Restore-AShellLegacyMachineLockScreenPin -ErrorAction SilentlyContinue){[void](Restore-AShellLegacyMachineLockScreenPin $Root)}
 if(Get-Command Release-AShellLockScreenPolicyBlockers -ErrorAction SilentlyContinue){[void](Release-AShellLockScreenPolicyBlockers)}
 if($saved.LockOriginal -and (Test-Path (Join-Path $Folder $saved.LockOriginal))) {
  $original=Join-Path $Folder $saved.LockOriginal
  if($saved.LockSource -and (Test-Path -LiteralPath $saved.LockSource) -and (Get-FileHash $saved.LockSource).Hash -eq (Get-FileHash $original).Hash){Set-LockImage $saved.LockSource}
  else {Set-LockImage $original}
 } else {Set-LockImage (Join-Path $Folder 'lock.img')}
 Prepare-AShellWindhawkForFileUpdate $Root -ForRestore
 foreach($file in $saved.Files) {
  $source=Join-Path $Folder $file.Saved
  Restore-AShellSavedFile -Source $source -Destination $file.Path -Root $Root | Out-Null
 }
 foreach($tree in $saved.Trees){Restore-AShellTree $tree}
 foreach($value in $saved.Values){Write-RegistryValue $value}
 if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
 $desktopLayout=Join-Path $Folder 'desktop-layout.bin'
 if(Test-Path -LiteralPath $desktopLayout){
  for($attempt=0;$attempt -lt 4;$attempt++){
   if($attempt){Start-Sleep -Milliseconds 200}
   & (Join-Path $Root 'bin\DesktopLayout.exe') restore $desktopLayout
   if($LASTEXITCODE -eq 0){break}
   if($LASTEXITCODE -ne 2 -or $attempt -eq 3){Write-Warning 'The desktop view may finish restoring when Explorer refreshes.';break}
  }
 }
 if($RestoreTerminal -and $saved.TerminalPath){Write-RegistryValue $saved.TerminalPath}
 Send-AShellColorChange
 [void](Update-SystemCursors -BestEffort)
 foreach($task in $saved.Tasks){
  if($task.Name -in @('A-Shell Session Repair','A-Shell Cursor Session Repair')){
   $owned=Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
   if($owned){Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false}
   continue
  }
  if($task.Exists){Register-ScheduledTask -TaskName $task.Name -Xml $task.Xml -Force | Out-Null;if($task.Running){Start-ScheduledTask -TaskName $task.Name}}
  elseif(Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false}
 }
 $windhawk=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if((Test-Path $windhawk) -and !$script:AShellWindhawkRestorePendingReboot){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
}
