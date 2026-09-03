param([switch]$Restore)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run from ashell admin, or use ashell icons refresh to apply the repair.'}
$snapshot=Join-Path $root 'state\taskbar-engine-before.clixml'
$source=Join-Path $env:ProgramData 'Windhawk\ModsSource\windows-11-taskbar-styler.wh.cpp'
$sourceBackup=Join-Path $root 'state\taskbar-engine-source-before.cpp'
$current=Get-ItemProperty -LiteralPath $key
if($Restore) {
 $saved=Import-Clixml -LiteralPath $snapshot
 Set-ItemProperty $key LibraryFileName $saved.LibraryFileName
 Set-ItemProperty $key Version $saved.Version
 if(Test-Path $sourceBackup){Copy-Item $sourceBackup $source -Force}
} else {
 $meta=Get-Content (Join-Path $root 'assets\windhawk\mod.json') -Raw|ConvertFrom-Json
 if($current.LibraryFileName -eq $meta.LibraryFileName){return}
 $payload=Join-Path $root ('assets\windhawk\'+$meta.LibraryFileName)
 $destination=Join-Path $env:ProgramData ('Windhawk\Engine\Mods\64\'+$meta.LibraryFileName)
 if(!(Test-Path $snapshot)) {
  @{LibraryFileName=$current.LibraryFileName;Version=$current.Version}|Export-Clixml $snapshot
  if(Test-Path $source){Copy-Item $source $sourceBackup}
 }
 Copy-Item -LiteralPath $payload -Destination $destination -Force
 if((Get-FileHash $payload).Hash -ne (Get-FileHash $destination).Hash){throw 'Installed taskbar engine failed verification.'}
 Copy-Item (Join-Path $root 'assets\windhawk\windows-11-taskbar-styler.wh.cpp') $source -Force
 Set-ItemProperty $key LibraryFileName $meta.LibraryFileName
 Set-ItemProperty $key Version $meta.Version
}
$next=[uint32][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if($current.SettingsChangeTime -and [uint32]$current.SettingsChangeTime -ge $next){$next=[uint32]$current.SettingsChangeTime+1}
Set-ItemProperty $key SettingsChangeTime $next
Write-Output '[OK] Taskbar engine switched; original library retained for rollback.'
