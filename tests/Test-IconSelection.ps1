$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\Icons.Support.ps1"
. "$root\scripts\Icon.Selection.ps1"
$fixture=Join-Path $root ('state\tests\selection-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory "$fixture\assets\icons","$fixture\state" -Force|Out-Null
'{}'|Set-Content "$fixture\assets\taskbar-base.json"
'{"version":1,"controls":[],"apps":[]}'|Set-Content "$fixture\assets\icon-map.json"
foreach($name in @('icons8-chrome-96.png','icons8-adobe-illustrator-96.png','icons8-opera-96.png','custom.png')){Copy-Item "$root\assets\logo\A-Shell_Logo_Original.png" "$fixture\assets\icons\$name"}
function Get-StartApps { @([pscustomobject]@{Name='Adobe Illustrator 2024';AppID='Illustrator.2024'},[pscustomobject]@{Name='Google Chrome';AppID='Chrome'},[pscustomobject]@{Name='Opera Browser';AppID='OperaStable'},[pscustomobject]@{Name='Unmatched app';AppID='Unknown.App'}) }
Add-AShellAutomaticIcons $fixture
$m=Get-Content "$fixture\assets\icon-map.json" -Raw|ConvertFrom-Json
if(@($m.apps).Count -ne 3 -or !(@($m.apps|Where-Object {$_.icon -eq 'icons8-adobe-illustrator-96.png'}).Count)){throw 'Automatic matching failed'}
if(($m.apps|Where-Object {$_.appIds -contains 'OperaStable'}).icon -ne 'icons8-opera-96.png'){throw 'Opera Browser generic/AppID matching failed'}
$hash=(Get-FileHash "$fixture\assets\icon-map.json").Hash
Add-AShellAutomaticIcons $fixture
if((Get-FileHash "$fixture\assets\icon-map.json").Hash -ne $hash){throw 'No-op matching rewrote mapping'}
Set-AShellIconSelection $fixture 'Google Chrome' 'custom.png'
Add-AShellAutomaticIcons $fixture
$m=Get-Content "$fixture\assets\icon-map.json" -Raw|ConvertFrom-Json
if(($m.apps|Where-Object {$_.appIds -contains 'Chrome'}).icon -ne 'custom.png'){throw 'Automatic matching overwrote custom choice'}
$hash=(Get-FileHash "$fixture\assets\icon-map.json").Hash
foreach($case in @(@('not installed','custom.png'),@('Google Chrome','..\custom.png'))) {
 $rejected=$false;try {Set-AShellIconSelection $fixture $case[0] $case[1]}catch{$rejected=$true};if(!$rejected){throw 'Invalid assignment accepted'}
}
if((Get-FileHash "$fixture\assets\icon-map.json").Hash -ne $hash){throw 'Rejected assignment mutated mapping'}
'PASS: automatic matching, no-op, custom override preservation, unknown apps and path rejection.'
$original=Join-Path $root 'assets\logo\A-Shell_Logo_Original.png'
Import-AShellIcon $fixture $original 'imported.png'
if((Get-FileHash $original).Hash -ne (Get-FileHash "$fixture\assets\icons\imported.png").Hash){throw 'Import changed image bytes'}
Import-AShellIcon $fixture $original 'imported.png'
Set-Content "$fixture\fake.png" 'not an image'
$rejected=$false;try {Import-AShellIcon $fixture "$fixture\fake.png" 'fake.png'}catch{$rejected=$true};if(!$rejected){throw 'Fake PNG accepted'}
$rejected=$false;try {Import-AShellIcon $fixture $original '..\outside.png'}catch{$rejected=$true};if(!$rejected){throw 'Invalid destination accepted'}
Copy-Item "$root\assets\LockScreenPicture.png" "$fixture\assets\icons\occupied.png"
$before=(Get-FileHash "$fixture\assets\icons\occupied.png").Hash
$rejected=$false;try {Import-AShellIcon $fixture $original 'occupied.png'}catch{$rejected=$true};if(!$rejected){throw 'Different existing icon overwritten'}
if((Get-FileHash "$fixture\assets\icons\occupied.png").Hash -ne $before){throw 'Collision changed icon'}
if((Get-AShellAppNameKey 'Adobe Illustrator 2024') -ne 'adobeillustrator'){throw 'Year normalization failed'}
if((Get-AShellAppNameKey 'Product 3D') -ne 'product3d'){throw 'Product number removed'}
'PASS: versioned Illustrator matching, byte-preserving import, repeat import, PNG validation and collision protection.'
# Explicit system-app aliases, exact-name precedence and ambiguous candidates.
foreach($name in @('icons8-bar-chart-96.png','icons8-terminal-96.png','icons8-codex-96.png','icons8-chatgpt-96.png','icons8-ambiguous-96.png','ambiguous.png')) {
 Copy-Item $original "$fixture\assets\icons\$name"
}
function Get-StartApps {
 @([pscustomobject]@{Name='Task Manager';AppID='TaskManager.Test'},
 [pscustomobject]@{Name='Terminal';AppID='Terminal.Test'},
 [pscustomobject]@{Name='Codex';AppID='Codex.Test'},
 [pscustomobject]@{Name='Ambiguous';AppID='Ambiguous.Test'},
 [pscustomobject]@{Name='KiCad 10.0 Command Prompt';AppID='KiCad.Test'})
}
Add-AShellAutomaticIcons $fixture
$m=Get-Content "$fixture\assets\icon-map.json" -Raw|ConvertFrom-Json
foreach($pair in @(@('TaskManager.Test','icons8-bar-chart-96.png'),@('Terminal.Test','icons8-terminal-96.png'),@('Codex.Test','icons8-codex-96.png'))) {
 if(($m.apps|Where-Object {$_.appIds -contains $pair[0]}).icon -ne $pair[1]){throw "Wrong icon for $($pair[0])"}
}
if($m.apps|Where-Object {$_.appIds -contains 'Ambiguous.Test' -or $_.appIds -contains 'KiCad.Test'}){throw 'Ambiguous or substring match accepted'}
'PASS: Task Manager chart, Terminal icon, exact-name priority and no ambiguous/substring guesses.'

# General publisher/product matching on both sides, not per-app Excel aliases.
foreach($name in @('icons8-microsoft-excel-96.png','icons8-microsoft-word-96.png','icons8-wordpress-96.png','icons8-adobe-photoshop-96.png','icons8-mozilla-firefox-96.png','icons8-microsoft-onenote-2019-96.png','icons8-microsoft-teams-2025-96.png','icons8-microsoft-designer-96.png','icons8-adobe-designer-96.png')) {
 Copy-Item $original "$fixture\assets\icons\$name"
}
$index=New-AShellIconIndex $fixture
foreach($case in @(
 @('Excel','Microsoft.Office.EXCEL.EXE.15','icons8-microsoft-excel-96.png'),
 @('Word','Microsoft.Office.WINWORD.EXE.15','icons8-microsoft-word-96.png'),
 @('Photoshop 2024','Adobe.Photoshop','icons8-adobe-photoshop-96.png'),
 @('Firefox','Firefox','icons8-mozilla-firefox-96.png'),
 @('OneNote','Microsoft.Office.ONENOTE.EXE.15','icons8-microsoft-onenote-2019-96.png'),
 @('Microsoft Teams','MSTeams_8wekyb3d8bbwe!MSTeams','icons8-microsoft-teams-2025-96.png'),
 @('Designer','Microsoft.Designer','icons8-microsoft-designer-96.png')
)) {
 $match=Find-AShellIcon $index ([pscustomobject]@{Name=$case[0];AppID=$case[1]}) @{}
 if($match.Icon -ne $case[2]){throw "Publisher/product match failed for $($case[0]): $($match.Icon)"}
}
foreach($case in @(@('Excel Viewer','Microsoft.ExcelViewer'),@('Adobe Excel','Adobe.Excel'),@('Designer','Unknown.Designer'),@('WordPad','Microsoft.WordPad'))) {
 $match=Find-AShellIcon $index ([pscustomobject]@{Name=$case[0];AppID=$case[1]}) @{}
 if($match.Icon){throw "False-positive icon: $($case[0]) -> $($match.Icon)"}
}
Copy-Item $original "$fixture\assets\icons\excel.png"
$match=Find-AShellIcon (New-AShellIconIndex $fixture) ([pscustomobject]@{Name='Excel';AppID='Microsoft.Office.EXCEL.EXE.15'}) @{}
if($match.Icon -ne 'excel.png'){throw 'Exact product did not outrank publisher fallback'}
'PASS: multi-publisher matching, versions on either side, identity disambiguation, exact priority and related-product false-positive rejection.'

foreach($name in 'icons8-powershell-96.png','icons8-odbc-data-sources-96.png','icons8-notepad-plus-plus-96.png','icons8-text-file-96.png') {Copy-Item $original "$fixture\assets\icons\$name"}
function Get-StartApps {
 @('Windows PowerShell','Windows PowerShell (x86)','Windows PowerShell ISE','Windows PowerShell ISE (x86)','ODBC Data Sources (32-bit)','ODBC Data Sources (64-bit)','Notepad++','Notepad') | ForEach-Object {[pscustomobject]@{Name=$_;AppID=('Audit.'+$_)}}
}
Add-AShellAutomaticIcons $fixture
$m=Get-Content "$fixture\assets\icon-map.json" -Raw|ConvertFrom-Json
foreach($app in Get-StartApps){
 $expected=if($app.Name -like '*PowerShell*'){'icons8-powershell-96.png'}elseif($app.Name -like 'ODBC*'){'icons8-odbc-data-sources-96.png'}elseif($app.Name -eq 'Notepad++'){'icons8-notepad-plus-plus-96.png'}else{'icons8-text-file-96.png'}
 if(($m.apps|Where-Object {$_.appIds -contains $app.AppID}).icon -ne $expected){throw "Audit match failed: $($app.Name)"}
}
$hash=(Get-FileHash "$fixture\assets\icon-map.json").Hash;Add-AShellAutomaticIcons $fixture
if((Get-FileHash "$fixture\assets\icon-map.json").Hash -ne $hash){throw 'Audit repeat rewrote mappings'}
'PASS: PowerShell variants, bitness normalization, distinct Notepad++/Notepad, stable repeated matching.'
