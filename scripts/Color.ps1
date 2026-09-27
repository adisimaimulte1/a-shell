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
 if($Color -eq 'list'){Show-AShellColorPresets;return}
 $selection=Resolve-AShellColor $Color
 $Color=$selection.Stored
 $saved=Get-AShellDesiredAccent $root
 $active=Read-RegistryValue 'HKCU:\Software\A-Shell' 'AccentColor'
 if($saved -eq $Color -and $active.Exists -and [string]$active.Value -eq $selection.Hex) {
  Write-Output ('[SKIP] Color is already '+$selection.Name+'. Nothing changed.')
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
  Set-AShellAccent $selection.Hex $selection.Rain
  Set-AShellDesiredAccent $root $Color
  if($selection.Rain -eq 'rainbow'){Write-Output '[OK] Color: rainbow. Windows highlight is white; rain is rainbow.'}
  else {Write-Output ('[OK] Color: '+$selection.Name+' (#'+$selection.Hex+'). Windows accent + rain synchronized.')}
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
