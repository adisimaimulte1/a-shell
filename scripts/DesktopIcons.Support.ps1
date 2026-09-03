$ErrorActionPreference='Stop'

function Get-AShellDesktopIconStatePath([string]$Root) { Join-Path $Root 'state\desktop-monochrome-before.clixml' }
function Get-AShellDesktopIconCachePath([string]$Root) { Join-Path $Root 'state\desktop-icons' }

function Convert-AShellPngToIco([string]$Source,[string]$Destination) {
 if(!(Test-Path -LiteralPath $Source -PathType Leaf)){throw "Desktop icon source is missing: $Source"}
 Add-Type -AssemblyName System.Drawing
 $raw=[IO.File]::ReadAllBytes($Source)
 $input=[IO.MemoryStream]::new($raw,$false)
 try {
  $sourceImage=[Drawing.Image]::FromStream($input,$true,$true)
  try {
   if($sourceImage.Width -lt 1 -or $sourceImage.Height -lt 1 -or $sourceImage.Width -gt 4096 -or $sourceImage.Height -gt 4096){throw 'Desktop monochrome icon dimensions must be between 1 and 4096 pixels per side.'}
   if($sourceImage.Width -le 256 -and $sourceImage.Height -le 256){$png=$raw;$width=$sourceImage.Width;$height=$sourceImage.Height}
   else {
    $scale=[Math]::Min(256.0/$sourceImage.Width,256.0/$sourceImage.Height)
    $width=[Math]::Max(1,[int][Math]::Round($sourceImage.Width*$scale));$height=[Math]::Max(1,[int][Math]::Round($sourceImage.Height*$scale))
    $bitmap=[Drawing.Bitmap]::new($width,$height,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
     $graphics=[Drawing.Graphics]::FromImage($bitmap)
     try {$graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic;$graphics.DrawImage($sourceImage,0,0,$width,$height)} finally {$graphics.Dispose()}
     $encoded=[IO.MemoryStream]::new()
     try {$bitmap.Save($encoded,[Drawing.Imaging.ImageFormat]::Png);$png=$encoded.ToArray()} finally {$encoded.Dispose()}
    } finally {$bitmap.Dispose()}
   }
  } finally {$sourceImage.Dispose()}
 } finally {$input.Dispose()}
 $iconWidth=if($width -eq 256){[byte]0}else{[byte]$width};$iconHeight=if($height -eq 256){[byte]0}else{[byte]$height}
 New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
 $output=[IO.File]::Open($Destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $writer=[IO.BinaryWriter]::new($output)
 try {
  $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1)
  $writer.Write($iconWidth);$writer.Write($iconHeight);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32)
  $writer.Write([uint32]$png.Length);$writer.Write([uint32]22);$writer.Write($png)
 } finally {$writer.Dispose()}
}

