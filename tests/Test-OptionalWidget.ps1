# Inject access denial without touching the user's registry.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'scripts\Appearance.Helpers.ps1')
function Read-RegistryValue($Path,$Name){@{Exists=$true;Kind='DWord';Value=0}}
function Test-Path {return $true}
function New-ItemProperty {throw [UnauthorizedAccessException]::new('Fixture access denial')}
$item=@{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='TaskbarDa';Kind='DWord';Value=1;Exists=$true}
$warnings=@();Write-RegistryValue $item -WarningVariable warnings
# Function warning streams propagate even when captured by the caller.
$item.Name='TaskbarAl';$failed=$false
try{Write-RegistryValue $item}catch{$failed=$true}
if(!$failed){throw 'Required appearance failures must still abort the transaction'}
'PASS: protected Widgets is nonfatal; other access failures still throw.'
