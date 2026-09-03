param([string]$Compiler='C:\Program Files\Windhawk\Compiler\bin\clang++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if(!(Test-Path $Compiler)){throw 'Pass -Compiler with the path to an LLVM-MinGW clang++.exe compiler.'}
if(Get-Process MatrixDesktop -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $root 'bin\MatrixDesktop.exe')}){throw 'Run Stop.cmd before rebuilding this copy.'}
& $Compiler -target x86_64-w64-mingw32 (Join-Path $root 'src\MatrixDesktop.cpp') -o (Join-Path $root 'bin\MatrixDesktop.exe') -std=c++17 -O2 -municode -mwindows -static -luser32 -lgdi32 -lwtsapi32 -ladvapi32 -lgdiplus -lole32 -luuid
if($LASTEXITCODE -ne 0){throw 'Build failed.'}
& (Join-Path $PSScriptRoot 'Embed-Manifest.ps1')
& $Compiler -target x86_64-w64-mingw32 (Join-Path $root 'src\DesktopLayout.cpp') -o (Join-Path $root 'bin\DesktopLayout.exe') -std=c++17 -O2 -municode -static -lole32 -loleaut32 -luuid -lshell32 -lshlwapi
if($LASTEXITCODE -ne 0){throw 'Desktop layout helper build failed.'}
& (Join-Path $PSScriptRoot 'Build-Branding.ps1')
