param([ValidateSet('Install','Remove','Start','Stop','Status','Migrate')][string]$Action='Status',[string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$exe=Join-Path $root 'bin\MatrixDesktop.exe'
$taskName='Matrix Desktop - Instant Rain'
$legacyRepairTaskName='A-Shell Session Repair'
$cursorRepairTaskName='A-Shell Cursor Session Repair'
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')
function Get-AShellRainProcesses {
 @((Get-Process MatrixDesktop -ErrorAction SilentlyContinue) | Where-Object {
  try {[IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($exe)} catch {$false}
 })
}
if($Action -in @('Install','Remove','Migrate') -and !(Test-AShellAdministrator)) {
 Write-Output "[WORKING] Requesting administrator access for startup $($Action.ToLowerInvariant()) in this terminal..."
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
  $legacyRepair=Get-ScheduledTask -TaskName $legacyRepairTaskName -ErrorAction SilentlyContinue
  if($legacyRepair){Write-Output '[STATUS] Legacy A-Shell sign-in repair task detected. Run Setup/update once to remove this obsolete visual replay task.'}
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
  # v1.9.3 briefly installed a delayed full appearance replay at logon. Persistent
  # Windows/Windhawk state already survives reboot, so replaying it only caused a
  # PowerShell flash and made the taskbar jump through baseline -> A-Shell twice.
  $legacyRepair=Get-ScheduledTask -TaskName $legacyRepairTaskName -ErrorAction SilentlyContinue
  if($legacyRepair){Unregister-ScheduledTask -TaskName $legacyRepairTaskName -Confirm:$false;Write-Output '[OK] Removed obsolete sign-in appearance replay task.'}
  $cursorTask=Get-ScheduledTask -TaskName $cursorRepairTaskName -ErrorAction SilentlyContinue
  if($cursorTask){& (Join-Path $PSScriptRoot 'Cursors.ps1') -Action RepairTask}
  if($wasRunning){
   Write-Output '[OK] Automatic rain startup repaired. Matrix was already running, so its live rain was not restarted.'
  } else {
   Start-ScheduledTask -TaskName $taskName
   Write-Output '[OK] Automatic rain startup installed and started. No startup delay is configured.'
  }
 }
 'Migrate' {
  # Code-only installer upgrades must fix startup tasks without replaying the
  # current started/stopped state, rain process, wallpaper, taskbar or colors.
  $legacyRepair=Get-ScheduledTask -TaskName $legacyRepairTaskName -ErrorAction SilentlyContinue
  if($legacyRepair){Unregister-ScheduledTask -TaskName $legacyRepairTaskName -Confirm:$false;Write-Output '[OK] Removed obsolete sign-in appearance replay task.'}
  $cursorTask=Get-ScheduledTask -TaskName $cursorRepairTaskName -ErrorAction SilentlyContinue
  if($cursorTask){& (Join-Path $PSScriptRoot 'Cursors.ps1') -Action RepairTask}
  # Setup now owns its live console/taskbar icon directly. Migration therefore
  # stays completely appearance-neutral and never touches Windhawk/taskbar settings.
  Write-Output '[OK] Startup-task migration complete. Rain and saved component state were not changed.'
 }
 'Remove' {
  $wasActive=Test-AShellRuntimeActive $root
  foreach($name in @($taskName,$legacyRepairTaskName)){$task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue;if($task){Unregister-ScheduledTask -TaskName $name -Confirm:$false}}
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
