param([ValidateSet('Install','Restore')][string]$Action='Install')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
$root=Split-Path $PSScriptRoot
$snapshot=Join-Path $root 'state\terminal-before.clixml'
$current=Read-RegistryValue 'HKCU:\Environment' 'Path'
if($Action -eq 'Install') {
 if(!(Test-Path $snapshot)) {
  New-Item -ItemType Directory (Split-Path $snapshot) -Force | Out-Null
  @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Path=$current;Added=(@(([string]$current.Value).Split(';')) -notcontains $root)} | Export-Clixml $snapshot
 }
 $saved=Import-Clixml $snapshot
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Terminal backup belongs to another account.'}
 if(@(([string]$current.Value).Split(';')) -notcontains $root) {
  $updated=([string]$current.Value).TrimEnd(';')
  if($updated){$updated+=';'};$updated+=$root
  Write-RegistryValue @{Path='HKCU:\Environment';Name='Path';Kind=$(if($current.Exists){$current.Kind}else{'ExpandString'});Value=$updated;Exists=$true}
 }
} elseif(Test-Path $snapshot) {
 $saved=Import-Clixml $snapshot
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Terminal backup belongs to another account.'}
 if($saved.Added -and $current.Exists) {
  $remaining=(@(([string]$current.Value).Split(';')) | Where-Object {$_ -ne $root}) -join ';'
  if($remaining -eq [string]$saved.Path.Value){Write-RegistryValue $saved.Path}
  else {Write-RegistryValue @{Path='HKCU:\Environment';Name='Path';Kind=$current.Kind;Value=$remaining;Exists=$true}}
 }
}
$result=[IntPtr]::Zero
[void][AShellAccentNative]::Broadcast([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'Environment',2,100,[ref]$result)
