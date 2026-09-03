param([Parameter(Mandatory=$true)][string]$Image,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if($Image -eq 'default'){$Image=Join-Path $root 'assets\LockScreenPicture.png'}
if($Image -ne 'original'){$Image=(Resolve-Path -LiteralPath $Image).ProviderPath}
if($Image.Contains('"')){throw 'Invalid image path.'}
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
 Write-Output "[WORKING] Background: $Image. Approve the administrator prompt."
 $p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Image "'+$Image+'" -ExpectedSid '+$ExpectedSid) -Wait -PassThru
 if($p.ExitCode){throw "Background change failed (exit $($p.ExitCode)). Your previous image was retained or rolled back."}
 Write-Output "[OK] Background command completed: $Image. Desktop, lock and sign-in have been updated."
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched accounts.'}
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
Enter-AShellOperation
try {if($Image -eq 'original'){Restore-AShellOriginalWallpaper $root}else{Set-AShellBackground $root $Image}} finally {Exit-AShellOperation}
