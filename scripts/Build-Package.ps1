param([string]$Output)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
if(!$Output){$Output=Join-Path (Split-Path $projectRoot) 'A-Shell.zip'}
$outPath=[IO.Path]::GetFullPath($Output)
if($outPath.StartsWith($projectRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Write the release ZIP outside the project folder.'}
$files=@(Get-ChildItem -LiteralPath $projectRoot -File -Recurse | Where-Object {
 $relative=$_.FullName.Substring($projectRoot.Length+1)
 $relative -notmatch '^(state|backup|\.git|\.codex|outputs)\\' -and $_.Extension -notin @('.log','.zip') -and $relative -ne 'assets\package-manifest.json'
})
$entries=@(foreach($file in $files){@{path=$file.FullName.Substring($projectRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName).Hash}})
@{version='1.0';files=$entries} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $projectRoot 'assets\package-manifest.json') -Encoding UTF8
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
