$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot)
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\\CLI.ps1') -Raw
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\\Runtime.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\\Features.Support.ps1') -Raw
$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\\Cursors.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\\Manage.ps1') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\\Installer.cs') -Raw
$signin=Get-Content -LiteralPath (Join-Path $root 'scripts\\SignIn-Backdrop.ps1') -Raw
$screenSource=Get-Content -LiteralPath (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
if($cli -notmatch "'uninstall'"){throw 'Uninstall CLI command missing.'}
if($cli -match "desktop hide|desktop keep"){throw 'Removed desktop visibility switch leaked into help.'}
if($runtime -match 'desktop-icons|DesktopShortcutIcons'){throw 'Desktop visibility/shortcut toggle still exists in runtime.'}
if($runtime -notmatch 'SessionRepair'){throw 'Sign-in session repair is missing.'}
if($features -match 'desktopIcons'){throw 'Desktop icon visibility remains configurable.'}
if($cursors -notmatch "'Capture'"){throw 'Cursor pre-mutation capture is missing.'}
if($setup -notmatch '-Action Capture'){throw 'Setup does not capture cursors before appearance mutation.'}
if($manage -notmatch 'A-Shell Session Repair'){throw 'Session repair scheduled task is missing.'}
if($installer -notmatch '1\.9\.2\.0'){throw 'Installer version metadata was not bumped.'}
if($signin -notmatch 'ColorOverlay' -or $signin -notmatch 'Background=Transparent'){throw 'Pure lock-screen XAML hardening rules are incomplete.'}
if($features -notmatch 'DisableWidgetsOnLockScreen'){throw 'Lock-screen widget suppression is missing.'}
if($screenSource -notmatch 'AShellIsDarkTranslucentBrush' -or $screenSource -notmatch 'AShellClearRawBackgroundFilter'){throw 'Native raw-background brush filter pass is missing.'}
'Runtime 1.9 source regression checks passed.'
