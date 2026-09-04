param([ValidateSet('refresh','list','check','auto','set','add')][string]$Action='refresh',[string]$App,[string]$Icon,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Icons.Support.ps1')
. (Join-Path $PSScriptRoot 'Icon.Selection.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
if($Action -notin @('list','check') -and !(Test-AShellRuntimeActive $root)){
 Write-Output '[SKIP] A-Shell is stopped. Icon mappings and live icon settings were not changed. Run ashell start first.'
 exit 0
}
if($Action -eq 'add') {
 . (Join-Path $PSScriptRoot 'State.Helpers.ps1')
 Enter-AShellOperation
 try {Import-AShellIcon $root $App $Icon} finally {Exit-AShellOperation}
 return
}
if($Action -in @('auto','set')) {
 . (Join-Path $PSScriptRoot 'State.Helpers.ps1')
 Enter-AShellOperation
 try {
  if(!(Test-Path (Join-Path $root 'state\before-setup.clixml'))){throw 'Run the A-Shell Setup EXE first.'}
  if($Action -eq 'set'){Set-AShellIconSelection $root $App $Icon}else{Add-AShellAutomaticIcons $root}
 } finally {Exit-AShellOperation}
 $Action='refresh'
}
if($Action -eq 'list') {
 $plan=Get-AShellIconPlan $root -SkipTaskbarBase
 Get-StartApps | Sort-Object Name | Select-Object Name,AppID,@{Name='Mapped';Expression={$plan.AppIds.ContainsKey($_.AppID)}} | Format-Table -AutoSize -Wrap
 Write-Output 'Assign an icon: ashell icons set "Exact app name" "icon.png". Put/import the PNG in assets\icons first.'
 exit 0
}
if($Action -eq 'check'){$plan=Get-AShellIconPlan $root -SkipTaskbarBase;Write-Output "Valid mapping: $($plan.AppIds.Count) exact app IDs, $($plan.Assets.Count) images.";Test-AShellPinnedShortcuts;exit 0}

$cfg=Get-AShellFeatureConfig $root
if(!$cfg.icons){Write-Output '[STATUS] Icon replacement component is off. Mapping changes are saved; use "ashell component icons on" to display them.';return}

if(!(Test-AShellAdministrator)) {
 Write-Output '[WORKING] Requesting administrator access to refresh A-Shell icons in this terminal...'
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters @{ExpectedSid=$ExpectedSid} -Title 'A-Shell Icons - Administrator'
 if($exitCode){throw "Icon refresh failed (exit $exitCode). Run ashell icons check for mapping errors."}
 Write-Output '[OK] Taskbar icon component refreshed.'
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched accounts.'}
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Setup.Support.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
. (Join-Path $PSScriptRoot 'Desktop.Support.ps1')
. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
Enter-AShellOperation
try {Set-AShellTaskbarRuntime $root ([bool]$cfg.taskbarTransparency) $true} finally {Exit-AShellOperation}
