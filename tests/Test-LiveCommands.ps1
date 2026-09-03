param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if(!$Worker){$p=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker') -Wait -PassThru;exit $p.ExitCode}
$log=Join-Path $root 'state\live-commands-test.txt'
Start-Transcript -Path $log -Force | Out-Null
function Run([string[]]$Command){
 $output=& (Join-Path $root 'ashell.cmd') @Command 2>&1
 $code=$LASTEXITCODE;Write-Output ($output -join "`n")
 if($code){throw "Command failed: $($Command -join ' ') (exit $code)"}
 if(!$output){throw 'Command returned no feedback.'}
}
try {
 . (Join-Path $root 'scripts\Appearance.Helpers.ps1')
 Run @('help');Run @('check');Run @('rain','status')
 Run @('rain','stop');if(Get-Process MatrixDesktop -ErrorAction SilentlyContinue){throw 'Stop left a renderer running'}
 Run @('rain','start');$rendererId=(Get-Process MatrixDesktop).Id
 Run @('rain','start');if((Get-Process MatrixDesktop).Id -ne $rendererId){throw 'Repeated start restarted rain'}
 Run @('color','00AAFF')
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Read-Accent.ps1') -Expected 00AAFF
 if($LASTEXITCODE){throw 'Windows accent differs from requested color'}
 $image=Join-Path $root 'state\live-tests\bright-wallpaper.png'
 Run @('background',$image)
 $desktop=(Get-ItemProperty 'HKCU:\Control Panel\Desktop').Wallpaper
 if((Get-FileHash -LiteralPath $desktop).Hash -ne (Get-FileHash -LiteralPath $image).Hash){throw 'Desktop image mismatch'}
 $lock=Get-AShellLockSource
 if(!$lock -or (Get-FileHash -LiteralPath $lock).Hash -ne (Get-FileHash -LiteralPath $image).Hash){throw 'Lock image source mismatch'}
 if((Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableLogonBackgroundImage').Value -ne 0){throw 'Sign-in background disabled'}
 Run @('background','original')
 $desktop=(Get-ItemProperty 'HKCU:\Control Panel\Desktop').Wallpaper
 $expected=Join-Path $root 'state\desktop-before.img'
 if(Test-Path (Join-Path $root 'state\baseline\desktop.img')){$expected=Join-Path $root 'state\baseline\desktop.img'}
 if((Get-FileHash -LiteralPath $desktop).Hash -ne (Get-FileHash -LiteralPath $expected).Hash){throw 'Original wallpaper was not restored'}
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Read-Accent.ps1') -Expected 00AAFF
 if($LASTEXITCODE -or (Get-Process MatrixDesktop).Id -ne $rendererId){throw 'Background commands changed accent or restarted rain'}
 Run @('background','default');Run @('color','default')
 Run @('icons','check');Run @('icons','list');Run @('icons','refresh')
 $key='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
 $stamp=(Get-ItemProperty $key).SettingsChangeTime
 Run @('icons','refresh')
 if((Get-ItemProperty $key).SettingsChangeTime -ne $stamp){throw 'Unchanged icon refresh reloaded settings'}
 Run @('startup','remove');if(Get-ScheduledTask -TaskName 'Matrix Desktop - Instant Rain' -ErrorAction SilentlyContinue){throw 'Startup task survived removal'}
 Run @('startup','install');Run @('rain','status')
 Write-Output 'PASS: help/check/status, stop/start/idempotent start, live accent, custom/original/default backgrounds, unchanged renderer and accent, icon validation/list/no-op refresh, startup removal/reinstall.'
} catch {Write-Output ('FAIL: '+$_);exit 1}
finally {Stop-Transcript | Out-Null}
