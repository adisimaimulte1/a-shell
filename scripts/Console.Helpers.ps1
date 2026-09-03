function Write-AShellHeading([string]$Title) {
 Write-Host ''
 Write-Host '  A-SHELL ' -NoNewline -ForegroundColor Black -BackgroundColor DarkYellow
 Write-Host ('  '+$Title) -ForegroundColor White
 Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray
}
function Write-AShellLine([string]$Text) {
 if($Text -match '^\[(OK|ERROR|WORKING|STATUS|SKIP)\]\s*(.*)$') {
  $kind=$Matches[1];$body=$Matches[2]
  $color=switch($kind){OK{'Green'} ERROR{'Red'} WORKING{'Yellow'} STATUS{'Cyan'} SKIP{'DarkYellow'}}
  Write-Host ('  '+$kind.PadRight(9)) -NoNewline -ForegroundColor $color
  Write-Host $body -ForegroundColor Gray
 } else {Write-Host ('  '+$Text) -ForegroundColor Gray}
}
function Write-AShellCommand([string]$Command,[string]$Description) {
 $width=40
 if($Command.Length -ge $width){
  Write-Host ('  '+$Command) -ForegroundColor Cyan
  Write-Host ('      '+$Description) -ForegroundColor Gray
 } else {
  Write-Host ('  '+$Command.PadRight($width)) -ForegroundColor Cyan -NoNewline
  Write-Host $Description -ForegroundColor Gray
 }
}
