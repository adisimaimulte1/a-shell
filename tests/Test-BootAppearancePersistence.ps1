$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$background=Get-Content -LiteralPath (Join-Path $root 'scripts\Background.Support.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
$setupSupport=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.Support.ps1') -Raw
$signin=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
$signinNative=Get-Content -LiteralPath (Join-Path $root 'src\signin-clear-background.wh.cpp') -Raw
$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\Cursors.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\Manage.ps1') -Raw
$uninstall=Get-Content -LiteralPath (Join-Path $root 'scripts\Uninstall.ps1') -Raw

# Do not reintroduce the legacy machine/CSP image pin that caused different
# lock-to-sign-in framing/zoom.
foreach($dead in @('Set-AShellMachineLockScreenImage','Suspend-AShellMachineLockScreenGuard','Save-AShellMachineLockScreenBaseline','Wait-AShellMachineLockScreenReady')) {
 if($background.Contains($dead) -or $features.Contains($dead) -or $runtime.Contains($dead) -or $setup.Contains($dead) -or $manage.Contains($dead)){throw "Retired machine-image path is still referenced: $dead"}
}
if(!$background.Contains('Restore-AShellLegacyMachineLockScreenPin')){throw 'Old machine-image state is not migrated away.'}
if(!$setup.Contains('Set-LockImage $image')){throw 'Fresh setup no longer uses the native per-user lock-screen image API.'}
if(!$features.Contains('Set-LockImage $target')){throw 'Runtime screen-on no longer uses the native per-user lock-screen image API.'}
if(!$runtime.Contains('Set-LockImage $lock')){throw 'Windows 10 compatibility path no longer uses the native lock-screen image API.'}
if(!$manage.Contains('Set-LockImage $lock')){throw 'Code-only upgrade does not reassert the native lock image after removing a legacy machine pin.'}

# Blur and 45% overlay are separate and both must be handled.
if(!$signin.Contains('DisableAcrylicBackgroundOnLogon')){throw 'Clear-logon acrylic policy is missing.'}
if($signin.Contains('LogonBackgroundBrush:=') -or $signin.Contains('LogonBackgroundBackdrop:=')){throw 'Retired guessed XAML resource overrides are still configured.'}
foreach($needle in @('0x94140','0x64970','ZoomHookInstalled','ZoomDisabled','0x170','0.45','Opacity(0.0)')){
 if(!$signinNative.Contains($needle)){throw "Known-good exact 45% fast path is missing: $needle"}
}
if(!$setupSupport.Contains('Get-AShellSignInPayloadInfo') -or !$setupSupport.Contains('ashell-signin-clear-background_1.0.build.json') -or !$setupSupport.Contains('bundled LogonUI Windhawk DLL is stale relative to its source')){throw 'Narrow sign-in hook is not bundled with verified source-to-binary provenance.'}
if(!$setupSupport.Contains('ashell-lockscreen-clear-background_1.7')){throw 'Stable selector-only LockApp payload is not configured.'}
if(Test-Path -LiteralPath (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background_1.9.dll')){throw 'Broad legacy LockApp payload is still packaged.'}
if($signin -match "Name='AnimationDisabled';Kind='DWord';Value=1"){throw 'A-Shell must not force LogonUI AnimationDisabled; that experiment caused black/scaled lock transitions.'}
if(!$signin.Contains("Name='AnimateLockScreenBackground';Kind='DWord';Value=1") -or !$features.Contains("'AnimateLockScreenBackground','DWord',1") -or !$setup.Contains("'AnimateLockScreenBackground','DWord',1")){throw 'The supported static lock/sign-in image policy is not applied by every screen-on path.'}
if(!$signin.Contains("'LockScreenOverlay'")){throw 'LockApp raw-photo overlay is not targeted explicitly.'}

# Preserve newest cursor persistence behavior.
if(!$cursors.Contains('Registry::HKEY_USERS\.DEFAULT\Control Panel\Cursors')){throw 'Winlogon/default desktop cursor state is not aligned with A-Shell.'}
if(!$cursors.Contains("Join-Path `$env:ProgramData 'A-Shell\Cursors\MaterialPureDarkV2'")){throw 'Cursor assets are not available before the user profile loads.'}
if(!$cursors.Contains('New-ScheduledTaskAction -Execute $guardExe') -or !$cursors.Contains("New-ScheduledTaskTrigger -AtLogOn")){throw 'Native cursor guard is not registered at interactive logon.'}
if($cursors -match 'New-ScheduledTaskAction -Execute \$powershell|wscript\.exe|cmd\.exe.+Cursor'){throw 'Cursor startup regressed to a script/console launcher.'}
if(!$cursors.Contains('$settings.Priority=0')){throw 'Cursor guard is not scheduled at the highest Task Scheduler priority.'}
if(!$cursors.Contains('ExecutionTimeLimit ([TimeSpan]::Zero)')){throw 'Cursor guard is still allowed to expire during a long A-Shell session.'}
$guard=Get-Content -LiteralPath (Join-Path $root 'src\CursorSessionGuard.cpp') -Raw
if(!$guard.Contains('FingerprintArrowCursor') -or $guard.Contains('FingerprintCoreCursors')){throw 'Cursor guard still fingerprints animated cursor roles and can self-trigger flicker.'}
if(!$guard.Contains('while (AShellIsActive(root))')){throw 'Cursor guard stops after an arbitrary startup window instead of protecting the active A-Shell session.'}
if(!$guard.Contains('expectedArrow NEVER gets replaced') -or !$guard.Contains('if (repaired == expectedArrow) continue;')){throw 'Cursor guard can still learn/bless a Windows-default cursor after a race.'}
if(!$setupSupport.Contains('Pre-logon cursor persistence verification failed.')){throw 'Setup verification does not check the .DEFAULT cursor state.'}
if(!$manage.Contains('Unregister-ScheduledTask -TaskName $cursorRepairTaskName')){throw 'Upgrade migration does not remove the old cursor task.'}
if(!$manage.Contains("Cursors.ps1') -Action Migrate")){throw 'Code-only installer upgrade does not migrate cursor persistence for an already-active A-Shell.'}
if(!$uninstall.Contains("Join-Path `$env:ProgramData 'A-Shell'")){throw 'Uninstall does not clean machine-level A-Shell cursor/legacy staging after restore.'}

Write-Output '[OK] Static lock/sign-in framing, guarded backdrop handling, and boot cursor persistence regression checks passed.'
