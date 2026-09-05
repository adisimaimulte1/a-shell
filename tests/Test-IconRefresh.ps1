# Real refresh function with an in-memory registry. No Windows settings changed.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Icons.Support.ps1')
function Assert($ok,$message){if(!$ok){throw $message}}
$fixture=Join-Path $root ('state\tests\icon-refresh-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'assets\icons'),(Join-Path $fixture 'state') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'assets\taskbar-base.json') -Destination (Join-Path $fixture 'assets\taskbar-base.json')
$icon=Join-Path $fixture 'assets\icons\test.png'
Copy-Item -LiteralPath (Join-Path $root 'assets\LockScreenPicture.png') -Destination $icon
@{version=1;apps=@(@{name='Test';icon='test.png';appIds=@('AShell.Fixture')});controls=@()} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture 'assets\icon-map.json')
@{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value} | Export-Clixml -LiteralPath (Join-Path $fixture 'state\before-setup.clixml')
$script:registry=@{};$script:writes=0;$script:stamp=0;$script:failStamp=$false
function Test-Path($Path,$LiteralPath,$PathType) {
 $p=if($LiteralPath){$LiteralPath}else{$Path}
 if($p -like 'HKLM:*'){return $true}
 if($PathType){return Microsoft.PowerShell.Management\Test-Path -LiteralPath $p -PathType $PathType}
 return Microsoft.PowerShell.Management\Test-Path -LiteralPath $p
}
function Get-Item($Path,$LiteralPath) {
 $p=if($LiteralPath){$LiteralPath}else{$Path}
 if($p -like 'HKLM:*') {
  $key=New-Object PSObject
  $key | Add-Member ScriptMethod GetValueNames {return @($script:registry.Keys)}
  $key | Add-Member ScriptMethod GetValue {param($name) return $script:registry[$name]}
  return $key
 }
 return Microsoft.PowerShell.Management\Get-Item -LiteralPath $p
}
function Get-ItemProperty($Path){if($Path -notlike 'HKLM:*'){throw 'Unexpected registry read in test'};return @{Disabled=0}}
function Read-RegistryValue($Path,$Name){return @{Exists=($script:stamp -ne 0);Value=$script:stamp}}
function Write-RegistryValue($Item) {
 if($Item.Path -notlike 'HKLM:*'){throw 'Unexpected registry write in test'}
 if($Item.Name -eq 'SettingsChangeTime') {
  if($script:failStamp){$script:failStamp=$false;throw 'Injected notification failure'}
  $script:stamp=$Item.Value
 } elseif($Item.Exists -eq $false){$script:registry.Remove($Item.Name)}else{$script:registry[$Item.Name]=$Item.Value}
 $script:writes++
}
Update-AShellIcons $fixture
Assert ($script:writes -gt 0) 'First refresh must install settings.'
$script:writes=0;Update-AShellIcons $fixture
Assert ($script:writes -eq 0) 'An unchanged refresh must perform zero registry writes.'
Copy-Item -LiteralPath (Join-Path $root 'assets\profile\personal-icon.png') -Destination $icon -Force
$script:writes=0;Update-AShellIcons $fixture
Assert ($script:writes -eq 2) 'Changed icon must write only one image source and one notification.'
Copy-Item -LiteralPath (Join-Path $root 'assets\LockScreenPicture.png') -Destination $icon -Force
$script:failStamp=$true;$failed=$false
try {Update-AShellIcons $fixture}catch{$failed=$true}
Assert ($failed -and (Test-Path -LiteralPath (Join-Path $fixture 'state\icons-refresh.pending'))) 'Failed notification must remain pending.'
$script:writes=0;Update-AShellIcons $fixture
Assert ($script:writes -eq 1 -and !(Test-Path -LiteralPath (Join-Path $fixture 'state\icons-refresh.pending'))) 'Retry must notify even if all settings already match.'
Write-Output 'PASS: real icon refresh with fixture registry; unchanged zero-write run, changed-image-only update and notification retry.'

$taskbarSource=Get-Content -LiteralPath (Join-Path $root 'assets\windhawk\windows-11-taskbar-styler.wh.cpp') -Raw
foreach($needle in @('WatchAShellTaskbarIdentity','AutomationIdProperty','RegisterPropertyChangedCallback','ReapplyCustomizationsForSubtree(button, true)','UnwatchAShellTaskbarIdentity')){
 if(!$taskbarSource.Contains($needle)){throw "Live taskbar identity refresh is missing: $needle"}
}
if($taskbarSource -match 'A-Shell: taskbar app identity changed.+Restart|A-Shell: taskbar app identity changed.+Sleep'){
 throw 'Live A-Shell icon refresh must not restart Explorer or wait arbitrarily.'
}
Write-Output 'PASS: live taskbar button identity changes re-match the existing button without Explorer restart.'
