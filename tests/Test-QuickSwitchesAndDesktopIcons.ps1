# Static regression checks for the concise runtime surface and hide-only Desktop design.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\CLI.ps1') -Raw
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
$desktop=Get-Content -LiteralPath (Join-Path $root 'scripts\Desktop.Support.ps1') -Raw
$layout=Get-Content -LiteralPath (Join-Path $root 'src\DesktopLayout.cpp') -Raw
$screen=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
foreach($command in @("'screen'","'taskbar'","'background'")){Assert ($cli.Contains($command)) "Missing canonical command $command"}
Assert ($cli.Contains("$PSScriptRoot\\Runtime.ps1") -or $cli.Contains('$PSScriptRoot\Runtime.ps1')) 'Quick switches must use the installed runtime controller.'
Assert ($runtime.Contains('Hide-AShellDesktopIconsNow')) 'Runtime must enforce the icon-free desktop when A-Shell starts.'
Assert ($desktop.Contains("Mode='HideOnly'")) 'Desktop state must use the hide-only schema.'
Assert ($desktop.Contains('No Desktop file is moved')) 'Current Desktop handling must not move personal files.'
Assert (!(Test-Path -LiteralPath (Join-Path $root 'scripts\DesktopIcons.Support.ps1'))) 'Unused shortcut-rewrite implementation is still packaged.'
Assert ($layout.Contains('L"restore"') -and $layout.Contains('FWF_AUTOARRANGE|FWF_SNAPTOGRID|FWF_NOICONS')) 'DesktopLayout restore must restore the saved live FWF_NOICONS flag.'
Assert ($features.Contains('RotatingLockScreenOverlayEnabled') -and $features.Contains('DisableWidgetsOnLockScreen')) 'Screen runtime must suppress Windows lock-screen informational overlays while A-Shell lock mode is on.'
foreach($target in @('LockScreenOverlay','DimmingOverlayPassword','DimmingOverlayNoPassword')){Assert ($screen.Contains($target)) "Narrow LockApp overlay rule is missing $target"}
Write-Output 'PASS: short runtime switches, hide-only Desktop state, explicit restore, and narrow screen rules are present.'
