param([string]$Output)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'VERSION must contain a semantic product version such as 1.9.7.'}
$buildId=(Get-Content -LiteralPath (Join-Path $root 'assets\build-id.txt') -Raw).Trim()
if([string]::IsNullOrWhiteSpace($buildId)){throw 'Missing build ID in assets\build-id.txt.'}
$installerSource=Get-Content -LiteralPath (Join-Path $root 'src\Installer.cs') -Raw
if($installerSource -notmatch '__ASHELL_VERSION__' -or $installerSource -notmatch '__ASHELL_BUILD_ID__'){throw 'Installer.cs is missing generated version/build placeholders.'}
if(!$Output){$Output=Join-Path (Split-Path $root) ('A-Shell-Setup-'+$version+'.exe')}
$Output=[IO.Path]::GetFullPath($Output)
if($Output.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Build the installer outside the source folder.'}
$build=Join-Path $root ('state\installer-build\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $build -Force|Out-Null
$zip=Join-Path ([IO.Path]::GetTempPath()) ('AShell-payload-'+[guid]::NewGuid().ToString('N')+'.zip')
$monochromeIcon=Join-Path $root 'assets\icons\icons-a-shell-96.png'
if(!(Test-Path -LiteralPath $monochromeIcon -PathType Leaf)){throw 'Missing monochrome A-Shell Setup icon: assets\icons\icons-a-shell-96.png'}
$normalIcon=Join-Path $root 'assets\logo\A-Shell_Logo_Original_HQ.png'
if(!(Test-Path -LiteralPath $normalIcon -PathType Leaf)){throw 'Missing HQ A-Shell Setup logo: assets\logo\A-Shell_Logo_Original_HQ.png'}
try {
 & "$PSScriptRoot\Build-Package.ps1" -Output $zip
 $hash=(Get-FileHash -LiteralPath $zip).Hash
 $source=[IO.File]::ReadAllText((Join-Path $root 'src\Installer.cs')).Replace('__PAYLOAD_SHA256__',$hash).Replace('__ASHELL_VERSION__',$version).Replace('__ASHELL_ASSEMBLY_VERSION__',($version+'.0')).Replace('__ASHELL_BUILD_ID__',$buildId)
 $generated=Join-Path $build 'Installer.cs'
 [IO.File]::WriteAllText($generated,$source,[Text.UTF8Encoding]::new($false))
 $framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
 $compiler=Join-Path $framework 'csc.exe'
 & $compiler /nologo /target:exe /platform:x64 /optimize+ "/out:$Output" "/win32icon:$root\assets\logo\A-Shell.ico" "/resource:$zip,AShell.Payload.zip" "/resource:$monochromeIcon,AShell.Monochrome.png" "/resource:$normalIcon,AShell.Normal.png" "/reference:$framework\System.Drawing.dll" "/reference:$framework\System.IO.Compression.dll" "/reference:$framework\System.IO.Compression.FileSystem.dll" "/reference:$framework\System.Web.Extensions.dll" $generated
 if($LASTEXITCODE){throw 'Installer compilation failed.'}
 Set-Content -LiteralPath ($Output+'.sha256') -Encoding ASCII -Value (((Get-FileHash -LiteralPath $Output).Hash)+'  '+[IO.Path]::GetFileName($Output))
 Write-Output "[OK] Single-file installer built: $Output"
} finally {if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip}}
