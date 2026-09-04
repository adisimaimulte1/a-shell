$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\Manage.ps1') -Raw
$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\Cursors.ps1') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
$icons=Get-Content -LiteralPath (Join-Path $root 'scripts\Icons.Support.ps1') -Raw
$launcher=Get-Content -LiteralPath (Join-Path $root 'scripts\CursorSessionRepair.vbs') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$installerBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Installer.ps1') -Raw

if($runtime -match 'SessionRepair'){throw 'Runtime still exposes the delayed full appearance replay.'}
if($manage -match '-Action SessionRepair'){throw 'Manage still schedules the delayed full appearance replay.'}
if($manage -notmatch 'Unregister-ScheduledTask -TaskName \$legacyRepairTaskName'){throw 'Upgrade/setup does not remove the obsolete repair task.'}
if($manage -notmatch "Cursors\.ps1'\) -Action RepairTask"){throw 'Startup repair does not migrate the cursor task to the windowless launcher.'}
if($cursors -notmatch 'System32\\wscript\.exe' -or $cursors -match 'New-ScheduledTaskAction -Execute \$powershell'){throw 'Cursor logon repair can still create a visible PowerShell console.'}
if($launcher -notmatch 'shell\.Run\(command, 0, True\)'){throw 'Cursor launcher is not explicitly windowless.'}

$start=[regex]::Match($runtime,'(?s)if\(\$Action -eq ''Start''\).*?# STOP').Value
if($start -match 'Send-AShellThemeChange'){throw 'ashell start still broadcasts WM_THEMECHANGED after applying the taskbar.'}
if($start -match 'Restart-AShellWindhawkRuntime'){throw 'ashell start still unconditionally restarts Windhawk.'}
if($start -notmatch 'Ensure-AShellTaskbarRuntimeLoaded'){throw 'ashell start has no pre-rain hot-load verification/fallback.'}

$postRain=[regex]::Match($setup,'(?s)& \(Join-Path \$PSScriptRoot ''Manage\.ps1''\) -Action Install.*?Assert-AShellInstalled').Value
if($postRain -match 'Send-AShellThemeChange'){throw 'Setup still broadcasts WM_THEMECHANGED after Matrix startup.'}
if($setup -match 'Assert-AShellInstalled[^\r\n]*[\r\n]+\s*if\(\$useFullAppearance\)\{Start-Process \$windhawk'){throw 'Setup still unconditionally restarts Windhawk at the end.'}
if($setup -notmatch 'Test-AShellWindhawkPayloadUpdateRequired'){throw 'Repeat setup still unloads Windhawk even when binaries already match.'}
if($setup -notmatch '\$themeRefreshRequired' -or $setup -notmatch 'Windows light/dark theme already matches A-Shell'){throw 'Repeat setup still forces an unnecessary Windows theme repaint.'}

if($features -notmatch 'Update-AShellIcons \$Root -SkipTaskbarBase -PreserveUnlisted -DeferApply'){throw 'Composite taskbar update does not defer icon notification.'}
if($icons -notmatch '\[switch\]\$DeferApply'){throw 'Icon refresh has no deferred transaction mode.'}
if($installer -notmatch 'MigrateStartupTasks'){throw 'Code-only installer upgrade leaves old logon tasks behind.'}
if($installer -notmatch 'A-Shell\.Setup'){throw 'Setup has no stable AppUserModelID.'}
if($installer -notmatch 'WM_SETICON' -or $installer -notmatch 'ApplyConfiguredSetupIcon' -or $installer -notmatch 'AShell\.Monochrome\.png' -or $installer -notmatch 'new Bitmap\(source,256,256\)'){throw 'Setup does not directly switch its live console/taskbar window icon at taskbar-safe resolution.'}
if($installerBuild -notmatch 'icons-a-shell-96\.png' -or $installerBuild -notmatch 'AShell\.Monochrome\.png' -or $installerBuild -notmatch 'System\.Drawing\.dll'){throw 'Installer build does not embed the monochrome Setup icon resource.'}
if($manage -match 'Update-AShellIcons.+A-Shell Setup' -or $manage -match 'Active monochrome icon rules include A-Shell Setup'){throw 'Code-only migration still touches taskbar settings just to style Setup.'}
if($icons -match "setupAppId='A-Shell\.Setup'"){throw 'Obsolete AppID-only Setup icon rule is still present.'}
Write-Output '[OK] No-startup-flicker regression checks passed.'
