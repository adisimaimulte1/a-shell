$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\\CLI.ps1') -Raw
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\\Runtime.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\\Features.Support.ps1') -Raw
$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\\Cursors.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\\Manage.ps1') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\\Installer.cs') -Raw
$installerBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Installer.ps1') -Raw
$signin=Get-Content -LiteralPath (Join-Path $root 'scripts\\SignIn-Backdrop.ps1') -Raw
$screenSource=Get-Content -LiteralPath (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
if($cli -notmatch "'uninstall'"){throw 'Uninstall CLI command missing.'}
if($cli -match "desktop hide|desktop keep"){throw 'Removed desktop visibility switch leaked into help.'}
if($runtime -match 'desktop-icons|DesktopShortcutIcons'){throw 'Desktop visibility/shortcut toggle still exists in runtime.'}
if($runtime -match 'SessionRepair'){throw 'Obsolete full sign-in appearance replay still exists.'}
if($features -match 'desktopIcons'){throw 'Desktop icon visibility remains configurable.'}
if($cursors -notmatch "'Capture'"){throw 'Cursor pre-mutation capture is missing.'}
if($setup -notmatch '-Action Capture'){throw 'Setup does not capture cursors before appearance mutation.'}
if($manage -match '-Action SessionRepair' -or $manage -match 'New-ScheduledTaskAction.+Runtime\.ps1'){throw 'Direct full-appearance PowerShell logon task still exists.'}
if($manage -notmatch 'legacyRepairTaskName'){throw 'Legacy sign-in repair cleanup is missing.'}
if($cursors -notmatch 'New-ScheduledTaskAction -Execute \$guardExe' -or $cursors -match 'wscript\.exe|New-ScheduledTaskAction -Execute \$powershell'){throw 'Cursor repair is not using the native windowless CursorSessionGuard helper.'}
if($installer -notmatch 'AssemblyVersion\("__ASHELL_ASSEMBLY_VERSION__"\)' -or $installer -notmatch 'Version="__ASHELL_VERSION__"'){throw 'Installer version metadata is not generated from the canonical VERSION file.'}
if($installer -notmatch 'MigrateStartupTasks'){throw 'Installer update path does not migrate obsolete startup tasks.'}
if($installer -notmatch 'SetCurrentProcessExplicitAppUserModelID\("A-Shell\.Setup"\)'){throw 'Setup does not expose its stable shell identity.'}
if($installer -notmatch 'GetConsoleWindow' -or $installer -notmatch 'WM_SETICON' -or $installer -notmatch 'MonochromeIconsAreActive'){throw 'Setup live-window monochrome icon switching is missing.'}
if($installerBuild -notmatch 'AShell\.Monochrome\.png' -or $installerBuild -notmatch 'AShell\.Normal\.png' -or $installerBuild -notmatch 'icons-a-shell-96\.png' -or $installerBuild -notmatch 'A-Shell_Logo_Original_HQ\.png'){throw 'Setup normal/monochrome icon resources are not embedded in the installer.'}
if($installer -notmatch 'ForceNoHandoff' -or $installer -notmatch 'RelaunchInClassicConsole'){throw 'Setup does not escape Windows Terminal pseudoconsole hosting for deterministic taskbar branding.'}
if($signin -notmatch 'LockScreenOverlay' -or $signin -notmatch 'DimmingOverlayPassword' -or $signin -notmatch 'DimmingOverlayNoPassword'){throw 'Explicit LockApp overlay selectors are incomplete.'}
if($features -notmatch 'DisableWidgetsOnLockScreen'){throw 'Lock-screen widget suppression is missing.'}
if($screenSource -notmatch 'AShellClearRawBackgroundFilter' -or $screenSource -match '@include\s+LogonUI\.exe'){throw 'Guarded LockApp-only overlay fallback is not present or is scoped too broadly.'}
if($features -notmatch "'AnimateLockScreenBackground','DWord',1"){throw 'Screen runtime does not prevent the lock/logon image zoom path.'}
'Runtime source regression checks passed, including guarded LockApp styling, static image policy and windowless sign-in startup.'
