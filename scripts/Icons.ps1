param([ValidateSet('refresh','list','check','auto','set','add')][string]$Action='refresh',[string]$App,[string]$Icon,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Icons.Support.ps1')
. (Join-Path $PSScriptRoot 'Icon.Selection.ps1')
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
  if(!(Test-Path (Join-Path $root 'state\before-setup.clixml'))){throw 'Run Setup first.'}
  if($Action -eq 'set'){Set-AShellIconSelection $root $App $Icon}else{Add-AShellAutomaticIcons $root}
 } finally {Exit-AShellOperation}
 $Action='refresh'
}
if($Action -eq 'list') {
 $plan=Get-AShellIconPlan $root
 Get-StartApps | Sort-Object Name | Select-Object Name,AppID,@{Name='Mapped';Expression={$plan.AppIds.ContainsKey($_.AppID)}} | Format-Table -AutoSize -Wrap
 Write-Output 'Assign an icon: ashell icons set "Exact app name" "icon.png". Put the PNG in assets\icons first.'
 exit 0
}
if($Action -eq 'check'){$plan=Get-AShellIconPlan $root;Write-Output "Valid mapping: $($plan.AppIds.Count) exact app IDs, $($plan.Assets.Count) images.";Test-AShellPinnedShortcuts;exit 0}
# A no-op refresh should not ask for administrator access.
$plan=Get-AShellIconPlan $root
$key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler\Settings'
$engineMeta=Get-Content (Join-Path $root 'assets\windhawk\mod.json') -Raw|ConvertFrom-Json
$installedEngine=Get-ItemProperty (Split-Path $key) -ErrorAction SilentlyContinue
$engineUpgrade=$installedEngine -and $installedEngine.LibraryFileName -ne $engineMeta.LibraryFileName
if(Test-Path $key) {
 $current=@{};$reg=Get-Item $key;foreach($name in $reg.GetValueNames()){$current[$name]=$reg.GetValue($name)}
 $desired=Align-AShellIconSlots $plan.Settings $current
 $delta=Get-AShellIconDelta $current $desired
 $missing=@($plan.Assets.Values|Where-Object {!(Test-Path $_.Path) -or (Get-FileHash $_.Path).Hash -ne $_.Hash})
 if(!$engineUpgrade -and !$delta.Count -and !$missing.Count -and !(Test-Path (Join-Path $root 'state\icons-refresh.pending'))) {
  Write-Output '[OK] Icons are already current. No changes or administrator approval needed.';return
 }
}
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
 Write-Output '[WORKING] Checking icon mappings and refreshing changed taskbar icons. Approve the administrator prompt.'
 $p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -ExpectedSid '+$ExpectedSid) -Wait -PassThru
 if($p.ExitCode){throw "Icon refresh failed (exit $($p.ExitCode)). Run ashell icons check for mapping errors."}
 Write-Output '[OK] Taskbar icon refresh completed. Unchanged icon settings were retained.'
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched accounts.'}
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
Enter-AShellOperation
try {& (Join-Path $PSScriptRoot 'Repair-TaskbarEngine.ps1');Update-AShellIcons $root} finally {Exit-AShellOperation}
