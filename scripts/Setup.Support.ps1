$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Color.Support.ps1')
function Get-AShellCapabilities([int]$Build=[Environment]::OSVersion.Version.Build,[string]$Architecture=[Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE','Machine'),[string]$LogonHash='') {
 if(!$LogonHash -and (Test-Path "$env:SystemRoot\System32\Windows.UI.Logon.dll")){$LogonHash=(Get-FileHash "$env:SystemRoot\System32\Windows.UI.Logon.dll").Hash}
 $core=($Build -ge 19045 -and $Architecture -eq 'AMD64' -and [Environment]::Is64BitProcess)
 return @{Core=$core;Full=($core -and $Build -ge 22000 -and $LogonHash -eq '51B3AA2B50944111F039C0DE035F9C8951A3FD7A65EDA7380AD30ECE5C2565BF')}
}
function Assert-AShellPackage([string]$Root,[switch]$RequireCompatible) {
 $manifest=Join-Path $Root 'assets\package-manifest.json'
 if(!(Test-Path $manifest)){throw 'Package manifest is missing. Extract the complete ZIP.'}
 $data=Get-Content $manifest -Raw | ConvertFrom-Json
 $prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 foreach($item in $data.files) {
  $full=[IO.Path]::GetFullPath((Join-Path $Root $item.path))
  if(!$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid package manifest path.'}
  $editable=$item.path -match '^assets/icons/[^/]+\.png$' -or $item.path -eq 'assets/icon-map.json'
  if(!$editable -and (!(Test-Path -LiteralPath $full) -or (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $item.sha256)){throw "Missing or modified package file: $($item.path). Re-extract the ZIP, or rebuild its manifest after intentional edits."}
 }
 foreach($file in Get-ChildItem (Join-Path $Root 'scripts') -Filter '*.ps1') {
  $errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$errors)
  if($errors){throw "Invalid PowerShell script: $($file.Name)"}
 }
 . (Join-Path $PSScriptRoot 'Icons.Support.ps1')
 $iconPlan=Get-AShellIconPlan $Root
 & (Join-Path $Root 'scripts\Cursors.ps1') -Action Check
 $build=[Environment]::OSVersion.Version.Build
 $arch=[Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE','Machine')
 $supported=($build -ge 22000 -and $arch -eq 'AMD64' -and [Environment]::Is64BitProcess -and (Get-FileHash "$env:SystemRoot\System32\Windows.UI.Logon.dll").Hash -eq '51B3AA2B50944111F039C0DE035F9C8951A3FD7A65EDA7380AD30ECE5C2565BF')
 Write-Output "Package integrity verified. Full appearance compatibility: $supported"
 if($RequireCompatible -and !(Get-AShellCapabilities).Core){throw 'Setup requires Windows 10 22H2 or Windows 11, x64. No appearance settings were changed.'}
 if(!$supported){Write-Output 'Core setup available: Matrix, accent color, cursors, background and native Windows transparency. Windows 11 mod styling and screen patches will be skipped.'}
}

function Ensure-Windhawk([string]$Root) {
 $exe=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if(Test-Path $exe){
  $version=(Get-Item $exe).VersionInfo.FileVersion -replace ',','.'
  if([version]$version -lt [version]'1.7.3'){throw 'Windhawk 1.7.3 or newer is required. Update Windhawk, then rerun Setup.'}
  Write-Output "Using installed Windhawk $version"
  return
 }
 $dep=(Get-Content (Join-Path $Root 'assets\dependencies.json') -Raw | ConvertFrom-Json).windhawk
 $cache=Join-Path $Root 'state\downloads';New-Item -ItemType Directory $cache -Force | Out-Null
 $installer=Join-Path $cache 'windhawk_setup.exe'
 if(!(Test-Path $installer) -or (Get-FileHash $installer).Hash -ne $dep.sha256) {
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $partial=$installer+'.partial'
  for($attempt=1;$attempt -le 3;$attempt++) {
   try {Invoke-WebRequest -UseBasicParsing -Uri $dep.url -OutFile $partial -TimeoutSec 180;break}
   catch {if($attempt -eq 3){throw 'Windhawk download failed. Check the internet connection and rerun Setup.'};Start-Sleep -Seconds 2}
  }
  if((Get-FileHash $partial).Hash -ne $dep.sha256){throw 'Windhawk installer checksum mismatch; it was not executed.'}
  Move-Item -LiteralPath $partial -Destination $installer -Force
 }
 Write-Output "Installing official Windhawk $($dep.version). Its installer may download additional components."
 $process=Start-Process -FilePath $installer -ArgumentList '/S','/STANDARD' -PassThru -Wait -WindowStyle Hidden
 if($process.ExitCode -notin @(0,3010) -or !(Test-Path $exe)){throw "Windhawk installation failed (exit $($process.ExitCode)). Rerun Setup after resolving the installer/network issue."}
}

function Assert-AShellInstalled([string]$Root,$Desired,[switch]$Core) {
 foreach($entry in $Desired) {
  $actual=Read-RegistryValue $entry[0] $entry[1]
  if($entry[1] -eq 'TaskbarDa' -and $entry[0] -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -and (!$actual.Exists -or [string]$actual.Value -ne [string]$entry[3])){Write-Warning 'Widgets remains controlled by Windows; the remaining appearance settings are being verified.';continue}
  if(!$actual.Exists -or [string]$actual.Value -ne [string]$entry[3]){throw "Appearance verification failed: $($entry[1])"}
 }
 foreach($id in $(if(!$Core){@('windows-11-taskbar-styler','ashell-signin-clear-background','ashell-lockscreen-clear-background')}else{@()})) {
  $config=Get-ItemProperty ('HKLM:\SOFTWARE\Windhawk\Engine\Mods\'+$id)
  if($config.Disabled -ne 0){throw "Mod is disabled: $id"}
  $installed=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$config.LibraryFileName)
  $original=Join-Path $Root ('assets\windhawk\'+$config.LibraryFileName)
  if((Get-FileHash $installed).Hash -ne (Get-FileHash $original).Hash){throw "Mod verification failed: $id"}
 }
 $task=Get-ScheduledTask -TaskName 'Matrix Desktop - Instant Rain'
 if($task.Actions[0].Execute -ne (Join-Path $Root 'bin\MatrixDesktop.exe')){throw 'Matrix startup points at the wrong folder.'}
 $deadline=(Get-Date).AddSeconds(8)
 while(!(Get-Process MatrixDesktop -ErrorAction SilentlyContinue)) {if((Get-Date) -gt $deadline){throw 'Matrix did not start.'};Start-Sleep -Milliseconds 200}
 $cursorPath=(Get-ItemProperty 'HKCU:\Control Panel\Cursors').Arrow
 if(!(Test-Path $cursorPath) -or (Get-FileHash $cursorPath).Hash -ne (Get-FileHash (Join-Path $Root 'assets\cursors\pointer.cur')).Hash){throw 'Cursor installation verification failed.'}
 if(!$Core){$service=Get-Service Windhawk;if($service.Status -ne 'Running'){Start-Service Windhawk}}
 if((Read-RegistryValue 'HKCU:\Software\A-Shell' 'AccentColor').Value -ne 'D65A00'){throw 'Setup accent color verification failed.'}
 Send-AShellColorChange
 Write-Output 'Verified appearance settings, selected mod payloads, cursor selection, shared accent and Matrix startup.'
}

function Read-AShellTree([string]$Path) {
 if(!(Test-Path -LiteralPath $Path)){return @{Path=$Path;Exists=$false;Keys=@();Values=@()}}
 $keys=@((Get-Item -LiteralPath $Path))+@(Get-ChildItem -LiteralPath $Path -Recurse)
 $values=@(foreach($key in $keys){foreach($name in $key.GetValueNames()){Read-RegistryValue $key.PSPath $name}})
 return @{Path=$Path;Exists=$true;Keys=@($keys | ForEach-Object {$_.PSPath});Values=$values}
}
function Restore-AShellTree($Tree) {
 # Only installer-owned appearance locations may be replaced.
 if($Tree.Path -notmatch '^HKLM:\\SOFTWARE\\Windhawk\\Engine\\Mods\\(windows-11-taskbar-styler|ashell-signin-clear-background|ashell-lockscreen-clear-background)$' -and $Tree.Path -ne 'HKCU:\Control Panel\Cursors'){throw 'Unrecognized registry checkpoint path.'}
 if(Test-Path -LiteralPath $Tree.Path){Remove-Item -LiteralPath $Tree.Path -Recurse -Force}
 if($Tree.Exists){foreach($path in $Tree.Keys){New-Item -Path $path -Force | Out-Null};foreach($value in $Tree.Values){Write-RegistryValue $value}}
}
function Save-AShellCheckpoint([string]$Folder,$Desired) {
 New-Item -ItemType Directory $Folder -Force | Out-Null
 $trees=@(foreach($path in @('HKCU:\Control Panel\Cursors','HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler','HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-signin-clear-background','HKLM:\SOFTWARE\Windhawk\Engine\Mods\ashell-lockscreen-clear-background')){Read-AShellTree $path})
 $values=@(foreach($v in $Desired){Read-RegistryValue $v[0] $v[1]})
 $values+=Read-RegistryValue 'HKLM:\SOFTWARE\Windhawk\Engine\Settings' 'Include'
 $values+=Get-AShellColorValues
 $values+=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
 $wallpaper=(Get-ItemProperty 'HKCU:\Control Panel\Desktop').Wallpaper
 $cached=Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
 $desktopCopy=Join-Path $Folder 'desktop.img'
 if($wallpaper -and (Test-Path -LiteralPath $wallpaper)){Copy-Item -LiteralPath $wallpaper -Destination $desktopCopy}
 elseif(Test-Path $cached){Copy-Item -LiteralPath $cached -Destination $desktopCopy}
 Save-LockImage (Join-Path $Folder 'lock.img')
 $lockSource=$null;$lockOriginal=$null
 $lockUri=[Windows.System.UserProfile.LockScreen]::OriginalImageFile
 if($lockUri -and $lockUri.IsFile -and (Test-Path -LiteralPath $lockUri.LocalPath)) {
  $lockSource=$lockUri.LocalPath
  $lockOriginal='lock-original'+[IO.Path]::GetExtension($lockSource)
  Copy-Item -LiteralPath $lockSource -Destination (Join-Path $Folder $lockOriginal)
 }
 $tasks=@(foreach($name in @('Matrix Desktop - Instant Rain','Codex Early Lively Wallpaper','Lively Wallpaper - Adi')){
  $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  @{Name=$name;Exists=($null -ne $task);Running=($task.State -eq 'Running');Xml=$(if($task){Export-ScheduledTask -TaskName $name})}
 })
 $files=@();$fileIndex=0
 foreach($tree in $trees | Where-Object {$_.Path -like 'HKLM:*'}) {
  $id=Split-Path $tree.Path -Leaf
  $paths=@((Join-Path $env:ProgramData ('Windhawk\ModsSource\'+$id+'.wh.cpp')))
  $config=Get-ItemProperty $tree.Path -ErrorAction SilentlyContinue
  if($config.LibraryFileName -and [IO.Path]::GetFileName($config.LibraryFileName) -eq $config.LibraryFileName){$paths+=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$config.LibraryFileName)}
  foreach($path in $paths){if(Test-Path -LiteralPath $path){$name='saved-file-'+$fileIndex+'.bin';Copy-Item -LiteralPath $path -Destination (Join-Path $Folder $name);$files+=@{Path=$path;Saved=$name};$fileIndex++}}
 }
 @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Trees=$trees;Values=$values;Wallpaper=$wallpaper;LockSource=$lockSource;LockOriginal=$lockOriginal;Tasks=$tasks;Files=$files;TerminalPath=(Read-RegistryValue 'HKCU:\Environment' 'Path')} | Export-Clixml (Join-Path $Folder 'checkpoint.clixml')
}
function Stop-AShellRendererForRestore([string]$Root,[switch]$PauseStartup) {
 $exe=Join-Path $Root 'bin\MatrixDesktop.exe'
 $session=(Get-Process -Id $PID).SessionId
 $running=@(Get-Process MatrixDesktop -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session})
 if($running|Where-Object {$_.Path -ne $exe}){throw 'Another A-Shell copy is running in this session. Stop that copy before restoring.'}
 if($PauseStartup){
  $task=Get-ScheduledTask -TaskName 'Matrix Desktop - Instant Rain' -ErrorAction SilentlyContinue
  if($task -and $task.Actions.Execute -contains $exe){Disable-ScheduledTask -TaskName $task.TaskName|Out-Null}
 }
 if($running.Count){
  Write-Output '[WORKING] New rain stopped. Waiting for the existing drops and trails to finish before restoring appearance...'
  Start-Process $exe -ArgumentList '--drain' -WindowStyle Hidden -Wait
  foreach($process in $running){if(!$process.WaitForExit(45000)){throw 'Rain has not finished fading. Appearance restoration has not started; no forced termination was performed.'}}
 }
 if(Get-Process MatrixDesktop -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session}){throw 'Rain restarted during shutdown; restoration stopped before changing appearance.'}
 Write-Output '[OK] Rain finished fading. Restoring wallpaper and colors now.'
}
function Restore-AShellCheckpoint([string]$Folder,[string]$Root,[switch]$RestoreTerminal) {
 $saved=Import-Clixml (Join-Path $Folder 'checkpoint.clixml')
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Checkpoint belongs to another account.'}
 Stop-AShellRendererForRestore $Root -PauseStartup
 if($saved.Wallpaper -and (Test-Path -LiteralPath $saved.Wallpaper) -and (Get-FileHash $saved.Wallpaper).Hash -eq (Get-FileHash (Join-Path $Folder 'desktop.img')).Hash){Set-DesktopImage $saved.Wallpaper}
 elseif(Test-Path (Join-Path $Folder 'desktop.img')){Set-DesktopImage (Join-Path $Folder 'desktop.img')}
 else {Set-DesktopImage ''}
 if($saved.LockOriginal -and (Test-Path (Join-Path $Folder $saved.LockOriginal))) {
  $original=Join-Path $Folder $saved.LockOriginal
  if($saved.LockSource -and (Test-Path -LiteralPath $saved.LockSource) -and (Get-FileHash $saved.LockSource).Hash -eq (Get-FileHash $original).Hash){Set-LockImage $saved.LockSource}
  else {Set-LockImage $original}
 } else {Set-LockImage (Join-Path $Folder 'lock.img')}
 foreach($tree in $saved.Trees){Restore-AShellTree $tree}
 foreach($value in $saved.Values){Write-RegistryValue $value}
 foreach($file in $saved.Files) {
  $source=Join-Path $Folder $file.Saved
  if(!(Test-Path -LiteralPath $file.Path) -or (Get-FileHash $file.Path).Hash -ne (Get-FileHash $source).Hash){Copy-Item -LiteralPath $source -Destination $file.Path -Force}
 }
 if($RestoreTerminal -and $saved.TerminalPath){Write-RegistryValue $saved.TerminalPath}
 Send-AShellColorChange
 Update-SystemCursors
 foreach($task in $saved.Tasks){
  if($task.Exists){Register-ScheduledTask -TaskName $task.Name -Xml $task.Xml -Force | Out-Null;if($task.Running){Start-ScheduledTask -TaskName $task.Name}}
  elseif(Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false}
 }
 $windhawk=Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
 if(Test-Path $windhawk){Start-Process $windhawk -ArgumentList '-restart','-tray-only' -WindowStyle Hidden}
}
