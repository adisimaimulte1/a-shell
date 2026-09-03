. (Join-Path $PSScriptRoot 'State.Helpers.ps1')

function Get-AShellChildPath([string]$Parent,[string]$Name) {
 if(!$Name -or $Name -in @('.','..') -or [IO.Path]::GetFileName($Name) -ne $Name){throw 'Invalid desktop journal name.'}
 $prefix=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
 $path=[IO.Path]::GetFullPath((Join-Path $Parent $Name))
 if(!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Desktop path escaped its saved folder.'}
 return $path
}

function Test-AShellSamePath([string]$Left,[string]$Right) {
 if(!$Left -or !$Right){return $false}
 $leftFull=[IO.Path]::GetFullPath($Left).TrimEnd('\')
 $rightFull=[IO.Path]::GetFullPath($Right).TrimEnd('\')
 return [string]::Equals($leftFull,$rightFull,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-AShellDesktopRoots(
 [string]$Desktop,
 [string]$Archive,
 [string]$KnownDesktop=([Environment]::GetFolderPath('DesktopDirectory'))
) {
 $a=[IO.Path]::GetFullPath($Desktop).TrimEnd('\')+'\'
 $b=[IO.Path]::GetFullPath($Archive).TrimEnd('\')+'\'
 if($a.StartsWith($b,[StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a,[StringComparison]::OrdinalIgnoreCase)){throw 'Desktop and archive must be separate folders.'}

 $desktopItem=Get-Item -LiteralPath $Desktop -ErrorAction SilentlyContinue
 if($desktopItem -and !$desktopItem.PSIsContainer){throw 'Desktop path is not a folder.'}
 if($desktopItem -and ($desktopItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  if(!(Test-AShellSamePath $Desktop $KnownDesktop)){throw 'A custom desktop link needs manual handling; no files were moved.'}
 }

 $archiveItem=Get-Item -LiteralPath $Archive -ErrorAction SilentlyContinue
 if($archiveItem -and !$archiveItem.PSIsContainer){throw 'Desktop archive path is not a folder.'}
 if($archiveItem -and ($archiveItem.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'The original_desktop archive is a link/reparse point and needs manual handling; no files were moved.'}
}

function Copy-AShellDirectorySafe([string]$Source,[string]$Target) {
 if(Test-Path -LiteralPath $Target){throw "Archive destination is occupied: $Target"}
 New-Item -ItemType Directory -Path $Target -Force | Out-Null
 try {
  foreach($child in Get-ChildItem -LiteralPath $Source -Force) {
   $childTarget=Join-Path $Target $child.Name
   if($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    # Never traverse/copy linked children. Leave them in place on the Desktop.
    continue
   }
   if($child.PSIsContainer) {
    Copy-AShellDirectorySafe $child.FullName $childTarget
   } else {
    Copy-Item -LiteralPath $child.FullName -Destination $childTarget -Force
   }
  }
 } catch {
  Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue
  throw
 }
}

function Remove-AShellDirectoryContentsSafe([string]$Source) {
 foreach($child in Get-ChildItem -LiteralPath $Source -Force) {
  if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
  Remove-Item -LiteralPath $child.FullName -Recurse -Force
 }
}

function Move-AShellItemSafe([string]$Source,[string]$Target,[bool]$IsDirectory) {
 if(Test-Path -LiteralPath $Target){throw "Archive destination is occupied: $Target"}

 if($IsDirectory) {
  try {
   [IO.Directory]::Move($Source,$Target)
   return
  } catch [System.UnauthorizedAccessException] {
   # OneDrive/controlled folders can deny Directory.Move even when normal file
   # reads/writes are allowed. Fall back to copy + verified cleanup.
  } catch [System.IO.IOException] {
   # Cross-volume/provider-backed folders can also reject Directory.Move.
  }

  Copy-AShellDirectorySafe $Source $Target

  # Only delete normal children we actually copied. Reparse-point children stay
  # on the Desktop and remain hidden while A-Shell mode is active.
  Remove-AShellDirectoryContentsSafe $Source

  # Remove the now-empty source directory if possible. If a skipped link remains
  # inside, leave the directory in place; HideIcons keeps it invisible.
  try { Remove-Item -LiteralPath $Source -Force -ErrorAction Stop } catch {}
 } else {
  try {
   [IO.File]::Move($Source,$Target)
   return
  } catch [System.UnauthorizedAccessException] {
  } catch [System.IO.IOException] {
  }

  Copy-Item -LiteralPath $Source -Destination $Target -Force
  if(!(Test-Path -LiteralPath $Target)){throw "File copy fallback failed: $Source"}
  Remove-Item -LiteralPath $Source -Force
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

 $layout=Join-Path $state 'desktop-layout.bin'
 if(!(Test-Path -LiteralPath $layout)) {
  $partial=$layout+'.partial';if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial}
  & (Join-Path $Root 'bin\DesktopLayout.exe') save $partial
  if($LASTEXITCODE){throw 'Could not capture desktop positions. Setup has not moved desktop files.'}
  [IO.File]::Move($partial,$layout)
 }

 $skippedLinks=@()
 $entries=@(foreach($item in Get-ChildItem -LiteralPath $desktop -Force) {
  if($item.Name -eq 'desktop.ini'){continue}
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
   $skippedLinks += $item.Name
   continue
  }
  $name=$item.Name
  if(Test-Path -LiteralPath (Join-Path $archive $name)){$name=$item.BaseName+'-ashell-'+[guid]::NewGuid().ToString('N').Substring(0,8)+$item.Extension}
  @{Name=$item.Name;ArchivedName=$name;State='Planned';IsDirectory=$item.PSIsContainer}
 })

 Save-AShellState @{
  Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  Desktop=$desktop
  Archive=$archive
  Entries=$entries
  SkippedLinks=$skippedLinks
  HideIcons=(Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons')
 } $manifest
}

function Move-AShellDesktopItems($Saved,[string]$Journal) {
 Assert-AShellDesktopRoots $Saved.Desktop $Saved.Archive
 New-Item -ItemType Directory -Path $Saved.Archive -Force | Out-Null

 foreach($entry in $Saved.Entries) {
  if($entry.State -eq 'Archived' -or $entry.State -eq 'Skipped'){continue}
  $source=Get-AShellChildPath $Saved.Desktop $entry.Name
  $target=Get-AShellChildPath $Saved.Archive $entry.ArchivedName

  if($entry.State -eq 'Moving') {
   if(!(Test-Path -LiteralPath $source) -and (Test-Path -LiteralPath $target)){$entry.State='Archived';Save-AShellState $Saved $Journal;continue}
   if(Test-Path -LiteralPath $target){throw "Interrupted desktop move needs attention; both copies retained: $source / $target"}
  }

  if(!(Test-Path -LiteralPath $source)){continue}
  if(Test-Path -LiteralPath $target){throw "Archive destination is occupied: $target"}

  $current=Get-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
  if($current -and ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   $entry.State='Skipped'
   Save-AShellState $Saved $Journal
   continue
  }

  $entry.State='Moving';Save-AShellState $Saved $Journal
  Move-AShellItemSafe $source $target ([bool]$entry.IsDirectory)
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

  if(Test-Path -LiteralPath $target) {
   # A directory may have been left behind because it contained a skipped
   # reparse-point child. Restore archived normal contents back into it.
   if($entry.IsDirectory) {
    try {
     foreach($child in Get-ChildItem -LiteralPath $source -Force) {
      $dest=Join-Path $target $child.Name
      if(Test-Path -LiteralPath $dest){$conflicts+="Kept both copies: $($child.FullName) (desktop name already exists)";continue}
      Move-AShellItemSafe $child.FullName $dest $child.PSIsContainer
     }
     if(!(Get-ChildItem -LiteralPath $source -Force -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue}
     $entry.State='Restored';Save-AShellState $Saved $Journal
     continue
    } catch {
     $conflicts+="Could not merge restored folder: $source -> $target"
     continue
    }
   }

   $conflicts+="Kept both copies: $source (desktop name already exists)"
   continue
  }

  $entry.State='Restoring';Save-AShellState $Saved $Journal
  Move-AShellItemSafe $source $target ([bool]$entry.IsDirectory)
  $entry.State='Restored';Save-AShellState $Saved $Journal
 }

 return $conflicts
}

function Set-AShellDesktopArchived([string]$Root) {
 $journal=Join-Path $Root 'state\desktop-before.clixml'
 $saved=Import-Clixml -LiteralPath $journal;Assert-AShellAccount $saved
 $toRollback=@($saved.Entries | Where-Object {$_.State -notin @('Archived','Skipped')} | ForEach-Object {$_.Name})
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

 $skipped=@()
 if($saved.PSObject.Properties['SkippedLinks']){$skipped=@($saved.SkippedLinks)}
 $suffix=if($skipped.Count){" Linked/cloud desktop items were left in place and hidden: "+($skipped -join ', ')}else{''}
 Write-Output "Personal desktop contents archived in $($saved.Archive). Shared/virtual desktop icons are hidden, not moved.$suffix"
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
