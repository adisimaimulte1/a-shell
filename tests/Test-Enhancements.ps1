# Isolated regression checks. No registry, desktop or taskbar mutations.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Icons.Support.ps1')
. (Join-Path $root 'scripts\Desktop.Support.ps1')
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
function MustThrow([scriptblock]$Action,[string]$Message){$failed=$false;try {& $Action | Out-Null}catch{$failed=$true};Assert $failed $Message}
$testRoot=Join-Path $root ('state\tests\fixtures-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$plan=Get-AShellIconPlan $root
$delta=Get-AShellIconDelta $plan.Settings $plan.Settings
Assert ($delta.Count -eq 0) 'An unchanged icon plan must produce zero writes.'
$reordered=@{};foreach($key in $plan.Settings.Keys){$reordered[$key]=$plan.Settings[$key]}
foreach($suffix in @('target','styles[0]')){$reordered["controlStyles[0].$suffix"]=$plan.Settings["controlStyles[1].$suffix"];$reordered["controlStyles[1].$suffix"]=$plan.Settings["controlStyles[0].$suffix"]}
$aligned=Align-AShellIconSlots $reordered $plan.Settings
Assert ((Get-AShellIconDelta $plan.Settings $aligned).Count -eq 0) 'Reordering the mapping file must not rewrite existing rules.'
$reordered['controlStyles[999].target']='Fixture.App > Image#Icon';$reordered['controlStyles[999].styles[0]']='Source=fixture.png'
$aligned=Align-AShellIconSlots $reordered $plan.Settings
Assert ((Get-AShellIconDelta $plan.Settings $aligned).Count -eq 2) 'Adding one mapping should only add its target/style pair.'
$changed=@{};foreach($key in $plan.Settings.Keys){$changed[$key]=$plan.Settings[$key]}
$changed['controlStyles[0].styles[0]']='Source=new.png'
$delta=Get-AShellIconDelta $plan.Settings $changed
Assert ($delta.Count -eq 1 -and $delta.Set.Count -eq 1) 'One changed icon must only change one setting.'
$changed.Remove('controlStyles[0].styles[0]')
$delta=Get-AShellIconDelta $plan.Settings $changed
Assert ($delta.Remove.Count -eq 1 -and $delta.Set.Count -eq 0) 'Removed mapping must remove its obsolete value.'
# A fixture map checks duplicate IDs, traversal and image cache invalidation.
$mapRoot=Join-Path $testRoot 'mapping';New-Item -ItemType Directory -Path (Join-Path $mapRoot 'assets\icons') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'assets\taskbar-base.json') -Destination (Join-Path $mapRoot 'assets\taskbar-base.json')
$sample=($plan.Assets.Values | Select-Object -First 1).Source
Copy-Item -LiteralPath $sample -Destination (Join-Path $mapRoot 'assets\icons\sample.png')
$mapping=@{version=1;apps=@(@{name='Fixture';icon='sample.png';appIds=@('Fixture.App')});controls=@()}
$mapPath=Join-Path $mapRoot 'assets\icon-map.json'
$mapping | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mapPath
$first=Get-AShellIconPlan $mapRoot
[IO.File]::AppendAllText((Join-Path $mapRoot 'assets\icons\sample.png'),'fixture change')
$second=Get-AShellIconPlan $mapRoot
Assert ($first.Assets['sample.png'].Path -ne $second.Assets['sample.png'].Path) 'New icon bytes must receive a new cache filename.'
$mapping.apps[0].appIds=@('Fixture.App','Fixture.App');$mapping | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mapPath
MustThrow {Get-AShellIconPlan $mapRoot} 'Duplicate exact IDs must be rejected.'
$mapping.apps[0].appIds=@('Fixture.App');$mapping.apps[0].icon='..\sample.png';$mapping | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mapPath
MustThrow {Get-AShellIconPlan $mapRoot} 'Icon paths cannot escape assets.'

