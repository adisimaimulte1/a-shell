param([string]$Command='help',[string]$Value,[string]$App,[string]$Icon)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Console.Helpers.ps1')
Write-AShellHeading $Command.ToUpperInvariant()
try {
 if($Value -and $Command -notin @('rain','startup','icons','background','color','setup')){throw 'Unexpected argument. Run ashell help.'}
 if($Command -eq 'icons' -and $Value -eq 'set' -and (!$App -or !$Icon)){throw 'Use: ashell icons set "App name" "icon.png"'}
 if($args.Count -or (($App -or $Icon) -and !($Command -eq 'icons' -and $Value -in @('set','add')))){throw 'Unexpected arguments. Run ashell help.'}
 & {
 switch($Command.ToLowerInvariant()) {
 'rain' {if($Value -notin @('start','stop','status')){throw 'Use: ashell rain start | stop | status'};& "$PSScriptRoot\Manage.ps1" -Action $Value}
 'startup' {if($Value -notin @('install','remove','status')){throw 'Use: ashell startup install | remove | status'};& "$PSScriptRoot\Manage.ps1" -Action $Value}
 'icons' {if(!$Value){$Value='auto'};& "$PSScriptRoot\Icons.ps1" -Action $Value -App $App -Icon $Icon}
 'background' {if(!$Value){throw 'Use: ashell background "C:\Pictures\image.png" | default | original'};if($Value -eq 'restore'){$Value='original'};& "$PSScriptRoot\Background.ps1" -Image $Value}
 'color' {if(!$Value){throw 'Use: ashell color 00AAFF | default'};Write-AShellLine '[WORKING] Updating your accent and live rain...'; & "$PSScriptRoot\Color.ps1" -Color $Value}
 'start' {& "$PSScriptRoot\Manage.ps1" -Action Start}
 'stop' {& "$PSScriptRoot\Manage.ps1" -Action Stop}
 'status' {& "$PSScriptRoot\Manage.ps1" -Action Status}
 'setup' {if($Value -and $Value -ne 'core'){throw 'Use: ashell setup [core]'};& "$PSScriptRoot\Setup.ps1" -Action Apply -Core:($Value -eq 'core')}
 'restore' {& "$PSScriptRoot\Setup.ps1" -Action Restore}
 'undo' {& "$PSScriptRoot\Setup.ps1" -Action Restore}
 'check' {& "$PSScriptRoot\Setup.ps1" -Action Check}
 'admin' {
  $session=Join-Path $PSScriptRoot 'AdminSession.cmd'
  Start-Process "$env:SystemRoot\System32\cmd.exe" -Verb RunAs -ArgumentList ('/d /s /k ""'+$session+'""')
  '[OK] Administrator Command Prompt requested. Commands in that window share one approval.'
 }
 'help' {
  foreach($section in @(
   @{Title='APPEARANCE';Rows=@(@('color 00AAFF | default','Windows accent + live rain'),@('background "C:\image.png"','Desktop, lock and sign-in image'),@('background original | default','Saved wallpaper or A-Shell wallpaper'))},
   @{Title='RAIN';Rows=@(@('rain start | stop | status','Start, finish existing rain, inspect'),@('startup install | remove','Automatic sign-in startup'))},
   @{Title='ICONS';Rows=@(@('icons','Auto-match known icons, apply changes'),@('icons list','Installed app names and mappings'),@('icons add "C:\Downloads\icon.png"','Import a PNG into assets\icons'),@('icons set "App name" "icon.png"','Assign an icon from assets\icons'),@('icons refresh | check','Apply mappings or validate them'))},
   @{Title='SETUP & UNDO';Rows=@(@('setup [core]','Install or reapply appearance'),@('restore','Restore your saved pre-setup state'),@('check','Verify package and compatibility'),@('admin','One approved terminal for admin work'))}
  )) {
   Write-Host ('  '+$section.Title) -ForegroundColor DarkYellow
   foreach($row in $section.Rows){Write-AShellCommand ('ashell '+$row[0]) $row[1]};Write-Host ''
  }
  Write-Host '  Keep state/ and Documents\original_desktop for undo.' -ForegroundColor DarkGray
 }
 default {throw 'Unknown command. Run ashell help.'}
 }
 } | ForEach-Object {if($_ -is [string]){Write-AShellLine $_}else{$_}}
} catch {Write-AShellLine ('[ERROR] '+$_.Exception.Message);exit 1}
