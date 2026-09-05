# Inject access denial without touching the user's registry.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'scripts\Appearance.Helpers.ps1')
$script:writes=0
function Read-RegistryValue($Path,$Name){@{Exists=$true;Kind='DWord';Value=0}}
function Test-Path {return $true}
function New-ItemProperty {$script:writes++;throw [UnauthorizedAccessException]::new('Fixture access denial')}

# PowerShell 5.1 may report registry denial through the provider category even
# when the outer exception is generic. That wrapper must still be recognized.
$wrapped=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('Fixture provider wrapper'),'fixture.permission',[Management.Automation.ErrorCategory]::PermissionDenied,$null)
if(!(Test-AShellAccessDeniedError $wrapped)){throw 'PermissionDenied provider errors were not recognized.'}

# Windows-owned shell polish must not abort the whole setup when protected.
$item=@{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='TaskbarDa';Kind='DWord';Value=1;Exists=$true}
Write-RegistryValue $item
$item.Name='TaskbarAl'
Write-RegistryValue $item

# SystemProtectedUserData is intentionally read-only to A-Shell; no write attempt.
$before=$script:writes
$item=@{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\S-1-5-21-fixture\AnyoneRead\LockScreen';Name='HideLogonBackgroundImage';Kind='DWord';Value=0;Exists=$true}
Write-RegistryValue $item
if($script:writes -ne $before){throw 'A-Shell attempted to write SystemProtectedUserData.'}

# Installer-owned Windhawk settings remain required in Complete mode.
$item=@{Path='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler';Name='Disabled';Kind='DWord';Value=1;Exists=$true}
$failed=$false
try{Write-RegistryValue $item}catch{$failed=$true}
if(!$failed){throw 'Required A-Shell integration failures must still abort the transaction.'}
'PASS: optional Windows shell settings are nonfatal, SystemProtectedUserData is never written, and required A-Shell registry writes still fail closed.'