function Get-AShellDesktopIco([string]$Root,[string]$PngName) {
 if($PngName -notmatch '^[a-zA-Z0-9_. -]+\.png$'){throw "Invalid desktop icon asset: $PngName"}
 $source=Join-Path $Root ('assets\icons\'+$PngName)
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Desktop icon asset is missing: $PngName"}
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $destination=Join-Path (Get-AShellDesktopIconCachePath $Root) ($hash+'.ico')
 if(!(Test-Path -LiteralPath $destination)){Convert-AShellPngToIco $source $destination}
 return $destination
}

function Get-AShellDesktopShortcutFiles {
 $folders=@([Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory),[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDesktopDirectory)) | Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Select-Object -Unique
 foreach($folder in $folders){Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue}
}

function Resolve-AShellDesktopShortcutIcon([string]$Root,$Index,$Aliases,[string]$Name,[string]$TargetPath) {
 $app=[pscustomobject]@{Name=$Name;AppID=$TargetPath}
 $match=Find-AShellIcon $Index $app $Aliases
 if(!$match.Icon -and $TargetPath){
  $targetName=[IO.Path]::GetFileNameWithoutExtension($TargetPath)
  if($targetName){$match=Find-AShellIcon $Index ([pscustomobject]@{Name=$targetName;AppID=$TargetPath}) $Aliases}
 }
 return $match
}

function Invoke-AShellDesktopIconRefresh {
 if(Get-Command Send-AShellDesktopRefresh -ErrorAction SilentlyContinue){Send-AShellDesktopRefresh}
 $ie4u=Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
 if(Test-Path -LiteralPath $ie4u){Start-Process -FilePath $ie4u -ArgumentList '-show' -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null}
}

function Enable-AShellDesktopMonochrome([string]$Root) {
 if(!(Get-Command Find-AShellIcon -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'Icon.Selection.ps1')}
 $snapshot=Get-AShellDesktopIconStatePath $Root
 if(Test-Path -LiteralPath $snapshot){
  $existing=Import-Clixml -LiteralPath $snapshot
  if($existing.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'The desktop-icon backup belongs to another Windows account.'}
 } else {$existing=$null}
 $entries=@();$registry=@()
 if($existing){$entries+=@($existing.Shortcuts);$registry+=@($existing.Registry)}
 $known=@{};foreach($entry in $entries){$known[[string]$entry.Path]=$true}
 $index=New-AShellIconIndex $Root;$aliases=Get-AShellIconAliases
 $shell=New-Object -ComObject WScript.Shell
 $changed=0;$matched=0;$ambiguous=0
 try {
  foreach($file in Get-AShellDesktopShortcutFiles) {
   $link=$shell.CreateShortcut($file.FullName)
   try {
    $target=[Environment]::ExpandEnvironmentVariables([string]$link.TargetPath)
    $match=Resolve-AShellDesktopShortcutIcon $Root $index $aliases $file.BaseName $target
    if(!$match.Icon){if($match.Reason -eq 'ambiguous'){$ambiguous++};continue}
    $matched++
    if(!$known.ContainsKey($file.FullName)){$entries+=[pscustomobject]@{Path=$file.FullName;IconLocation=[string]$link.IconLocation};$known[$file.FullName]=$true}
    $ico=Get-AShellDesktopIco $Root $match.Icon
    $desired=$ico+',0'
    if([string]$link.IconLocation -cne $desired){$link.IconLocation=$desired;$link.Save();$changed++}
   } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
  }
 } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}

 # Windows shell icons shown on the desktop aren't .lnk files. Override only the
 # two common app-like shell entries; document/folder file-type icons stay global
 # Windows choices and are intentionally not changed outside the desktop surface.
 $shellIcons=@(
  @{Path='HKCU:\Software\Classes\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}\DefaultIcon';Asset='icons8-recycle-96.png';Label='Recycle Bin'},
  @{Path='HKCU:\Software\Classes\CLSID\{20D04FE0-3AEA-1069-A2D8-08002B30309D}\DefaultIcon';Asset='icons8-computer-management-96.png';Label='This PC'}
 )
 $knownReg=@{};foreach($entry in $registry){$knownReg[[string]$entry.Path]=$true}
 foreach($item in $shellIcons){
  if(!$knownReg.ContainsKey($item.Path)){$registry+=[pscustomobject]@{Path=$item.Path;Value=(Read-RegistryValue $item.Path '')};$knownReg[$item.Path]=$true}
  $ico=Get-AShellDesktopIco $Root $item.Asset
  Write-RegistryValue @{Path=$item.Path;Name='';Kind='String';Value=$ico;Exists=$true}
 }

 [pscustomobject]@{Version=1;Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Shortcuts=@($entries);Registry=@($registry)} | Export-Clixml -LiteralPath $snapshot
 Invoke-AShellDesktopIconRefresh
 Write-Output "[OK] Desktop monochrome icons active: $matched shortcut match(es), $changed shortcut update(s)."
 if($ambiguous){Write-Output "[STATUS] $ambiguous desktop shortcut name(s) were ambiguous and were left unchanged."}
}

function Restore-AShellDesktopMonochrome([string]$Root) {
 $snapshot=Get-AShellDesktopIconStatePath $Root
 if(!(Test-Path -LiteralPath $snapshot)){return}
 $saved=Import-Clixml -LiteralPath $snapshot
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'The desktop-icon backup belongs to another Windows account.'}
 $shell=New-Object -ComObject WScript.Shell;$restored=0
 try {
  foreach($entry in @($saved.Shortcuts)){
   if(!(Test-Path -LiteralPath $entry.Path -PathType Leaf)){continue}
   $link=$shell.CreateShortcut([string]$entry.Path)
   try {if([string]$link.IconLocation -cne [string]$entry.IconLocation){$link.IconLocation=[string]$entry.IconLocation;$link.Save();$restored++}}
   finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
  }
 } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
 foreach($entry in @($saved.Registry)){Write-RegistryValue $entry.Value}
 Remove-Item -LiteralPath $snapshot -Force
 Remove-Item -LiteralPath (Get-AShellDesktopIconCachePath $Root) -Recurse -Force -ErrorAction SilentlyContinue
 Invoke-AShellDesktopIconRefresh
 Write-Output "[OK] Original desktop shortcut/shell icons restored ($restored shortcut change(s))."
}

function Sync-AShellDesktopMonochrome([string]$Root,[string]$DesktopMode,[bool]$Icons) {
 if($DesktopMode -eq 'keep' -and $Icons){Enable-AShellDesktopMonochrome $Root}else{Restore-AShellDesktopMonochrome $Root}
}
