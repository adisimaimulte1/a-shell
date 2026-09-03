$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\Setup.Support.ps1"
function Assert($ok,$message){if(!$ok){throw $message}}
$known='51B3AA2B50944111F039C0DE035F9C8951A3FD7A65EDA7380AD30ECE5C2565BF'
$known11=Get-AShellCapabilities -Build 26100 -Architecture AMD64 -LogonHash $known
Assert ($known11.Core -and $known11.Windows11 -and $known11.TaskbarStyling -and $known11.LockScreenBackdrop -and $known11.SignInOverlay) 'Known Windows 11 build should enable every feature.'
$updated11=Get-AShellCapabilities -Build 26200 -Architecture AMD64 -LogonHash '0000000000000000000000000000000000000000000000000000000000000000'
Assert ($updated11.Core -and $updated11.Windows11 -and $updated11.Full -and $updated11.TaskbarStyling -and $updated11.LockScreenBackdrop) 'Unknown Windows 11 LogonUI hash must not downgrade stable Windows 11 styling.'
Assert (!$updated11.SignInOverlay) 'Unknown Windows 11 LogonUI hash must keep the private overlay hook disabled.'
$win10=Get-AShellCapabilities -Build 19045 -Architecture AMD64 -LogonHash ''
Assert ($win10.Core -and !$win10.Windows11 -and !$win10.Full -and !$win10.SignInOverlay) 'Windows 10 22H2 should remain on the compatibility feature profile.'
Write-Output 'PASS: Windows 11 stable styling is decoupled from the private LogonUI hash; Windows 10 remains on the compatibility feature profile.'
