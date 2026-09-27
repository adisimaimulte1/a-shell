$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Appearance.Helpers.ps1')
. (Join-Path $root 'scripts\Color.Support.ps1')
$presets=@(Get-AShellColorPresets)
if($presets.Count -lt 400){throw 'The included color range is too small.'}
if((Resolve-AShellColor 'vynil').Name -ne 'vinyl' -or (Resolve-AShellColor 'sky blue').Name -ne 'sky-blue'){throw 'Expected friendly preset aliases are missing.'}
$rainbow=Resolve-AShellColor 'rainbow'
if($rainbow.Hex -ne 'FFFFFF' -or $rainbow.Rain -ne 'rainbow' -or $rainbow.Stored -ne 'RAINBOW'){throw 'Rainbow must use a white Windows accent and rainbow rain mode.'}
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
