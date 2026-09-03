function Test-AShellAdministrator {
 return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function ConvertTo-AShellPowerShellLiteral([object]$Value) {
 if($null -eq $Value){return '$null'}
 if($Value -is [bool]){if($Value){return '$true'}else{return '$false'}}
 return "'"+([string]$Value).Replace("'","''")+"'"
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
 $titleLiteral=ConvertTo-AShellPowerShellLiteral $Title
 $worker=@"
`$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
try {[Console]::Title=$titleLiteral}catch{}
try {
 $invoke
 exit 0
} catch {
 Write-Host ('[ERROR] '+`$_.Exception.Message) -ForegroundColor Red
 exit 1
}
"@
 # EncodedCommand avoids cmd.exe quoting edge cases for paths/arguments and avoids
 # writing a user-writable temporary script that would then be executed elevated.
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker))
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 # UAC elevates cmd.exe. PowerShell runs inside that visible Administrator Command
 # Prompt, so the user always sees progress instead of waiting on a hidden worker.
 $cmdArgs='/d /s /c ""'+$ps+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$encoded+'"'
 try {
  try {$p=Start-Process -FilePath $env:ComSpec -Verb RunAs -ArgumentList $cmdArgs -Wait -PassThru -ErrorAction Stop}
  catch [ComponentModel.Win32Exception] {
   if($_.Exception.NativeErrorCode -eq 1223){throw 'Administrator approval was cancelled.'}
   throw
  }
  return [int]$p.ExitCode
 } catch {throw}
}
