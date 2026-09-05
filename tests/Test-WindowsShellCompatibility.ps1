$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$setup=Get-Content (Join-Path $root 'scripts\Setup.ps1') -Raw
if($setup -match "'TaskbarDa','DWord'"){throw 'Fresh setup must not write the UCPD-protected TaskbarDa preference.'}
$map=Get-Content (Join-Path $root 'assets\icon-map.json') -Raw | ConvertFrom-Json
$widgets=@($map.controls | Where-Object {$_.target -match 'AugmentedEntryPointButton' -and $_.target -match 'WidgetsButton' -and $_.style -eq 'Visibility=Collapsed'})
if($widgets.Count -ne 1){throw 'Exactly one version-tolerant WidgetsButton collapse rule is required.'}
$signIn=Get-Content (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
if($signIn -notmatch 'Include=\$lockTarget;Exclude='''''){throw 'LockApp support must remain LockApp-only.'}
if($signIn -notmatch 'Include=\$target;Exclude='''''){throw 'Dedicated narrow sign-in hook must target LogonUI.'}
$native=Get-Content (Join-Path $root 'src\signin-clear-background.wh.cpp') -Raw
if($native -notmatch '0x94140' -or $native -notmatch '0x64970' -or $native -notmatch 'ZoomHookInstalled' -or $native -notmatch '0x170' -or $native -notmatch '0.45'){throw 'Narrow verified LogonUI backdrop/framing hooks are missing.'}
$cursors=Get-Content (Join-Path $root 'scripts\Cursors.ps1') -Raw
if($cursors -notmatch '\[void\]\(Set-AShellCursorSession -Strict\)'){throw 'Cursor strict success must not leak a Boolean to installer output.'}
Write-Output 'Windows shell compatibility regression checks passed.'
