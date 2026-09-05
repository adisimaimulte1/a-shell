$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$files=@('Runtime.ps1','Icons.ps1','Background.ps1','Manage.ps1','Profile-Picture.ps1','SignIn-Backdrop.ps1','Setup.ps1','Uninstall.ps1')
foreach($name in $files){
 $text=Get-Content -LiteralPath (Join-Path $root ('scripts\'+$name)) -Raw
 if($text -match 'Start-Process\s+powershell(?:\.exe)?\s+-Verb\s+RunAs'){throw "$name bypasses the shared elevation helper."}
 if($text -match 'Opening an Administrator Command Prompt'){throw "$name still promises a second visible administrator terminal."}
}
$helper=Get-Content -LiteralPath (Join-Path $root 'scripts\Elevation.Helpers.ps1') -Raw
if($helper -match '\$env:ComSpec'){throw 'Elevation helper still launches a second Command Prompt.'}
if($helper -notmatch '-Verb RunAs' -or $helper -notmatch '-WindowStyle Hidden'){throw 'Elevation helper must request UAC with a hidden worker.'}
if($helper -notmatch 'A-Shell-Elevation-' -or $helper -notmatch 'Show-AShellElevatedOutput'){throw 'Elevated progress is not streamed back to the invoking terminal.'}
if($helper -notmatch 'while\(!\$p\.HasExited\)'){throw 'The invoking terminal does not wait for the real elevated worker to finish.'}
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
if($installer -notmatch 'RelaunchElevated' -or $installer -notmatch 'Verb="runas"'){throw 'Interactive Setup EXE must still request elevation before protected installation work.'}
$handoff=[regex]::Match($installer,'(?s)static int RelaunchElevated.*?static void InitColor').Value
if($handoff -match 'WaitForExit'){throw 'The non-elevated Setup launcher still stays open beside the elevated Setup window.'}
Write-Output '[OK] Runtime elevation keeps one visible terminal, and Setup hands off to its elevated window without leaving the launcher open.'
