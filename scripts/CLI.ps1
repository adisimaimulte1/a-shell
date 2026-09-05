param([string]$Command='help',[string]$Value,[string]$App,[string]$Icon)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Console.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
$root=Split-Path $PSScriptRoot
$commandKey=$Command.ToLowerInvariant()
if($commandKey -in @('screen','screens','locscreen')){$commandKey='lockscreen'}
if($commandKey -eq 'bg'){$commandKey='background'}
$Command=$commandKey
function Test-AShellCommandActive { Test-AShellRuntimeActive $root }
function Skip-AShellWhenStopped([string]$What) {
 if(Test-AShellCommandActive){return $false}
 Write-AShellLine ("[SKIP] A-Shell is stopped. Run 'ashell start' first; $What was not changed.")
 return $true
}
Write-AShellHeading $Command.ToUpperInvariant()
try {
 $simpleValueCommands=@('rain','startup','background','color','component','components','lockscreen','taskbar')
 if($Value -and $Command -notin @($simpleValueCommands+@('icons'))){throw 'Unexpected argument. Run ashell help.'}
 if($Command -eq 'icons' -and $Value -eq 'set' -and (!$App -or !$Icon)){throw 'Use: ashell icons set "App name" "icon.png"'}
 if($Command -in @('component','components')){
  if($args.Count -or $Icon){throw 'Use: ashell component <name> <value>'}
 } elseif($args.Count -or (($App -or $Icon) -and !($Command -eq 'icons' -and $Value -in @('set','add')))){throw 'Unexpected arguments. Run ashell help.'}
 & {
 switch($Command.ToLowerInvariant()) {
 'rain' {
  if($Value -notin @('on','off','status','start','stop')){throw 'Use: ashell rain on | off | status'}
  $rainAction=switch($Value){'on'{'start'} 'off'{'stop'} default{$Value}}
  if($rainAction -ne 'status' -and (Skip-AShellWhenStopped 'rain')){break}
  if($rainAction -in @('start','stop')){
   $rainEnabled=($rainAction -eq 'start')
   & "$PSScriptRoot\Manage.ps1" -Action $rainAction
   $rainConfig=Get-AShellFeatureConfig $root
   if([bool]$rainConfig.rain -ne $rainEnabled){Set-AShellRainPreference $root $rainEnabled}
  } else {
   & "$PSScriptRoot\Manage.ps1" -Action $rainAction
  }
 }
 'startup' {
  if($Value -notin @('install','remove','status')){throw 'Use: ashell startup install | remove | status'}
  if($Value -ne 'status' -and (Skip-AShellWhenStopped 'startup setting')){break}
  & "$PSScriptRoot\Manage.ps1" -Action $Value
 }
 'icons' {
  $action=if($Value){$Value}else{'auto'}
  if($action -notin @('list','check') -and (Skip-AShellWhenStopped 'icon settings')){break}
  if($Value -in @('on','off')){& "$PSScriptRoot\Runtime.ps1" -Action Component -Component icons -Value $Value}
  else {& "$PSScriptRoot\Icons.ps1" -Action $action -App $App -Icon $Icon}
 }
 'background' {
  if(!$Value){throw 'Use: ashell background "C:\Pictures\image.png" | default | original'}
  if(Skip-AShellWhenStopped 'background'){break}
  if($Value -eq 'restore'){$Value='original'};& "$PSScriptRoot\Background.ps1" -Image $Value
 }
 'color' {
  if(!$Value){throw 'Use: ashell color 00AAFF | default'}
  if(Skip-AShellWhenStopped 'accent/rain color'){break}
  & "$PSScriptRoot\Color.ps1" -Color $Value
 }
 'start' {& "$PSScriptRoot\Runtime.ps1" -Action Start}
 'stop' {& "$PSScriptRoot\Runtime.ps1" -Action Stop}
 'status' {& "$PSScriptRoot\Runtime.ps1" -Action Status}
 'lockscreen' {
  if($Value -notin @('on','off')){throw 'Use: ashell lockscreen on | off'}
  if(Skip-AShellWhenStopped 'lock-screen setting'){break}
  & "$PSScriptRoot\Runtime.ps1" -Action Component -Component screens -Value $Value
 }
 'taskbar' {
  if($Value -notin @('on','off')){throw 'Use: ashell taskbar on | off'}
  if(Skip-AShellWhenStopped 'taskbar setting'){break}
  & "$PSScriptRoot\Runtime.ps1" -Action Component -Component taskbar-transparency -Value $Value
 }
 'component' {
  if(!$Value -or !$App){throw 'Use: ashell component screens|taskbar-transparency|icons on|off'}
  if(Skip-AShellWhenStopped 'component setting'){break}
  & "$PSScriptRoot\Runtime.ps1" -Action Component -Component $Value -Value $App
 }
 'components' {
  if(!$Value){& "$PSScriptRoot\Runtime.ps1" -Action Status}
  elseif(!$App){throw 'Use: ashell component <name> <value>'}
  elseif(!(Skip-AShellWhenStopped 'component setting')){& "$PSScriptRoot\Runtime.ps1" -Action Component -Component $Value -Value $App}
 }
 'uninstall' {& "$PSScriptRoot\Uninstall.ps1"}
 'version' {
  $versionFile=Join-Path $root 'VERSION'
  if(!(Test-Path -LiteralPath $versionFile -PathType Leaf)){throw 'The installed VERSION file is missing. Run the Setup EXE to repair A-Shell.'}
  $productVersion=(Get-Content -LiteralPath $versionFile -Raw).Trim()
  if($productVersion -notmatch '^\d+\.\d+\.\d+$'){throw 'The installed VERSION file is invalid. Run the Setup EXE to repair A-Shell.'}
  Write-Output ('A-Shell '+$productVersion)
 }
 'setup' {throw 'Setup is installer-only. Run the A-Shell Setup EXE to install or update.'}
 'restore' {Write-Output '[INFO] "restore" is a legacy alias for stop.';& "$PSScriptRoot\Runtime.ps1" -Action Stop}
 'undo' {Write-Output '[INFO] "undo" is a legacy alias for stop.';& "$PSScriptRoot\Runtime.ps1" -Action Stop}
 'check' {& "$PSScriptRoot\Setup.ps1" -Action Check}
 'admin' {
  $session=Join-Path $PSScriptRoot 'AdminSession.cmd'
  Start-Process "$env:SystemRoot\System32\cmd.exe" -Verb RunAs -ArgumentList ('/d /s /k ""'+$session+'""')
  '[OK] Administrator Command Prompt requested.'
 }
 'help' {
  $active=Test-AShellCommandActive
  $activeText='stopped'
  if($active){$activeText='started'}
  Write-AShellLine ('[STATUS] A-Shell: '+$activeText)

  Write-AShellSection 'Runtime'
  Write-AShellCommand 'ashell start' 'Apply the saved A-Shell state.'
  Write-AShellCommand 'ashell stop' 'Restore the original Windows appearance.'
  Write-AShellCommand 'ashell status' 'Show the saved runtime and switches.'

  Write-AShellSection 'Appearance'
  Write-AShellCommand 'ashell lockscreen on | off' 'Lock + sign-in styling.'
  Write-AShellCommand 'ashell taskbar on | off' 'Taskbar transparency.'
  Write-AShellCommand 'ashell icons on | off' 'Monochrome app icons.'
  Write-AShellCommand 'ashell background "C:\image.png"' 'Set desktop + lock/sign-in image.'
  Write-AShellCommand 'ashell background default | original' 'Use bundled or original image.'
  Write-AShellCommand 'ashell color 00AAFF | default' 'Set accent + rain color.'
  Write-AShellCommand 'ashell rain on | off | status' 'Control Matrix rain.'

  Write-AShellSection 'Icon mappings'
  Write-AShellCommand 'ashell icons' 'Auto-match installed apps.'
  Write-AShellCommand 'ashell icons list' 'Show detected mappings.'
  Write-AShellCommand 'ashell icons add "C:\icon.png"' 'Import a monochrome PNG.'
  Write-AShellCommand 'ashell icons set "App" "icon.png"' 'Assign an imported icon.'
  Write-AShellCommand 'ashell icons refresh | check' 'Refresh or validate mappings.'

  Write-AShellSection 'System'
  Write-AShellCommand 'ashell check' 'Verify this installation.'
  Write-AShellCommand 'ashell version' 'Show the installed version.'
  Write-AShellCommand 'ashell admin' 'Open an approved admin terminal.'
  Write-AShellCommand 'ashell uninstall' 'Restore Windows and remove A-Shell.'
  Write-Host ''
  Write-Host '  Legacy aliases still work, but are intentionally hidden from this list.' -ForegroundColor DarkGray
 }
 default {throw 'Unknown command. Run ashell help.'}
 }
 } | ForEach-Object {if($_ -is [string]){Write-AShellLine $_}else{$_}}
} catch {Write-AShellLine ('[ERROR] '+$_.Exception.Message);exit 1}
