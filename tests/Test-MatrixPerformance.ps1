param([string]$Compiler='C:\Program Files\Windhawk\Compiler\bin\clang++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$folder=Join-Path $root 'state\tests';New-Item -ItemType Directory -Path $folder -Force | Out-Null
$exe=Join-Path $folder 'MatrixBenchmark.exe'
& $Compiler -target x86_64-w64-mingw32 (Join-Path $PSScriptRoot 'MatrixBenchmark.cpp') -o $exe -std=c++17 -O2 -static -luser32 -lgdi32 -lwtsapi32 -ladvapi32 -lgdiplus -lole32 -luuid
if($LASTEXITCODE){throw 'Benchmark build failed.'}
& $exe
if($LASTEXITCODE){throw 'Benchmark failed.'}
