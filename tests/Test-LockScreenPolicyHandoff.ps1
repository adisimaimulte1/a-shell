# Isolated regression checks for lock-screen policy discovery/handoff. No registry changes.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Appearance.Helpers.ps1')
. (Join-Path $root 'scripts\Background.Support.ps1')
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
$policy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
$csp='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
$system='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$fixture=@{
 ($policy+'|NoChangingLockScreen')=@{Path=$policy;Name='NoChangingLockScreen';Exists=$true;Kind='DWord';Value=1}
 ($policy+'|NoLockScreen')=@{Path=$policy;Name='NoLockScreen';Exists=$true;Kind='DWord';Value=0}
 ($policy+'|NoLockScreenSlideshow')=@{Path=$policy;Name='NoLockScreenSlideshow';Exists=$true;Kind='DWord';Value=1}
 ($policy+'|LockScreenImage')=@{Path=$policy;Name='LockScreenImage';Exists=$true;Kind='String';Value='C:\old-lock.jpg'}
 ($csp+'|LockScreenImageStatus')=@{Path=$csp;Name='LockScreenImageStatus';Exists=$true;Kind='DWord';Value=1}
 ($csp+'|LockScreenImagePath')=@{Path=$csp;Name='LockScreenImagePath';Exists=$true;Kind='String';Value='C:\provisioned.jpg'}
 ($system+'|DisableLogonBackgroundImage')=@{Path=$system;Name='DisableLogonBackgroundImage';Exists=$true;Kind='DWord';Value=1}
}
function Read-RegistryValue([string]$Path,[string]$Name){
 $id=$Path+'|'+$Name
 if($fixture.ContainsKey($id)){return $fixture[$id]}
 return @{Path=$Path;Name=$Name;Exists=$false;Kind='DWord';Value=$null}
}
function Get-AShellExternalManagementState {[pscustomobject]@{Managed=$false;Reasons=@()}}
$handoff=Get-AShellLockScreenPolicyHandoff
Assert (!$handoff.ExternallyManaged) 'Fixture should be classified as personal/unmanaged.'
$names=@($handoff.Entries | ForEach-Object {$_.Name})
foreach($name in @('NoChangingLockScreen','NoLockScreenSlideshow','LockScreenImage','LockScreenImagePath','DisableLogonBackgroundImage')){
 Assert ($names -contains $name) "Blocking value was not included in handoff: $name"
}
Assert ($names -notcontains 'NoLockScreen') 'A disabled NoLockScreen=0 value must not be removed.'
Assert ($names -notcontains 'LockScreenImageStatus') 'CSP LockScreenImageStatus is status-only and must not be deleted.'
foreach($entry in @($handoff.Entries | Where-Object {$_.Name -ne 'DisableLogonBackgroundImage'})){Assert ($entry.Exists -eq $false) "Handoff must temporarily remove, not rewrite, $($entry.Name)."}
$logon=@($handoff.Entries | Where-Object {$_.Name -eq 'DisableLogonBackgroundImage'})[0]
Assert ($logon.Exists -and [int]$logon.Value -eq 0) 'An existing sign-in image disable policy must be temporarily set to 0, not deleted.'

$override=@(Get-AShellLockScreenOverrideValues $handoff 'C:\A-Shell-lock.png')
$noChange=@($override | Where-Object {$_.Name -eq 'NoChangingLockScreen'})[0]
Assert ($noChange.Exists -and [int]$noChange.Value -eq 0) 'Consented override must explicitly disable NoChangingLockScreen while A-Shell is active.'
$forced=@($override | Where-Object {$_.Name -eq 'LockScreenImage'})[0]
Assert ($forced.Exists -and $forced.Value -eq 'C:\A-Shell-lock.png') 'When Windows already forces a lock image, consented override should point that same policy at the active A-Shell image.'
function Get-AShellExternalManagementState {[pscustomobject]@{Managed=$true;Reasons=@('fixture MDM')}}
$managed=Get-AShellLockScreenPolicyHandoff
Assert $managed.ExternallyManaged 'Managed fixture was not detected.'
Assert (@($managed.Entries).Count -eq @($handoff.Entries).Count) 'Managed detection must still report blockers for diagnostics.'
'PASS: lock-screen blockers are captured reversibly; consent disables blocking switches and re-points an existing forced-image policy at A-Shell; managed devices remain identifiable without blocking explicit consent.'
