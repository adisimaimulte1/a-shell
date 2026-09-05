$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'scripts\Desktop.Support.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ashell-desktop-tests-'+[guid]::NewGuid().ToString('N'))
$realDesktop=Join-Path $fixture 'desktop-real'
$desktopLink=Join-Path $fixture 'desktop-link'
$archive=Join-Path $fixture 'original_desktop'
try {
 New-Item -ItemType Directory -Path $realDesktop,$archive -Force | Out-Null
 New-Item -ItemType Junction -Path $desktopLink -Target $realDesktop | Out-Null
 # OneDrive Known Folder Move and redirected Desktop roots are valid in the
 # current hide-only design, provided the old archive is a separate path.
 Assert-AShellDesktopRoots $desktopLink $archive

 $childTarget=Join-Path $fixture 'child-target'
 $childLink=Join-Path $realDesktop 'CloudOrLinkedFolder'
 New-Item -ItemType Directory -Path $childTarget -Force | Out-Null
 New-Item -ItemType Junction -Path $childLink -Target $childTarget | Out-Null
 $journal=Join-Path $fixture 'journal.clixml'
 $linked=@{Desktop=$realDesktop;Archive=$archive;Entries=@([pscustomobject]@{Name='CloudOrLinkedFolder';ArchivedName='CloudOrLinkedFolder';State='Planned';IsDirectory=$true})}
 $blocked=$false
 try {Move-AShellDesktopItems $linked $journal}catch{$blocked=$_.Exception.Message -like '*Legacy desktop link needs manual handling*'}
 if(!$blocked){throw 'Legacy recovery attempted to move a linked/reparse Desktop item.'}

 Set-Content -LiteralPath (Join-Path $realDesktop 'note.txt') -Value 'fixture'
 $normal=@{Desktop=$realDesktop;Archive=$archive;Entries=@([pscustomobject]@{Name='note.txt';ArchivedName='note.txt';State='Planned';IsDirectory=$false})}
 Move-AShellDesktopItems $normal $journal
 if(!(Test-Path -LiteralPath (Join-Path $archive 'note.txt'))){throw 'Legacy file was not archived.'}
 $conflicts=@(Restore-AShellDesktopItems $normal $journal)
 if($conflicts.Count -or !(Test-Path -LiteralPath (Join-Path $realDesktop 'note.txt'))){throw 'Legacy file was not restored.'}
 Write-Output '[OK] Redirected Desktop roots are accepted; legacy links are blocked and ordinary legacy files restore safely.'
}
finally {
 if(Test-Path -LiteralPath $childLink){[IO.Directory]::Delete($childLink)}
 if(Test-Path -LiteralPath $desktopLink){[IO.Directory]::Delete($desktopLink)}
 if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
