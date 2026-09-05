param([string]$Color='default',[ValidateSet('Apply','Restore','Check')][string]$Action='Apply')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
$root=Split-Path $PSScriptRoot
$snapshot=Join-Path $root 'state\accent-before.clixml'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($Action -eq 'Check'){Get-AShellColorValues;return}
if($Action -eq 'Apply'){
 $Color=ConvertTo-AShellColor $Color
 $saved=Get-AShellDesiredAccent $root
 $active=Read-RegistryValue 'HKCU:\Software\A-Shell' 'AccentColor'
 if($saved -eq $Color -and $active.Exists -and [string]$active.Value -eq $Color) {
  Write-Output ('[SKIP] Color is already #'+$Color+'. Nothing changed.')
  return
 }
}
. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
Enter-AShellOperation
$previous=@()
try {
 $previous=Get-AShellColorValues
 if($Action -eq 'Apply') {
  if(!(Test-Path $snapshot)) {
   New-Item -ItemType Directory (Split-Path $snapshot) -Force | Out-Null
   @{Sid=$sid;Values=$previous} | Export-Clixml $snapshot
  }
  if((Import-Clixml $snapshot).Sid -ne $sid){throw 'Accent backup belongs to another account.'}
  Set-AShellAccent $Color
  Set-AShellDesiredAccent $root $Color
  Write-Output ('[OK] Color: #'+$Color+'. Windows accent + rain synchronized.')
 } elseif(Test-Path $snapshot) {
  $saved=Import-Clixml $snapshot
  if($saved.Sid -ne $sid){throw 'Accent backup belongs to another account.'}
  foreach($value in $saved.Values){Write-RegistryValue $value}
  Send-AShellColorChange
  Write-Output '[OK] Previous Windows accent and Matrix color restored.'
 }
} catch {
 foreach($value in $previous){Write-RegistryValue $value}
 try {Send-AShellColorChange} catch {}
 throw
} finally {Exit-AShellOperation}
