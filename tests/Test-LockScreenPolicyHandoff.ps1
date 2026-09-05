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
Assert (!$forced.Exists) 'A pre-existing forced LockScreenImage must be temporarily removed, not repointed at A-Shell, to preserve native lock-to-sign-in framing.'
function Get-AShellExternalManagementState {[pscustomobject]@{Managed=$true;Reasons=@('fixture MDM')}}
$managed=Get-AShellLockScreenPolicyHandoff
Assert $managed.ExternallyManaged 'Managed fixture was not detected.'
Assert (@($managed.Entries).Count -eq @($handoff.Entries).Count) 'Managed detection must still report blockers for diagnostics.'
'PASS: lock-screen blockers are captured reversibly; consent releases forced-image policy without re-pointing it; managed devices remain identifiable without blocking explicit consent.'
# The known-good exact hook is the only LogonUI overlay hook; unknown builds fail closed.
$signInScript=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
$nativeSource=Get-Content -LiteralPath (Join-Path $root 'src\signin-clear-background.wh.cpp') -Raw
foreach($retired in @('LogonBackgroundBrush:=','LogonBackgroundBackdrop:=')) {
 if($signInScript -match [regex]::Escape($retired)){throw "Retired sign-in resource override is still configured: $retired"}
}
foreach($needle in @('0x94140','0x64970','ZoomHookInstalled','ZoomDisabled','0x170','0.45','51b3aa2b50944111f039c0de035f9c8951a3fd7a65eda7380ad30ece5c2565bf')) {
 if($nativeSource -notmatch [regex]::Escape($needle)){throw "Sign-in hook is missing expected exact/narrow guard: $needle"}
}

if($signInScript -notmatch 'Include=\$lockTarget;Exclude=''''') {throw 'The generic LockApp support module must stay out of LogonUI.'}
if($signInScript -notmatch 'Include=\$target;Exclude=''''') {throw 'The dedicated narrow backdrop hook must own LogonUI.'}
