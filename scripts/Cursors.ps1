param([ValidateSet('Apply','Restore','Check')][string]$Action='Check')
$ErrorActionPreference='Stop'
$cursorRoot=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'Appearance.Helpers.ps1')
$cursorSource=Join-Path $cursorRoot 'assets\cursors'
$cursorState=Join-Path $cursorRoot 'state\cursors-before.clixml'
$cursorKey='HKCU:\Control Panel\Cursors'
$schemeName='Material Design Pure Dark v2 by Jepri Creations (A-Shell)'
$cursorMap=[ordered]@{Arrow='pointer.cur';Help='help.cur';AppStarting='working.ani';Wait='busy.ani';Crosshair='precision.cur';IBeam='beam.cur';NWPen='handwriting.cur';No='unavailable.cur';SizeNS='vert.cur';SizeWE='horz.cur';SizeNWSE='dgn1.cur';SizeNESW='dgn2.cur';SizeAll='move.cur';UpArrow='alternate.cur';Hand='link.cur';Person='person.cur';Pin='pin.cur'}
if($Action -in @('Apply','Check')) {
 foreach($file in $cursorMap.Values) {
  $path=Join-Path $cursorSource $file
  if(!(Test-Path -LiteralPath $path)){throw "Missing cursor: $file"}
  $bytes=[IO.File]::ReadAllBytes($path)
  if($file.EndsWith('.cur')) {
   if($bytes.Length -lt 22 -or [BitConverter]::ToUInt16($bytes,0) -ne 0 -or [BitConverter]::ToUInt16($bytes,2) -ne 2){throw "Invalid cursor file: $file"}
  } elseif($bytes.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'RIFF' -or [Text.Encoding]::ASCII.GetString($bytes,8,4) -ne 'ACON'){throw "Invalid animated cursor: $file"}
 }
}
if($Action -eq 'Check'){Write-Output 'All 17 cursor files validated.';return}
if($Action -eq 'Apply') {
 if(!(Test-Path $cursorState)) {
  $values=@(foreach($name in @($cursorMap.Keys)+@('','Scheme Source')){Read-RegistryValue $cursorKey $name})
  $values+=Read-RegistryValue "$cursorKey\Schemes" $schemeName
  New-Item -ItemType Directory (Split-Path $cursorState) -Force | Out-Null
  @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Values=$values} | Export-Clixml $cursorState
 }
 $saved=Import-Clixml $cursorState
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
 # Separate files prevent overwriting an existing cursor scheme.
 $destination=Join-Path $env:LOCALAPPDATA 'A-Shell\Cursors\MaterialPureDarkV2'
 New-Item -ItemType Directory $destination -Force | Out-Null
 foreach($entry in $cursorMap.GetEnumerator()) {
  $file=Join-Path $destination $entry.Value
  if(!(Test-Path $file) -or (Get-FileHash $file).Hash -ne (Get-FileHash (Join-Path $cursorSource $entry.Value)).Hash){Copy-Item -LiteralPath (Join-Path $cursorSource $entry.Value) -Destination $file -Force}
  Write-RegistryValue @{Path=$cursorKey;Name=$entry.Key;Kind='ExpandString';Value=$file;Exists=$true}
 }
 $scheme=(@($cursorMap.Values | ForEach-Object {Join-Path $destination $_}) -join ',')
 Write-RegistryValue @{Path="$cursorKey\Schemes";Name=$schemeName;Kind='String';Value=$scheme;Exists=$true}
 Write-RegistryValue @{Path=$cursorKey;Name='';Kind='String';Value=$schemeName;Exists=$true}
 Write-RegistryValue @{Path=$cursorKey;Name='Scheme Source';Kind='DWord';Value=1;Exists=$true}
} else {
 if(!(Test-Path $cursorState)){return}
 $saved=Import-Clixml $cursorState
 if($saved.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Cursor backup belongs to another account.'}
 foreach($value in $saved.Values){Write-RegistryValue $value}
}
Update-SystemCursors
Write-Output "Cursors: $Action complete."
