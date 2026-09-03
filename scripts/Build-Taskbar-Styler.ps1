param([string]$Windhawk='C:\Program Files\Windhawk')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$compiler=Join-Path $Windhawk 'Compiler\bin\clang++.exe'
$engine=Get-ChildItem (Join-Path $Windhawk 'Engine') -Directory|Sort-Object {[version]$_.Name} -Descending|Select-Object -First 1
$library=Join-Path $engine.FullName '64\windhawk.lib'
$output=Join-Path $root 'assets\windhawk\windows-11-taskbar-styler_1.9_ashell_identity1.dll'
& $compiler -target x86_64-w64-mingw32 -std=c++23 -O2 -shared -static -DUNICODE -D_UNICODE -DWH_MOD -include (Join-Path $root 'src\taskbar-build.h') -include windhawk_api.h (Join-Path $root 'assets\windhawk\windows-11-taskbar-styler.wh.cpp') $library -lcomctl32 -lgdi32 -lole32 -loleaut32 -lruntimeobject -lshlwapi '-Wl,--export-all-symbols' -o $output
if($LASTEXITCODE){throw 'Taskbar styler compilation failed.'}
Write-Output '[OK] Taskbar identity fix compiled.'
