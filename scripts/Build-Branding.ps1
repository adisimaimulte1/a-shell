$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -Path (Join-Path $PSScriptRoot 'Branding.Helpers.cs') -ReferencedAssemblies System.Drawing
$logo=Join-Path $root 'assets\logo\A-Shell_Logo_Original.png'
$ico=Join-Path $root 'assets\logo\A-Shell.ico'
[AShellBranding]::Apply((Join-Path $root 'bin\MatrixDesktop.exe'),$logo,$ico,'A-Shell Matrix Rain')
[AShellBranding]::Apply((Join-Path $root 'bin\DesktopLayout.exe'),$logo,$ico,'A-Shell Desktop Layout')
Write-Output '[OK] A-Shell icons and file descriptions embedded in both executables.'
