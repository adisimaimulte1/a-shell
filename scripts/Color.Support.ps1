$ErrorActionPreference='Stop'
if(-not ('AShellAccentNative' -as [type])) {
 Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AShellAccentNative {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
 [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode)] public static extern IntPtr Broadcast(IntPtr hwnd,uint msg,IntPtr w,string l,uint flags,uint timeout,out IntPtr result);
 [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW")] public static extern IntPtr Send(IntPtr hwnd,uint msg,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
}
'@
}
function Get-AShellColorPresets {
 $path=Join-Path (Split-Path $PSScriptRoot) 'assets\color-presets.json'
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw 'The color preset catalog is missing. Run Setup to repair A-Shell.'}
 @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).presets)
}
function Get-AShellVarietySortedColorPresets {
 # Greedily choose the RGB color farthest from the previous item. This keeps
 # long families of similar colors from clumping together in the CLI catalog.
 $remaining=[Collections.ArrayList]@(Get-AShellColorPresets)
 $ordered=[Collections.Generic.List[object]]::new()
 $current=$remaining | Where-Object name -eq 'default' | Select-Object -First 1
 if(!$current){$current=$remaining[0]}
 while($remaining.Count) {
  [void]$ordered.Add($current)
  [void]$remaining.Remove($current)
  if(!$remaining.Count){break}
  $hex=[string]$current.hex
  $red=[Convert]::ToInt32($hex.Substring(0,2),16)
  $green=[Convert]::ToInt32($hex.Substring(2,2),16)
  $blue=[Convert]::ToInt32($hex.Substring(4,2),16)
  $next=$null;$bestDistance=-1;$bestName=''
  foreach($item in $remaining) {
   $candidate=[string]$item.hex
   $dr=$red-[Convert]::ToInt32($candidate.Substring(0,2),16)
   $dg=$green-[Convert]::ToInt32($candidate.Substring(2,2),16)
   $db=$blue-[Convert]::ToInt32($candidate.Substring(4,2),16)
   $distance=$dr*$dr+$dg*$dg+$db*$db
   $name=[string]$item.name
   if($distance -gt $bestDistance -or ($distance -eq $bestDistance -and [string]::CompareOrdinal($name,$bestName) -lt 0)) {
    $next=$item;$bestDistance=$distance;$bestName=$name
   }
  }
  $current=$next
 }
 @($ordered)
}
function Resolve-AShellColor([string]$Color) {
 $inputValue=([string]$Color).Trim()
 if($inputValue -match '^#?([0-9a-fA-F]{6})$'){
  return [pscustomobject]@{Name='custom';Hex=$Matches[1].ToUpperInvariant();Rain='solid';Stored=$Matches[1].ToUpperInvariant()}
 }
 $key=$inputValue.ToLowerInvariant()
 foreach($preset in Get-AShellColorPresets) {
  if($preset.name -eq $key -or @($preset.aliases) -contains $key) {
   $rain=if($preset.rain){[string]$preset.rain}else{'solid'}
   $stored=switch($rain){'rainbow'{'RAINBOW'}'purple-orange'{'PURPLE_ORANGE'}default{([string]$preset.hex).ToUpperInvariant()}}
   return [pscustomobject]@{Name=[string]$preset.name;Hex=([string]$preset.hex).ToUpperInvariant();Rain=$rain;Stored=$stored}
  }
 }
 throw "Unknown color '$Color'. Use six hexadecimal digits or run 'ashell color list'."
}
function ConvertTo-AShellColor([string]$Color) {
 (Resolve-AShellColor $Color).Hex
}
function Format-AShellColorSwatch([string]$Hex,[bool]$Enabled=$true) {
 if(!$Enabled){return ''}
 $value=$Hex.TrimStart('#').ToUpperInvariant()
 if($value -notmatch '^[0-9A-F]{6}$'){return ''}
 $red=[Convert]::ToInt32($value.Substring(0,2),16)
 $green=[Convert]::ToInt32($value.Substring(2,2),16)
 $blue=[Convert]::ToInt32($value.Substring(4,2),16)
 $escape=[char]27
 $escape+'[38;2;'+$red+';'+$green+';'+$blue+'m'+[char]0x25A0+$escape+'[0m'
}
function Show-AShellColorPresets {
 Write-Output 'A-Shell color presets:'
 $supportsSwatches=$false
 try {
  $property=$Host.UI.PSObject.Properties['SupportsVirtualTerminal']
  $supportsSwatches=$property -and [bool]$property.Value -and ![Console]::IsOutputRedirected
 } catch {}
 foreach($preset in Get-AShellVarietySortedColorPresets) {
  $swatch=Format-AShellColorSwatch ([string]$preset.hex) $supportsSwatches
  $suffix=if($preset.rain -eq 'rainbow'){"  #$($preset.hex) $swatch  (rainbow rain)"}else{"  #$($preset.hex) $swatch"}
  Write-Output ('  {0,-22}{1}  {2}' -f $preset.name,$suffix,$preset.description)
 }
 Write-Output "`nUse: ashell color <preset>"
}
function Send-AShellPolicyChange {
 $result=[IntPtr]::Zero
 [void][AShellAccentNative]::Broadcast([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'Policy',2,250,[ref]$result)
}
function Send-AShellMaterialPreferenceChange {
 # Settings uses this lightweight WM_SETTINGCHANGE notification when immersive
 # color/material preferences change. It refreshes Acrylic/Smoke eligibility
 # without the expensive WM_THEMECHANGED taskbar repaint.
 $result=[IntPtr]::Zero
 [void][AShellAccentNative]::Broadcast([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'ImmersiveColorSet',2,150,[ref]$result)
}
function Send-AShellThemeChange {
 # Theme changes need a refresh beyond the lightweight accent notification.
 # Only setup/restore calls this; live rain-color changes keep their fast path.
 $result=[IntPtr]::Zero
 [void][AShellAccentNative]::Broadcast([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'ImmersiveColorSet',2,100,[ref]$result)
 $tray=[AShellAccentNative]::FindWindow('Shell_TrayWnd',$null)
 if($tray -ne [IntPtr]::Zero){[void][AShellAccentNative]::Send($tray,0x31a,[IntPtr]::Zero,[IntPtr]::Zero,2,1500,[ref]$result)}
 Write-Output '[OK] Taskbar refreshed to the Windows light/dark theme.'
}
function Get-AShellColorValues {
 $list=@(
  @('HKCU:\Software\A-Shell','AccentColor'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent','AccentPalette'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent','AccentColorMenu'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent','StartColorMenu'),
  @('HKCU:\Software\Microsoft\Windows\DWM','AccentColor'),
  @('HKCU:\Software\Microsoft\Windows\DWM','ColorizationColor'),
  @('HKCU:\Software\Microsoft\Windows\DWM','ColorPrevalence'),
  @('HKCU:\Control Panel\Desktop','AutoColorization')
 )
 @(foreach($entry in $list){Read-RegistryValue $entry[0] $entry[1]})
}
function Send-AShellColorChange([string]$RainMode='solid') {
 $result=[IntPtr]::Zero
 $stored=Read-RegistryValue 'HKCU:\Software\A-Shell' 'AccentColor'
 $hex=if($stored.Exists){ConvertTo-AShellColor $stored.Value}else{'D65A00'}
 $rendererValue=switch($RainMode){'rainbow'{'RAINBOW'}'purple-orange'{'PURPLE_ORANGE'}default{$hex}}
 $folder=Join-Path (Split-Path $PSScriptRoot) 'state'
 New-Item -ItemType Directory $folder -Force | Out-Null
 $file=Join-Path $folder 'accent-color.txt'
 $temporary=$file+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temporary,$rendererValue,[Text.Encoding]::ASCII)
 if(Test-Path $file){[IO.File]::Replace($temporary,$file,$file+'.previous')}else{[IO.File]::Move($temporary,$file)}
 # Notify the renderer directly first; it returns the RGB value plus one.
 $window=[AShellAccentNative]::FindWindow('MatrixDesktopController',$null)
 if($window -ne [IntPtr]::Zero) {
  $message=[AShellAccentNative]::RegisterWindowMessage('A-Shell.AccentChanged.v1')
  if([AShellAccentNative]::Send($window,$message,[IntPtr]::Zero,[IntPtr]::Zero,2,1500,[ref]$result) -eq [IntPtr]::Zero){throw 'Matrix did not acknowledge the color update.'}
  if($result.ToInt64() -ne ([Convert]::ToInt64($hex,16)+1)){throw 'Update MatrixDesktop.exe before using live colors.'}
 }
 Send-AShellMaterialPreferenceChange
 # ImmersiveColorSet is sufficient; WM_THEMECHANGED forces expensive global redraws.
}
function Set-AShellAccent([string]$Color,[string]$RainMode='solid') {
 $hex=ConvertTo-AShellColor $Color
 $r=[Convert]::ToInt32($hex.Substring(0,2),16);$g=[Convert]::ToInt32($hex.Substring(2,2),16);$b=[Convert]::ToInt32($hex.Substring(4,2),16)
 # AccentPalette is eight RGBX entries: light variants, base, dark variants.
 $palette=New-Object byte[] 32
 $shades=@(0.65,0.4,0.2,0,-0.2,-0.4,-0.6,0)
 for($i=0;$i -lt 8;$i++) {
  $channels=@($r,$g,$b)
  for($j=0;$j -lt 3;$j++) {
   $component=if($shades[$i] -ge 0){$channels[$j]+(255-$channels[$j])*$shades[$i]}else{$channels[$j]*(1+$shades[$i])}
   $palette[$i*4+$j]=[byte][math]::Round($component)
  }
 }
 $abgr=[BitConverter]::ToInt32([byte[]]@($r,$g,$b,255),0)
 $argb=[BitConverter]::ToInt32([byte[]]@($b,$g,$r,255),0)
 $dark=[BitConverter]::ToInt32([byte[]]@($palette[16],$palette[17],$palette[18],255),0)
 foreach($entry in @(
  @('HKCU:\Software\A-Shell','AccentColor','String',$hex),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent','AccentPalette','Binary',$palette),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent','AccentColorMenu','DWord',$abgr),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent','StartColorMenu','DWord',$dark),
  @('HKCU:\Software\Microsoft\Windows\DWM','AccentColor','DWord',$abgr),
  @('HKCU:\Software\Microsoft\Windows\DWM','ColorizationColor','DWord',$argb),
  @('HKCU:\Control Panel\Desktop','AutoColorization','DWord',0)
 )) {Write-RegistryValue @{Path=$entry[0];Name=$entry[1];Kind=$entry[2];Value=$entry[3];Exists=$true}}
 Send-AShellColorChange $RainMode
}
