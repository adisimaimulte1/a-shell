$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\Manage.ps1') -Raw
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\CLI.ps1') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$uninstall=Get-Content -LiteralPath (Join-Path $root 'scripts\Uninstall.ps1') -Raw

if($runtime -notmatch 'already started.+No settings.+Matrix rain were touched'){throw 'Runtime start no-op guard is missing.'}
if($runtime -notmatch 'already stopped.+Nothing was restarted'){throw 'Runtime stop no-op guard is missing.'}
if($runtime -notmatch 'was not changed or saved.+Run ashell start first'){throw 'Stopped component mutation guard is missing.'}
if($cli -notmatch 'appearance/rain changes are skipped' -or $cli -notmatch "Title='SWITCHES'" -or $cli -notmatch "Title='APPEARANCE'"){throw 'Always-visible state-aware help is missing.'}
if($cli -notmatch 'Skip-AShellWhenStopped'){throw 'CLI stopped-state mutation gating is missing.'}
if($manage -notmatch 'Rain is already running.+left untouched'){throw 'Matrix start no-op is missing.'}
if($manage -notmatch 'Rain is already stopped'){throw 'Matrix stop no-op is missing.'}
if($installer -notmatch 'UPDATE COMPLETE' -or $installer -notmatch 'Saved user data and the existing started/stopped state were not changed'){throw 'Code-only update path is missing.'}
if($installer -notmatch 'MatrixDesktop\.exe\.pending'){throw 'Live Matrix update staging is missing.'}
if($uninstall -notmatch '⢀⣴⣾⣿⣿⣿⣷⣦'){throw 'Requested uninstall farewell art is missing.'}
Write-Output '[OK] Runtime idempotency, stopped-state command gating, code-only update and uninstall checks passed.'
