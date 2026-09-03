$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\Desktop.Support.ps1"
function Assert($Condition,$Message){if(!$Condition){throw $Message}}
function MustFail([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};Assert $failed 'Unsafe path was accepted'}
for($i=0;$i -lt 16;$i++){Assert ([AShellFileTags]::IsCloud([uint32](2415919130+$i*4096))) 'Cloud tag rejected'}
foreach($tag in @([uint32]2684354563,[uint32]2684354572,[uint32]2415919131,[uint32]0)){Assert (![AShellFileTags]::IsCloud($tag)) 'Non-cloud tag accepted'}
$fixture=Join-Path $root ('state\tests\paths-'+[guid]::NewGuid().ToString('N'))
$desktop=Join-Path $fixture 'Desktop';$archive=Join-Path $fixture 'archive'
New-Item -ItemType Directory $desktop,$archive|Out-Null
Assert ((Get-AShellReparseTag $desktop) -eq 0) 'Ordinary folder metadata failed'
Assert-AShellDesktopRoots $desktop $archive
$junction=Join-Path $fixture 'junction'
New-Item -ItemType Junction -Path $junction -Value $desktop|Out-Null
Assert ((Get-AShellReparseTag $junction) -eq [uint32]2684354563) 'Junction tag read failed'
MustFail {Assert-AShellDesktopRoots $junction $archive}
MustFail {Assert-AShellDesktopRoots $desktop (Join-Path $junction 'not-created')}
MustFail {Assert-AShellDesktopRoots $desktop (Join-Path $desktop 'nested')}
# Exercise the real policy against simulated Cloud Files metadata. This does not
# manufacture cloud reparse points or change OneDrive registration on this PC.
function Get-Item {
 param([string]$LiteralPath,[switch]$Force,[string]$ErrorAction)
 $item=Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -Force -ErrorAction $ErrorAction
 if($item -and $LiteralPath -in @($desktop,$archive,(Join-Path $desktop 'cloud.txt'))){return [pscustomobject]@{FullName=$item.FullName;Attributes=([IO.FileAttributes]::ReparsePoint)}}
 $item
}
function Get-AShellReparseTag([string]$Path){if($Path -in @($desktop,$archive,(Join-Path $desktop 'cloud.txt'))){return [uint32]2415947802};[AShellFileTags]::Read($Path)}
Assert-AShellDesktopRoots $desktop $archive
Set-Content (Join-Path $desktop 'cloud.txt') 'fixture contents'
$saved=@{Desktop=$desktop;Archive=$archive;Entries=@(@{Name='cloud.txt';ArchivedName='cloud.txt';State='Planned';IsDirectory=$false})}
$journal=Join-Path $fixture 'journal.clixml'
Move-AShellDesktopItems $saved $journal
Assert (Test-Path (Join-Path $archive 'cloud.txt')) 'Cloud policy prevented journaled move'
$conflicts=@(Restore-AShellDesktopItems $saved $journal)
Assert (!$conflicts.Count -and (Get-Content (Join-Path $desktop 'cloud.txt')) -eq 'fixture contents') 'Restore lost contents'
MustFail {Assert-AShellDesktopRoots $junction $archive}
'PASS: 16 cloud tags, native ordinary/junction metadata, junction ancestors, overlap rejection, simulated cloud-root/item archive and restore.'
# Remove only the fixture link itself, never its target or a recursive tree.
[IO.Directory]::Delete($junction)
