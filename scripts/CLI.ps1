param([string]$Command='help',[string]$Value,[string]$App,[string]$Icon)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Console.Helpers.ps1')
. (Join-Path $PSScriptRoot 'Features.Support.ps1')
$root=Split-Path $PSScriptRoot
function Test-AShellCommandActive { Test-AShellRuntimeActive $root }
function Skip-AShellWhenStopped([string]$What) {
 if(Test-AShellCommandActive){return $false}
 Write-AShellLine ("[SKIP] A-Shell is stopped. Run 'ashell start' first; $What was not changed.")
 return $true
}
Write-AShellHeading $Command.ToUpperInvariant()
try {
 $simpleValueCommands=@('rain','startup','background','bg','color','component','components','screen','screens','taskbar')
 if($Value -and $Command -notin @($simpleValueCommands+@('icons'))){throw 'Unexpected argument. Run ashell help.'}
 if($Command -eq 'icons' -and $Value -eq 'set' -and (!$App -or !$Icon)){throw 'Use: ashell icons set "App name" "icon.png"'}
 if($Command -in @('component','components')){
  if($args.Count -or $Icon){throw 'Use: ashell component <name> <value>'}
 } elseif($args.Count -or (($App -or $Icon) -and !($Command -eq 'icons' -and $Value -in @('set','add')))){throw 'Unexpected arguments. Run ashell help.'}
 & {
 switch($Command.ToLowerInvariant()) {
 'rain' {
  if($Value -notin @('start','stop','status')){throw 'Use: ashell rain start | stop | status'}
  if($Value -ne 'status' -and (Skip-AShellWhenStopped 'rain')){break}
  & "$PSScriptRoot\Manage.ps1" -Action $Value
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
  if(!$Value){throw 'Use: ashell bg "C:\Pictures\image.png" | default | original'}
  if(Skip-AShellWhenStopped 'background'){break}
  if($Value -eq 'restore'){$Value='original'};& "$PSScriptRoot\Background.ps1" -Image $Value
 }
 'bg' {
  if(!$Value){throw 'Use: ashell bg "C:\Pictures\image.png" | default | original'}
  if(Skip-AShellWhenStopped 'background'){break}
  if($Value -eq 'restore'){$Value='original'};& "$PSScriptRoot\Background.ps1" -Image $Value
 }
 'color' {
  if(!$Value){throw 'Use: ashell color 00AAFF | default'}
  if(Skip-AShellWhenStopped 'accent/rain color'){break}
  Write-AShellLine '[WORKING] Updating the active A-Shell accent and rain color...'; & "$PSScriptRoot\Color.ps1" -Color $Value
 }
 'start' {& "$PSScriptRoot\Runtime.ps1" -Action Start}
 'stop' {& "$PSScriptRoot\Runtime.ps1" -Action Stop}
 'status' {& "$PSScriptRoot\Runtime.ps1" -Action Status}
 'screen' {
  if($Value -notin @('on','off')){throw 'Use: ashell screen on | off'}
  if(Skip-AShellWhenStopped 'screen setting'){break}
  & "$PSScriptRoot\Runtime.ps1" -Action Component -Component screens -Value $Value
 }
 'screens' {
  if($Value -notin @('on','off')){throw 'Use: ashell screen on | off'}
  if(Skip-AShellWhenStopped 'screen setting'){break}
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
 'version' {Write-Output 'A-Shell 1.9.3'}
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
  $sections=@(
   @{Title='A-SHELL';Rows=@(
    @('start','Start A-Shell (no-op if already started)'),
    @('stop','Stop A-Shell (no-op if already stopped)'),
    @('status','Show runtime + switch state'),
    @('version','Show installed version')
   )},
   @{Title='SWITCHES';Rows=@(
    @('screen on | off','A-Shell or original lock/login screen'),
    @('taskbar on | off','Transparent taskbar'),
    @('icons on | off','Monochrome app icons')
   )},
   @{Title='APPEARANCE';Rows=@(
    @('bg "C:\image.png"','Set desktop + lock/login image'),
    @('bg original | default','Original or bundled A-Shell image'),
    @('color 00AAFF | default','Set accent + rain color')
   )},
   @{Title='RAIN';Rows=@(
    @('rain start | stop | status','Control Matrix rain'),
    @('startup install|remove|status','Repair/remove sign-in startup')
   )},
   @{Title='ICON MAPPINGS';Rows=@(
    @('icons','Auto-match + refresh icons'),
    @('icons list','Show app mappings'),
    @('icons add "C:\icon.png"','Import monochrome PNG'),
    @('icons set "App" "icon.png"','Assign imported icon'),
    @('icons refresh | check','Refresh or validate mappings')
   )},
   @{Title='SYSTEM';Rows=@(
    @('check','Verify this installation'),
    @('admin','Open one approved admin terminal'),
    @('uninstall','Restore Windows + remove A-Shell')
   )}
  )
  $stateText=if($active){'STARTED - appearance/rain commands run now; start is skipped.'}else{'STOPPED - appearance/rain changes are skipped; stop is skipped.'}
  Write-Host ('  State: '+$stateText) -ForegroundColor DarkGray
  Write-Host ''
  foreach($section in $sections){
   Write-Host ('  '+$section.Title) -ForegroundColor DarkYellow
   foreach($row in $section.Rows){Write-AShellCommand ('ashell '+$row[0]) $row[1]}
   Write-Host ''
  }
  Write-Host '  Setup / update happens only through the A-Shell Setup EXE.' -ForegroundColor DarkGray
 }
 default {throw 'Unknown command. Run ashell help.'}
 }
 } | ForEach-Object {if($_ -is [string]){Write-AShellLine $_}else{$_}}
} catch {Write-AShellLine ('[ERROR] '+$_.Exception.Message);exit 1}
