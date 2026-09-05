param([string]$Output,[switch]$SkipBuild)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'VERSION must contain a semantic product version such as 1.9.7.'}
$buildId=(Get-Content -LiteralPath (Join-Path $projectRoot 'assets\build-id.txt') -Raw).Trim()
if([string]::IsNullOrWhiteSpace($buildId)){throw 'Missing build ID in assets\build-id.txt.'}
# Do not spend time compiling native helpers or produce an installer payload that
# Windows PowerShell 5.1 cannot parse. This is the same parser used by Setup.
$scriptFiles=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts') -Filter '*.ps1' -File)
$syntaxProblems=New-Object System.Collections.Generic.List[string]
foreach($scriptFile in $scriptFiles) {
 $tokens=$null
 $parseErrors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseErrors)
 foreach($parseError in @($parseErrors)) {
  $syntaxProblems.Add(("{0}:{1}:{2}: {3}" -f $scriptFile.Name,$parseError.Extent.StartLineNumber,$parseError.Extent.StartColumnNumber,$parseError.Message))
 }
}
if($syntaxProblems.Count -gt 0){throw ("PowerShell syntax check failed before packaging:`n - "+($syntaxProblems -join "`n - "))}
Write-Output ('[OK] PowerShell syntax preflight passed for '+$scriptFiles.Count+' scripts.')
if(!$SkipBuild){& (Join-Path $PSScriptRoot 'Build.ps1')}
if(!$Output){$Output=Join-Path (Split-Path $projectRoot) 'A-Shell.zip'}
$outPath=[IO.Path]::GetFullPath($Output)
if($outPath.StartsWith($projectRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Write the release ZIP outside the project folder.'}
$files=@(Get-ChildItem -LiteralPath $projectRoot -File -Recurse | Where-Object {
 $relative=$_.FullName.Substring($projectRoot.Length+1)
 $relative -notmatch '^(state|backup|\.git|\.codex|outputs)\\' -and $_.Extension -notin @('.log','.zip') -and $relative -ne 'assets\package-manifest.json'
})
$entries=@(foreach($file in $files){@{path=$file.FullName.Substring($projectRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName).Hash}})
$manifestJson=(@{version=$version;files=$entries} | ConvertTo-Json -Depth 5).Replace("`r`n","`n")+"`n"
[IO.File]::WriteAllText((Join-Path $projectRoot 'assets\package-manifest.json'),$manifestJson,[Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipStream=[IO.File]::Open($outPath,[IO.FileMode]::Create)
$archive=New-Object IO.Compression.ZipArchive($zipStream,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($file in @($files)+@(Get-Item (Join-Path $projectRoot 'assets\package-manifest.json'))) {
  $relative=$file.FullName.Substring($projectRoot.Length+1).Replace('\','/')
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,('A-Shell/'+$relative),[IO.Compression.CompressionLevel]::Optimal)
 }
} finally {$archive.Dispose();$zipStream.Dispose()}
Write-Output "Created $outPath with $($files.Count+1) files. Personal state and logs excluded."
