# Static regression checks for the 1.8 runtime command surface and reversible desktop-icon layer.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\CLI.ps1') -Raw
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$desktop=Get-Content -LiteralPath (Join-Path $root 'scripts\DesktopIcons.Support.ps1') -Raw
$layout=Get-Content -LiteralPath (Join-Path $root 'src\DesktopLayout.cpp') -Raw
$screen=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
foreach($command in @("'lock'","'taskbar'","'desktop'","'bg'")){Assert ($cli.Contains($command)) "Missing quick command $command"}
Assert ($cli.Contains("$PSScriptRoot\\Runtime.ps1") -or $cli.Contains('$PSScriptRoot\Runtime.ps1')) 'Quick switches must use the installed runtime controller.'
Assert ($runtime.Contains('Sync-AShellDesktopMonochrome')) 'Runtime must synchronize visible desktop shortcuts with the icon switch.'
Assert ($desktop.Contains("Filter '*.lnk'")) 'Desktop monochrome layer must target shortcut files without moving Desktop contents.'
Assert ($desktop.Contains('desktop-monochrome-before.clixml')) 'Desktop shortcut originals must be backed up for stop/restore.'
Assert ($layout.Contains('L"show"') -and $layout.Contains('SetCurrentFolderFlags(FWF_NOICONS,0)')) 'DesktopLayout must clear the live FWF_NOICONS flag for `ashell desktop show`.'
Assert ($features.Contains('LockScreenOverlaysDisabled')) 'Screen runtime must suppress Windows lock-screen informational overlays while A-Shell lock mode is on.'
foreach($target in @('BackgroundDimmingLayer','DimmingOverlayPassword','BackgroundScrim','HotspotContainer')){Assert ($screen.Contains($target)) "Pure-image screen rules are missing $target"}
Write-Output 'PASS: short runtime switches, reversible desktop monochrome shortcuts, explicit desktop show, and pure-image screen rules are present.'
