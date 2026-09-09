$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\Cursors.ps1') -Raw
$guard=Get-Content -LiteralPath (Join-Path $root 'src\CursorSessionGuard.cpp') -Raw
$background=Get-Content -LiteralPath (Join-Path $root 'scripts\Background.Support.ps1') -Raw
$signin=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
$screenSource=Get-Content -LiteralPath (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') -Raw
$signInNative=Get-Content -LiteralPath (Join-Path $root 'src\signin-clear-background.wh.cpp') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
$matrix=Get-Content -LiteralPath (Join-Path $root 'src\MatrixDesktop.cpp') -Raw

if($cursors -notmatch "ThemeChangesMousePointers';Kind='DWord';Value=0"){throw 'Windows theme activation can still swap the A-Shell cursor scheme.'}
if($cursors -notmatch 'Registry::HKEY_USERS\\\.DEFAULT\\Control Panel\\Cursors'){throw 'Pre-login cursor registry is not synchronized.'}
if($cursors -notmatch 'New-ScheduledTaskAction -Execute \$guardExe' -or $cursors -match 'wscript\.exe|New-ScheduledTaskAction -Execute \$powershell'){throw 'Cursor guard is not a native/windowless logon action.'}
if($guard -notmatch 'FingerprintArrowCursor' -or $guard -match 'FingerprintCoreCursors'){throw 'Animated cursor fingerprinting can still self-trigger resets.'}
if($guard -notmatch 'while \(AShellIsActive\(root\)\)' -or $guard -match 'deadline = GetTickCount64\(\) \+ 45000'){throw 'Cursor protection still expires while A-Shell is active.'}
if($cursors -notmatch 'ExecutionTimeLimit \(\[TimeSpan\]::Zero\)'){throw 'Task Scheduler can still terminate the cursor guard during an active session.'}
if($guard -notmatch 'expectedArrow NEVER gets replaced'){throw 'Guard can still learn an incorrect cursor after a reset race.'}

if($background -match 'Set-AShellMachineLockScreenImage|Suspend-AShellMachineLockScreenGuard|Wait-AShellMachineLockScreenReady'){throw 'Retired machine/CSP lock-image forcing is still present.'}
if($background -notmatch 'Restore-AShellLegacyMachineLockScreenPin'){throw 'Legacy machine-image migration cleanup is missing.'}
if($signin -match 'LogonBackgroundBrush:=|LogonBackgroundBackdrop:='){throw 'Retired guessed LogonUI resource overrides are still configured.'}
foreach($needle in @('HookSymbols','noUndecoratedSymbols','ZoomHookInstalled','ZoomDisabled','QueryInterface','0.45')) {
 if($signInNative -notmatch [regex]::Escape($needle)){throw "Sign-in backdrop narrow guard is missing: $needle"}
}

# The fallback is now LockApp-only and accepts only dark translucent brushes in
# named background contexts or near-full-screen surfaces. It must never target
# images, opaque backgrounds, or LogonUI.
foreach($needle in @('AShellClearRawBackgroundFilter','AShellIsBackgroundContext','AShellIsDarkTranslucentBrush','alpha > 0.0 && alpha <= 0.75','width >= rootWidth * 0.90','element.try_as<winrt::Windows::UI::Xaml::Shapes::Rectangle>')){
 if(!$screenSource.Contains($needle)){throw "Guarded LockApp overlay fallback is missing: $needle"}
}
if($screenSource -match '@include\s+LogonUI\.exe' -or $screenSource -match '_wcsicmp\(processName, L"LogonUI\.exe"\)'){throw 'The broader LockApp fallback must not run inside LogonUI.'}
if($screenSource -match 'try_as<winrt::Windows::UI::Xaml::Controls::Image>'){throw 'LockApp fallback must never alter the photo element.'}
if($features -notmatch "'AnimateLockScreenBackground','DWord',1" -or $signin -notmatch "Name='AnimateLockScreenBackground';Kind='DWord';Value=1"){throw 'Static lock/sign-in image policy is missing.'}
if($signin -notmatch 'DimmingOverlayPassword' -or $signin -notmatch 'DimmingOverlayNoPassword'){throw 'Known credential-screen dimmers are no longer configured.'}

foreach($switch in @('screens','signInHook','taskbarTransparency','icons','rain')){
 if($features -notmatch $switch){throw "Saved feature state is missing '$switch'."}
}
if($matrix -notmatch 'AShellShouldAutoStartRain' -or $matrix -notmatch '"rain",true'){throw 'Native rain startup does not consult the saved rain preference.'}


if(!$signin.Contains("'LockScreenOverlay'")){throw 'LockApp LockScreenOverlay is not explicitly suppressed.'}
if($signin -match "Name='AnimationDisabled';Kind='DWord';Value=1"){throw 'Obsolete LogonUI AnimationDisabled override is still actively configured.'}
Write-Output '[OK] Cursor, static lock/sign-in framing, guarded backdrop handling, and reboot-state persistence regression checks passed.'
