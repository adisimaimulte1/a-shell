param([string]$Windhawk='C:\Program Files\Windhawk')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$compiler=Join-Path $Windhawk 'Compiler\bin\clang++.exe'
$engine=Get-ChildItem (Join-Path $Windhawk 'Engine') -Directory | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
$library=Join-Path $engine.FullName '64\windhawk.lib'
& $compiler -target x86_64-w64-mingw32 -std=c++23 -O2 -shared -static -DUNICODE -D_UNICODE -DWH_MOD (Join-Path $root 'src\signin-clear-background.wh.cpp') $library -lruntimeobject -ladvapi32 -lole32 -loleaut32 '-Wl,--export-all-symbols' -o (Join-Path $root 'assets\windhawk\ashell-signin-clear-background_1.0.dll')
if($LASTEXITCODE){throw 'Sign-in backdrop mod compilation failed.'}
& $compiler -target x86_64-w64-mingw32 -std=c++23 -O2 -shared -static -DUNICODE -D_UNICODE -DWH_MOD -include windhawk_api.h (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp') $library -lcomctl32 -lole32 -loleaut32 -lruntimeobject -lversion '-Wl,--export-all-symbols' -o (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background_1.9.dll')
if($LASTEXITCODE){throw 'Lock/sign-in visual-tree mod compilation failed.'}
$screenSource=Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp'
$screenBinary=Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background_1.9.dll'
@{sourceSha256=(Get-FileHash -LiteralPath $screenSource -Algorithm SHA256).Hash;binarySha256=(Get-FileHash -LiteralPath $screenBinary -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.build.json') -Encoding UTF8
