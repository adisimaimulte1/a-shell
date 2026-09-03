function Get-AShellNameKey([string]$Name) {($Name.ToLowerInvariant() -replace '\+','plus' -replace '[^a-z0-9]','')}
function Get-AShellAppNameKey([string]$Name) {
 # Strip release metadata only at the end, never product numbers such as 3D.
 $clean=$Name.Trim() -replace '(?i)\s*\((?:x64|x86|64[- ]bit|32[- ]bit)\)$',''
 $clean=$clean -replace '(?i)\s+(?:20\d{2}|v?\d+\.\d+(?:\.\d+)*)(?:\s+(?:x64|x86))?$',''
 Get-AShellNameKey $clean
}
function Import-AShellIcon([string]$Root,[string]$Source,[string]$Name) {
 if(!$Source -or !(Test-Path -LiteralPath $Source -PathType Leaf)){throw 'Use: ashell icons add "C:\Downloads\icon.png" [name.png]'}
 $sourcePath=(Get-Item -LiteralPath $Source).FullName
 if(!$Name){$Name=[IO.Path]::GetFileName($sourcePath)}
 if($Name -notmatch '^[a-zA-Z0-9_. -]+\.png$'){throw 'Choose a simple PNG filename, for example illustrator.png.'}
 if((Get-Item -LiteralPath $sourcePath).Length -gt 16MB){throw 'Icon exceeds the 16 MB limit.'}
 Add-Type -AssemblyName System.Drawing
 $stream=[IO.File]::OpenRead($sourcePath)
 try {
  $signature=New-Object byte[] 8
  if($stream.Read($signature,0,8) -ne 8 -or [BitConverter]::ToString($signature) -ne '89-50-4E-47-0D-0A-1A-0A'){throw 'The source must be a valid PNG image.'}
  $stream.Position=0;$image=[Drawing.Image]::FromStream($stream,$true,$true)
  try {if($image.Width -gt 4096 -or $image.Height -gt 4096){throw 'Icon dimensions must not exceed 4096 x 4096.'}} finally {$image.Dispose()}
 } finally {$stream.Dispose()}
 $destination=Join-Path $Root ('assets\icons\'+$Name)
 if(Test-Path -LiteralPath $destination) {
  if((Get-FileHash -LiteralPath $sourcePath).Hash -ne (Get-FileHash -LiteralPath $destination).Hash){throw 'A different icon already has that name. Supply another destination filename.'}
  Write-Output "[OK] $Name is already in assets\icons."
 } else {[IO.File]::Copy($sourcePath,$destination,$false);Write-Output "[OK] Added $Name to assets\icons."}
 Write-Output ('[STATUS] Assign it: ashell icons set "App name" "'+$Name+'", or run ashell icons for automatic matching.')
}
function Save-AShellIconSelection([string]$Root,$Mapping) {
 $path=Join-Path $Root 'assets\icon-map.json'
 $old=[IO.File]::ReadAllText($path)
 $backup=Join-Path $Root 'state\icon-map-before-commands.json'
 if(!(Test-Path $backup)){[IO.File]::WriteAllText($backup,$old,[Text.UTF8Encoding]::new($false))}
 $temp=$path+'.tmp'
 try {
  [IO.File]::WriteAllText($temp,($Mapping|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
  [IO.File]::Replace($temp,$path,(Join-Path $Root 'state\icon-map-last.json'))
  $null=Get-AShellIconPlan $Root
 } catch {[IO.File]::WriteAllText($path,$old,[Text.UTF8Encoding]::new($false));throw}
}
function Set-AShellIconSelection([string]$Root,[string]$App,[string]$Icon) {
 $found=@(Get-StartApps | Where-Object {$_.Name -ieq $App -or $_.AppID -ieq $App})
 if($found.Count -ne 1){throw 'Use one exact app name from ashell icons list (or its AppID when names repeat).'}
 if($Icon -notmatch '^[a-zA-Z0-9_. -]+\.png$' -or !(Test-Path -LiteralPath (Join-Path $Root ('assets\icons\'+$Icon)))){throw 'Put the PNG in assets\icons, then pass its filename only.'}
 $path=Join-Path $Root 'assets\icon-map.json';$mapping=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 foreach($entry in $mapping.apps){$entry.appIds=@($entry.appIds|Where-Object {$_ -ine $found[0].AppID})}
 $mapping.apps=@($mapping.apps|Where-Object {@($_.appIds).Count})+@([pscustomobject]@{name=$found[0].Name;icon=$Icon;appIds=@($found[0].AppID)})
 Save-AShellIconSelection $Root $mapping
 Write-Output "[OK] Assigned $Icon to $($found[0].Name)."
}
function Get-AShellIconIdentity([string]$Name,[string]$AppID='') {
 $label=$Name -replace '[-_]',' '
 $key=Get-AShellNameKey $label
 $normalized=Get-AShellAppNameKey $label
 $publisher='';$product=$normalized
 # Only recognized publisher prefixes are optional, never arbitrary words.
 $vendors='microsoft|adobe|google|mozilla|autodesk|jetbrains|oracle|apple|videolan|openai|github|canonical|nvidia|lenovo|samsung|intel'
 if($label -match ('(?i)^('+ $vendors +')\s+(.+)$')) {
  $publisher=$Matches[1].ToLowerInvariant();$product=Get-AShellAppNameKey $Matches[2]
 } elseif($AppID -match '^(?i:Microsoft\.|MicrosoftWindows\.|MSTeams_)') {$publisher='microsoft'}
 elseif($AppID -match '(?i)(^Adobe\.|\\Adobe\\)') {$publisher='adobe'}
 [pscustomobject]@{Key=$key;Normalized=$normalized;Product=$product;Publisher=$publisher;Name=$Name}
}
function New-AShellIconIndex([string]$Root) {
 $index=@{Exact=@{};Normalized=@{};Product=@{}}
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $Root 'assets\icons') -Filter '*.png') {
  $identity=Get-AShellIconIdentity ($file.BaseName -replace '^icons8-','' -replace '-(?:16|24|32|48|64|96|100|128|256|512|1024)$','')
  $item=[pscustomobject]@{File=$file.Name;Identity=$identity}
  foreach($pair in @(@('Exact',$identity.Key),@('Normalized',$identity.Normalized),@('Product',$identity.Product))) {
   if(!$index[$pair[0]].ContainsKey($pair[1])){$index[$pair[0]][$pair[1]]=@()}
   $index[$pair[0]][$pair[1]]+=@($item)
  }
 }
 $index
}
function Find-AShellIcon($Index,$App,$Aliases) {
 $identity=Get-AShellIconIdentity $App.Name $App.AppID
 $queries=@(@('Exact',$identity.Key,'exact name'),@('Normalized',$identity.Normalized,'release-normalized name'))
 foreach($key in @($identity.Key,$identity.Normalized)) {
  if($Aliases.ContainsKey($key)){$queries+=,@('Normalized',$Aliases[$key],'known alias')}
 }
 $queries+=,@('Product',$identity.Product,'publisher/product identity')
 foreach($query in $queries) {
  $candidates=@($Index[$query[0]][$query[1]] | Where-Object {
   $_ -and (!$identity.Publisher -or !$_.Identity.Publisher -or $identity.Publisher -eq $_.Identity.Publisher)
  })
  if(!$candidates.Count){continue}
  if($candidates.Count -gt 1){return [pscustomobject]@{Icon=$null;Reason='ambiguous';Candidates=@($candidates.File)}}
  return [pscustomobject]@{Icon=$candidates[0].File;Reason=$query[2];Candidates=@()}
 }
 return [pscustomobject]@{Icon=$null;Reason='no matching product';Candidates=@()}
}
function Add-AShellAutomaticIcons([string]$Root) {
 $path=Join-Path $Root 'assets\icon-map.json';$mapping=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 $known=@{};foreach($entry in $mapping.apps){foreach($id in $entry.appIds){$known[$id]=$true}}
 $index=New-AShellIconIndex $Root
 $aliases=@{taskmanager='barchart';windowsterminal='terminal';googlechrome='chrome';microsoftedge='microsoftedge';visualstudiocode='visualstudiocode';mozillafirefox='firefox';adobeacrobat='adobeacrobatreader';windowsnotepad='textfile';notepad='textfile';androidstudio='androidos';fusion='360view';autodeskfusion='360view';discord='discordnew';codex='chatgpt'}
 $aliases.windowspowershell='powershell';$aliases.windowspowershellise='powershell';$aliases.powershellise='powershell'
 $aliases.commandprompt='terminal';$aliases.stickynotesnew='stickynotes'
 $aliases.gitbash='git';$aliases.gitcmd='git';$aliases.gitgui='git'
 $added=0
 foreach($app in Get-StartApps | Sort-Object Name) {
  if($known.ContainsKey($app.AppID)){continue}
  $match=Find-AShellIcon $index $app $aliases
  if(!$match.Icon){if($match.Reason -eq 'ambiguous'){Write-Output "[STATUS] Choose an icon for $($app.Name): $($match.Candidates -join ', '). Use ashell icons set."};continue}
  $icon=$match.Icon
  $mapping.apps+=@([pscustomobject]@{name=$app.Name;icon=$icon;appIds=@($app.AppID)})
  $known[$app.AppID]=$true;$added++;Write-Output "[OK] Matched $($app.Name) -> $icon ($($match.Reason))"
 }
 if($added){Save-AShellIconSelection $Root $mapping}
 Write-Output "[STATUS] $added new automatic matches. Existing choices preserved; ambiguous names left unchanged."
}
