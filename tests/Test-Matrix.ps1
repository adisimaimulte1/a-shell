param([string]$Compiler='C:\Program Files\Windhawk\Compiler\bin\clang++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$testOutput=Join-Path $root 'state\tests'
New-Item -ItemType Directory $testOutput -Force | Out-Null
$binary=Join-Path $testOutput 'MatrixTests.exe'
& $Compiler -target x86_64-w64-mingw32 (Join-Path $PSScriptRoot 'MatrixTests.cpp') -o $binary -std=c++17 -O2 -static -luser32 -lgdi32 -lwtsapi32 -ladvapi32 -lgdiplus -lole32 -luuid
if($LASTEXITCODE){throw 'Matrix regression test build failed.'}
& (Join-Path $root 'scripts\Embed-Manifest.ps1') -File $binary
& $binary
if($LASTEXITCODE){throw 'Matrix regression test failed.'}
