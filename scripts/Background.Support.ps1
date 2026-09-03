. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
function Save-AShellBackground([string]$Folder) {
 New-Item -ItemType Directory -Path $Folder -Force | Out-Null
 $wallpaper=(Read-RegistryValue 'HKCU:\Control Panel\Desktop' 'Wallpaper').Value
 $source=$wallpaper
 if(!$source -or !(Test-Path -LiteralPath $source)){$source=Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'}
 if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $Folder 'desktop.img')}
 $lockSource=Get-AShellLockSource;$lockFile='lock.img'
 if($lockSource) {
  $lockFile='lock'+[IO.Path]::GetExtension($lockSource)
  Copy-Item -LiteralPath $lockSource -Destination (Join-Path $Folder $lockFile)
 } else {Save-LockImage (Join-Path $Folder $lockFile)}
 $values=@(Get-AShellColorValues)
 foreach($entry in @(
  @('HKCU:\Control Panel\Desktop','WallpaperStyle'),@('HKCU:\Control Panel\Desktop','TileWallpaper'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled'),
  @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableLogonBackgroundImage')
 )){$values+=Read-RegistryValue $entry[0] $entry[1]}
 Save-AShellState @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Wallpaper=$wallpaper;LockSource=$lockSource;LockFile=$lockFile;Values=$values} (Join-Path $Folder 'background.clixml')
}
function Restore-AShellBackground([string]$Folder) {
 if(!(Test-Path -LiteralPath (Join-Path $Folder 'background.clixml'))){return}
 $saved=Import-Clixml -LiteralPath (Join-Path $Folder 'background.clixml');Assert-AShellAccount $saved
 $desktop=Join-Path $Folder 'desktop.img'
 if(Test-Path -LiteralPath $desktop) {
  if($saved.Wallpaper -and (Test-Path -LiteralPath $saved.Wallpaper) -and (Get-FileHash -LiteralPath $saved.Wallpaper).Hash -eq (Get-FileHash -LiteralPath $desktop).Hash){Set-DesktopImage $saved.Wallpaper}
  else {Set-DesktopImage $desktop}
 } else {Set-DesktopImage ''}
 $lock=Join-Path $Folder $saved.LockFile
 if($saved.LockSource -and (Test-Path -LiteralPath $saved.LockSource) -and (Get-FileHash -LiteralPath $saved.LockSource).Hash -eq (Get-FileHash -LiteralPath $lock).Hash){Set-LockImage $saved.LockSource}
 else {Set-LockImage $lock}
 foreach($value in $saved.Values){Write-RegistryValue $value}
 Send-AShellColorChange
}
function Set-AShellBackground([string]$Root,[string]$Image) {
 if(!(Test-Path -LiteralPath $Image -PathType Leaf)){throw 'Choose an existing local image file.'}
 Add-Type -AssemblyName System.Drawing
 # Validate decode before taking backups or changing any setting.
 $decoded=[Drawing.Image]::FromFile($Image)
 try {
  if($decoded.Width -gt 16384 -or $decoded.Height -gt 16384){throw 'Image dimensions exceed 16384 pixels. Resize the image first.'}
  if($decoded.RawFormat.Guid -notin @([Drawing.Imaging.ImageFormat]::Png.Guid,[Drawing.Imaging.ImageFormat]::Jpeg.Guid,[Drawing.Imaging.ImageFormat]::Bmp.Guid)){throw 'Use a PNG, JPEG or BMP image; convert other formats first.'}
  $ext=if($decoded.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Png.Guid){'.png'}elseif($decoded.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Jpeg.Guid){'.jpg'}else{'.bmp'}
 } finally {$decoded.Dispose()}
 $checkpoint=Join-Path $Root ('state\background-runs\'+[guid]::NewGuid().ToString('N'))
 Save-AShellBackground $checkpoint
 $baseline=Join-Path $Root 'state\background-before'
 if(!(Test-Path -LiteralPath (Join-Path $baseline 'background.clixml'))){
  New-Item -ItemType Directory -Path $baseline -Force | Out-Null
  Get-ChildItem -LiteralPath $checkpoint -File | Copy-Item -Destination $baseline
 }
 $folder=Join-Path $Root 'state\backgrounds';New-Item -ItemType Directory -Path $folder -Force | Out-Null
 $hash=(Get-FileHash -LiteralPath $Image).Hash
 $target=Join-Path $folder ($hash+$ext)
 if(!(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target).Hash -ne $hash){Copy-Item -LiteralPath $Image -Destination $target -Force}
 $colors=@(Get-AShellColorValues)
 try {
  foreach($entry in @(
   @('HKCU:\Control Panel\Desktop','WallpaperStyle','String','10'),@('HKCU:\Control Panel\Desktop','TileWallpaper','String','0'),
   @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled','DWord',0),
   @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled','DWord',0),
   @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled','DWord',0),
   @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System','DisableLogonBackgroundImage','DWord',0)
  )){Write-RegistryValue @{Path=$entry[0];Name=$entry[1];Kind=$entry[2];Value=$entry[3];Exists=$true}}
  Set-DesktopImage $target;Set-LockImage $target
  foreach($value in $colors){Write-RegistryValue $value};Send-AShellColorChange
 } catch {Restore-AShellBackground $checkpoint;throw}
 Write-Output 'Image set for desktop, lock and sign-in; accent preserved. Windows may crop it to fit. Clear shading still requires the supported screen mods.'
}
function Restore-AShellOriginalWallpaper([string]$Root) {
 $baseline=Join-Path $Root 'state\baseline'
 $legacy=Join-Path $Root 'state\before-setup.clixml'
 $checkpoint=Join-Path $Root ('state\background-runs\'+[guid]::NewGuid().ToString('N'))
 Save-AShellBackground $checkpoint
 $colors=@(Get-AShellColorValues)
 try {
  if(Test-Path -LiteralPath (Join-Path $baseline 'checkpoint.clixml')){
   $saved=Import-Clixml -LiteralPath (Join-Path $baseline 'checkpoint.clixml');Assert-AShellAccount $saved
   $desktop=Join-Path $baseline 'desktop.img'
   $lock=Join-Path $baseline $(if($saved.LockOriginal){$saved.LockOriginal}else{'lock.img'})
  } elseif(Test-Path -LiteralPath $legacy) {
   $saved=Import-Clixml -LiteralPath $legacy;Assert-AShellAccount $saved
   $desktop=Join-Path $Root 'state\desktop-before.img';$lock=Join-Path $Root 'state\lock-before.img'
  } elseif(Test-Path -LiteralPath (Join-Path $Root 'state\background-before\background.clixml')) {
   Restore-AShellBackground (Join-Path $Root 'state\background-before')
   foreach($value in $colors){Write-RegistryValue $value};Send-AShellColorChange
   Write-Output '[OK] Original backgrounds restored. Your accent and other A-Shell features are unchanged.';return
  } else {throw 'No original background backup exists. Run Setup or set a background first.'}
  if(Test-Path -LiteralPath $desktop) {
   if($saved.Wallpaper -and (Test-Path -LiteralPath $saved.Wallpaper) -and (Get-FileHash -LiteralPath $saved.Wallpaper).Hash -eq (Get-FileHash -LiteralPath $desktop).Hash){$desktop=$saved.Wallpaper}
   Set-DesktopImage $desktop
  } else {Set-DesktopImage ''}
  if(!(Test-Path -LiteralPath $lock)){throw 'Original lock-screen backup is missing.'}
  Set-LockImage $lock
  foreach($value in $saved.Values){if($value.Name -in @('WallpaperStyle','TileWallpaper','SlideshowEnabled','RotatingLockScreenEnabled','RotatingLockScreenOverlayEnabled','DisableLogonBackgroundImage')){Write-RegistryValue $value}}
  foreach($value in $colors){Write-RegistryValue $value};Send-AShellColorChange
  Write-Output '[OK] Pre-setup desktop, lock and sign-in backgrounds restored. Accent, icons and rain remain enabled.'
 } catch {Restore-AShellBackground $checkpoint;throw}
}
