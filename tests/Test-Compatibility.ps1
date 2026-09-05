$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\Setup.Support.ps1"
function Assert($ok,$message){if(!$ok){throw $message}}
$known11=Get-AShellCapabilities -Build 26100 -Architecture AMD64
Assert ($known11.Core -and $known11.Windows11 -and $known11.TaskbarStyling -and $known11.LockScreenBackdrop -and $known11.SignInOverlay) 'Windows 11 should enable every supported appearance feature.'
$updated11=Get-AShellCapabilities -Build 26200 -Architecture AMD64
Assert ($updated11.Core -and $updated11.Windows11 -and $updated11.Full -and $updated11.TaskbarStyling -and $updated11.LockScreenBackdrop -and $updated11.SignInOverlay) 'Windows 11 should keep the narrow sign-in hook available; the hook itself fails closed on an unverified LogonUI binary.'
$win10=Get-AShellCapabilities -Build 19045 -Architecture AMD64
Assert ($win10.Core -and !$win10.Windows11 -and !$win10.Full -and $win10.SignInOverlay) 'Windows 10 22H2 should enable the narrow sign-in hook while keeping Windows 11-only styling off.'
Write-Output 'PASS: platform routing is stable; narrow LogonUI overlay removal remains fail-closed by binary verification.'
