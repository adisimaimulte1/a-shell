$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$cli=Get-Content (Join-Path $root 'scripts\CLI.ps1') -Raw
foreach($token in @("'screen'","'taskbar'","'background'")){if(!$cli.Contains($token)){throw "Missing canonical CLI command: $token"}}
if($cli -match "'desktop'|desktop hide|desktop keep"){throw 'Desktop visibility switch should not exist anymore.'}
$runtime=Get-Content (Join-Path $root 'scripts\Runtime.ps1') -Raw
if($runtime -notmatch 'Hide-AShellDesktopIconsNow'){throw 'Runtime does not enforce the icon-free desktop.'}
$screen=Get-Content (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') -Raw
if(!$screen.Contains('// @include         LockApp.exe') -or $screen.Contains('// @include         LogonUI.exe')){throw 'Generic screen styling must remain LockApp-only.'}
$signin=Get-Content (Join-Path $root 'src\signin-clear-background.wh.cpp') -Raw
if(!$signin.Contains('// @include         LogonUI.exe')){throw 'Narrow verified sign-in module does not include LogonUI.'}
Write-Output '[OK] legacy runtime regression guards passed under the v1.9 icon-free desktop design.'
