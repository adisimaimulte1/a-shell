param(
 [ValidateSet('Start','Stop','Status','Component','SessionRepair')][string]$Action='Status',
 [ValidateSet('','screens','taskbar-transparency','icons')][string]$Component='',
 [string]$Value='',
 [string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Setup.Support.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
. (Join-Path $PSScriptRoot 'Desktop.Support.ps1')
. (Join-Path $PSScriptRoot 'Icon.Selection.ps1')
. (Join-Path $PSScriptRoot 'Icons.Support.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')

if($Action -eq 'Status'){Write-AShellComponentStatus $root;& (Join-Path $PSScriptRoot 'Manage.ps1') -Action Status;exit 0}
if(!(Test-Path -LiteralPath (Join-Path $root 'state\before-setup.clixml'))){throw 'A-Shell is not initialized. Run the Setup EXE first; start/stop only control an installed A-Shell.'}

# Fast idempotency guard: repeated start/stop calls should not replay visual
# transitions or send Matrix control messages when the requested state already exists.
$matrixExe=Join-Path $root 'bin\MatrixDesktop.exe'
$ourMatrix=@((Get-Process MatrixDesktop -ErrorAction SilentlyContinue) | Where-Object {
 try {[IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($matrixExe)} catch {$false}
})
if($Action -eq 'Start' -and (Test-AShellRuntimeActive $root)) {
 Write-Output '[SKIP] A-Shell is already started. No settings, cursors, Windhawk state or Matrix rain were touched.'
 exit 0
}
if($Action -eq 'Stop' -and !(Test-AShellRuntimeActive $root)) {
 if($ourMatrix.Count){
  Write-Output '[SKIP] A-Shell is already stopped. Existing Matrix trails may still be draining; they were left untouched.'
 } else {
  Write-Output '[SKIP] A-Shell is already stopped. Nothing was restarted, drained or restored again.'
 }
 exit 0
}

if($Action -eq 'Component') {
 if(!$Component){throw 'Choose a component: screens, taskbar-transparency, or icons.'}
 if($Value -notin @('on','off')){throw "Use: ashell component $Component on | off"}
 if(!(Test-AShellRuntimeActive $root)){
  Write-Output "[SKIP] A-Shell is stopped. Component '$Component' was not changed or saved. Run ashell start first."
  exit 0
 }
}

$needsAdmin=$Action -in @('Start','Stop') -or ($Action -eq 'Component' -and (Test-AShellRuntimeActive $root))
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($needsAdmin -and !$admin) {
 Write-Output "[WORKING] Opening an Administrator Command Prompt for A-Shell $($Action.ToLowerInvariant())..."
 $parameters=@{Action=$Action;ExpectedSid=$ExpectedSid}
 if($Component){$parameters.Component=$Component;$parameters.Value=$Value}
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title ('A-Shell '+$Action+' - Administrator')
 if($exitCode){throw "A-Shell $($Action.ToLowerInvariant()) did not finish (exit $exitCode). See state\runtime.log."}
 Write-Output "[OK] A-Shell $($Action.ToLowerInvariant()) completed."
 exit 0
}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid){throw 'Elevation switched to a different Windows account.'}

New-Item -ItemType Directory -Path (Join-Path $root 'state') -Force|Out-Null
Start-Transcript -Path (Join-Path $root 'state\runtime.log') -Append|Out-Null
. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
Enter-AShellOperation
function Write-AShellRuntimeStep([int]$Number,[int]$Total,[string]$Title,[string]$Detail='') {
 Write-Output ''
 Write-Output '################################################################'
 Write-Output (('### STEP {0} OF {1}  |  {2}' -f $Number,$Total,$Title.ToUpperInvariant()))
 Write-Output '################################################################'
 if($Detail){Write-Output ('    '+$Detail)}
}
try {
 if($Action -eq 'Component') {
  $cfg=Get-AShellFeatureConfig $root
  $next=[pscustomobject]@{version=2;screens=$cfg.screens;taskbarTransparency=$cfg.taskbarTransparency;icons=$cfg.icons}
  switch($Component){
   'screens' {$next.screens=($Value -eq 'on')}
   'taskbar-transparency' {$next.taskbarTransparency=($Value -eq 'on')}
   'icons' {$next.icons=($Value -eq 'on')}
  }
  switch($Component){
   'screens' {Set-AShellScreenRuntime $root ([bool]$next.screens)}
   'taskbar-transparency' {Set-AShellTaskbarRuntime $root ([bool]$next.taskbarTransparency) ([bool]$next.icons)}
   'icons' {Set-AShellTaskbarRuntime $root ([bool]$next.taskbarTransparency) ([bool]$next.icons)}
  }
  Save-AShellFeatureConfig $root $next
  Write-Output "[OK] Component changed: $Component = $Value."
  Write-AShellComponentStatus $root
  exit 0
 }

 if($Action -eq 'SessionRepair') {
  if(!(Test-AShellRuntimeActive $root)){Write-Output '[STATUS] Session repair skipped because A-Shell is stopped.';exit 0}
  $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if(!$admin){Write-Warning 'Session repair requires its installed highest-privilege scheduled task; skipping instead of showing a UAC prompt at sign-in.';exit 0}
  Start-Sleep -Milliseconds 1800
  $cfg=Get-AShellFeatureConfig $root
  Hide-AShellDesktopIconsNow $root;Set-AShellDesktopHidden $root
  Write-AShellRuntimeValues (Get-AShellCoreRuntimeValues)
  $desktop=Resolve-AShellRuntimeBackground $root
  Set-DesktopImage $desktop
  & (Join-Path $PSScriptRoot 'Color.ps1') -Color (Get-AShellDesiredAccent $root)
  $caps=Get-AShellCapabilities
  if($caps.Windows11){Set-AShellScreenRuntime $root ([bool]$cfg.screens) -NoRestart;Set-AShellTaskbarRuntime $root ([bool]$cfg.taskbarTransparency) ([bool]$cfg.icons) -NoRestart}
  elseif($cfg.screens){Write-AShellRuntimeValues (Get-AShellScreenRuntimeValues);if($desktop){Set-LockImage $desktop}}
  Send-AShellThemeChange
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action SessionApply
  if($caps.Windows11){Restart-AShellWindhawkRuntime}
  Write-Output '[OK] A-Shell session settings, images and integrations re-applied after sign-in.'
  exit 0
 }

 if($Action -eq 'Start') {
  $cfg=Get-AShellFeatureConfig $root
  Write-AShellRuntimeStep 1 5 'Prepare desktop surface' 'Hiding desktop icons immediately. A-Shell always uses an empty desktop surface while active.'
  Hide-AShellDesktopIconsNow $root;Set-AShellDesktopHidden $root

  Write-AShellRuntimeStep 2 5 'Apply core appearance' 'Restoring the installed A-Shell theme, desktop image and saved A-Shell accent without repeating setup or package installation.'
  Write-AShellRuntimeValues (Get-AShellCoreRuntimeValues)
  $desktop=Resolve-AShellRuntimeBackground $root
  Set-DesktopImage $desktop
  & (Join-Path $PSScriptRoot 'Color.ps1') -Color (Get-AShellDesiredAccent $root)

  Write-AShellRuntimeStep 3 5 'Apply optional components' 'Applying screens, taskbar transparency and icon replacement from the saved component switches.'
  $caps=Get-AShellCapabilities
  if($caps.Windows11){Set-AShellScreenRuntime $root ([bool]$cfg.screens) -NoRestart}
  elseif($cfg.screens){Write-AShellRuntimeValues (Get-AShellScreenRuntimeValues);$lock=Resolve-AShellRuntimeBackground $root;if($lock){Set-LockImage $lock};Write-Output '[OK] Windows 10 lock/sign-in supported settings enabled; Windows 11 visual-tree screen mod is not used.'}
  else {Restore-AShellScreenBaseline $root -NoRestart}
  if($caps.Windows11){Set-AShellTaskbarRuntime $root ([bool]$cfg.taskbarTransparency) ([bool]$cfg.icons) -NoRestart}

  Write-AShellRuntimeStep 4 5 'Rain and cursors' 'Ensuring rain startup is enabled without restarting an existing Matrix process, then applying the cursor scheme last.'
  Set-AShellRainRuntime $root $true
  Send-AShellThemeChange
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Apply
  if($caps.Windows11){Restart-AShellWindhawkRuntime}

  Write-AShellRuntimeStep 5 5 'Finish' 'A-Shell is active. Setup files and backups were not rebuilt or recopied.'
  Set-AShellRuntimeState $root $true 'ashell start'
  Set-Content -LiteralPath (Join-Path $root 'state\applied.txt') -Value (Get-Date -Format o) -Encoding ascii
  Write-AShellComponentStatus $root
  Write-Output '[OK] A-Shell settings are active. If Matrix was already running, its existing rain process was preserved.'
  exit 0
 }

 # STOP deliberately has no "restore the pre-stop checkpoint on failure" path.
 # A failed old full restore used to roll back to the A-Shell-active checkpoint,
 # which could re-enable the Matrix startup task and make rain appear to restart.
 # Stop is a best-effort deactivation transaction: each independent component is
 # restored even if another one reports an error, and rain is never re-enabled.
 $errors=New-Object System.Collections.Generic.List[string]
 function Invoke-AShellStopPart([string]$Name,[scriptblock]$Block) {
  try {& $Block}
  catch {$message="${Name}: $($_.Exception.Message)";$errors.Add($message);Write-Warning $message}
 }
 Set-AShellRuntimeState $root $false 'ashell stop started'
 Write-AShellRuntimeStep 1 5 'Stop rain first' 'Disabling A-Shell rain startup before the fade begins. Nothing later in stop can re-enable it.'
 Invoke-AShellStopPart 'Rain' {Set-AShellRainRuntime $root $false}

 Write-AShellRuntimeStep 2 5 'Restore screens and taskbar' 'Restoring original lock/sign-in policy and visual styling, then the pre-A-Shell taskbar registry configuration. No Windhawk DLL is replaced.'
 $caps=Get-AShellCapabilities
 Invoke-AShellStopPart 'Screens' {Restore-AShellScreenBaseline $root -NoRestart}
 if($caps.Windows11){Invoke-AShellStopPart 'Taskbar' {Restore-AShellTaskbarBaseline $root}}

 Write-AShellRuntimeStep 3 5 'Restore Windows appearance' 'Restoring saved theme values, desktop wallpaper and accent while the existing rain trails finish independently.'
 Invoke-AShellStopPart 'Windows preferences' {Restore-AShellOriginalSetupValues $root}
 Invoke-AShellStopPart 'Desktop background' {Set-DesktopImage (Get-AShellOriginalDesktopImage $root)}
 Invoke-AShellStopPart 'Accent color' {& (Join-Path $PSScriptRoot 'Color.ps1') -Action Restore}

 Write-AShellRuntimeStep 4 5 'Restore cursors and desktop icons' 'Restoring the original cursor scheme and exact saved desktop icon visibility/layout.'
 Invoke-AShellStopPart 'Cursors' {& (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Restore}
 Invoke-AShellStopPart 'Desktop icons' {Restore-AShellDesktop $root}
 Invoke-AShellStopPart 'Theme refresh' {Send-AShellThemeChange}
 if($caps.Windows11){Invoke-AShellStopPart 'Windhawk refresh' {Restart-AShellWindhawkRuntime}}

 Write-AShellRuntimeStep 5 5 'Finish' 'A-Shell remains installed and its command stays available; only the active desktop transformation is stopped.'
 Set-AShellRuntimeState $root $false $(if($errors.Count){'ashell stop completed with warnings'}else{'ashell stop'})
 if($errors.Count){
  Write-Output '[ERROR] A-Shell stopped as far as possible, but some independent restore parts need attention:'
  foreach($message in $errors){Write-Output ('  - '+$message)}
  Write-Output '[OK] Rain startup remains disabled. A-Shell will NOT roll back to the active state.'
  exit 1
 }
 Write-Output '[OK] A-Shell stopped. Original appearance is restored; A-Shell remains installed for a fast ashell start.'
} finally {Exit-AShellOperation;Stop-Transcript|Out-Null}
