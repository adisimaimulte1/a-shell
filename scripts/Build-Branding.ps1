$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'VERSION must contain a semantic product version such as 1.9.7.'}
$assemblyVersion=$version+'.0'
Add-Type -Path (Join-Path $PSScriptRoot 'Branding.Helpers.cs') -ReferencedAssemblies System.Drawing

# Always build the normal/orange executable icon from the high-resolution logo.
# The old 96x96 source had to be upscaled for the 128px and 256px ICO entries,
# which made the Setup/taskbar icon visibly soft on high-DPI Windows displays.
$logo=Join-Path $root 'assets\logo\A-Shell_Logo_Original_HQ.png'
$ico=Join-Path $root 'assets\logo\A-Shell.ico'
if(!(Test-Path -LiteralPath $logo -PathType Leaf)){throw 'Missing HQ A-Shell logo: assets\logo\A-Shell_Logo_Original_HQ.png'}

[AShellBranding]::Apply((Join-Path $root 'bin\MatrixDesktop.exe'),$logo,$ico,'A-Shell Matrix Rain',$assemblyVersion)
[AShellBranding]::Apply((Join-Path $root 'bin\DesktopLayout.exe'),$logo,$ico,'A-Shell Desktop Layout',$assemblyVersion)
Write-Output '[OK] High-resolution A-Shell icons and file descriptions embedded in both executables.'
