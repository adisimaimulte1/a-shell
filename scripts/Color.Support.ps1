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
function ConvertTo-AShellColor([string]$Color) {
 if($Color -eq 'default'){return 'D65A00'}
 if($Color -notmatch '^#?([0-9a-fA-F]{6})$'){throw 'Use six hexadecimal digits, for example 00AAFF, or default.'}
 return $Matches[1].ToUpperInvariant()
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
function Send-AShellColorChange {
 $result=[IntPtr]::Zero
 $stored=Read-RegistryValue 'HKCU:\Software\A-Shell' 'AccentColor'
 $hex=if($stored.Exists){ConvertTo-AShellColor $stored.Value}else{'D65A00'}
 $folder=Join-Path (Split-Path $PSScriptRoot) 'state'
 New-Item -ItemType Directory $folder -Force | Out-Null
 $file=Join-Path $folder 'accent-color.txt'
 $temporary=$file+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temporary,$hex,[Text.Encoding]::ASCII)
 if(Test-Path $file){[IO.File]::Replace($temporary,$file,$file+'.previous')}else{[IO.File]::Move($temporary,$file)}
 # Notify the renderer directly first; it returns the RGB value plus one.
 $window=[AShellAccentNative]::FindWindow('MatrixDesktopController',$null)
 if($window -ne [IntPtr]::Zero) {
  $message=[AShellAccentNative]::RegisterWindowMessage('A-Shell.AccentChanged.v1')
  if([AShellAccentNative]::Send($window,$message,[IntPtr]::Zero,[IntPtr]::Zero,2,1500,[ref]$result) -eq [IntPtr]::Zero){throw 'Matrix did not acknowledge the color update.'}
  if($result.ToInt64() -ne ([Convert]::ToInt64($hex,16)+1)){throw 'Update MatrixDesktop.exe before using live colors.'}
 }
 [void][AShellAccentNative]::Broadcast([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'ImmersiveColorSet',2,100,[ref]$result)
 # ImmersiveColorSet is sufficient; WM_THEMECHANGED forces expensive global redraws.
}
function Set-AShellAccent([string]$Color) {
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
 Send-AShellColorChange
}
