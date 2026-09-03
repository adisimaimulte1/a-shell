# Creates only uniquely named test items, exercises the real desktop view,
# archives/restores those items, then restores the original visibility/layout.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Appearance.Helpers.ps1')
. (Join-Path $root 'scripts\Desktop.Support.ps1')
$id=[guid]::NewGuid().ToString('N')
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
$test=Join-Path $root ('state\live-tests\desktop-'+$id)
$archive=Join-Path $test 'archive';New-Item -ItemType Directory $test -Force | Out-Null
$helper=Join-Path $root 'bin\DesktopLayout.exe'
$original=Join-Path $test 'before.bin';$shown=Join-Path $test 'shown.bin';$layout=Join-Path $test 'items.bin'
& $helper save $original;if($LASTEXITCODE){throw 'Cannot save initial desktop state'}
$names=@(('AShell-Test-'+$id+'.txt'),('AShell-Folder-'+$id))
$saved=@{Desktop=$desktop;Archive=$archive;Entries=@(@{Name=$names[0];ArchivedName=$names[0];State='Planned';IsDirectory=$false},@{Name=$names[1];ArchivedName=$names[1];State='Planned';IsDirectory=$true})}
$journal=Join-Path $test 'moves.clixml'
function Read-Layout($Path){
 $r=[IO.BinaryReader]::new([IO.File]::OpenRead($Path));$result=@{}
 try {$null=$r.ReadUInt32();$null=$r.ReadUInt32();$count=$r.ReadUInt32();for($i=0;$i -lt $count;$i++){$n=$r.ReadUInt32();$name=[Text.Encoding]::Unicode.GetString($r.ReadBytes(2*$n));$result[$name]=@($r.ReadInt32(),$r.ReadInt32())}}finally{$r.Dispose()};return $result
}
try {
 $bytes=[IO.File]::ReadAllBytes($original);$flags=[BitConverter]::ToUInt32($bytes,4) -band (-bnot 0x1000)
 [BitConverter]::GetBytes([uint32]$flags).CopyTo($bytes,4);[IO.File]::WriteAllBytes($shown,$bytes)
 & $helper restore $shown;if($LASTEXITCODE){throw 'Could not show test desktop'}
 Set-Content -LiteralPath (Get-AShellChildPath $desktop $names[0]) 'A-Shell temporary restore test'
 $folder=Get-AShellChildPath $desktop $names[1];New-Item -ItemType Directory $folder | Out-Null
 Set-Content -LiteralPath (Join-Path $folder 'nested.txt') 'A-Shell nested restore test'
 Send-AShellDesktopRefresh;Start-Sleep -Seconds 2
 & $helper save $layout;if($LASTEXITCODE){throw 'Could not capture test item positions'}
 # Use deliberately non-grid coordinates, then move/archive/restore both items.
 # This catches a restore that silently snaps saved coordinates to the grid.
 $stream=[IO.File]::Open($layout,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
 $reader=[IO.BinaryReader]::new($stream);$writer=[IO.BinaryWriter]::new($stream)
 try {
  $null=$reader.ReadUInt32();$flags=$reader.ReadUInt32();$count=$reader.ReadUInt32()
  $stream.Position=4;$writer.Write([uint32]($flags -band (-bnot 0x5)));$stream.Position=12
  $offset=0
  for($i=0;$i -lt $count;$i++){
   $n=$reader.ReadUInt32();$name=[Text.Encoding]::Unicode.GetString($reader.ReadBytes(2*$n))
   if($name -like ('*'+$id+'*')){$writer.Write([int](257+$offset));$writer.Write([int]283);$offset+=300}
   else{$stream.Position+=8}
  }
 } finally {$writer.Dispose();$reader.Dispose();$stream.Dispose()}
 & $helper restore $layout;if($LASTEXITCODE){throw 'Could not set deliberately positioned test icons'}
 $before=Read-Layout $layout
 if(@($before.Keys | Where-Object {$_ -like ('*'+$id+'*')}).Count -ne 2){throw 'Explorer did not enumerate both test icons'}
 Save-AShellState $saved $journal;Move-AShellDesktopItems $saved $journal
 Send-AShellDesktopRefresh;Start-Sleep -Milliseconds 500
 $conflicts=@(Restore-AShellDesktopItems $saved $journal);if($conflicts.Count){throw ($conflicts -join '; ')}
 Send-AShellDesktopRefresh;Start-Sleep -Seconds 1
 & $helper restore $layout;if($LASTEXITCODE){throw 'Position restore failed'}
 $afterPath=Join-Path $test 'after.bin';& $helper save $afterPath;if($LASTEXITCODE){throw 'Position readback failed'}
 $after=Read-Layout $afterPath
 foreach($name in $before.Keys | Where-Object {$_ -like ('*'+$id+'*')}){if([string]$before[$name] -ne [string]$after[$name]){throw "Position mismatch: $name"}}
 if((Get-Content -LiteralPath (Join-Path $folder 'nested.txt')) -ne 'A-Shell nested restore test'){throw 'Nested test file was changed'}
 'PASS: real desktop file/folder archive, nested file contents, exact icon-position readback, original visibility restored in cleanup.' | Tee-Object -FilePath (Join-Path $root 'state\desktop-live-test.txt')
} finally {
 if(Test-Path $journal){$null=Restore-AShellDesktopItems $saved $journal}
 foreach($name in $names){
  $path=Get-AShellChildPath $desktop $name
  if($name -notlike ('*'+$id+'*')){throw 'Invalid fixture cleanup target'}
  if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}
 }
 Send-AShellDesktopRefresh;Start-Sleep -Milliseconds 500
 & $helper restore $original
 if($LASTEXITCODE){Write-Warning "Restore original desktop visibility manually; backup: $original"}
}
