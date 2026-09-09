param([string]$Compiler='C:\Program Files\Windhawk\Compiler\bin\clang++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$output=Join-Path $root 'state\tests\SignInBrushTests.exe'
New-Item -ItemType Directory -Force (Split-Path $output) | Out-Null
& $Compiler -target x86_64-w64-mingw32 -std=c++23 -O2 -static -DUNICODE -D_UNICODE -DASHELL_TEST (Join-Path $root 'src\signin-clear-background.wh.cpp') -lruntimeobject -ladvapi32 -lole32 -loleaut32 -o $output
if($LASTEXITCODE){throw 'Sign-in target test compilation failed.'}
& $output
if($LASTEXITCODE){throw "Sign-in brush/Windows entry-point validation failed: $LASTEXITCODE"}
