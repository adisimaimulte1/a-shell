param(
 [ValidateSet('Install','Remove','Start','Stop','Status','Migrate')][string]$Action='Status',
 [string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
 [switch]$StartNow
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$exe=Join-Path $root 'bin\MatrixDesktop.exe'
$taskName='Matrix Desktop - Instant Rain'
$legacyRepairTaskName='A-Shell Session Repair'
$cursorRepairTaskName='A-Shell Cursor Session Repair'
$cursorGuardTaskName='A-Shell Cursor Session Guard'
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')

function Get-AShellRainProcesses {
 @((Get-Process MatrixDesktop -ErrorAction SilentlyContinue) | Where-Object {
  try {[IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($exe)} catch {$false}
 })
}
function New-AShellRainStartupTask {
 $user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(1))
 # Priority 4 keeps the renderer responsive without competing with Explorer during logon.
 $settings.Priority=4
 Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $exe -Argument '--autostart' -WorkingDirectory (Split-Path $exe)) -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited) -Settings $settings -Description 'A-Shell: starts Matrix rain at sign-in only when the saved A-Shell/rain state says it should.' -Force | Out-Null
}
function Remove-AShellObsoleteStartupTasks {
 $legacyRepair=Get-ScheduledTask -TaskName $legacyRepairTaskName -ErrorAction SilentlyContinue
 if($legacyRepair){Unregister-ScheduledTask -TaskName $legacyRepairTaskName -Confirm:$false;Write-Output '[OK] Removed obsolete sign-in appearance replay task.'}
 $cursorTask=Get-ScheduledTask -TaskName $cursorRepairTaskName -ErrorAction SilentlyContinue
 if($cursorTask){Unregister-ScheduledTask -TaskName $cursorRepairTaskName -Confirm:$false;Write-Output '[OK] Removed obsolete delayed cursor PowerShell repair task.'}
}

if($Action -in @('Install','Remove','Migrate') -and !(Test-AShellAdministrator)) {
 Write-Output "[WORKING] Requesting administrator access for startup $($Action.ToLowerInvariant()) in this terminal..."
 $parameters=@{Action=$Action;ExpectedSid=$ExpectedSid}
 if($StartNow){$parameters.StartNow=$true}
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title 'A-Shell Startup - Administrator'
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
   # A renderer can still exist while it is naturally draining after `rain off`.
   # Explicit `rain on` must cancel that drain instead of mistaking the PID for
   # visible/active rain. --resume is idempotent when the renderer is not draining.
   Start-Process -FilePath $exe -ArgumentList '--resume' -WindowStyle Hidden -Wait
   Write-Output "[OK] Rain is on. Existing Matrix renderer resumed/confirmed active. PID $($running[0].Id)."
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
  Write-Output '[STATUS] The saved rain preference is unchanged; ashell rain on/off controls what happens next sign-in.'
 }
 'Status' {
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  $running=Get-Process MatrixDesktop -ErrorAction SilentlyContinue
  $cfg=Get-AShellFeatureConfig $root
  if($running){Write-Output "[STATUS] Rain: running, PID $($running.Id). Executable: $($running.Path)"}else{Write-Output '[STATUS] Rain: stopped.'}
  Write-Output ('[STATUS] Saved rain switch: '+$(if($cfg.rain){'on'}else{'off'})+'. This is the state restored after sign-in.')
  if($task){
   $enabled=if($task.State -eq 'Disabled'){'disabled'}else{'enabled'}
   $args=[string]$task.Actions[0].Arguments
   Write-Output "[STATUS] Rain sign-in startup: $enabled (task $($task.State)). Target: $($task.Actions[0].Execute) $args"
  }else{Write-Output '[STATUS] Rain sign-in startup: not installed.'}
  $legacyRepair=Get-ScheduledTask -TaskName $legacyRepairTaskName -ErrorAction SilentlyContinue
  if($legacyRepair){Write-Output '[STATUS] Legacy A-Shell sign-in repair task detected. Run Setup/update once to remove it.'}
  $cursorGuard=Get-ScheduledTask -TaskName $cursorGuardTaskName -ErrorAction SilentlyContinue
  if($cursorGuard){Write-Output '[STATUS] Cursor sign-in guard: installed (native/windowless).'}
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
  $wasRunning=@(Get-AShellRainProcesses).Count -gt 0
  New-AShellRainStartupTask
  Remove-AShellObsoleteStartupTasks
  if($wasRunning){
   Write-Output '[OK] Automatic rain startup repaired. Matrix was already running, so its live rain was not restarted.'
  } elseif($StartNow){
   & $PSCommandPath -Action Start
   Write-Output '[OK] Automatic rain startup installed and the requested live rain session was started.'
  } else {
   Write-Output '[OK] Automatic rain startup installed. Current rain state was left untouched.'
  }
 }
 'Migrate' {
  Remove-AShellObsoleteStartupTasks
  # Upgrade an existing rain task in place to the state-aware --autostart action.
  # If the user explicitly removed startup, leave it removed. Never start/stop rain here.
  $existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if($existing){
   $wasDisabled=$existing.State -eq 'Disabled'
   New-AShellRainStartupTask
   if($wasDisabled){Disable-ScheduledTask -TaskName $taskName | Out-Null}
   Write-Output '[OK] Rain sign-in launcher migrated to saved-state-aware startup without touching live rain.'
  }
  if(Test-AShellRuntimeActive $root){
   # Upgrade invisible next-boot persistence only; no live cursor/theme/taskbar replay.
   & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Migrate
   $cfg=Get-AShellFeatureConfig $root
   # Rewrite old feature files to the current schema while preserving every switch.
   Save-AShellFeatureConfig $root $cfg
   if($cfg.screens){
    . (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
    . (Join-Path $PSScriptRoot 'Setup.Support.ps1')
    . (Join-Path $PSScriptRoot 'Background.Support.ps1')
    # Deploy a changed ProgramData Windhawk screen DLL during code-only updates;
    # otherwise an updated source ZIP could leave the previous overlay guard live.
    if($cfg.signInHook){
     & (Join-Path $PSScriptRoot 'SignIn-Backdrop.ps1') -Action Apply -NoRestart -RuntimeOnly | Out-Null
    }
    [void](Restore-AShellLegacyScreenMaterialOverrides $root)
    [void](Restore-AShellLegacyMachineLockScreenPin $root)
    $lock=Resolve-AShellRuntimeBackground $root
    if($lock){Set-LockImage $lock}
    Write-Output '[OK] Lock/sign-in policy and backdrop handling migrated without replaying the desktop.'
   }
  }
  Write-Output '[OK] Startup/persistence migration complete. Saved screen/taskbar/icon/rain switches and the live desktop were not changed.'
 }
 'Remove' {
  $wasActive=Test-AShellRuntimeActive $root
  foreach($name in @($taskName,$legacyRepairTaskName,$cursorRepairTaskName,$cursorGuardTaskName)){
   $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
   if($task){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
  }
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
