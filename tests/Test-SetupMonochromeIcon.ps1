$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$build=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Installer.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\Manage.ps1') -Raw
$icons=Get-Content -LiteralPath (Join-Path $root 'scripts\Icons.Support.ps1') -Raw
$asset=Join-Path $root 'assets\icons\icons-a-shell-96.png'
if(!(Test-Path -LiteralPath $asset -PathType Leaf)){throw 'Canonical monochrome A-Shell icon is missing.'}
if($installer -notmatch 'RuntimeIsActive' -or $installer -notmatch 'features\.json' -or $installer -notmatch '"icons",true'){throw 'Setup does not gate its monochrome icon on the saved active/icons state.'}
if($installer -notmatch 'GetConsoleWindow' -or $installer -notmatch 'WM_SETICON' -or $installer -notmatch 'ICON_BIG' -or $installer -notmatch 'ICON_SMALL' -or $installer -notmatch 'new Bitmap\(source,256,256\)'){throw 'Setup does not set a high-resolution live console/titlebar/taskbar icon.'}
if($installer -notmatch 'AShell\.Monochrome\.png'){throw 'Setup does not load the embedded monochrome icon resource.'}
if($build -notmatch '/resource:\$monochromeIcon,AShell\.Monochrome\.png' -or $build -notmatch 'System\.Drawing\.dll'){throw 'Build-Installer does not embed/compile the live monochrome icon support.'}
if($manage -match 'Active monochrome icon rules include A-Shell Setup'){throw 'Old AppID-only taskbar workaround is still active during upgrade.'}
if($icons -match "setupAppId='A-Shell\.Setup'"){throw 'Old AppID-only Setup icon rule is still generated.'}
Write-Output '[OK] Setup monochrome live-window icon regression checks passed.'
