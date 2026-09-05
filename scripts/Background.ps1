param([Parameter(Mandatory=$true)][string]$Image,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
$requested=$Image
if($Image -eq 'default'){$Image=Join-Path $root 'assets\LockScreenPicture.png'}
if($Image -ne 'original'){$Image=(Resolve-Path -LiteralPath $Image).ProviderPath}
if($Image.Contains('"')){throw 'Invalid image path.'}

function Test-AShellSameImage([string]$A,[string]$B) {
 if([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)){return $false}
 if(!(Test-Path -LiteralPath $A -PathType Leaf) -or !(Test-Path -LiteralPath $B -PathType Leaf)){return $false}
 try {return (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash}catch{return $false}
}
function Test-AShellBackgroundAlreadyApplied([string]$Choice) {
 $desired=Get-AShellDesiredBackground $root
 $desktop=(Read-RegistryValue 'HKCU:\Control Panel\Desktop' 'Wallpaper').Value
 $screenOn=[bool](Get-AShellFeatureConfig $root).screens
 $expectedDesktop=''
 $expectedLock=''
 if($Choice -eq 'original') {
  if($desired -ne 'original'){return $false}
  $expectedDesktop=Get-AShellOriginalDesktopImage $root
  $expectedLock=Get-AShellOriginalLockImage $root
 } else {
  if(!(Test-AShellSameImage $desired $Choice)){return $false}
  $expectedDesktop=$Choice
  $expectedLock=$Choice
 }
 if(!(Test-AShellSameImage $desktop $expectedDesktop)){return $false}
 if($screenOn) {
  $currentLock=Get-AShellLockSource
  if(!$currentLock -or !(Test-AShellSameImage $currentLock $expectedLock)){return $false}
 }
 return $true
}
if(Test-AShellBackgroundAlreadyApplied $Image) {
 $label=$requested
 if($requested -eq 'default'){$label='default'}elseif($requested -eq 'original'){$label='original'}else{$label=[IO.Path]::GetFileName($Image)}
 Write-Output ('[SKIP] Background is already '+$label+'. Nothing changed.')
 exit 0
}

if(!(Test-AShellAdministrator)) {
 Write-Output '[WORKING] Requesting administrator access to update A-Shell backgrounds in this terminal...'
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters @{Image=$Image;ExpectedSid=$ExpectedSid} -Title 'A-Shell Background - Administrator'
 if($exitCode){throw "Background change failed (exit $exitCode). Your previous image was retained or rolled back."}
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched accounts.'}
Enter-AShellOperation
try {
 $screenOn=[bool](Get-AShellFeatureConfig $root).screens
 if($Image -eq 'original'){Restore-AShellOriginalWallpaper $root;Set-Content -LiteralPath (Join-Path $root 'state\desired-background.txt') -Value 'original' -Encoding UTF8}
 else {Set-AShellBackground $root $Image -DesktopOnly:(!$screenOn)}
 if((Test-AShellRuntimeActive $root) -and $screenOn){Set-AShellScreenRuntime $root $true | Out-Null}
 Write-Output '[OK] Background updated.'
} finally {Exit-AShellOperation}
