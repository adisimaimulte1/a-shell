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
if($cursors -notmatch 'wscript\.exe' -or $cursors -match 'New-ScheduledTaskAction -Execute \$powershell'){throw 'Cursor repair is not using the windowless WScript launcher.'}
if($installer -notmatch '1\.9\.3\.0'){throw 'Installer version metadata is stale.'}
if($installer -notmatch 'MigrateStartupTasks'){throw 'Installer update path does not migrate obsolete startup tasks.'}
if($installer -notmatch 'SetCurrentProcessExplicitAppUserModelID\("A-Shell\.Setup"\)'){throw 'Setup does not expose its stable shell identity.'}
if($installer -notmatch 'GetConsoleWindow' -or $installer -notmatch 'WM_SETICON' -or $installer -notmatch 'MonochromeIconsAreActive'){throw 'Setup live-window monochrome icon switching is missing.'}
if($installerBuild -notmatch 'AShell\.Monochrome\.png' -or $installerBuild -notmatch 'icons-a-shell-96\.png'){throw 'Setup monochrome icon is not embedded in the installer.'}
if($signin -notmatch 'ColorOverlay' -or $signin -notmatch 'Background=Transparent'){throw 'Pure lock-screen XAML hardening rules are incomplete.'}
if($features -notmatch 'DisableWidgetsOnLockScreen'){throw 'Lock-screen widget suppression is missing.'}
if($screenSource -notmatch 'AShellIsDarkTranslucentBrush' -or $screenSource -notmatch 'AShellClearRawBackgroundFilter'){throw 'Native raw-background brush filter pass is missing.'}
'Runtime 1.9 source regression checks passed, including windowless sign-in startup.'