$desktop=Join-Path $testRoot 'Desktop';$archive=Join-Path $testRoot 'original_desktop'
New-Item -ItemType Directory -Path $desktop,$archive -Force | Out-Null
Set-Content -LiteralPath (Join-Path $desktop 'notes.txt') 'original'
New-Item -ItemType Directory -Path (Join-Path $desktop 'Folder') | Out-Null
Set-Content -LiteralPath (Join-Path $desktop 'Folder\nested.txt') 'nested'
$saved=@{Desktop=$desktop;Archive=$archive;Entries=@(@{Name='notes.txt';ArchivedName='notes.txt';State='Planned';IsDirectory=$false},@{Name='Folder';ArchivedName='Folder';State='Planned';IsDirectory=$true})}
$journal=Join-Path $testRoot 'journal.clixml'
Save-AShellState $saved $journal
Move-AShellDesktopItems $saved $journal
Assert (!(Test-Path -LiteralPath (Join-Path $desktop 'notes.txt'))) 'Desktop file should be moved.'
Assert ((Get-Content -LiteralPath (Join-Path $archive 'Folder\nested.txt')) -eq 'nested') 'Folder contents must survive.'
Move-AShellDesktopItems $saved $journal
Set-Content -LiteralPath (Join-Path $desktop 'notes.txt') 'new conflicting file'
$conflicts=@(Restore-AShellDesktopItems $saved $journal)
Assert ($conflicts.Count -eq 1) 'Undo should report a collision and continue with other files.'
Assert ((Get-Content -LiteralPath (Join-Path $desktop 'notes.txt')) -eq 'new conflicting file') 'New desktop content must not be overwritten.'
Assert ((Get-Content -LiteralPath (Join-Path $archive 'notes.txt')) -eq 'original') 'Original archive content must survive a conflict.'
Remove-Item -LiteralPath (Join-Path $desktop 'notes.txt')
$conflicts=@(Restore-AShellDesktopItems $saved $journal)
Assert ($conflicts.Count -eq 0 -and (Get-Content -LiteralPath (Join-Path $desktop 'notes.txt')) -eq 'original') 'Undo retry must restore originals.'
$conflicts=@(Restore-AShellDesktopItems $saved $journal)
Assert ($conflicts.Count -eq 0) 'Repeated undo should do nothing.'
Move-AShellDesktopItems $saved $journal
# Crash after move, before journal commit.
$saved.Entries[0].State='Moving';Save-AShellState $saved $journal
Move-AShellDesktopItems $saved $journal
Assert ($saved.Entries[0].State -eq 'Archived') 'An interrupted successful move must be recoverable.'
$null=Restore-AShellDesktopItems $saved $journal
$saved.Entries[0].State='Restoring'
$null=Restore-AShellDesktopItems $saved $journal
Assert ($saved.Entries[0].State -eq 'Restored') 'An interrupted successful restore must be recoverable.'
Move-AShellDesktopItems $saved $journal
$null=Restore-AShellDesktopItems $saved $journal -OnlyNames @('notes.txt')
Assert ((Test-Path -LiteralPath (Join-Path $archive 'Folder\nested.txt')) -and (Test-Path -LiteralPath (Join-Path $desktop 'notes.txt'))) 'Failed reapply rollback must leave previously archived items alone.'
Assert ((Import-Clixml -LiteralPath $journal).Entries.Count -eq 2) 'Partial rollback must retain the complete journal.'
MustThrow {Get-AShellChildPath $desktop '..\outside'} 'Journal traversal must be rejected.'
MustThrow {Assert-AShellDesktopRoots $desktop (Join-Path $desktop 'archive')} 'Nested archive must be rejected.'
Write-Output 'PASS: unchanged/changed/deleted icon plans, asset cache invalidation, duplicate IDs, path validation, nested folders, repeated archive/undo, collisions, interrupted moves/restores.'
Write-Output "Fixtures retained in $testRoot"
