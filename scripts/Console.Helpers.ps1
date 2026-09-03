function Write-AShellHeading([string]$Title) {
 Write-Host ''
 Write-Host '  A-SHELL ' -NoNewline -ForegroundColor Black -BackgroundColor DarkYellow
 Write-Host ('  '+$Title) -ForegroundColor White
 Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray
}
function Write-AShellLine([string]$Text) {
 if($Text -match '^\[(OK|ERROR|WORKING|STATUS)\]\s*(.*)$') {
  $kind=$Matches[1];$body=$Matches[2]
  $color=switch($kind){OK{'Green'} ERROR{'Red'} WORKING{'Yellow'} STATUS{'Cyan'}}
  Write-Host ('  '+$kind.PadRight(9)) -NoNewline -ForegroundColor $color
  Write-Host $body -ForegroundColor Gray
 } else {Write-Host ('  '+$Text) -ForegroundColor Gray}
}
function Write-AShellCommand([string]$Command,[string]$Description) {
 Write-Host ('  '+$Command.PadRight(42)) -ForegroundColor Cyan -NoNewline
 Write-Host $Description -ForegroundColor Gray
}
