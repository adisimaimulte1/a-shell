param([ValidateSet('Install','Remove','Start','Stop','Status')][string]$Action='Status',[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$exe=Join-Path $root 'bin\MatrixDesktop.exe'
$taskName='Matrix Desktop - Instant Rain'
$repairTaskName='A-Shell Session Repair'
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
function Get-AShellRainProcesses {
 @((Get-Process MatrixDesktop -ErrorAction SilentlyContinue) | Where-Object {
  try {[IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($exe)} catch {$false}
 })
}
if($Action -in @('Install','Remove') -and !(Test-AShellAdministrator)) {
 Write-Output "[WORKING] Opening an Administrator Command Prompt for startup $($Action.ToLowerInvariant())..."
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters @{Action=$Action;ExpectedSid=$ExpectedSid} -Title 'A-Shell Startup - Administrator'
 if($exitCode){throw "Startup $Action failed (exit $exitCode)."}
 Write-Output "[OK] Startup $Action completed."
 exit 0
}
if((Test-AShellAdministrator) -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched to another Windows account.'}
switch($Action) {
 'Start' {
  $running=@(Get-AShellRainProcesses)
  $pending=Join-Path $root 'bin\MatrixDesktop.exe.pending'
  if(!$running.Count -and (Test-Path -LiteralPath $pending)){
   Move-Item -LiteralPath $pending -Destination $exe -Force
   Write-Output '[OK] Pending Matrix executable update applied.'
  }
  $running=@(Get-AShellRainProcesses)
  if($running.Count){
   Write-Output "[OK] Rain is already running. Existing Matrix state was left untouched. PID $($running[0].Id)."
   break
  }
  $other=@(Get-Process MatrixDesktop -ErrorAction SilentlyContinue)
  if($other.Count){
   $path=try {$other[0].Path} catch {'another location'}
   throw "Another A-Shell/Matrix copy is already running from $path. Stop it before starting this copy."
  }
  Start-Process -FilePath $exe -WindowStyle Hidden
  $deadline=(Get-Date).AddSeconds(5)
  do {Start-Sleep -Milliseconds 100;$running=@(Get-AShellRainProcesses)}while(!$running.Count -and (Get-Date) -lt $deadline)
  if(!$running.Count){throw 'Rain did not start. See bin\MatrixDesktop.log.'}
  Write-Output "[OK] Rain started. Process: A-Shell Matrix Rain (MatrixDesktop.exe), PID $($running[0].Id)."
 }
 'Stop' {
  $running=@(Get-AShellRainProcesses)
  if(!$running.Count){
   Write-Output '[OK] Rain is already stopped. No Matrix control process was started.'
   break
  }
  Start-Process -FilePath $exe -ArgumentList '--drain' -WindowStyle Hidden -Wait
  Write-Output '[OK] New streams stopped. Existing rain will finish falling and fade away.'
  Write-Output '[STATUS] Automatic startup is unchanged. Use ashell rain start afterward.'
 }
 'Status' {
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;$running=Get-Process MatrixDesktop -ErrorAction SilentlyContinue
  if($running){Write-Output "[STATUS] Rain: running, PID $($running.Id). Executable: $($running.Path)"}else{Write-Output '[STATUS] Rain: stopped.'}
  if($task){$enabled=if($task.State -eq 'Disabled'){'disabled'}else{'enabled'};Write-Output "[STATUS] Rain sign-in startup: $enabled (task $($task.State)). Target: $($task.Actions.Execute)"}else{Write-Output '[STATUS] Rain sign-in startup: not installed.'}
  $repair=Get-ScheduledTask -TaskName $repairTaskName -ErrorAction SilentlyContinue
  if($repair){Write-Output "[STATUS] A-Shell settings repair at sign-in: $($repair.State)."}else{Write-Output '[STATUS] A-Shell settings repair at sign-in: not installed.'}
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
  # Installing/repairing startup must not bounce Matrix when this installed copy is already running.
  # The scheduled task can be safely replaced while the process keeps its live streams/trails.
  $wasRunning=@(Get-AShellRainProcesses).Count -gt 0
  $user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(1))
  $settings.Priority=4
  Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $exe -WorkingDirectory (Split-Path $exe)) -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited) -Settings $settings -Description 'A-Shell: standalone Matrix Desktop, no Lively required.' -Force | Out-Null
  $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $runtime=Join-Path $root 'scripts\Runtime.ps1'
  $repairArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runtime+'" -Action SessionRepair'
  $repairAction=New-ScheduledTaskAction -Execute $powershell -Argument $repairArgs -WorkingDirectory $root
  $repairPrincipal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName $repairTaskName -Action $repairAction -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) -Principal $repairPrincipal -Settings $settings -Description 'A-Shell: re-apply saved images, hidden desktop, screen/taskbar/icon settings and cursor scheme after Windows initializes the shell.' -Force | Out-Null
  if($wasRunning){
   Write-Output '[OK] Automatic rain startup repaired. Matrix was already running, so its live rain was not restarted.'
  } else {
   Start-ScheduledTask -TaskName $taskName
   Write-Output '[OK] Automatic rain startup installed and started. No startup delay is configured.'
  }
 }
 'Remove' {
  $wasActive=Test-AShellRuntimeActive $root
  foreach($name in @($taskName,$repairTaskName)){$task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue;if($task){Unregister-ScheduledTask -TaskName $name -Confirm:$false}}
  $running=@(Get-AShellRainProcesses)
  if($wasActive -and $running.Count){
   Start-Process -FilePath $exe -ArgumentList '--stop' -WindowStyle Hidden -Wait
   Write-Output '[OK] Automatic rain startup removed and active rain stopped.'
  } elseif($running.Count){
   Write-Output '[SKIP] A-Shell is already stopped. Automatic startup was removed; existing drain trails were not stopped again.'
  } else {
   Write-Output '[OK] Automatic rain startup removed. Rain was already stopped.'
  }
 }
}
