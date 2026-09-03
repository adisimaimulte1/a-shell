. (Join-Path (Split-Path $PSScriptRoot) 'scripts\Desktop.Support.ps1')

$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('ashell-desktop-tests-'+[guid]::NewGuid().ToString('N'))
$realDesktop=Join-Path $root 'desktop-real'
$desktopLink=Join-Path $root 'desktop-link'
$otherTarget=Join-Path $root 'other-target'
$otherLink=Join-Path $root 'other-link'
$archive=Join-Path $root 'original_desktop'
$archiveTarget=Join-Path $root 'archive-target'
$archiveLink=Join-Path $root 'archive-link'

function Expect-Throw([scriptblock]$Block,[string]$Contains) {
 try {& $Block; throw "Expected failure containing: $Contains"}
 catch {
  if($_.Exception.Message -notlike "*$Contains*"){throw}
 }
}

try {
 New-Item -ItemType Directory -Path $realDesktop,$otherTarget,$archiveTarget -Force | Out-Null
 New-Item -ItemType Junction -Path $desktopLink -Target $realDesktop | Out-Null
 Assert-AShellDesktopRoots $desktopLink $archive $desktopLink

 New-Item -ItemType Junction -Path $otherLink -Target $otherTarget | Out-Null
 Expect-Throw {Assert-AShellDesktopRoots $otherLink $archive $desktopLink} 'custom desktop link'

 New-Item -ItemType Junction -Path $archiveLink -Target $archiveTarget | Out-Null
 Expect-Throw {Assert-AShellDesktopRoots $desktopLink $archiveLink $desktopLink} 'archive is a link/reparse point'

 Expect-Throw {Assert-AShellDesktopRoots $desktopLink (Join-Path $desktopLink 'archive') $desktopLink} 'separate folders'

 $childTarget=Join-Path $root 'child-target'
 $childLink=Join-Path $realDesktop 'CloudOrLinkedFolder'
 New-Item -ItemType Directory -Path $childTarget -Force | Out-Null
 New-Item -ItemType Junction -Path $childLink -Target $childTarget | Out-Null
 $child=Get-Item -LiteralPath $childLink -Force
 if(!($child.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Test child junction was not recognized as a reparse point.'}

 # Exercise the copy fallback on a normal directory.
 $src=Join-Path $root 'copy-source'
 $dst=Join-Path $root 'copy-target'
 New-Item -ItemType Directory -Path $src | Out-Null
 Set-Content -LiteralPath (Join-Path $src 'file.txt') -Value 'ok'
 Copy-AShellDirectorySafe $src $dst
 if(!(Test-Path -LiteralPath (Join-Path $dst 'file.txt'))){throw 'Directory copy fallback did not copy normal files.'}

 Write-Output '[OK] Redirected Desktop and move-fallback tests passed.'
}
finally {
 foreach($p in @($childLink,$otherLink,$desktopLink,$archiveLink)){
  if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
 }
 if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
