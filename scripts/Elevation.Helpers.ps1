function Test-AShellAdministrator {
 return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function ConvertTo-AShellPowerShellLiteral([object]$Value) {
 if($null -eq $Value){return '$null'}
 if($Value -is [bool]){if($Value){return '$true'}else{return '$false'}}
 return "'"+([string]$Value).Replace("'","''")+"'"
}
function Write-AShellElevatedOutputLine([string]$Line) {
 if($null -eq $Line){return}
 $color='Gray'
 if($Line -match '^\s*\[OK\]'){$color='Green'}
 elseif($Line -match '^\s*\[(ERROR|FAILED)\]' -or $Line -match '^\s*FAILED:'){$color='Red'}
 elseif($Line -match '^\s*\[WORKING\]'){$color='Yellow'}
 elseif($Line -match '^\s*\[STATUS\]'){$color='Cyan'}
 elseif($Line -match '^\s*\[SKIP\]'){$color='DarkYellow'}
 elseif($Line -match '^\s*WARNING:'){$color='Yellow'}
 elseif($Line -match '^\s*### STEP '){$color='DarkYellow'}
 elseif($Line -match '^\s*#{20,}\s*$'){$color='DarkGray'}
 Write-Host $Line -ForegroundColor $color
}
function Invoke-AShellElevatedScript {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$ScriptPath,
  [hashtable]$Parameters=@{},
  [string]$Title='A-Shell - Administrator'
 )
 if(Test-AShellAdministrator){throw 'Invoke-AShellElevatedScript was called from an already elevated process.'}
 $scriptPath=[IO.Path]::GetFullPath($ScriptPath)
 if(!(Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw "Elevation target not found: $scriptPath"}

 $invoke="& "+(ConvertTo-AShellPowerShellLiteral $scriptPath)
 foreach($name in $Parameters.Keys | Sort-Object){
  $value=$Parameters[$name]
  if($value -is [Management.Automation.SwitchParameter]){if($value.IsPresent){$invoke+=' -'+$name};continue}
  if($value -is [bool]){if($value){$invoke+=' -'+$name};continue}
  if($null -ne $value){$invoke+=' -'+$name+' '+(ConvertTo-AShellPowerShellLiteral $value)}
 }

 # The elevated worker is deliberately hidden. UAC still appears, but the user's
 # current terminal remains the only terminal window. The worker mirrors every
 # output line through a small per-call text channel so progress and failures stay
 # visible in the terminal where `ashell` was invoked.
 $channel=Join-Path $env:TEMP ('A-Shell-Elevation-'+[guid]::NewGuid().ToString('N')+'.log')
 $channelLiteral=ConvertTo-AShellPowerShellLiteral $channel
 $titleLiteral=ConvertTo-AShellPowerShellLiteral $Title
 $worker=@"
`$ErrorActionPreference='Stop'
try {[Console]::OutputEncoding=[Text.UTF8Encoding]::new(`$false)}catch{}
try {[Console]::Title=$titleLiteral}catch{}
`$channel=$channelLiteral
`$utf8=[Text.UTF8Encoding]::new(`$false)
function Write-AShellParentLine([object]`$Item) {
 `$text=if(`$null -eq `$Item){''}elseif(`$Item -is [Management.Automation.ErrorRecord]){('[ERROR] '+`$Item.Exception.Message)}else{[string]`$Item}
 foreach(`$line in (`$text -split '\r?\n')){
  if(`$line.Length -or `$text.Length -eq 0){[IO.File]::AppendAllText(`$channel,`$line+[Environment]::NewLine,`$utf8)}
 }
}
try {
 $invoke *>&1 | ForEach-Object {Write-AShellParentLine `$_}
 exit 0
} catch {
 Write-AShellParentLine ('[ERROR] '+`$_.Exception.Message)
 exit 1
}
"@
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker))
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $arguments=@('-NoLogo','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)
 $shown=0
 function Show-AShellElevatedOutput([ref]$Shown) {
  if(!(Test-Path -LiteralPath $channel)){return}
  try {$lines=@(Get-Content -LiteralPath $channel -Encoding UTF8 -ErrorAction Stop)}catch{return}
  while($Shown.Value -lt $lines.Count){Write-AShellElevatedOutputLine ([string]$lines[$Shown.Value]);$Shown.Value++}
 }
 try {
  try {$p=Start-Process -FilePath $ps -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru -ErrorAction Stop}
  catch [ComponentModel.Win32Exception] {
   if($_.Exception.NativeErrorCode -eq 1223){throw 'Administrator approval was cancelled.'}
   throw
  }
  while(!$p.HasExited){Show-AShellElevatedOutput ([ref]$shown);Start-Sleep -Milliseconds 70}
  $p.WaitForExit()
  Show-AShellElevatedOutput ([ref]$shown)
  return [int]$p.ExitCode
 } finally {
  Remove-Item -LiteralPath $channel -Force -ErrorAction SilentlyContinue
 }
}
