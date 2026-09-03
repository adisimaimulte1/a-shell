. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
function Get-AShellChildPath([string]$Parent,[string]$Name) {
 if(!$Name -or $Name -in @('.','..') -or [IO.Path]::GetFileName($Name) -ne $Name){throw 'Invalid desktop journal name.'}
 $prefix=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
 $path=[IO.Path]::GetFullPath((Join-Path $Parent $Name))
 if(!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Desktop path escaped its saved folder.'}
 return $path
}

# Legacy archive journals used two physical folders. Keep the path-safety check for
# restoring those old installations, but do not reject redirected/reparse roots:
# OneDrive Known Folder Move can legitimately make Desktop/Documents redirected.
function Assert-AShellDesktopRoots([string]$Desktop,[string]$Archive) {
 if(!$Desktop -or !$Archive){throw 'Legacy desktop journal is incomplete.'}
 $a=[IO.Path]::GetFullPath($Desktop).TrimEnd('\')+'\'
 $b=[IO.Path]::GetFullPath($Archive).TrimEnd('\')+'\'
 if($a.StartsWith($b,[StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a,[StringComparison]::OrdinalIgnoreCase)){throw 'Desktop and archive must be separate folders.'}
}

function Save-AShellDesktop([string]$Root) {
 $state=Join-Path $Root 'state';$manifest=Join-Path $state 'desktop-before.clixml'
 if(Test-Path -LiteralPath $manifest){Assert-AShellAccount (Import-Clixml -LiteralPath $manifest);return}
 $desktop=[Environment]::GetFolderPath('DesktopDirectory')
 if(!$desktop){throw 'Windows did not return the current Desktop known-folder path.'}

 # Positions and shell-view flags are captured before any appearance changes.
 # No Desktop file is moved. This intentionally supports OneDrive Known Folder Move,
 # Files On-Demand, redirected profiles and other legitimate Desktop providers.
 $layout=Join-Path $state 'desktop-layout.bin'
 if(!(Test-Path -LiteralPath $layout)) {
  $partial=$layout+'.partial';if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial}
  & (Join-Path $Root 'bin\DesktopLayout.exe') save $partial
  if($LASTEXITCODE){throw 'Could not capture desktop positions. Setup has not changed desktop visibility.'}
  [IO.File]::Move($partial,$layout)
 }
 Save-AShellState @{SchemaVersion=2;Mode='HideOnly';Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Desktop=$desktop;HideIcons=(Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons')} $manifest
}

# These two functions exist only so an older A-Shell installation that already moved
# files into original_desktop can still be undone safely. New installs never call the
# move function and never create an archive folder.
function Move-AShellDesktopItems($Saved,[string]$Journal) {
 Assert-AShellDesktopRoots $Saved.Desktop $Saved.Archive
 New-Item -ItemType Directory -Path $Saved.Archive -Force | Out-Null
 foreach($entry in $Saved.Entries) {
  if($entry.State -eq 'Archived'){continue}
  $source=Get-AShellChildPath $Saved.Desktop $entry.Name
  $target=Get-AShellChildPath $Saved.Archive $entry.ArchivedName
  if($entry.State -eq 'Moving') {
   if(!(Test-Path -LiteralPath $source) -and (Test-Path -LiteralPath $target)){$entry.State='Archived';Save-AShellState $Saved $Journal;continue}
   if(Test-Path -LiteralPath $target){throw "Interrupted desktop move needs attention; both copies retained: $source / $target"}
  }
  if(!(Test-Path -LiteralPath $source)){continue}
  if(Test-Path -LiteralPath $target){throw "Archive destination is occupied: $target"}
  $item=Get-Item -LiteralPath $source
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Legacy desktop link needs manual handling before it can be moved: $($entry.Name)"}
  $entry.State='Moving';Save-AShellState $Saved $Journal
  if($entry.IsDirectory){[IO.Directory]::Move($source,$target)}else{[IO.File]::Move($source,$target)}
  $entry.State='Archived';Save-AShellState $Saved $Journal
 }
}
function Restore-AShellDesktopItems($Saved,[string]$Journal,[string[]]$OnlyNames=$null) {
 Assert-AShellDesktopRoots $Saved.Desktop $Saved.Archive
 $conflicts=@()
 foreach($entry in $Saved.Entries) {
  if($null -ne $OnlyNames -and $OnlyNames -notcontains $entry.Name){continue}
  if($entry.State -notin @('Archived','Moving','Restoring')){continue}
  $source=Get-AShellChildPath $Saved.Archive $entry.ArchivedName
  $target=Get-AShellChildPath $Saved.Desktop $entry.Name
  if($entry.State -eq 'Restoring' -and !(Test-Path -LiteralPath $source) -and (Test-Path -LiteralPath $target)){$entry.State='Restored';Save-AShellState $Saved $Journal;continue}
  if($entry.State -eq 'Moving' -and !(Test-Path -LiteralPath $source) -and (Test-Path -LiteralPath $target)){$entry.State='Planned';Save-AShellState $Saved $Journal;continue}
  if(!(Test-Path -LiteralPath $source)){$conflicts+="Missing legacy archive item: $source";continue}
  if(Test-Path -LiteralPath $target){$conflicts+="Kept both copies: $source (desktop name already exists)";continue}
  $entry.State='Restoring';Save-AShellState $Saved $Journal
  if($entry.IsDirectory){[IO.Directory]::Move($source,$target)}else{[IO.File]::Move($source,$target)}
  $entry.State='Restored';Save-AShellState $Saved $Journal
 }
 return $conflicts
}

function Hide-AShellDesktopIconsNow([string]$Root) {
 Write-RegistryValue @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideIcons';Kind='DWord';Exists=$true;Value=1}
 # FWF_NOICONS changes the active Explorer desktop view immediately; HideIcons keeps
 # that choice persistent across Explorer restarts/sign-in. Use both so the desktop is
 # the first visible part of A-Shell to transform without touching Desktop files.
 $helper=Join-Path $Root 'bin\DesktopLayout.exe'
 if(Test-Path -LiteralPath $helper){
  & $helper hide unused
  if($LASTEXITCODE){Write-Warning 'Explorer did not accept the immediate hide request; the persistent hide setting is still applied.'}
 }
 Send-AShellDesktopRefresh
 Write-Output '[OK] Desktop icons hidden first. Desktop files stay exactly where Windows/OneDrive keeps them.'
}
function Set-AShellDesktopHidden([string]$Root) {
 $journal=Join-Path $Root 'state\desktop-before.clixml'
 $saved=Import-Clixml -LiteralPath $journal;Assert-AShellAccount $saved
 Write-RegistryValue @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideIcons';Kind='DWord';Exists=$true;Value=1}
 Send-AShellDesktopRefresh
 $helper=Join-Path $Root 'bin\DesktopLayout.exe'
 if(Test-Path -LiteralPath $helper){
  $liveHidden=$false
  for($attempt=1;$attempt -le 8;$attempt++) {
   if(Get-Process explorer -ErrorAction SilentlyContinue) {
    & $helper hide unused
    if($LASTEXITCODE -eq 0){$liveHidden=$true;break}
   }
   Start-Sleep -Milliseconds (100 + (75*$attempt))
  }
  if(!$liveHidden) {
   $persisted=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
   if(!$persisted.Exists -or [int]$persisted.Value -ne 1){throw 'Desktop icon hiding did not persist.'}
   Write-Output '[INFO] Explorer was still restarting during the final live-view check. Desktop icons are already hidden persistently and will remain hidden after Explorer settles.'
  }
 }
 if($saved.PSObject.Properties.Name -contains 'Entries'){
  $remaining=@($saved.Entries | Where-Object {$_.State -in @('Archived','Moving','Restoring')}).Count
  if($remaining){Write-Output "[STATUS] Legacy A-Shell archive detected ($remaining item(s)). It is preserved for safe undo; no new Desktop items are moved."}
 }
 Write-Output '[OK] Desktop surface is icon-free. No personal files were moved, copied, hydrated or removed from OneDrive.'
}
# Backward-compatible function name for scripts from older packages.
function Set-AShellDesktopArchived([string]$Root) {Set-AShellDesktopHidden $Root}

function Send-AShellDesktopRefresh {
 if(!('AShellDesktopRefresh' -as [type])){Add-Type @'
using System;using System.Runtime.InteropServices;
public static class AShellDesktopRefresh {
 [DllImport("shell32.dll")] public static extern void SHChangeNotify(uint e,uint f,IntPtr a,IntPtr b);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,string l,uint f,uint t,out IntPtr r);
}
'@}
 [AShellDesktopRefresh]::SHChangeNotify(0x8000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
 $result=[IntPtr]::Zero
 [void][AShellDesktopRefresh]::SendMessageTimeout([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',2,1000,[ref]$result)
}
function Restore-AShellDesktop([string]$Root) {
 $journal=Join-Path $Root 'state\desktop-before.clixml'
 if(!(Test-Path -LiteralPath $journal)){return}
 $saved=Import-Clixml -LiteralPath $journal;Assert-AShellAccount $saved
 $conflicts=@()
 # Restore files only for legacy v1 journals which physically archived them.
 if($saved.PSObject.Properties.Name -contains 'Entries'){$conflicts=@(Restore-AShellDesktopItems $saved $journal)}
 Write-RegistryValue $saved.HideIcons
 Send-AShellDesktopRefresh

 # Restore both saved shell-view flags (including the user's original Show desktop
 # icons choice) and positions. Bounded retries allow Explorer/OneDrive enumeration.
 $layout=Join-Path $Root 'state\desktop-layout.bin'
 if(Test-Path -LiteralPath $layout){
  for($attempt=0;$attempt -lt 8;$attempt++){
   if($attempt){Start-Sleep -Milliseconds 250}
   & (Join-Path $Root 'bin\DesktopLayout.exe') restore $layout
   if($LASTEXITCODE -eq 0){break}
   if($LASTEXITCODE -ne 2 -or $attempt -eq 7){Write-Warning 'Some desktop positions or view flags could not be verified. A changed display layout or unavailable cloud item may prevent an exact position restore; the original backup is retained.';break}
  }
 }
 if($conflicts.Count){Write-Warning ($conflicts -join "`n");throw 'Some legacy archived desktop files need attention. No conflicting files were overwritten. Resolve the listed names, then rerun undo.'}
}
