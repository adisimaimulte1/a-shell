$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Appearance.Helpers.ps1')
. (Join-Path $root 'scripts\Color.Support.ps1')
$presets=@(Get-AShellColorPresets)
if($presets.Count -lt 160){throw 'The included color range is too small.'}
if((Resolve-AShellColor 'vynil').Name -ne 'vinyl' -or (Resolve-AShellColor 'sky blue').Name -ne 'sky-blue'){throw 'Expected friendly preset aliases are missing.'}
if((Resolve-AShellColor 'icy blue').Name -ne 'icy-blue' -or (Resolve-AShellColor 'lilac').Name -ne 'lila'){throw 'The icy-blue and lila presets or aliases are missing.'}
$fruitNames=@('apple','apricot','banana','blackberry','blueberry','cherry','cranberry','grape','kiwi','lemon','mango','papaya','pear','pineapple','pomegranate','raspberry','strawberry','tangerine','watermelon')
foreach($fruit in $fruitNames){if($presets.name -notcontains $fruit){throw "Fruit preset missing: $fruit"}}
if(@($presets|Where-Object {$_.description -match ' shade [0-9]+$' -or $_.name -match '(^|-)purple($|-)|(^|-)orange($|-)'}).Count){throw 'Retired shade, purple or orange presets remain.'}
$sorted=@(Get-AShellVarietySortedColorPresets)
if($sorted.Count -ne $presets.Count -or $sorted[0].name -ne 'default' -or @($sorted.name|Select-Object -Unique).Count -ne $presets.Count){throw 'Variety sorting lost, duplicated or misplaced presets.'}
$swatch=Format-AShellColorSwatch '38BDF8'
if($swatch -notmatch ([regex]::Escape(([char]27)+'[38;2;56;189;248m')) -or $swatch -notmatch [char]0x25A0 -or (Format-AShellColorSwatch '38BDF8' $false)){throw 'True-color preset swatch formatting is incorrect.'}
$rainbow=Resolve-AShellColor 'rainbow'
if($rainbow.Hex -ne 'FFFFFF' -or $rainbow.Rain -ne 'rainbow' -or $rainbow.Stored -ne 'RAINBOW'){throw 'Rainbow must use a white Windows accent and rainbow rain mode.'}
$strawberry=Resolve-AShellColor 'strawberry'
if($strawberry.Hex -ne 'E4475B'){throw 'Strawberry brand preset is incorrect.'}
$initial=Get-AShellColorValues
$pidBefore=(Get-Process MatrixDesktop).Id
$baseline=Join-Path $root 'state\accent-before.clixml'
$baselineHash=if(Test-Path $baseline){(Get-FileHash $baseline).Hash}else{''}
try {
 foreach($hex in @('00AAFF','00CC66','D65A00')) {
  & (Join-Path $root 'scripts\Color.ps1') -Color $hex
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Read-Accent.ps1') -Expected $hex
  if($LASTEXITCODE){throw 'Windows accent did not update.'}
  if((Get-Process MatrixDesktop).Id -ne $pidBefore){throw 'Color change restarted the renderer.'}
 }
 $previous=Get-AShellColorValues
 $rejected=$false
 try {& (Join-Path $root 'scripts\Color.ps1') -Color 'not-a-color'}catch{$rejected=$true}
 if(!$rejected){throw 'Invalid color was accepted.'}
 $after=Get-AShellColorValues
 for($i=0;$i -lt $previous.Count;$i++){if([string]$after[$i].Value -ne [string]$previous[$i].Value){throw 'Invalid color changed settings.'}}
 & (Join-Path $root 'scripts\Color.ps1') -Action Restore
 $saved=Import-Clixml $baseline
 foreach($value in $saved.Values) {
  $actual=Read-RegistryValue $value.Path $value.Name
  if($actual.Exists -ne $value.Exists -or ($value.Exists -and ($actual.Kind -ne $value.Kind -or [string]$actual.Value -ne [string]$value.Value))){throw "Accent restore mismatch: $($value.Name)"}
 }
 if($baselineHash -and (Get-FileHash $baseline).Hash -ne $baselineHash){throw 'Original accent backup changed.'}
 'PASS: three live colors, Windows UISettings readback, same renderer PID, invalid input rejection, original accent restore and stable backup.'
} finally {
 # Finish in the requested A-Shell default, including if a test fails.
 & (Join-Path $root 'scripts\Color.ps1') -Color default
}
