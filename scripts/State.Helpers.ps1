# Atomic state writes: the last complete journal survives an interrupted write.
function Save-AShellState($Data,[string]$Path) {
 New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try {
  $Data | Export-Clixml -LiteralPath $temp
  if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,$Path+'.previous')}
  else {[IO.File]::Move($temp,$Path)}
 } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Assert-AShellAccount($Data) {
 if($Data.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'This backup belongs to another Windows account.'}
}
function Enter-AShellOperation {
 $script:operationAcquired=$false
 $script:operationMutex=New-Object Threading.Mutex($false,'Local\AShellAppearanceOperation')
 try {$acquired=$script:operationMutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$acquired=$true}
 if(!$acquired){$script:operationMutex.Dispose();throw 'Another A-Shell operation is running. Wait for it to finish.'}
 $script:operationAcquired=$true
}
function Exit-AShellOperation {
 if($script:operationAcquired){$script:operationMutex.ReleaseMutex();$script:operationMutex.Dispose();$script:operationMutex=$null;$script:operationAcquired=$false}
}
