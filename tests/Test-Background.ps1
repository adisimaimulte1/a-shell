# Exercise production background transactions with fake Windows setters.
# All image copies and state stay in a fixture directory; no appearance changes.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'scripts\Background.Support.ps1')
function Assert($ok,$message){if(!$ok){throw $message}}
$fixture=Join-Path $root ('state\tests\background-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$original=Join-Path $fixture 'original.png';$next=Join-Path $fixture 'next image.png'
Copy-Item -LiteralPath (Join-Path $root 'assets\LockScreenPicture.png') -Destination $original
Copy-Item -LiteralPath (Join-Path $root 'assets\profile\personal-icon.png') -Destination $next
$script:desktopPath=$original;$script:lockPath=$original;$script:failure=$false;$script:notifications=0
function Get-AShellLockSource {return $script:lockPath}
function Save-LockImage($Path){Copy-Item -LiteralPath $script:lockPath -Destination $Path}
function Read-RegistryValue($Path,$Name){return @{Path=$Path;Name=$Name;Exists=$true;Kind='String';Value=$(if($Name -eq 'Wallpaper'){$script:desktopPath}else{'original value'})}}
function Write-RegistryValue($Item){}
function Get-AShellColorValues {return @{Path='fake';Name='Accent';Value='12AB34';Exists=$true;Kind='String'}}
function Send-AShellColorChange {$script:notifications++}
function Set-DesktopImage($Path){$script:desktopPath=$Path}
function Set-LockImage($Path){if($script:failure){$script:failure=$false;throw 'Injected lock setter failure'};$script:lockPath=$Path}
Set-AShellBackground $fixture $next
Assert ($script:desktopPath -eq $script:lockPath) 'All backgrounds must use one owned image.'
Assert ((Get-FileHash -LiteralPath $script:desktopPath).Hash -eq (Get-FileHash -LiteralPath $next).Hash) 'Source pixels must not be edited.'
$baseline=Join-Path $fixture 'state\background-before'
$baselineHash=(Get-FileHash -LiteralPath (Join-Path $baseline 'background.clixml')).Hash
$previous=$script:desktopPath
$script:failure=$true;$failed=$false
try {Set-AShellBackground $fixture $original}catch{$failed=$true}
Assert $failed 'Setter failure should propagate.'
Assert ($script:desktopPath -eq $previous -and $script:lockPath -eq $previous) 'Partial setter failure must roll back both screens.'
Assert ((Get-FileHash -LiteralPath (Join-Path $baseline 'background.clixml')).Hash -eq $baselineHash) 'First backup must not be overwritten.'
Restore-AShellBackground $baseline
Assert ($script:desktopPath -eq $original -and $script:lockPath -eq $original) 'Restore should reuse an unchanged original source.'
$originalHash=(Get-FileHash -LiteralPath $original).Hash
Copy-Item -LiteralPath $next -Destination $original -Force
Restore-AShellBackground $baseline
Assert ((Get-FileHash -LiteralPath $script:desktopPath).Hash -eq $originalHash) 'Changed original source should use the saved desktop bytes.'
Assert ((Get-FileHash -LiteralPath $script:lockPath).Hash -eq $originalHash) 'Changed lock source should use its saved copy.'
Assert ($script:notifications -gt 0) 'Shared accent should be preserved/notified.'
$invalid=Join-Path $fixture 'bad.png';Set-Content -LiteralPath $invalid 'not an image'
$before=$script:desktopPath;$failed=$false
try {Set-AShellBackground $fixture $invalid}catch{$failed=$true}
Assert ($failed -and $script:desktopPath -eq $before) 'Invalid image must fail without changing backgrounds.'
Write-Output 'PASS: same-image backgrounds, source byte preservation, partial-failure rollback, immutable first backup, missing/changed-source fallback, invalid image rejection.'
