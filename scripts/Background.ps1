param([Parameter(Mandatory=$true)][string]$Image,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
if($Image -eq 'default'){$Image=Join-Path $root 'assets\LockScreenPicture.png'}
if($Image -ne 'original'){$Image=(Resolve-Path -LiteralPath $Image).ProviderPath}
if($Image.Contains('"')){throw 'Invalid image path.'}
if(!(Test-AShellAdministrator)) {
 Write-Output '[WORKING] Opening an Administrator Command Prompt to update A-Shell backgrounds...'
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters @{Image=$Image;ExpectedSid=$ExpectedSid} -Title 'A-Shell Background - Administrator'
 if($exitCode){throw "Background change failed (exit $exitCode). Your previous image was retained or rolled back."}
 Write-Output "[OK] Background command completed: $Image. Saved A-Shell background updated. The lock/login screen changes only when ashell screen on is enabled."
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched accounts.'}
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
Enter-AShellOperation
try {
 $screenOn=[bool](Get-AShellFeatureConfig $root).screens
 if($Image -eq 'original'){Restore-AShellOriginalWallpaper $root;Set-Content -LiteralPath (Join-Path $root 'state\desired-background.txt') -Value 'original' -Encoding UTF8}
 else {Set-AShellBackground $root $Image -DesktopOnly:(!$screenOn)}
 if((Test-AShellRuntimeActive $root) -and $screenOn){Set-AShellScreenRuntime $root $true}
} finally {Exit-AShellOperation}
