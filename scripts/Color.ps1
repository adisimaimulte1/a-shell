param([string]$Color='default',[ValidateSet('Apply','Restore','Check')][string]$Action='Apply')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
$root=Split-Path $PSScriptRoot
$snapshot=Join-Path $root 'state\accent-before.clixml'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($Action -eq 'Check'){Get-AShellColorValues;return}
if($Action -eq 'Apply'){$Color=ConvertTo-AShellColor $Color}
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
  $desiredFile=Join-Path $root 'state\desired-accent.txt'
  Set-Content -LiteralPath $desiredFile -Value $Color -Encoding ascii
  Write-Output "[OK] Windows accent and Matrix rain: #$Color. Existing rain keeps running."
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
