. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
function Get-AShellChildPath([string]$Parent,[string]$Name) {
 if(!$Name -or $Name -in @('.','..') -or [IO.Path]::GetFileName($Name) -ne $Name){throw 'Invalid desktop journal name.'}
 $prefix=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
 $path=[IO.Path]::GetFullPath((Join-Path $Parent $Name))
 if(!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Desktop path escaped its saved folder.'}
 return $path
}
function Assert-AShellDesktopRoots([string]$Desktop,[string]$Archive) {
 $a=[IO.Path]::GetFullPath($Desktop).TrimEnd('\')+'\'
 $b=[IO.Path]::GetFullPath($Archive).TrimEnd('\')+'\'
 if($a.StartsWith($b,[StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a,[StringComparison]::OrdinalIgnoreCase)){throw 'Desktop and archive must be separate folders.'}
 foreach($path in @($Desktop,$Archive)) {
  $item=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'A redirected desktop/archive link needs manual handling; no files were moved.'}
 }
}
function Save-AShellDesktop([string]$Root) {
 $state=Join-Path $Root 'state';$manifest=Join-Path $state 'desktop-before.clixml'
 if(Test-Path -LiteralPath $manifest){Assert-AShellAccount (Import-Clixml -LiteralPath $manifest);return}
 $desktop=[Environment]::GetFolderPath('DesktopDirectory')
 $archive=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'original_desktop'
 Assert-AShellDesktopRoots $desktop $archive
 foreach($location in @($desktop,$archive)){
  $prefix=[IO.Path]::GetFullPath($location).TrimEnd('\')+'\'
  if(([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\').StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Keep A-Shell outside Desktop and original_desktop before running Setup.'}
 }
 # Positions and display preference are captured before any appearance changes.
 $layout=Join-Path $state 'desktop-layout.bin'
 if(!(Test-Path -LiteralPath $layout)) {
  $partial=$layout+'.partial';if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial}
  & (Join-Path $Root 'bin\DesktopLayout.exe') save $partial
  if($LASTEXITCODE){throw 'Could not capture desktop positions. Setup has not moved desktop files.'}
  [IO.File]::Move($partial,$layout)
 }
 $entries=@(foreach($item in Get-ChildItem -LiteralPath $desktop -Force) {
  if($item.Name -eq 'desktop.ini'){continue}
  # A junction can reach outside the desktop; never recurse through one.
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Desktop link/cloud placeholder needs manual handling before setup: $($item.Name)"}
  $name=$item.Name
  if(Test-Path -LiteralPath (Join-Path $archive $name)){$name=$item.BaseName+'-ashell-'+[guid]::NewGuid().ToString('N').Substring(0,8)+$item.Extension}
  @{Name=$item.Name;ArchivedName=$name;State='Planned';IsDirectory=$item.PSIsContainer}
 })
 Save-AShellState @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Desktop=$desktop;Archive=$archive;Entries=$entries;HideIcons=(Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons')} $manifest
}
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
  $entry.State='Moving';Save-AShellState $Saved $Journal
  # Paths have been validated against the explicitly saved desktop/archive.
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
  if(!(Test-Path -LiteralPath $source)){$conflicts+="Missing archive item: $source";continue}
  if(Test-Path -LiteralPath $target){$conflicts+="Kept both copies: $source (desktop name already exists)";continue}
  $entry.State='Restoring';Save-AShellState $Saved $Journal
  if($entry.IsDirectory){[IO.Directory]::Move($source,$target)}else{[IO.File]::Move($source,$target)}
  $entry.State='Restored';Save-AShellState $Saved $Journal
 }
 return $conflicts
}
function Set-AShellDesktopArchived([string]$Root) {
 $journal=Join-Path $Root 'state\desktop-before.clixml'
 $saved=Import-Clixml -LiteralPath $journal;Assert-AShellAccount $saved
 $toRollback=@($saved.Entries | Where-Object {$_.State -ne 'Archived'} | ForEach-Object {$_.Name})
 $priorVisibility=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
 try {
  Move-AShellDesktopItems $saved $journal
  Write-RegistryValue @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideIcons';Kind='DWord';Exists=$true;Value=1}
  Send-AShellDesktopRefresh
  & (Join-Path $Root 'bin\DesktopLayout.exe') hide unused
  if($LASTEXITCODE){Write-Warning 'Files are archived; desktop visibility may refresh at the next sign-in.'}
 } catch {
  $failure=$_
  $conflicts=@(Restore-AShellDesktopItems $saved $journal -OnlyNames $toRollback)
  if($conflicts.Count){Write-Warning ($conflicts -join '; ')}
  Write-RegistryValue $priorVisibility;Send-AShellDesktopRefresh
  throw $failure
 }
 Write-Output "Personal desktop contents archived in $($saved.Archive). Shared/virtual desktop icons are hidden, not moved."
}
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
 $conflicts=@(Restore-AShellDesktopItems $saved $journal)
 Write-RegistryValue $saved.HideIcons
 Send-AShellDesktopRefresh
 # Explorer processes directory notifications asynchronously. Bounded retries
 # give it time to enumerate restored files before positioning them.
 $layout=Join-Path $Root 'state\desktop-layout.bin'
 if(Test-Path -LiteralPath $layout){
  for($attempt=0;$attempt -lt 8;$attempt++){
   Start-Sleep -Milliseconds 300
   & (Join-Path $Root 'bin\DesktopLayout.exe') restore $layout
   if($LASTEXITCODE -eq 0){break}
   if($LASTEXITCODE -ne 2 -or $attempt -eq 7){Write-Warning 'Some desktop positions could not be verified. Missing items or a changed display layout may prevent an exact restore; the original backup is retained.';break}
  }
 }
 if($conflicts.Count){Write-Warning ($conflicts -join "`n");throw 'Some desktop files need attention. No conflicting files were overwritten. Resolve the listed names, then rerun undo.'}
}
