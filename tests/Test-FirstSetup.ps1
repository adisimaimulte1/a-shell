param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if(!$Worker){$p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker') -Wait -PassThru;exit $p.ExitCode}
$folder=Join-Path $root ('state\first-setup-test-'+[guid]::NewGuid().ToString('N'))
$copy=Join-Path $folder 'A-Shell'
New-Item -ItemType Directory $copy -Force | Out-Null
$manifest=Get-Content (Join-Path $root 'assets\package-manifest.json') -Raw | ConvertFrom-Json
foreach($item in @($manifest.files)+@(@{path='assets/package-manifest.json'})) {
 $destination=Join-Path $copy $item.path
 New-Item -ItemType Directory (Split-Path $destination) -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path $root $item.path) -Destination $destination
}
$log=Join-Path $root 'state\first-setup-test.txt'
'Testing a fresh package against non-A-Shell backgrounds and an automatic accent.' | Set-Content $log
function Run-Setup([string]$Location,[string]$Action,[switch]$Core) {
 $extra=if($Core){' -Core'}else{''}
 $p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $Location 'scripts\Setup.ps1')+'" -Action '+$Action+$extra) -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $folder 'out.txt') -RedirectStandardError (Join-Path $folder 'err.txt')
 Get-Content (Join-Path $folder 'out.txt'),(Join-Path $folder 'err.txt') | Out-File $log -Append -Encoding utf8
 if($p.ExitCode){throw "Setup $Action failed (exit $($p.ExitCode))."}
}
try {
 . (Join-Path $root 'scripts\Appearance.Helpers.ps1')
 . (Join-Path $root 'scripts\Setup.Support.ps1')
 Set-DesktopImage "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg"
 Set-LockImage "$env:SystemRoot\Web\Screen\img100.jpg"
 Write-RegistryValue @{Path='HKCU:\Control Panel\Desktop';Name='AutoColorization';Kind='DWord';Value=1;Exists=$true}
 Run-Setup $copy Apply -Core
 $baselinePath=Join-Path $copy 'state\baseline\checkpoint.clixml'
 $hash=(Get-FileHash $baselinePath).Hash
 $baseline=Import-Clixml $baselinePath
 if(($baseline.Values | Where-Object {$_.Name -eq 'AutoColorization'}).Value -ne 1){throw 'Automatic accent was not captured before setup.'}
 Run-Setup $copy Apply -Core
 if((Get-FileHash $baselinePath).Hash -ne $hash){throw 'Repeat setup replaced the original baseline.'}
 Run-Setup $copy Restore
 foreach($value in $baseline.Values) {
  $actual=Read-RegistryValue $value.Path $value.Name
  if($actual.Exists -ne $value.Exists -or ($value.Exists -and ($actual.Kind -ne $value.Kind -or [string]$actual.Value -ne [string]$value.Value))){throw "Restore mismatch: $($value.Path) / $($value.Name)"}
 }
 foreach($tree in $baseline.Trees){foreach($value in $tree.Values){$actual=Read-RegistryValue $value.Path $value.Name;if([string]$actual.Value -ne [string]$value.Value){throw 'Mod/cursor baseline mismatch.'}}}
 if((Get-ItemProperty 'HKCU:\Control Panel\Desktop').Wallpaper -ne $baseline.Wallpaper){throw 'Previous wallpaper path was not restored.'}
 Save-LockImage (Join-Path $folder 'restored-lock.img')
 if((Get-FileHash (Join-Path $folder 'restored-lock.img')).Hash -ne (Get-FileHash (Join-Path $copy 'state\baseline\lock.img')).Hash){throw 'Previous lock image was not restored exactly.'}
 $path=Read-RegistryValue 'HKCU:\Environment' 'Path'
 if([string]$path.Value -ne [string]$baseline.TerminalPath.Value){throw 'Terminal PATH did not return to its previous value.'}
 'PASS: fresh pre-change baseline, repeat install, exact appearance/accent/cursor/mod values, previous wallpaper/lock image and terminal PATH restored.' | Add-Content $log
} catch {('FAIL: '+$_) | Add-Content $log;exit 1}
finally {Run-Setup $root Apply}
