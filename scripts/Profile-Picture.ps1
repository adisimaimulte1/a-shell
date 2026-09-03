param([switch]$Restore,[switch]$Worker,[string]$TargetSid,[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
if(!$Worker) {
 if(!(Test-AShellAdministrator)) {
  Write-Output '[WORKING] Opening an Administrator Command Prompt to update the account picture...'
  $parameters=@{ExpectedSid=$ExpectedSid};if($Restore){$parameters.Restore=$true}
  $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title 'A-Shell Profile Picture - Administrator'
  if($exitCode){throw 'Account-picture update failed. Existing backups are preserved.'}
  Write-Output '[OK] Account-picture update completed. Lock/sign in again to refresh the image.'
  exit 0
 }
 $TargetSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($TargetSid -ne $ExpectedSid){throw 'Elevation switched accounts. No account picture was changed.'}
 $taskName='A-Shell Profile Picture Maintenance'
 $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker -TargetSid '+$TargetSid
 if($Restore){$args+=' -Restore'}
 $status=Join-Path $env:ProgramData ('A-Shell\AccountPictures\'+$TargetSid+'\result.txt')
 if(Test-Path $status){Remove-Item -LiteralPath $status}
 try {
  Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args) -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount) -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1))) -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
  $deadline=(Get-Date).AddSeconds(30)
  while(!(Test-Path $status)){if((Get-Date) -gt $deadline){throw 'Account picture update timed out.'};Start-Sleep -Milliseconds 200}
  $result=Get-Content $status -Raw
  Write-Output $result
  if(!$result.StartsWith('SUCCESS')){exit 1}
 } finally {Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue}
 exit 0
}
if($TargetSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'Invalid account SID.'}
$folder=Join-Path $env:ProgramData ('A-Shell\AccountPictures\'+$TargetSid)
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$status=Join-Path $folder 'result.txt'
try {
 $key='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\'+$TargetSid
 $backup=Join-Path $folder 'before.clixml'
 if($Restore) {
  $saved=Import-Clixml $backup
  foreach($entry in $saved){Set-ItemProperty -LiteralPath $key -Name $entry.Name -Value $entry.Value}
 } else {
  $registry=Get-Item -LiteralPath $key
  $saved=@(foreach($name in $registry.GetValueNames() | Where-Object {$_ -match '^Image\d+$'}){@{Name=$name;Value=$registry.GetValue($name)}})
  if(!$saved.Count){throw 'No Windows account picture entries were found.'}
  if(!(Test-Path $backup)){$saved | Export-Clixml $backup}
  $original=Join-Path $root 'assets\profile\personal-icon.png'
  $png=Join-Path $folder 'personal-icon.png'
  Copy-Item -LiteralPath $original -Destination $png -Force
  if((Get-FileHash $original).Hash -ne (Get-FileHash $png).Hash){throw 'PNG integrity check failed.'}
  foreach($entry in $saved){Set-ItemProperty -LiteralPath $key -Name $entry.Name -Value $png}
  foreach($entry in $saved){if((Get-ItemPropertyValue -LiteralPath $key -Name $entry.Name) -ne $png){throw 'Picture path verification failed.'}}
 }
 Set-Content $status 'SUCCESS: local account picture paths updated; original files and permissions preserved. Lock/sign in again to refresh.'
} catch {Set-Content $status ('FAILED: '+$_);exit 1}
