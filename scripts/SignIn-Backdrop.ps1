param([ValidateSet('Apply','Restore','Check')][string]$Action='Apply',[switch]$NoRestart)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$state=Join-Path $root 'state'
$snapshot=Join-Path $state 'signin-backdrop-before.clixml'
$key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-signin-clear-background'
$engine='HKLM:\SOFTWARE\Windhawk\Engine\Settings'
$target='%SystemRoot%\System32\LogonUI.exe'
$lockTarget='%SystemRoot%\SystemApps\Microsoft.LockApp_cw5n1h2txyewy\LockApp.exe'
$lockKey='HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-lockscreen-clear-background'
$lockLibrary='ashell-lockscreen-clear-background_1.7.dll'
$library='ashell-signin-clear-background_1.0.dll'
$payload=Join-Path $root ('assets\windhawk\'+$library)
$expected='51B3AA2B50944111F039C0DE035F9C8951A3FD7A65EDA7380AD30ECE5C2565BF'
$supported=((Get-FileHash "$env:SystemRoot\System32\Windows.UI.Logon.dll").Hash -eq $expected)
if($Action -eq 'Check') {
 Write-Output "Windows binary supported: $supported"
 Get-ItemProperty $key -ErrorAction SilentlyContinue | Select-Object Disabled,LibraryFileName,Include
 Get-ItemProperty 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable\ashell-signin-clear-background\LocalStorage' -ErrorAction SilentlyContinue | Format-List
 Get-ItemProperty 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable\ashell-lockscreen-clear-background\LocalStorage' -ErrorAction SilentlyContinue | Format-List
 exit 0
}
if($Action -eq 'Apply' -and !$supported){throw 'This Windows version has not been verified. No changes made.'}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$admin){
 Write-Output "[WORKING] Lock/sign-in shading: $Action. Approve the administrator prompt."
 $p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Action',$Action) -PassThru -Wait
 if($p.ExitCode -ne 0){throw "Sign-in backdrop action failed ($($p.ExitCode)). See state\signin-backdrop.log."}
 Write-Output "[OK] Lock/sign-in shading $Action completed. Check it at the next lock/sign-in."
 exit 0
}
New-Item -ItemType Directory $state -Force | Out-Null
Start-Transcript (Join-Path $state 'signin-backdrop.log') -Append | Out-Null
try {
 . (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
 . (Join-Path $PSScriptRoot 'Setup.Support.ps1')
 if($Action -eq 'Apply') {
  if(!(Test-Path $payload)){throw 'The sign-in mod binary is missing.'}
  $lockPayload=Join-Path $root ('assets\windhawk\'+$lockLibrary)
  if(!(Test-Path $lockPayload)){throw 'The lock-screen mod binary is missing.'}
  if(!(Test-Path $engine)){throw 'Install Windhawk first.'}
  if(!(Test-Path $snapshot)) {
   @{Include=Read-RegistryValue $engine 'Include';Acrylic=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon';Trees=@((Read-AShellTree $key),(Read-AShellTree $lockKey))} | Export-Clixml $snapshot
  }
  $destination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$library)
  New-Item -ItemType Directory (Split-Path $destination) -Force | Out-Null
  if(!(Test-Path $destination) -or (Get-FileHash $payload).Hash -ne (Get-FileHash $destination).Hash){Copy-Item -LiteralPath $payload -Destination $destination -Force}
  $sourceDir=Join-Path $env:ProgramData 'Windhawk\ModsSource'
  New-Item -ItemType Directory $sourceDir -Force | Out-Null
  Copy-Item (Join-Path $root 'src\signin-clear-background.wh.cpp') (Join-Path $sourceDir 'ashell-signin-clear-background.wh.cpp') -Force
  $lockDestination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$lockLibrary)
  if(!(Test-Path $lockDestination) -or (Get-FileHash $lockPayload).Hash -ne (Get-FileHash $lockDestination).Hash){Copy-Item $lockPayload $lockDestination -Force}
  Copy-Item (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') (Join-Path $sourceDir 'ashell-lockscreen-clear-background.wh.cpp') -Force
  foreach($entry in @{LibraryFileName=$lockLibrary;Version='1.7';Include=$lockTarget;Exclude='';Architecture='x86-64'}.GetEnumerator()) {
   Write-RegistryValue @{Path=$lockKey;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
  }
  Write-RegistryValue @{Path="$lockKey\Settings";Name='disableNewStartMenuLayout';Kind='String';Value='default';Exists=$true}
  $index=0
  foreach($name in @('DimmingOverlayPassword','DimmingOverlayNoPassword')) {
   $selector=(@('Rectangle','Grid','Border','Canvas') | ForEach-Object {$_+'#'+$name}) -join ', '
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].target";Kind='String';Value=$selector;Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[0]";Kind='String';Value='Opacity=0';Exists=$true}
   Write-RegistryValue @{Path="$lockKey\Settings";Name="controlStyles[$index].styles[1]";Kind='String';Value='Visibility=Collapsed';Exists=$true}
   $index++
  }
  Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
  Write-RegistryValue @{Path=$lockKey;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
  foreach($entry in @{LibraryFileName=$library;Version='1.0';Include=$target;Exclude='';Architecture='x86-64'}.GetEnumerator()) {
   Write-RegistryValue @{Path=$key;Name=$entry.Key;Kind='String';Value=$entry.Value;Exists=$true}
  }
  Write-RegistryValue @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';Name='DisableAcrylicBackgroundOnLogon';Kind='DWord';Value=1;Exists=$true}
  $current=[string](Get-ItemProperty $engine).Include
  $entries=@($current -split '\|' | Where-Object {$_})
  if($entries -notcontains $target){$entries+= $target}
  if($entries -notcontains $lockTarget){$entries+= $lockTarget}
  Write-RegistryValue @{Path=$engine;Name='Include';Kind='String';Value=($entries -join '|');Exists=$true}
  Write-RegistryValue @{Path=$key;Name='Disabled';Kind='DWord';Value=0;Exists=$true}
  Write-RegistryValue @{Path=$key;Name='SettingsChangeTime';Kind='DWord';Value=[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Exists=$true}
  Write-Output 'Installed. The next sign-in view will test the backdrop change. Use Restore Sign-in Shading.cmd to undo.'
 } else {
  if(!(Test-Path $snapshot)){Write-Output 'No sign-in backdrop backup; nothing to restore.';exit 0}
  if(Test-Path $key){Write-RegistryValue @{Path=$key;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
  if(Test-Path $lockKey){Write-RegistryValue @{Path=$lockKey;Name='Disabled';Kind='DWord';Value=1;Exists=$true}}
  $before=Import-Clixml $snapshot
  if($before.ContainsKey('Trees')){foreach($tree in $before.Trees){Restore-AShellTree $tree}}
  $current=[string](Get-ItemProperty $engine).Include
  $oldEntries=@(([string]$before.Include.Value) -split '\|' | Where-Object {$_})
  $addedTargets=@(@($target,$lockTarget) | Where-Object {$oldEntries -notcontains $_})
  if($addedTargets.Count){
   $remaining=@($current -split '\|' | Where-Object {$_ -and $addedTargets -notcontains $_}) -join '|'
   if($remaining -eq [string]$before.Include.Value){Write-RegistryValue $before.Include}
   else {Write-RegistryValue @{Path=$engine;Name='Include';Kind='String';Value=$remaining;Exists=$true}}
  }
  Write-RegistryValue $before.Acrylic
  Write-Output 'Previous screen-mod settings restored. Lock and unlock to refresh the views.'
 }
 if(!$NoRestart){Start-Process (Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe') -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
} finally {Stop-Transcript | Out-Null}
