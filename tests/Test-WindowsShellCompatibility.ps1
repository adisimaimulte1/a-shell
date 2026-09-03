$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$setup=Get-Content (Join-Path $root 'scripts\Setup.ps1') -Raw
if($setup -match "'TaskbarDa','DWord'"){throw 'Fresh setup must not write the UCPD-protected TaskbarDa preference.'}
$map=Get-Content (Join-Path $root 'assets\icon-map.json') -Raw | ConvertFrom-Json
$widgets=@($map.controls | Where-Object {$_.target -match 'AugmentedEntryPointButton' -and $_.target -match 'WidgetsButton' -and $_.style -eq 'Visibility=Collapsed'})
if($widgets.Count -ne 1){throw 'Exactly one version-tolerant WidgetsButton collapse rule is required.'}
$signIn=Get-Content (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
if(!$signIn.Contains("Include=(`$lockTarget+'|'+`$target)")){throw 'Visual-tree screen mod must target both LockApp and LogonUI.'}
$visual=Get-Content (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') -Raw
if($visual -notmatch '@include\s+LogonUI\.exe' -or $visual -notmatch 'LogonUI\.exe'){throw 'Visual-tree mod source must allow LogonUI.exe.'}
$cursors=Get-Content (Join-Path $root 'scripts\Cursors.ps1') -Raw
if($cursors -notmatch '\[void\]\(Set-AShellCursorSession -Strict\)'){throw 'Cursor strict success must not leak a Boolean to installer output.'}
Write-Output 'Windows shell compatibility regression checks passed.'
