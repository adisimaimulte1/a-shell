$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSCommandPath)

# Every packaged PowerShell script must parse before an installer can be built.
$problems=New-Object System.Collections.Generic.List[string]
foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File){
 $tokens=$null
 $errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 foreach($error in @($errors)){
  $problems.Add(("{0}:{1}:{2}: {3}" -f $file.Name,$error.Extent.StartLineNumber,$error.Extent.StartColumnNumber,$error.Message))
 }
}
if($problems.Count){throw ("PowerShell syntax errors:`n - "+($problems -join "`n - "))}

$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw

$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Canonical VERSION file is invalid.'}
if($installer -notmatch 'Version="__ASHELL_VERSION__"' -or $installer -notmatch 'BuildId="__ASHELL_BUILD_ID__"'){throw 'Installer source does not use generated version/build placeholders.'}
$packageBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Package.ps1') -Raw
$installerBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Installer.ps1') -Raw
if(!$packageBuild.Contains("Join-Path `$projectRoot 'VERSION'") -or !$packageBuild.Contains('@{version=$version')){throw 'Package build does not derive its product version from VERSION.'}
foreach($token in @('__ASHELL_VERSION__','__ASHELL_ASSEMBLY_VERSION__','__ASHELL_BUILD_ID__')){if($installerBuild -notmatch $token){throw "Installer build does not generate $token from canonical metadata."}}
$brandingBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Branding.ps1') -Raw
$brandingSource=Get-Content -LiteralPath (Join-Path $root 'scripts\Branding.Helpers.cs') -Raw
if(!$brandingBuild.Contains("Join-Path `$root 'VERSION'") -or $brandingSource -match '1\.9\.7'){throw 'Native executable branding does not derive its version from VERSION.'}
$signInBuild=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-SignIn-Backdrop.ps1') -Raw
if(!$signInBuild.Contains("Join-Path `$root 'assets\windhawk'") -or $signInBuild.Contains("Join-Path `$root 'state\compiled'")){throw 'Release build can compile the LogonUI DLL outside the packaged assets folder.'}

if($installer -notmatch 'ValidateStagedPowerShell\(staging\)'){
 throw 'Installer does not syntax-check the staged package before touching an installation.'
}
if($installer -notmatch 'StopExistingCursorGuard\(target\)'){
 throw 'Updater does not pause CursorSessionGuard.exe before replacing program files.'
}
if($installer -notmatch 'StartCursorGuardIfActive\(target\)'){
 throw 'Updater does not restore the cursor guard after a successful update/rollback.'
}
if($installer -notmatch 'RollbackUpgrade\(previousInstall,target\)'){
 throw 'Startup-task migration failure does not roll program files back.'
}

$cursors=Get-Content -LiteralPath (Join-Path $root 'scripts\Cursors.ps1') -Raw
if($cursors -notmatch 'if\(Test-AShellRuntimeActive \$cursorRoot\)\{Start-ScheduledTask -TaskName \$guardTaskName'){
 throw 'Cursor migration does not restart the windowless guard for an active A-Shell session.'
}


$setupSupport=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.Support.ps1') -Raw
$signin=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw
$uninstall=Get-Content -LiteralPath (Join-Path $root 'scripts\Uninstall.ps1') -Raw
if($setupSupport -notmatch 'Get-AShellLockScreenPayloadInfo' -or $setupSupport -notmatch 'Substring\(0,12\)' -or $setupSupport -notmatch 'content-addressed'){
 throw 'Lock/sign-in updates are not using a content-addressed Windhawk DLL filename.'
}
if($signin -notmatch 'KeepLibrary \$lockLibrary' -or $signin -notmatch 'clear-logon policy write could not be verified'){
 throw 'Lock/sign-in update cleanup or clear-logon policy verification is missing.'
}
if($uninstall -notmatch "ashell-lockscreen-clear-background_\*\.dll" -or $uninstall -notmatch "ashell-signin-clear-background_\*\.dll"){
 throw 'Uninstall does not clean content-addressed lock/sign-in Windhawk DLLs.'
}
if($installer -notmatch 'ReadInstalledManifestPaths' -or $installer -notmatch 'previouslyPackaged'){throw 'Updater cannot distinguish removed bundled icons from preserved custom icons.'}

Write-Output '[OK] Installer update safety and PowerShell syntax regression checks passed.'
