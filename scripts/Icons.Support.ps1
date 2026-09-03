function Test-AShellPinnedShortcuts {
 $folder=Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
 $shell=New-Object -ComObject WScript.Shell
 $broken=0
 try {
  foreach($file in Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue){
   $link=$shell.CreateShortcut($file.FullName)
   try {
    $target=[Environment]::ExpandEnvironmentVariables([string]$link.TargetPath)
    if($target -and [IO.Path]::IsPathRooted($target) -and $target.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase) -and !(Test-Path -LiteralPath $target)){
     $broken++;Write-Warning "Broken pinned shortcut '$($file.BaseName)': executable missing at $target. Re-pin the current app from Start; changing its icon cannot repair the launcher."
    }
   } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
  }
 } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
 if(!$broken){Write-Output '[OK] Pinned executable shortcuts point to existing files.'}
}
function Get-AShellIconPlan([string]$Root) {
 $base=Get-Content -LiteralPath (Join-Path $Root 'assets\taskbar-base.json') -Raw | ConvertFrom-Json
 $mapping=Get-Content -LiteralPath (Join-Path $Root 'assets\icon-map.json') -Raw | ConvertFrom-Json
 if($mapping.version -ne 1){throw 'Unsupported icon-map version.'}
 $desired=@{};$seen=@{};$assets=@{};$index=0
 foreach($p in $base.PSObject.Properties){$desired[$p.Name]=[string]$p.Value}
 foreach($app in $mapping.apps) {
  if(!$app.name -or !$app.icon -or !@($app.appIds).Count){throw 'Every icon mapping needs name, icon and appIds.'}
  if($app.icon -notmatch '^[a-zA-Z0-9_. -]+\.png$'){throw "Invalid icon filename: $($app.icon)"}
  $source=Join-Path $Root ('assets\icons\'+$app.icon)
  if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing icon: $($app.icon)"}
  if(!$assets.ContainsKey($app.icon)){
   # Hash each mapped asset once. Content-addressed paths invalidate XAML's
   # image cache only when bytes change; no Explorer restart/cache purge.
   $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
   $assets[$app.icon]=@{Source=$source;Path=(Join-Path $Root ('state\icons\'+$hash+'.png'));Hash=$hash}
  }
  foreach($id in $app.appIds) {
   if(!$id -or $id -match '[\[\]<>"\r\n,*?]' -or $id.Length -gt 1024){throw "Invalid exact app ID for $($app.name)"}
   if($seen.ContainsKey($id)){throw "Duplicate app ID: $id. Keep one explicit mapping."}
   $seen[$id]=$true
   $target='Taskbar.TaskListButton[AutomationProperties.AutomationId=Appid: '+$id+'] > '
   $desired["controlStyles[$index].target"]=$target+'Grid#IconPanel > Image#Icon, '+$target+'Taskbar.TaskListLabeledButtonPanel#IconPanel > Image#Icon'
   $desired["controlStyles[$index].styles[0]"]='Source='+$assets[$app.icon].Path
   $index++
  }
 }
 foreach($rule in $mapping.controls) {
  if(!$rule.target){throw 'Missing fixed-control target.'}
  $desired["controlStyles[$index].target"]=[string]$rule.target
  $style=[string]$rule.style
  foreach($match in [regex]::Matches($style,'\{\{ICONS\}\}\\([^"<>]+?\.png)')) {
   $name=$match.Groups[1].Value
   if($name -notmatch '^[a-zA-Z0-9_. -]+\.png$'){throw 'Invalid control icon filename.'}
   if(!$assets.ContainsKey($name)){
    $source=Join-Path $Root ('assets\icons\'+$name)
    $hash=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()
    $assets[$name]=@{Source=$source;Path=(Join-Path $Root ('state\icons\'+$hash+'.png'));Hash=$hash}
   }
   $replacement=$assets[$name].Path
   if($style.Contains('<Image')){$replacement=[Security.SecurityElement]::Escape($replacement)}
   $style=$style.Replace($match.Value,$replacement)
  }
  $desired["controlStyles[$index].styles[0]"]=$style;$index++
 }
 return @{Settings=$desired;Assets=$assets;AppIds=$seen}
}
function Align-AShellIconSlots($Desired,$Current) {
 $result=@{};$existing=@{};$rules=@();$used=@{}
 foreach($name in $Current.Keys){if($name -match '^controlStyles\[(\d+)\]\.target$'){$existing[[string]$Current[$name]]=[int]$Matches[1]}}
 foreach($name in $Desired.Keys){
  if($name -notmatch '^controlStyles\['){$result[$name]=$Desired[$name]}
  elseif($name -match '^controlStyles\[(\d+)\]\.target$') {
   $oldIndex=[int]$Matches[1];$target=$Desired[$name];$slot=-1
   if($existing.ContainsKey($target)){$slot=$existing[$target];$used[$slot]=$true}
   $rules+=@{Target=$target;Style=$Desired["controlStyles[$oldIndex].styles[0]"];Slot=$slot;Order=$oldIndex}
  }
 }
 foreach($rule in $rules | Sort-Object Order){
  if($rule.Slot -lt 0){$slot=0;while($used.ContainsKey($slot)){$slot++};$rule.Slot=$slot;$used[$slot]=$true}
  $result["controlStyles[$($rule.Slot)].target"]=$rule.Target
  $result["controlStyles[$($rule.Slot)].styles[0]"]=$rule.Style
 }
 # Windhawk reads contiguous indices. Keep harmless placeholders for holes;
 # new mappings reuse them, and removing a tail trims it completely.
 if($used.Count){$last=($used.Keys | Measure-Object -Maximum).Maximum;for($i=0;$i -le $last;$i++){
  if(!$used.ContainsKey($i)){$result["controlStyles[$i].target"]='// A-Shell unused icon slot';$result["controlStyles[$i].styles[0]"]='Opacity=1'}
 }}
 return $result
}
function Get-AShellIconDelta($Current,$Desired) {
 $set=@{};$remove=@()
 foreach($name in $Desired.Keys){if(!$Current.ContainsKey($name) -or [string]$Current[$name] -cne [string]$Desired[$name]){$set[$name]=$Desired[$name]}}
 # This mod configuration is owned by A-Shell after setup. Remove obsolete
 # generated rules only; leave unrelated mod options alone.
 foreach($name in $Current.Keys){if($name -match '^controlStyles\[\d+\]\.' -and !$Desired.ContainsKey($name)){$remove+=$name}}
 return @{Set=$set;Remove=$remove;Count=($set.Count+$remove.Count)}
}
function Update-AShellIcons([string]$Root) {
 $baseline=Join-Path $Root 'state\before-setup.clixml'
 if(!(Test-Path -LiteralPath $baseline)){throw 'Run Setup first so the original taskbar configuration is backed up.'}
 $before=Import-Clixml -LiteralPath $baseline
 if($before.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'The taskbar backup belongs to another account.'}
 $plan=Get-AShellIconPlan $Root
 $mod='HKLM:\SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler'
 if(!(Test-Path -LiteralPath $mod) -or (Get-ItemProperty $mod).Disabled -ne 0){throw 'Taskbar icon refresh requires the active Windows 11 Taskbar Styler installed by full Setup.'}
 $key=$mod+'\Settings';$current=@{}
 if(Test-Path -LiteralPath $key){$reg=Get-Item -LiteralPath $key;foreach($name in $reg.GetValueNames()){$current[$name]=$reg.GetValue($name)}}
 $plan.Settings=Align-AShellIconSlots $plan.Settings $current
 $delta=Get-AShellIconDelta $current $plan.Settings
 New-Item -ItemType Directory -Path (Join-Path $Root 'state\icons') -Force | Out-Null
 $copied=0
 foreach($asset in $plan.Assets.Values){
  if(!(Test-Path -LiteralPath $asset.Path) -or (Get-FileHash -LiteralPath $asset.Path).Hash -ne $asset.Hash){Copy-Item -LiteralPath $asset.Source -Destination $asset.Path -Force;$copied++}
 }
 $pending=Join-Path $Root 'state\icons-refresh.pending'
 if($delta.Count -or $copied){[IO.File]::WriteAllText($pending,'Refresh required')}
 if($delta.Count){
  try {
   foreach($name in $delta.Set.Keys){Write-RegistryValue @{Path=$key;Name=$name;Value=$delta.Set[$name];Kind='String';Exists=$true}}
   foreach($name in $delta.Remove){Write-RegistryValue @{Path=$key;Name=$name;Exists=$false}}
  } catch {
   foreach($name in @($delta.Set.Keys)+@($delta.Remove)){
    Write-RegistryValue @{Path=$key;Name=$name;Value=$current[$name];Kind='String';Exists=$current.ContainsKey($name)}
   }
   throw
  }
 }
 if(Test-Path -LiteralPath $pending){
  $stamp=Read-RegistryValue $mod 'SettingsChangeTime'
  $next=[uint32]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
  if($stamp.Exists -and [uint32]$stamp.Value -ge $next){$next=[uint32]$stamp.Value+1}
  Write-RegistryValue @{Path=$mod;Name='SettingsChangeTime';Kind='DWord';Value=$next;Exists=$true}
  Remove-Item -LiteralPath $pending
 }
 Write-Output "Icon refresh: $($delta.Count) settings changed; $copied image files updated."
}
