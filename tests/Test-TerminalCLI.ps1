$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Appearance.Helpers.ps1')
. (Join-Path $root 'scripts\Color.Support.ps1')
$initial=Read-RegistryValue 'HKCU:\Environment' 'Path'
$backup=Join-Path $root 'state\terminal-before.clixml'
$hash=(Get-FileHash $backup).Hash
$marker=Join-Path $env:TEMP ('AShell-PATH-Probe-'+[guid]::NewGuid().ToString('N'))
try {
 Write-RegistryValue @{Path='HKCU:\Environment';Name='Path';Kind='ExpandString';Exists=$true;Value=([string]$initial.Value+';'+$marker)}
 & (Join-Path $root 'scripts\Terminal.ps1') -Action Restore
 $path=[string](Read-RegistryValue 'HKCU:\Environment' 'Path').Value
 if($path.Split(';') -notcontains $marker -or $path.Split(';') -contains $root){throw 'Undo did not preserve a later PATH addition while removing its own entry.'}
 & (Join-Path $root 'scripts\Terminal.ps1') -Action Install
 if((Get-FileHash $backup).Hash -ne $hash){throw 'Terminal baseline was replaced.'}
 $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[string](Read-RegistryValue 'HKCU:\Environment' 'Path').Value
 Push-Location $env:TEMP
 try {
  if((Get-Command ashell.cmd).Source -ne (Join-Path $root 'ashell.cmd')){throw 'ashell resolves to the wrong installation.'}
  $rendererId=(Get-Process MatrixDesktop).Id
  & ashell color 00AAFF
  if($LASTEXITCODE){throw 'Terminal color command failed.'}
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Read-Accent.ps1') -Expected 00AAFF
  if($LASTEXITCODE){throw 'Windows color readback failed.'}
  & ashell color default
  if($LASTEXITCODE -or (Get-Process MatrixDesktop).Id -ne $rendererId){throw 'Default color failed or restarted the renderer.'}
  & ashell help
  if($LASTEXITCODE){throw 'Terminal help failed.'}
 } finally {Pop-Location}
 'PASS: terminal command from another folder, live/default colors, unchanged renderer PID, stable backup and preservation of later PATH additions.'
} finally {
 Write-RegistryValue $initial
 $result=[IntPtr]::Zero
 [void][AShellAccentNative]::Broadcast([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'Environment',2,100,[ref]$result)
}
