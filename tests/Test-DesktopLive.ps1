# Creates uniquely named test items on the real Desktop, verifies A-Shell hides the
# desktop view without moving those files, then restores the original view/layout.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Appearance.Helpers.ps1')
. (Join-Path $root 'scripts\Desktop.Support.ps1')
$id=[guid]::NewGuid().ToString('N')
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
$test=Join-Path $root ('state\live-tests\desktop-'+$id);New-Item -ItemType Directory $test -Force | Out-Null
$helper=Join-Path $root 'bin\DesktopLayout.exe'
$original=Join-Path $test 'before.bin';$shown=Join-Path $test 'shown.bin';$layout=Join-Path $test 'items.bin';$hidden=Join-Path $test 'hidden.bin';$afterPath=Join-Path $test 'after.bin'
$originalHideIcons=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
& $helper save $original;if($LASTEXITCODE){throw 'Cannot save initial desktop state'}
$names=@(('AShell-Test-'+$id+'.txt'),('AShell-Folder-'+$id))
function Read-Layout($Path){
 $r=[IO.BinaryReader]::new([IO.File]::OpenRead($Path));$result=@{};$flags=0
 try {$null=$r.ReadUInt32();$flags=$r.ReadUInt32();$count=$r.ReadUInt32();for($i=0;$i -lt $count;$i++){$n=$r.ReadUInt32();$name=[Text.Encoding]::Unicode.GetString($r.ReadBytes(2*$n));$result[$name]=@($r.ReadInt32(),$r.ReadInt32())}}finally{$r.Dispose()}
 return @{Flags=$flags;Items=$result}
}
try {
 # Temporarily show desktop icons even if the test account normally hides them.
 $bytes=[IO.File]::ReadAllBytes($original);$flags=[BitConverter]::ToUInt32($bytes,4) -band (-bnot 0x1000)
 [BitConverter]::GetBytes([uint32]$flags).CopyTo($bytes,4);[IO.File]::WriteAllBytes($shown,$bytes)
 Write-RegistryValue @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideIcons';Kind='DWord';Exists=$true;Value=0}
 & $helper restore $shown;if($LASTEXITCODE){throw 'Could not show the test desktop'}

 Set-Content -LiteralPath (Get-AShellChildPath $desktop $names[0]) 'A-Shell hide-only desktop test'
 $folder=Get-AShellChildPath $desktop $names[1];New-Item -ItemType Directory $folder | Out-Null
 Set-Content -LiteralPath (Join-Path $folder 'nested.txt') 'A-Shell nested hide-only test'
 Send-AShellDesktopRefresh;Start-Sleep -Seconds 1
 & $helper save $layout;if($LASTEXITCODE){throw 'Could not capture test item positions'}

 # Put the two fixtures at deliberate non-grid positions so restore still verifies
 # exact coordinates; no file-system operation should be involved in hiding them.
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
 $before=(Read-Layout $layout).Items
 if(@($before.Keys | Where-Object {$_ -like ('*'+$id+'*')}).Count -ne 2){throw 'Explorer did not enumerate both test icons'}

 Hide-AShellDesktopIconsNow $root
 Start-Sleep -Milliseconds 300
 if(!(Test-Path -LiteralPath (Join-Path $desktop $names[0])) -or !(Test-Path -LiteralPath $folder)){throw 'Hiding the desktop moved or removed a test item.'}
 if((Get-Content -LiteralPath (Join-Path $folder 'nested.txt')) -ne 'A-Shell nested hide-only test'){throw 'Nested Desktop file changed while icons were hidden.'}
 & $helper save $hidden;if($LASTEXITCODE){throw 'Could not inspect hidden desktop view'}
 if(((Read-Layout $hidden).Flags -band 0x1000) -eq 0){throw 'Explorer desktop view did not enter FWF_NOICONS mode.'}
 $hideValue=Read-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideIcons'
 if(!$hideValue.Exists -or [int]$hideValue.Value -ne 1){throw 'Persistent HideIcons preference was not set.'}

 # Restore original visible test layout and verify coordinates remained intact because
 # files never left the Desktop (including when Desktop is OneDrive-redirected).
 & $helper restore $layout;if($LASTEXITCODE){throw 'Position/view restore failed'}
 Write-RegistryValue @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideIcons';Kind='DWord';Exists=$true;Value=0}
 Send-AShellDesktopRefresh;Start-Sleep -Milliseconds 500
 & $helper save $afterPath;if($LASTEXITCODE){throw 'Position readback failed'}
 $after=(Read-Layout $afterPath).Items
 foreach($name in $before.Keys | Where-Object {$_ -like ('*'+$id+'*')}){
  if(!$after.ContainsKey($name) -or $before[$name][0] -ne $after[$name][0] -or $before[$name][1] -ne $after[$name][1]){throw "Position mismatch: $name"}
 }
 'PASS: desktop icons hidden through Explorer view + HideIcons; files stayed in place; exact icon positions and nested file contents survived.' | Tee-Object -FilePath (Join-Path $root 'state\desktop-live-test.txt')
} finally {
 foreach($name in $names){
  $path=Get-AShellChildPath $desktop $name
  if($name -notlike ('*'+$id+'*')){throw 'Invalid fixture cleanup target'}
  if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}
 }
 Write-RegistryValue $originalHideIcons
 Send-AShellDesktopRefresh;Start-Sleep -Milliseconds 300
 & $helper restore $original
 if($LASTEXITCODE){Write-Warning "Restore original desktop visibility/layout manually; backup: $original"}
}
