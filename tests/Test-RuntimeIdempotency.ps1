$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$manage=Get-Content -LiteralPath (Join-Path $root 'scripts\Manage.ps1') -Raw
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\CLI.ps1') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$uninstall=Get-Content -LiteralPath (Join-Path $root 'scripts\Uninstall.ps1') -Raw

if($runtime -notmatch 'already started\. Nothing was reapplied'){throw 'Runtime start no-op guard is missing.'}
if($runtime -notmatch 'already stopped\. Nothing needed restoring'){throw 'Runtime stop no-op guard is missing.'}
if($runtime -notmatch 'A-Shell is stopped.+was not changed'){throw 'Stopped component mutation guard is missing.'}
$help=[regex]::Match($cli,"(?s)'help' \{.*?default \{throw 'Unknown command").Value
if($help -notmatch 'ashell background' -or $help -notmatch 'ashell rain on \| off \| status' -or $help -match 'ashell bg|startup install'){throw 'Canonical concise help surface is missing or still advertises legacy/technical aliases.'}
if($cli -notmatch 'Skip-AShellWhenStopped'){throw 'CLI stopped-state mutation gating is missing.'}
if($cli -notmatch '(?s)Manage\.ps1.+Set-AShellRainPreference'){throw 'Rain preference is saved before the live action succeeds.'}
if($manage -notmatch 'Existing Matrix renderer resumed/confirmed active'){throw 'Matrix repeated-start resume/confirmation path is missing.'}
if($manage -notmatch 'Rain is already stopped'){throw 'Matrix stop no-op is missing.'}
if($installer -notmatch 'UPDATE COMPLETE' -or $installer -notmatch 'Saved user data and the existing started/stopped state were not changed'){throw 'Code-only update path is missing.'}
if($installer -notmatch 'MatrixDesktop\.exe\.pending'){throw 'Live Matrix update staging is missing.'}
if($uninstall -notmatch 'Test-AShellRuntimeActive' -or $uninstall -notmatch 'already stopped; appearance restore is already complete' -or $uninstall -notmatch 'Restore-AShellLegacyDesktopArchive'){throw 'Stopped-state fast uninstall / exhaustive Desktop recovery is missing.'}
Write-Output '[OK] Runtime idempotency, canonical help, stopped-state command gating, code-only update and safe uninstall checks passed.'
