param(
 [string]$Action='Status',
 [string]$Component='',
 [string]$Value='',
 [string]$ExpectedSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
)
$ErrorActionPreference='Stop'

if($Action -ne 'Start' -and $Action -ne 'Stop' -and $Action -ne 'Status' -and $Action -ne 'Component') {
 throw 'Action must be Start, Stop, Status, or Component.'
}
if($Component -ne '' -and $Component -ne 'screens' -and $Component -ne 'taskbar-transparency' -and $Component -ne 'icons') {
 throw 'Component must be screens, taskbar-transparency, or icons.'
}

$root=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Setup.Support.ps1')
. (Join-Path $PSScriptRoot 'Background.Support.ps1')
. (Join-Path $PSScriptRoot 'Desktop.Support.ps1')
. (Join-Path $PSScriptRoot 'Icon.Selection.ps1')
. (Join-Path $PSScriptRoot 'Icons.Support.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
. (Join-Path $PSScriptRoot 'Elevation.Helpers.ps1')

if($Action -eq 'Status') {
 Write-AShellComponentStatus $root
 exit 0
}

if(!(Test-Path -LiteralPath (Join-Path $root 'state\before-setup.clixml'))) {
 throw 'A-Shell is not initialized. Run the Setup EXE first; start/stop only control an installed A-Shell.'
}

# Repeated start/stop calls must not replay visual transitions.
$matrixExe=Join-Path $root 'bin\MatrixDesktop.exe'
$ourMatrix=@((Get-Process MatrixDesktop -ErrorAction SilentlyContinue) | Where-Object {
 try {
  [IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($matrixExe)
 } catch {
  $false
 }
})

if($Action -eq 'Start' -and (Test-AShellRuntimeActive $root)) {
 Write-Output '[SKIP] A-Shell is already started. Nothing was reapplied.'
 exit 0
}
if($Action -eq 'Stop' -and !(Test-AShellRuntimeActive $root)) {
 if($ourMatrix.Count -gt 0) {
  Write-Output '[SKIP] A-Shell is already stopped. Existing rain trails were left to drain.'
 } else {
  Write-Output '[SKIP] A-Shell is already stopped. Nothing needed restoring.'
 }
 exit 0
}

if($Action -eq 'Component') {
 if($Component -eq '') {
  throw 'Choose a component: screens, taskbar-transparency, or icons.'
 }
 if($Value -ne 'on' -and $Value -ne 'off') {
  throw ('Use: ashell component '+$Component+' on | off')
 }
 if(!(Test-AShellRuntimeActive $root)) {
  Write-Output ('[SKIP] A-Shell is stopped. '+$Component+' was not changed.')
  exit 0
 }

 # Do the cheap saved-state/live-state check before requesting elevation or
 # rewriting features.json. Repeating a switch should be as quiet as rain.
 $cfg=Get-AShellFeatureConfig $root
 $wanted=($Value -eq 'on')
 $savedSame=$false
 $liveSame=$false
 $label=$Component
 if($Component -eq 'screens') {
  $label='Lock screen'
  $savedSame=([bool]$cfg.screens -eq $wanted)
  if($wanted){$liveSame=Test-AShellScreenRuntimeApplied $root}else{$liveSame=$true}
 } elseif($Component -eq 'taskbar-transparency') {
  $label='Taskbar'
  $savedSame=([bool]$cfg.taskbarTransparency -eq $wanted)
  if($savedSame){$liveSame=Test-AShellTaskbarRuntimeApplied $root $wanted ([bool]$cfg.icons)}
 } elseif($Component -eq 'icons') {
  $label='Icons'
  $savedSame=([bool]$cfg.icons -eq $wanted)
  if($savedSame){$liveSame=Test-AShellTaskbarRuntimeApplied $root ([bool]$cfg.taskbarTransparency) $wanted}
 }
 if($savedSame -and $liveSame) {
  Write-Output ('[SKIP] '+$label+' is already '+$Value+'. Nothing changed.')
  exit 0
 }
}

$needsAdmin=$false
if($Action -eq 'Start' -or $Action -eq 'Stop') {
 $needsAdmin=$true
} elseif($Action -eq 'Component' -and (Test-AShellRuntimeActive $root)) {
 $needsAdmin=$true
}

$currentIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal=New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$admin=$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if($needsAdmin -and !$admin) {
 Write-Output ('[WORKING] Requesting administrator access for A-Shell '+$Action.ToLowerInvariant()+'...')
 $parameters=@{Action=$Action;ExpectedSid=$ExpectedSid}
 if($Component -ne '') {
  $parameters.Component=$Component
  $parameters.Value=$Value
 }
 $exitCode=Invoke-AShellElevatedScript -ScriptPath $PSCommandPath -Parameters $parameters -Title ('A-Shell '+$Action+' - Administrator')
 if($exitCode -ne 0) {
  throw ('A-Shell '+$Action.ToLowerInvariant()+' did not finish (exit '+$exitCode+'). See state\runtime.log.')
 }
 exit 0
}

if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid) {
 throw 'Elevation switched to a different Windows account.'
}

New-Item -ItemType Directory -Path (Join-Path $root 'state') -Force | Out-Null
Start-Transcript -Path (Join-Path $root 'state\runtime.log') -Append | Out-Null
. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
Enter-AShellOperation

function Write-AShellRuntimeStep([int]$Number,[int]$Total,[string]$Title) {
 if($Number -ge $Total) {
  return
 }
 Write-Output ('[WORKING] '+$Title+'.')
}

try {
 if($Action -eq 'Component') {
  $cfg=Get-AShellFeatureConfig $root
  $next=[pscustomobject]@{
   version=4
   screens=$cfg.screens
   signInHook=$cfg.signInHook
   taskbarTransparency=$cfg.taskbarTransparency
   icons=$cfg.icons
   rain=$cfg.rain
  }

  if($Component -eq 'screens') {
   $next.screens=($Value -eq 'on')
   Set-AShellScreenRuntime $root ([bool]$next.screens) | Out-Null
  } elseif($Component -eq 'taskbar-transparency') {
   $next.taskbarTransparency=($Value -eq 'on')
   Set-AShellTaskbarRuntime $root ([bool]$next.taskbarTransparency) ([bool]$next.icons) | Out-Null
  } elseif($Component -eq 'icons') {
   $next.icons=($Value -eq 'on')
   Set-AShellTaskbarRuntime $root ([bool]$next.taskbarTransparency) ([bool]$next.icons) | Out-Null
  }

  # Persist only after Windows accepted the requested runtime change.
  Save-AShellFeatureConfig $root $next

  $label=$Component
  if($Component -eq 'screens') {
   $label='Lock screen'
  } elseif($Component -eq 'taskbar-transparency') {
   $label='Taskbar'
  } elseif($Component -eq 'icons') {
   $label='Icons'
  }
  Write-Output ('[OK] '+$label+': '+$Value+'.')
  exit 0
 }

 if($Action -eq 'Start') {
  $cfg=Get-AShellFeatureConfig $root

  Write-AShellRuntimeStep 1 5 'Prepare desktop surface'
  Hide-AShellDesktopIconsNow $root
  Set-AShellDesktopHidden $root

  Write-AShellRuntimeStep 2 5 'Apply core appearance'
  Write-AShellRuntimeValues (Get-AShellCoreRuntimeValues)
  $desktop=Resolve-AShellRuntimeBackground $root
  Set-DesktopImage $desktop
  & (Join-Path $PSScriptRoot 'Color.ps1') -Color (Get-AShellDesiredAccent $root)

  Write-AShellRuntimeStep 3 5 'Apply optional components'
  $caps=Get-AShellCapabilities
  if($caps.Core) {
   Set-AShellScreenRuntime $root ([bool]$cfg.screens) -NoRestart
  } elseif([bool]$cfg.screens) {
   Write-AShellRuntimeValues (Get-AShellScreenRuntimeValues)
   $lock=Resolve-AShellRuntimeBackground $root
   if($lock){Set-LockImage $lock}
   Write-Output '[OK] Compatibility lock/sign-in settings enabled.'
  } else {
   Restore-AShellScreenBaseline $root -NoRestart
  }

  if($caps.Windows11) {
   Set-AShellTaskbarRuntime $root ([bool]$cfg.taskbarTransparency) ([bool]$cfg.icons) -NoRestart
   if([bool]$cfg.taskbarTransparency -or [bool]$cfg.icons) {
    Ensure-AShellTaskbarRuntimeLoaded $root
   }
  }

  Write-AShellRuntimeStep 4 5 'Restore rain and cursors'
  Set-AShellRainRuntime $root ([bool]$cfg.rain)
  & (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Apply

  Set-AShellRuntimeState $root $true 'ashell start'
  Set-Content -LiteralPath (Join-Path $root 'state\applied.txt') -Value (Get-Date -Format o) -Encoding ascii
  Write-AShellComponentStatus $root

  $rainState='off'
  if([bool]$cfg.rain) {
   $rainState='on'
  }
  Write-Output ('[OK] A-Shell started. Rain: '+$rainState+'.')
  exit 0
 }

 # Stop is best-effort: independent restore parts continue even if one fails.
 $restoreErrors=@()
 function Invoke-AShellStopPart([string]$Name,[scriptblock]$Block) {
  try {
   & $Block
  } catch {
   $message=$Name+': '+$_.Exception.Message
   $script:restoreErrors+=@($message)
   Write-Warning $message
  }
 }

 Set-AShellRuntimeState $root $false 'ashell stop started'

 Write-AShellRuntimeStep 1 5 'Stop rain'
 Invoke-AShellStopPart 'Rain' {Set-AShellRainRuntime $root $false}

 Write-AShellRuntimeStep 2 5 'Restore screens and taskbar'
 $caps=Get-AShellCapabilities
 Invoke-AShellStopPart 'Screens' {Restore-AShellScreenBaseline $root -NoRestart}
 if($caps.Windows11) {
  Invoke-AShellStopPart 'Taskbar' {Restore-AShellTaskbarBaseline $root}
 }

 Write-AShellRuntimeStep 3 5 'Restore Windows appearance'
 Invoke-AShellStopPart 'Windows preferences' {Restore-AShellOriginalSetupValues $root}
 Invoke-AShellStopPart 'Desktop background' {Set-DesktopImage (Get-AShellOriginalDesktopImage $root)}
 Invoke-AShellStopPart 'Accent color' {& (Join-Path $PSScriptRoot 'Color.ps1') -Action Restore}

 Write-AShellRuntimeStep 4 5 'Restore cursors and desktop icons'
 Invoke-AShellStopPart 'Cursors' {& (Join-Path $PSScriptRoot 'Cursors.ps1') -Action Restore}
 Invoke-AShellStopPart 'Desktop icons' {Restore-AShellDesktop $root}
 Invoke-AShellStopPart 'Theme refresh' {Send-AShellThemeChange}
 if($caps.Windows11) {
  Invoke-AShellStopPart 'Windhawk refresh' {Restart-AShellWindhawkRuntime}
 }

 $stopReason='ashell stop'
 if($restoreErrors.Count -gt 0) {
  $stopReason='ashell stop completed with warnings'
 }
 Set-AShellRuntimeState $root $false $stopReason

 if($restoreErrors.Count -gt 0) {
  Write-Output '[ERROR] A-Shell stopped, but some restore steps reported warnings:'
  foreach($message in $restoreErrors) {
   Write-Output ('  - '+$message)
  }
  Write-Output '[OK] A-Shell remains stopped. Saved component preferences were preserved.'
  exit 1
 }

 Write-Output '[OK] A-Shell stopped. Original Windows appearance restored.'
} finally {
 Exit-AShellOperation
 Stop-Transcript | Out-Null
}
