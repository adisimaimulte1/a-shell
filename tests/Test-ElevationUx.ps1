$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$files=@('Runtime.ps1','Icons.ps1','Background.ps1','Manage.ps1','Profile-Picture.ps1','SignIn-Backdrop.ps1','Setup.ps1','Uninstall.ps1')
foreach($name in $files){
 $text=Get-Content -LiteralPath (Join-Path $root ('scripts\\'+$name)) -Raw
 if($text -match 'Start-Process\\s+powershell(?:\\.exe)?\\s+-Verb\\s+RunAs'){throw "$name still elevates PowerShell directly."}
}
$helper=Get-Content -LiteralPath (Join-Path $root 'scripts\\Elevation.Helpers.ps1') -Raw
if($helper -notmatch '\\$env:ComSpec' -or $helper -notmatch '-Verb RunAs'){throw 'Elevation helper must elevate Command Prompt.'}
$installer=Get-Content -LiteralPath (Join-Path $root 'src\\Installer.cs') -Raw
if($installer -notmatch 'RelaunchElevated' -or $installer -notmatch 'Verb="runas"'){throw 'Interactive Setup EXE must request elevation immediately.'}
Write-Output '[OK] User-facing elevation uses visible Administrator Command Prompt windows; interactive Setup self-elevates immediately.'
