param([string]$Output)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if(!$Output){$Output=Join-Path (Split-Path $root) 'A-Shell-Setup-1.9.3.exe'}
$Output=[IO.Path]::GetFullPath($Output)
if($Output.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Build the installer outside the source folder.'}
$build=Join-Path $root ('state\installer-build\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $build -Force|Out-Null
$zip=Join-Path ([IO.Path]::GetTempPath()) ('AShell-payload-'+[guid]::NewGuid().ToString('N')+'.zip')
$monochromeIcon=Join-Path $root 'assets\icons\icons-a-shell-96.png'
if(!(Test-Path -LiteralPath $monochromeIcon -PathType Leaf)){throw 'Missing monochrome A-Shell Setup icon: assets\icons\icons-a-shell-96.png'}
try {
 & "$PSScriptRoot\Build-Package.ps1" -Output $zip
 $hash=(Get-FileHash -LiteralPath $zip).Hash
 $source=[IO.File]::ReadAllText((Join-Path $root 'src\Installer.cs')).Replace('__PAYLOAD_SHA256__',$hash)
 $generated=Join-Path $build 'Installer.cs'
 [IO.File]::WriteAllText($generated,$source,[Text.UTF8Encoding]::new($false))
 $framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
 $compiler=Join-Path $framework 'csc.exe'
 & $compiler /nologo /target:exe /platform:x64 /optimize+ "/out:$Output" "/win32icon:$root\assets\logo\A-Shell.ico" "/resource:$zip,AShell.Payload.zip" "/resource:$monochromeIcon,AShell.Monochrome.png" "/reference:$framework\System.Drawing.dll" "/reference:$framework\System.IO.Compression.dll" "/reference:$framework\System.IO.Compression.FileSystem.dll" "/reference:$framework\System.Web.Extensions.dll" $generated
 if($LASTEXITCODE){throw 'Installer compilation failed.'}
 Set-Content -LiteralPath ($Output+'.sha256') -Encoding ASCII -Value (((Get-FileHash -LiteralPath $Output).Hash)+'  '+[IO.Path]::GetFileName($Output))
 Write-Output "[OK] Single-file installer built: $Output"
} finally {if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip}}
