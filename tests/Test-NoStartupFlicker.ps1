$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\Manage.ps1') -Raw
$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\Cursors.ps1') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
$icons=Get-Content -LiteralPath (Join-Path $root 'scripts\Icons.Support.ps1') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$installerBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Installer.ps1') -Raw

if($runtime -match 'SessionRepair'){throw 'Runtime still exposes the delayed full appearance replay.'}
if($manage -match '-Action SessionRepair'){throw 'Manage still schedules the delayed full appearance replay.'}
if($manage -notmatch 'Unregister-ScheduledTask -TaskName \$legacyRepairTaskName'){throw 'Upgrade/setup does not remove the obsolete appearance repair task.'}
if($manage -notmatch 'Unregister-ScheduledTask -TaskName \$cursorRepairTaskName'){throw 'Upgrade/setup does not remove the obsolete cursor repair task.'}
if($cursors -notmatch 'New-ScheduledTaskAction -Execute \$guardExe' -or $cursors -notmatch 'New-ScheduledTaskTrigger -AtLogOn'){throw 'Cursor startup guard is not native/windowless at logon.'}
if($cursors -match 'New-ScheduledTaskAction -Execute \$powershell|wscript\.exe'){throw 'Cursor startup still launches a script host/PowerShell.'}
if($cursors -notmatch '\$settings\.Priority=0'){throw 'Cursor guard is not scheduled at highest priority.'}
if($cursors -notmatch 'ExecutionTimeLimit \(\[TimeSpan\]::Zero\)'){throw 'Cursor guard still has a scheduler time limit and can be killed while A-Shell remains active.'}
if($cursors -notmatch 'HKEY_USERS\\\.DEFAULT\\Control Panel\\Cursors'){throw 'Pre-logon cursor registry is not configured.'}
if($cursors -notmatch "ProgramData 'A-Shell\\Cursors\\MaterialPureDarkV2'"){throw 'Cursor files are not staged in ProgramData for pre-logon access.'}
if(Test-Path -LiteralPath (Join-Path $root 'scripts\CursorSessionRepair.vbs')){throw 'Obsolete cursor-session launcher is still packaged.'}
$guard=Get-Content -LiteralPath (Join-Path $root 'src\CursorSessionGuard.cpp') -Raw
if($guard -match 'FingerprintCoreCursors'){throw 'Cursor guard still uses multi-role/animated cursor state as its change detector.'}
if($guard -notmatch 'FingerprintArrowCursor' -or $guard -notmatch 'expectedArrow NEVER gets replaced'){throw 'Cursor guard does not use the stable normal-select cursor as a fixed expected state.'}


$start=[regex]::Match($runtime,'(?s)if\(\$Action -eq ''Start''\).*?Set-AShellRuntimeState \$root \$true').Value
if(!$start){throw 'Could not locate the ashell start transaction.'}
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
if($installer -notmatch 'WM_SETICON' -or $installer -notmatch 'ApplyConfiguredSetupIcon' -or $installer -notmatch 'AShell\.Monochrome\.png' -or $installer -notmatch 'LoadWindowIconResource' -or $installer -notmatch 'HighQualityBicubic'){throw 'Setup does not directly switch its live console/taskbar window icon at taskbar-safe resolution.'}
if($installerBuild -notmatch 'icons-a-shell-96\.png' -or $installerBuild -notmatch 'AShell\.Monochrome\.png' -or $installerBuild -notmatch 'AShell\.Normal\.png' -or $installerBuild -notmatch 'A-Shell_Logo_Original_HQ\.png' -or $installerBuild -notmatch 'System\.Drawing\.dll'){throw 'Installer build does not embed both live Setup icon resources.'}
if($installer -notmatch 'ForceNoHandoff' -or $installer -notmatch 'RelaunchInClassicConsole'){throw 'Interactive Setup can still be handed to Windows Terminal, where WM_SETICON cannot own the visible tab/window icon.'}
if($manage -match 'Update-AShellIcons.+A-Shell Setup' -or $manage -match 'Active monochrome icon rules include A-Shell Setup'){throw 'Code-only migration still touches taskbar settings just to style Setup.'}
if($icons -match "setupAppId='A-Shell\.Setup'"){throw 'Obsolete AppID-only Setup icon rule is still present.'}
Write-Output '[OK] No-startup-flicker regression checks passed.'
