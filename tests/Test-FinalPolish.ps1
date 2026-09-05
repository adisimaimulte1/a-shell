$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$cli=Get-Content -LiteralPath (Join-Path $root 'scripts\CLI.ps1') -Raw
$console=Get-Content -LiteralPath (Join-Path $root 'scripts\Console.Helpers.ps1') -Raw
$features=Get-Content -LiteralPath (Join-Path $root 'scripts\Features.Support.ps1') -Raw
$setupSupport=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.Support.ps1') -Raw
$setup=Get-Content -LiteralPath (Join-Path $root 'scripts\Setup.ps1') -Raw
$installer=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
$build=Get-Content -LiteralPath (Join-Path $root 'scripts\Build-Installer.ps1') -Raw
$desktop=Get-Content -LiteralPath (Join-Path $root 'scripts\Desktop.Support.ps1') -Raw
$uninstall=Get-Content -LiteralPath (Join-Path $root 'scripts\Uninstall.ps1') -Raw
$signin=Get-Content -LiteralPath (Join-Path $root 'scripts\SignIn-Backdrop.ps1') -Raw

$help=[regex]::Match($cli,"(?s)'help' \{.*?default \{throw 'Unknown command").Value
if(!$help){throw 'Could not locate CLI help block.'}
if($help -notmatch 'ashell background' -or $help -match 'ashell bg'){throw 'Help must advertise the full background command, not bg.'}
if($help -notmatch 'ashell lockscreen on \| off' -or $help -match 'ashell locscreen'){throw 'Help must advertise lockscreen, not the old locscreen typo.'}
if($help -notmatch 'ashell rain on \| off \| status' -or $help -match 'rain start|rain stop'){throw 'Help must advertise rain on/off/status.'}
if($help -match 'startup install|ashell component'){throw 'Internal/legacy command surface leaked into normal help.'}
if($console -notmatch '214;90;0' -or $console -notmatch 'Write-AShellCommand' -or $console -notmatch "'WORKING'"){throw 'Concise orange-accent console formatter is missing.'}
$runtime=Get-Content -LiteralPath (Join-Path $root 'scripts\Runtime.ps1') -Raw
if($runtime -match '\[FAREWELL\]|A-Shell has left the desktop\.' -or $runtime -notmatch 'A-Shell stopped\. Original Windows appearance restored\.') {throw 'ashell stop must not show the uninstall farewell.'}
$uninstall=Get-Content (Join-Path $root 'scripts\Uninstall.ps1') -Raw
if($uninstall -notmatch 'function Write-AShellFarewell' -or $uninstall -notmatch 'A-Shell has left the desktop\.') {throw 'Uninstall farewell message is missing.'}

if($features -notmatch "DisableAcrylicBackgroundOnLogon','DWord',1"){throw 'Screen-on does not apply the Windows clear-logon policy DisableAcrylicBackgroundOnLogon=1.'}
if($features -notmatch "SignIn-Backdrop.ps1'\) -Action Apply -NoRestart -RuntimeOnly"){throw 'Windows 10/11 runtime screen-on no longer applies the narrow LogonUI backdrop hook.'}
if($setup -notmatch "DisableAcrylicBackgroundOnLogon','DWord',1"){throw 'Fresh Setup does not apply DisableAcrylicBackgroundOnLogon=1.'}
if($signin -notmatch 'Include=\$lockTarget;Exclude='''''){throw 'Generic lock-screen module must remain LockApp-only.'}
if($signin -notmatch 'Include=\$target;Exclude=''''' -or $signin -notmatch 'Get-AShellSignInPayloadInfo'){throw 'Portable LogonUI backdrop hook is not installed independently.'}
if($setupSupport -match 'configured for both LockApp and LogonUI'){throw 'STEP 8 still contains the obsolete both-process verifier.'}
if($installer -notmatch 'ReassertConfiguredSetupIcon' -or $installer -notmatch 'A-Shell Setup icon'){throw 'Setup icon is not reasserted after late console-host initialization.'}

if($installer -notmatch 'RelaunchInClassicConsole' -or $installer -notmatch 'ForceNoHandoff' -or $installer -notmatch 'IsWindowVisible'){throw 'Interactive Setup is not forced into an icon-owning classic console when Terminal delegation is active.'}
if($installer -notmatch 'AShell\.Normal\.png' -or $installer -notmatch 'AShell\.Monochrome\.png'){throw 'Setup cannot switch between HQ normal and monochrome live icons.'}
if($build -notmatch 'A-Shell_Logo_Original_HQ\.png' -or $build -notmatch 'AShell\.Normal\.png'){throw 'HQ normal Setup logo is not embedded by Build-Installer.'}

foreach($token in @('Restore-AShellLegacyDesktopArchive','Get-ChildItem -LiteralPath $Source -Force','Move-AShellLegacyDesktopTree','restored by A-Shell')){if($desktop -notmatch [regex]::Escape($token)){throw "Desktop exhaustive restore is missing: $token"}}
if($desktop -notmatch 'Remove-Item -LiteralPath \$full'){throw 'original_desktop is not removed after successful recovery.'}
if($uninstall -notmatch 'Test-AShellRuntimeActive' -or $uninstall -notmatch 'already stopped; appearance restore is already complete'){throw 'Uninstall does not fast-skip the full appearance restore when already stopped.'}
if($uninstall -notmatch 'Restore-AShellLegacyDesktopArchive'){throw 'Uninstall does not always check/recover legacy original_desktop content.'}

Write-Output '[OK] Final polish: canonical CLI, concise accent output, supported clear-logon policy, deterministic Setup branding and exhaustive Desktop uninstall recovery are present.'

if($uninstall -notmatch "Write-AShellAccent '.+' -NoNewline") {throw 'Uninstall farewell text is not continuing on the final heart line.'}
