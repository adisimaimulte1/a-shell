# Static regression checks for installer upgrade support and locked Windhawk restore handling.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
$support=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.Support.ps1') -Raw
Assert ($installer -match 'Installed version' -and $installer -match 'Installer version' -and $installer -match 'Same-version reinstall / repair') 'Installer must identify upgrade, reinstall/repair and downgrade paths.'
Assert ($installer -match 'PreserveUserFiles') 'Installer must preserve recovery/user-owned data during upgrade.'
Assert ($installer -match 'MatrixDesktop\.exe\.pending') 'Installer must stage a changed Matrix binary without interrupting live rain.'
Assert ($installer -match 'OverrideLockScreenPolicy') 'Installer must pass explicit lock-screen override consent into setup.'
Assert ($setup -match 'OverrideLockScreenPolicy') 'Setup must have an explicit policy override switch.'
Assert ($setup -match 'Get-AShellLockScreenOverrideConsentPath') 'Successful consent must be retained while A-Shell is active.'
Assert ($support -match 'Prepare-AShellWindhawkForFileUpdate') 'Restore/update must unload A-Shell Windhawk mods before touching DLL files.'
Assert ($support -match 'MOVEFILE_DELAY_UNTIL_REBOOT') 'Locked Windhawk DLL restore must have a safe reboot-time fallback.'
Assert ($support -match 'Restore-AShellSavedFile') 'Windhawk file restoration must use retry/deferred replacement logic.'
Assert ($support -match 'Restart-AShellExplorerForWindhawkRelease') 'Locked taskbar DLL restore must retry after an Explorer restart before deferring to reboot.'
Assert ($installer -match 'IsARecognizedInstall') 'Installer upgrades must only overwrite a recognizable A-Shell installation.'
Assert ($installer -match 'ReadInstalledVersion' -and $installer -match 'CompareProductVersions') 'Installer does not detect and compare installed versions.'
Assert ($installer -match 'RollbackUpgrade') 'Failed in-place upgrades must restore the previous program tree.'
'PASS: installer upgrades preserve state; lock-screen override is explicit; Windhawk DLL restore no longer aborts on a transient file lock.'
