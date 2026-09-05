param([string]$Windhawk='C:\Program Files\Windhawk')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$compiler=Join-Path $Windhawk 'Compiler\bin\clang++.exe'
$engine=Get-ChildItem (Join-Path $Windhawk 'Engine') -Directory | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
$library=Join-Path $engine.FullName '64\windhawk.lib'
function Write-BuildMetadata([string]$Path,[hashtable]$Data){
 $json=($Data | ConvertTo-Json).Replace("`r`n","`n")+"`n"
 [IO.File]::WriteAllText($Path,$json,[Text.UTF8Encoding]::new($false))
}

# LogonUI 45% backdrop hook. Release builds regenerate the DLL from the
# checked-in source and package matching source/binary provenance metadata.
$signInSource=Join-Path $root 'src\signin-clear-background.wh.cpp'
$signInDir=Join-Path $root 'assets\windhawk'
New-Item -ItemType Directory -Path $signInDir -Force | Out-Null
$signInBinary=Join-Path $signInDir 'ashell-signin-clear-background_1.0.dll'
& $compiler -target x86_64-w64-mingw32 -std=c++23 -O2 -shared -static -DUNICODE=1 -D_UNICODE=1 -DWH_MOD $signInSource $library -lruntimeobject -ladvapi32 -lole32 -loleaut32 '-Wl,--export-all-symbols' -o $signInBinary
if($LASTEXITCODE){throw 'Portable sign-in backdrop mod compilation failed.'}
Write-BuildMetadata (Join-Path $signInDir 'ashell-signin-clear-background_1.0.build.json') @{sourceSha256=(Get-FileHash -LiteralPath $signInSource -Algorithm SHA256).Hash;binarySha256=(Get-FileHash -LiteralPath $signInBinary -Algorithm SHA256).Hash}

# LockApp style engine with explicit selectors and a guarded LockApp-only fallback.
$screenSource=Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.wh.cpp'
$screenBinary=Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background_1.7.dll'
& $compiler -target x86_64-w64-mingw32 -std=c++23 -O2 -shared -static -DUNICODE=1 -D_UNICODE=1 -DWH_MOD -include windhawk_api.h $screenSource $library -lcomctl32 -lole32 -loleaut32 -lruntimeobject -lversion '-Wl,--export-all-symbols' -o $screenBinary
if($LASTEXITCODE){throw 'Lock-screen support mod compilation failed.'}
Write-BuildMetadata (Join-Path $root 'assets\windhawk\ashell-lockscreen-clear-background.build.json') @{sourceSha256=(Get-FileHash -LiteralPath $screenSource -Algorithm SHA256).Hash;binarySha256=(Get-FileHash -LiteralPath $screenBinary -Algorithm SHA256).Hash}
