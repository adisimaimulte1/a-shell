$script:AShellAccentRgb='214;90;0'
$script:AShellSupportsVt=$false
try {
 $supports=$Host.UI.PSObject.Properties['SupportsVirtualTerminal']
 if($supports){$script:AShellSupportsVt=[bool]$supports.Value}
} catch {}

function Write-AShellAccent([string]$Text,[switch]$NoNewline) {
 if($script:AShellSupportsVt){
  $esc=[char]27
  $value=$esc+'[38;2;'+$script:AShellAccentRgb+'m'+$Text+$esc+'[0m'
  Write-Host $value -NoNewline:$NoNewline
 } else {
  Write-Host $Text -ForegroundColor DarkYellow -NoNewline:$NoNewline
 }
}
function Write-AShellHeading([string]$Title) {
 Write-Host ''
 Write-AShellAccent '  A-SHELL' -NoNewline
 Write-Host ('  '+$Title.ToUpperInvariant()) -ForegroundColor White
 Write-Host '  ----------------------------------------------' -ForegroundColor DarkGray
}
function Write-AShellLine([string]$Text) {
 if($null -eq $Text){return}
 if($Text -match '^\[(OK|ERROR|WORKING|STATUS|SKIP|INFO)\]\s*(.*)$') {
  $kind=$Matches[1];$body=$Matches[2]
  switch($kind){
   'OK'      {Write-Host '  +  ' -NoNewline -ForegroundColor Green}
   'ERROR'   {Write-Host '  x  ' -NoNewline -ForegroundColor Red}
   'WORKING' {Write-AShellAccent '  >  ' -NoNewline}
   'STATUS'  {Write-AShellAccent '  *  ' -NoNewline}
   'SKIP'    {Write-Host '  -  ' -NoNewline -ForegroundColor DarkGray}
   'INFO'    {Write-Host '  i  ' -NoNewline -ForegroundColor DarkCyan}
  }
  if($kind -eq 'STATUS' -and $body -match '^([^:]{1,28}):\s*(.*)$'){
   Write-AShellAccent ($Matches[1]+':') -NoNewline
   Write-Host (' '+$Matches[2]) -ForegroundColor Gray
  } else {
   $color=if($kind -eq 'ERROR'){'Red'}elseif($kind -eq 'SKIP'){'DarkGray'}else{'Gray'}
   Write-Host $body -ForegroundColor $color
  }
  return
 }
 if($Text -match '^WARNING:\s*(.*)$'){
  Write-Host '  !  ' -NoNewline -ForegroundColor Yellow
  Write-Host $Matches[1] -ForegroundColor Yellow
  return
 }
 Write-Host ('  '+$Text) -ForegroundColor Gray
}
function Write-AShellSection([string]$Title) {
 Write-Host ''
 Write-AShellAccent ('  '+$Title.ToUpperInvariant())
}
function Write-AShellCommand([string]$Command,[string]$Description) {
 Write-AShellAccent '  -  ' -NoNewline
 $remaining=$Command
 if($remaining.StartsWith('ashell',[StringComparison]::OrdinalIgnoreCase)) {
  Write-Host $remaining.Substring(0,6) -ForegroundColor White -NoNewline
  $remaining=$remaining.Substring(6)
 }
 $parts=[regex]::Split($remaining,'(\|)')
 foreach($part in $parts) {
  if($part -eq '|') {Write-Host $part -ForegroundColor White -NoNewline}
  elseif($part.Length -gt 0) {Write-AShellAccent $part -NoNewline}
 }
 if($Description){Write-Host ('  '+$Description) -ForegroundColor Gray}else{Write-Host ''}
}
