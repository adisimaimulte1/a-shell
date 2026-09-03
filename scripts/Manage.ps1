param([ValidateSet('Install','Remove','Start','Stop','Status')][string]$Action='Status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$exe=Join-Path $root 'bin\MatrixDesktop.exe'
$taskName='Matrix Desktop - Instant Rain'
if($Action -in @('Install','Remove') -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
 Write-Output "[WORKING] Startup: $Action. Approve the administrator prompt."
 $elevated=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$Action) -Wait -PassThru
 if($elevated.ExitCode){throw "Startup $Action failed (exit $($elevated.ExitCode))."}
 Write-Output "[OK] Startup $Action completed."
 exit 0
}
switch($Action) {
 'Start' {
  $running=Get-Process MatrixDesktop -ErrorAction SilentlyContinue
  if(!$running){Start-Process -FilePath $exe -WindowStyle Hidden;$deadline=(Get-Date).AddSeconds(5);do {Start-Sleep -Milliseconds 100;$running=Get-Process MatrixDesktop -ErrorAction SilentlyContinue}while(!$running -and (Get-Date) -lt $deadline)}
  if(!$running){throw 'Rain did not start. See bin\MatrixDesktop.log.'}
  if($running.Path -ne $exe){throw "Another A-Shell copy is running: $($running.Path). Stop it before starting this copy."}
  Start-Process -FilePath $exe -ArgumentList '--resume' -WindowStyle Hidden -Wait
  Write-Output "[OK] Rain is running. Process: A-Shell Matrix Rain (MatrixDesktop.exe), PID $($running.Id)."
 }
 'Stop' {
  Start-Process -FilePath $exe -ArgumentList '--drain' -WindowStyle Hidden -Wait
  Write-Output '[OK] New streams stopped. Existing rain will finish falling and fade away.'
  Write-Output '[STATUS] Automatic startup is unchanged. Use ashell rain start afterward.'
 }
 'Status' {
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;$running=Get-Process MatrixDesktop -ErrorAction SilentlyContinue
  if($running){Write-Output "[STATUS] Rain: running, PID $($running.Id). Executable: $($running.Path)"}else{Write-Output '[STATUS] Rain: stopped.'}
  if($task){$enabled=if($task.State -eq 'Disabled'){'disabled'}else{'enabled'};Write-Output "[STATUS] Sign-in startup: $enabled (task $($task.State)). Target: $($task.Actions.Execute)"}else{Write-Output '[STATUS] Sign-in startup: not installed.'}
  $color=Join-Path $root 'state\accent-color.txt';if(Test-Path $color){Write-Output ('[STATUS] Accent: #'+(Get-Content $color -Raw))}
 }
 'Install' {
  New-Item -ItemType Directory (Join-Path $root 'backup') -Force | Out-Null
  foreach($oldName in @($taskName,'Codex Early Lively Wallpaper','Lively Wallpaper - Adi')) {
   $old=Get-ScheduledTask -TaskName $oldName -ErrorAction SilentlyContinue
   if($old) {
    $backup=Join-Path $root ('backup\'+$oldName+'.xml')
    if(!(Test-Path $backup)) { Export-ScheduledTask -TaskName $oldName | Set-Content $backup -Encoding Unicode }
    Disable-ScheduledTask -TaskName $oldName | Out-Null
   }
  }
  Start-Process -FilePath $exe -ArgumentList '--stop' -WindowStyle Hidden -Wait
  $deadline=(Get-Date).AddSeconds(5)
  while(Get-Process MatrixDesktop -ErrorAction SilentlyContinue) { if((Get-Date) -gt $deadline){throw 'Matrix did not stop.'}; Start-Sleep -Milliseconds 100 }
  $user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(1))
  $settings.Priority=4
  Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $exe -WorkingDirectory (Split-Path $exe)) -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited) -Settings $settings -Description 'A-Shell: standalone Matrix Desktop, no Lively required.' -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
  Write-Output '[OK] Automatic rain startup installed and started. No startup delay is configured.'
 }
 'Remove' {
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if($task) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
  Start-Process -FilePath $exe -ArgumentList '--stop' -WindowStyle Hidden -Wait
  Write-Output '[OK] Automatic rain startup removed; rain stopped. Other appearance settings are unchanged.'
 }
}
