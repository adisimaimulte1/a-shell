. (Join-Path $PSScriptRoot 'State.Helpers.ps1')
function Get-AShellExternalManagementState {
 $reasons=@()
 try {
  $computer=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
  if($computer.PartOfDomain){$reasons+='Active Directory domain join'}
 } catch {}
 try {
  $dsreg=& (Join-Path $env:SystemRoot 'System32\dsregcmd.exe') /status 2>$null
  $text=($dsreg -join "`n")
  if($text -match '(?im)^\s*AzureAdJoined\s*:\s*YES\s*$'){$reasons+='Microsoft Entra device join'}
  if($text -match '(?im)^\s*EnterpriseJoined\s*:\s*YES\s*$'){$reasons+='enterprise device join'}
 } catch {}
 try {
  # Intune/other Windows MDM enrollment creates EnterpriseMgmt scheduled tasks.
  # A registered work account alone is not enough to classify the PC as managed.
  $mdm=@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskPath -like '\Microsoft\Windows\EnterpriseMgmt\*'})
  if($mdm.Count){$reasons+='MDM enrollment'}
 } catch {}
 return [pscustomobject]@{Managed=($reasons.Count -gt 0);Reasons=@($reasons)}
}

function Get-AShellMachineLockScreenRegistryValues {
 $items=@(
  @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization','LockScreenImage'),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization','NoChangingLockScreen'),
  @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP','LockScreenImagePath'),
  @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP','LockScreenImageUrl')
 )
 return @(foreach($item in $items){Read-RegistryValue $item[0] $item[1]})
}
function Test-AShellLegacyMachineLockScreenPath([string]$Value) {
 if([string]::IsNullOrWhiteSpace($Value)){return $false}
 $candidate=$Value.Trim()
 if($candidate.StartsWith('file:',[StringComparison]::OrdinalIgnoreCase)){try {$candidate=([Uri]$candidate).LocalPath}catch{return $false}}
 try {$candidate=[IO.Path]::GetFullPath($candidate)}catch{return $false}
 $legacyFolder=[IO.Path]::GetFullPath((Join-Path $env:ProgramData 'A-Shell\LockScreen')).TrimEnd('\')+'\'
 return $candidate.StartsWith($legacyFolder,[StringComparison]::OrdinalIgnoreCase)
}
function Restore-AShellLegacyMachineLockScreenPin([string]$Root) {
 # A legacy release briefly forced LockScreenImage/PersonalizationCSP values so the image
 # survived pre-login boot. That path changed Windows' framing/crop behavior.
 # Restore its saved machine values once, then delete the old staging folder.
 $baseline=Join-Path $Root 'state\machine-lockscreen-before.clixml'
 $changed=$false
 if(Test-Path -LiteralPath $baseline) {
  try {
   $saved=Import-Clixml -LiteralPath $baseline
   $currentValues=@(Get-AShellMachineLockScreenRegistryValues)
   $ownsLegacyImage=@($currentValues | Where-Object {$_.Exists -and (Test-AShellLegacyMachineLockScreenPath ([string]$_.Value))}).Count -gt 0
   # Restore the snapshot only while the old A-Shell path is still active. If
   # an administrator or management tool changed these values later, preserve
   # that newer choice instead of treating our old snapshot as authoritative.
   if($ownsLegacyImage){
    foreach($value in @($saved.Values)) {
     if($value.Name -eq 'LockScreenImageStatus'){continue}
     $current=Read-RegistryValue $value.Path $value.Name
     $different=($current.Exists -ne [bool]$value.Exists)
     if(!$different -and $value.Exists){$different=([string]$current.Value -ne [string]$value.Value)}
     if($different){Write-RegistryValue $value;$changed=$true}
    }
   }
   Remove-Item -LiteralPath $baseline -Force -ErrorAction SilentlyContinue
  } catch {Write-Warning "Could not fully migrate the old machine lock-screen pin: $($_.Exception.Message)"}
 } else {
  $current=@(Get-AShellMachineLockScreenRegistryValues)
  $ownsLegacyImage=@($current | Where-Object {$_.Exists -and (Test-AShellLegacyMachineLockScreenPath ([string]$_.Value))}).Count -gt 0
  if($ownsLegacyImage) {
   foreach($value in $current) {
    $remove=(Test-AShellLegacyMachineLockScreenPath ([string]$value.Value))
    if(!$remove -and $value.Name -eq 'NoChangingLockScreen' -and $value.Exists -and [string]$value.Value -notin @('','0')){$remove=$true}
    if($remove){
     Write-RegistryValue @{Path=$value.Path;Name=$value.Name;Kind=$value.Kind;Value=$null;Exists=$false}
     $changed=$true
    }
   }
  }
 }
 if($changed -and (Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue)){Send-AShellPolicyChange;Start-Sleep -Milliseconds 200}
 $legacyFolder=Join-Path $env:ProgramData 'A-Shell\LockScreen'
 if(Test-Path -LiteralPath $legacyFolder -PathType Container) {
  $stillReferenced=@(Get-AShellMachineLockScreenRegistryValues | Where-Object {$_.Exists -and (Test-AShellLegacyMachineLockScreenPath ([string]$_.Value))}).Count -gt 0
  if(!$stillReferenced){Remove-Item -LiteralPath $legacyFolder -Recurse -Force -ErrorAction SilentlyContinue}
 }
 return $changed
}

function Get-AShellLockScreenPolicyHandoff {
 $management=Get-AShellExternalManagementState
 $policyPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
 $entries=@()

 # Only values which can prevent A-Shell from owning the current lock-screen
 # surface are handed off. Removing them is equivalent to "Not configured";
 # the checkpoint/baseline records the exact previous value and recreates it on
 # rollback/Undo. Unrelated Personalization policy values are never touched.
 foreach($item in @(
  @{Path=$policyPath;Name='NoChangingLockScreen';Mode='disable';Block={param($v) $v.Exists -and [string]$v.Value -notin @('','0')};Meaning='Prevent changing lock screen and logon image'},
  @{Path=$policyPath;Name='NoLockScreen';Mode='disable';Block={param($v) $v.Exists -and [string]$v.Value -notin @('','0')};Meaning='Do not display the lock screen'},
  @{Path=$policyPath;Name='NoLockScreenSlideshow';Mode='disable';Block={param($v) $v.Exists -and [string]$v.Value -notin @('','0')};Meaning='Prevent enabling lock-screen slideshow'},
  @{Path=$policyPath;Name='LockScreenImage';Mode='force-image';Block={param($v) $v.Exists -and -not [string]::IsNullOrWhiteSpace([string]$v.Value)};Meaning='Force a specific lock-screen/logon image'}
 )) {
  $current=Read-RegistryValue $item.Path $item.Name
  $ownedImage=Read-RegistryValue $policyPath 'LockScreenImage'
  $aShellOwnsMachineImage=($ownedImage.Exists -and (Test-AShellLegacyMachineLockScreenPath ([string]$ownedImage.Value)))
  if($item.Name -eq 'LockScreenImage' -and $aShellOwnsMachineImage){continue}
  if($item.Name -eq 'NoChangingLockScreen' -and $aShellOwnsMachineImage -and $current.Exists -and [string]$current.Value -notin @('','0')){continue}
  if(& $item.Block $current) {
   $operation=if($item.Mode -eq 'force-image'){'temporarily remove'}else{'temporarily disable'}
   $entries += [pscustomobject]@{Path=$item.Path;Name=$item.Name;Kind=$current.Kind;Value=$null;Exists=$false;OverrideMode=$item.Mode;Operation=$operation;Meaning=$item.Meaning;Original=$current.Value}
  }
 }

 # Some locally provisioned/customized PCs use the Personalization CSP backing
 # values directly. If they already exist and actively pin a different lock image,
 # temporarily remove only those pre-existing values so the supported per-user
 # LockScreen API can own the image, then restore the exact originals on stop/Undo.
 $cspPath='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
 # LockScreenImageStatus is a CSP status/output value (Get-only in the public
 # CSP contract), not an image-selection input. Leave it alone. Only existing
 # Path/Url values can pin the image through legacy/provisioning-backed setups.
 $cspImage=Read-RegistryValue $cspPath 'LockScreenImagePath'
 $cspUrl=Read-RegistryValue $cspPath 'LockScreenImageUrl'
 $cspInputs=@(@($cspImage,$cspUrl) | Where-Object {$_.Exists -and -not [string]::IsNullOrWhiteSpace([string]$_.Value) -and !(Test-AShellLegacyMachineLockScreenPath ([string]$_.Value))})
 foreach($current in $cspInputs) {
  $entries += [pscustomobject]@{Path=$cspPath;Name=$current.Name;Kind=$current.Kind;Value=$null;Exists=$false;Operation='temporarily remove';Meaning='Existing lock-screen Personalization CSP image input';Original=$current.Value}
 }

 # Do not create this legacy policy on clean PCs: value 0 is Windows' normal
 # image-enabled behavior. If an existing value explicitly disables the sign-in
 # background, temporarily flip only that existing value and restore it on Undo.
 $systemPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
 $disableLogon=Read-RegistryValue $systemPath 'DisableLogonBackgroundImage'
 if($disableLogon.Exists -and [string]$disableLogon.Value -notin @('','0')) {
  $entries += [pscustomobject]@{Path=$systemPath;Name='DisableLogonBackgroundImage';Kind=$disableLogon.Kind;Value=0;Exists=$true;Operation='temporarily set to 0';Meaning='Allow the lock-screen picture on the sign-in screen';Original=$disableLogon.Value}
 }
 return [pscustomobject]@{ExternallyManaged=[bool]$management.Managed;ManagementReasons=@($management.Reasons);Entries=@($entries)}
}
function Get-AShellLockScreenOverrideValues($Handoff,[string]$Image) {
 $result=@()
 foreach($entry in @($Handoff.Entries)) {
  if($entry.OverrideMode -eq 'disable') {
   $result += [pscustomobject]@{Path=$entry.Path;Name=$entry.Name;Kind=$entry.Kind;Value=0;Exists=$true}
  } elseif($entry.OverrideMode -eq 'force-image') {
   # Do not repoint LockScreenImage at A-Shell: that machine policy uses a
   # different render/cache path and can zoom/crop the sign-in image differently.
   $result += [pscustomobject]@{Path=$entry.Path;Name=$entry.Name;Kind=$entry.Kind;Value=$null;Exists=$false}
  } else {
   $result += [pscustomobject]@{Path=$entry.Path;Name=$entry.Name;Kind=$entry.Kind;Value=$entry.Value;Exists=$entry.Exists}
  }
 }
 return @($result)
}
function Release-AShellLockScreenPolicyBlockers {
 $handoff=Get-AShellLockScreenPolicyHandoff
 foreach($entry in @($handoff.Entries)) {
  Write-RegistryValue @{Path=$entry.Path;Name=$entry.Name;Kind=$entry.Kind;Value=$entry.Value;Exists=$entry.Exists}
 }
 if(@($handoff.Entries).Count -and (Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue)){Send-AShellPolicyChange;Start-Sleep -Milliseconds 200}
 return $handoff
}
function Get-AShellLockScreenOverrideConsentPath([string]$Root) { Join-Path $Root 'state\lockscreen-policy-override-consent.txt' }
function Test-AShellLockScreenOverrideConsent([string]$Root) { Test-Path -LiteralPath (Get-AShellLockScreenOverrideConsentPath $Root) }
function Write-AShellLockScreenPolicyHandoffStatus($Handoff,[switch]$DiagnosticOnly,[switch]$OverridePolicy) {
 if(!$Handoff -or !$Handoff.Entries -or @($Handoff.Entries).Count -eq 0){
  Write-Output '[OK] No local lock-screen policy is blocking A-Shell image control.'
  return
 }
 $managedText=''
 if($Handoff.ExternallyManaged){$managedText=' This device also reports: '+(@($Handoff.ManagementReasons) -join ', ')+'.'}
 if($DiagnosticOnly) {
  Write-Output "[CHECK] Found $(@($Handoff.Entries).Count) lock/sign-in blocker(s).$managedText"
  foreach($entry in @($Handoff.Entries)){Write-Output "[CHECK]   $($entry.Name) -- can $($entry.Operation): $($entry.Meaning)"}
  Write-Output '[CHECK] A-Shell changes these values only after explicit lock-screen override consent and restores the exact originals on Undo.'
  return
 }
 if(!$OverridePolicy) {
  Write-Warning "Lock-screen policy is active.$managedText A-Shell was not given policy-override consent, so these values are left unchanged."
  foreach($entry in @($Handoff.Entries)){Write-Output "[SKIP] $($entry.Name): $($entry.Meaning)"}
  return
 }
 if($Handoff.ExternallyManaged){
  $why=if(@($Handoff.ManagementReasons).Count){@($Handoff.ManagementReasons) -join ', '}else{'device management'}
  Write-Warning "Explicit consent granted: A-Shell will temporarily override only the lock-screen personalization values it needs even though Windows reports management ($why). Enrollment, MDM services and unrelated policy are not modified."
 } else {
  Write-Output '[INFO] Explicit consent granted for temporary lock-screen personalization policy override.'
 }
 Write-Output "[INFO] Handing off $(@($Handoff.Entries).Count) lock/sign-in policy value(s) while A-Shell is active."
 foreach($entry in @($Handoff.Entries)){Write-Output "[INFO]   $($entry.Name) -- $($entry.Operation): $($entry.Meaning); exact original value saved for Undo."}
 Write-Output '[OK] Lock-screen picture control released for A-Shell. If Windows Settings was already open, reopen the Lock screen page to refresh its controls.'
}
function Get-AShellSignInPreferenceKey {
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\'+$sid+'\AnyoneRead\LockScreen'
}
function Get-AShellSignInBackgroundPreference {
 try {
  $value=Read-RegistryValue (Get-AShellSignInPreferenceKey) 'HideLogonBackgroundImage'
  if($value.Exists){return ([int]$value.Value -eq 0)}
 } catch {}
 return $null
}
function Show-AShellSignInBackgroundStatus {
 $enabled=Get-AShellSignInBackgroundPreference
 if($enabled -eq $false){
  Write-Warning 'Windows has "Show the lock screen background picture on the sign-in screen" turned off for this account. That preference lives in SystemProtectedUserData and this Windows build blocks administrator writes to it. A-Shell does not take ownership or run as SYSTEM to bypass that protection. Turn it on once in Settings > Personalization > Lock screen if you want the same picture on sign-in.'
 } elseif($enabled -eq $true){
  Write-Output '[OK] Windows is configured to reuse the lock-screen picture on the sign-in screen.'
 } else {
  Write-Output '[INFO] Windows did not expose the per-user sign-in background preference. The lock image was set successfully; Windows will use its current sign-in-screen preference.'
 }
}
function Save-AShellBackground([string]$Folder,[switch]$OverrideManaged) {
 New-Item -ItemType Directory -Path $Folder -Force | Out-Null
 $wallpaper=(Read-RegistryValue 'HKCU:\Control Panel\Desktop' 'Wallpaper').Value
 $source=$wallpaper
 if(!$source -or !(Test-Path -LiteralPath $source)){$source=Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'}
 if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $Folder 'desktop.img')}
 $lockSource=Get-AShellLockSource;$lockFile='lock.img'
 if($lockSource) {
  $lockFile='lock'+[IO.Path]::GetExtension($lockSource)
  Copy-Item -LiteralPath $lockSource -Destination (Join-Path $Folder $lockFile)
 } else {Save-LockImage (Join-Path $Folder $lockFile)}
 $values=@(Get-AShellColorValues)
 $values+=Get-AShellMachineLockScreenRegistryValues
 foreach($entry in @(
  @('HKCU:\Control Panel\Desktop','WallpaperStyle'),@('HKCU:\Control Panel\Desktop','TileWallpaper'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338387Enabled'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','DetailedStatusApp'),
  @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled'),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh','DisableWidgetsOnLockScreen'),
  @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','DisableLogonBackgroundImage')
 )){$values+=Read-RegistryValue $entry[0] $entry[1]}
 $handoff=Get-AShellLockScreenPolicyHandoff
 if($OverrideManaged -or !$handoff.ExternallyManaged){foreach($entry in @($handoff.Entries)){$values+=Read-RegistryValue $entry.Path $entry.Name}}
 Save-AShellState @{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Wallpaper=$wallpaper;LockSource=$lockSource;LockFile=$lockFile;Values=$values} (Join-Path $Folder 'background.clixml')
}
function Restore-AShellBackground([string]$Folder,[string]$Root='') {
 if(!$Root){$Root=Split-Path (Split-Path $Folder)}
 if(!(Test-Path -LiteralPath (Join-Path $Folder 'background.clixml'))){return}
 $saved=Import-Clixml -LiteralPath (Join-Path $Folder 'background.clixml');Assert-AShellAccount $saved
 # Remove any legacy A-Shell machine image pin, then temporarily release original
 # blockers so the supported per-user LockScreen API can restore the checkpoint.
 [void](Restore-AShellLegacyMachineLockScreenPin $Root)
 [void](Release-AShellLockScreenPolicyBlockers)
 $desktop=Join-Path $Folder 'desktop.img'
 if(Test-Path -LiteralPath $desktop) {
  if($saved.Wallpaper -and (Test-Path -LiteralPath $saved.Wallpaper) -and (Get-FileHash -LiteralPath $saved.Wallpaper).Hash -eq (Get-FileHash -LiteralPath $desktop).Hash){Set-DesktopImage $saved.Wallpaper}
  else {Set-DesktopImage $desktop}
 } else {Set-DesktopImage ''}
 $lock=Join-Path $Folder $saved.LockFile
 if($saved.LockSource -and (Test-Path -LiteralPath $saved.LockSource) -and (Get-FileHash -LiteralPath $saved.LockSource).Hash -eq (Get-FileHash -LiteralPath $lock).Hash){Set-LockImage $saved.LockSource}
 else {Set-LockImage $lock}
 foreach($value in @($saved.Values)){Write-RegistryValue $value}
 if(Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue){Send-AShellPolicyChange}
 Send-AShellColorChange
}
function Set-AShellBackground([string]$Root,[string]$Image,[switch]$DesktopOnly) {
 if(!(Test-Path -LiteralPath $Image -PathType Leaf)){throw 'Choose an existing local image file.'}
 Add-Type -AssemblyName System.Drawing
 # Validate decode before taking backups or changing any setting.
 $decoded=[Drawing.Image]::FromFile($Image)
 try {
  if($decoded.Width -gt 16384 -or $decoded.Height -gt 16384){throw 'Image dimensions exceed 16384 pixels. Resize the image first.'}
  if($decoded.RawFormat.Guid -notin @([Drawing.Imaging.ImageFormat]::Png.Guid,[Drawing.Imaging.ImageFormat]::Jpeg.Guid,[Drawing.Imaging.ImageFormat]::Bmp.Guid)){throw 'Use a PNG, JPEG or BMP image; convert other formats first.'}
  $ext=if($decoded.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Png.Guid){'.png'}elseif($decoded.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Jpeg.Guid){'.jpg'}else{'.bmp'}
 } finally {$decoded.Dispose()}
 $checkpoint=Join-Path $Root ('state\background-runs\'+[guid]::NewGuid().ToString('N'))
 $allowPolicyOverride=$(if($DesktopOnly){$false}else{Test-AShellLockScreenOverrideConsent $Root})
 Save-AShellBackground $checkpoint -OverrideManaged:$allowPolicyOverride
 $baseline=Join-Path $Root 'state\background-before'
 if(!(Test-Path -LiteralPath (Join-Path $baseline 'background.clixml'))){
  New-Item -ItemType Directory -Path $baseline -Force | Out-Null
  Get-ChildItem -LiteralPath $checkpoint -File | Copy-Item -Destination $baseline
 }
 $folder=Join-Path $Root 'state\backgrounds';New-Item -ItemType Directory -Path $folder -Force | Out-Null
 $hash=(Get-FileHash -LiteralPath $Image).Hash
 $target=Join-Path $folder ($hash+$ext)
 if(!(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target).Hash -ne $hash){Copy-Item -LiteralPath $Image -Destination $target -Force}
 $colors=@(Get-AShellColorValues)
 if(!$DesktopOnly){[void](Restore-AShellLegacyMachineLockScreenPin $Root)}
 $handoff=$(if($DesktopOnly){[pscustomobject]@{Entries=@();ExternallyManaged=$false;ManagementReasons=@()}}else{Get-AShellLockScreenPolicyHandoff})
 try {
  if(@($handoff.Entries).Count -and !$allowPolicyOverride){
   $why=if($handoff.ExternallyManaged -and @($handoff.ManagementReasons).Count){' Windows reports: '+(@($handoff.ManagementReasons) -join ', ')+'.'}else{''}
   throw "Lock-screen personalization policy is blocking this background change.$why Run the A-Shell Setup EXE again and approve the temporary lock-screen policy override first."
  }
  if($allowPolicyOverride){
   foreach($entry in @(Get-AShellLockScreenOverrideValues $handoff $target)){Write-RegistryValue $entry}
   if(@($handoff.Entries).Count -and (Get-Command Send-AShellPolicyChange -ErrorAction SilentlyContinue)){Send-AShellPolicyChange}
  }
  foreach($entry in @(@('HKCU:\Control Panel\Desktop','WallpaperStyle','String','10'),@('HKCU:\Control Panel\Desktop','TileWallpaper','String','0'))){Write-RegistryValue @{Path=$entry[0];Name=$entry[1];Kind=$entry[2];Value=$entry[3];Exists=$true}}
  if(!$DesktopOnly){
   foreach($entry in @(
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenEnabled','DWord',0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','RotatingLockScreenOverlayEnabled','DWord',0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','SlideshowEnabled','DWord',0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338387Enabled','DWord',0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen','DetailedStatusApp','String',''),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh','DisableWidgetsOnLockScreen','DWord',1)
   )){Write-RegistryValue @{Path=$entry[0];Name=$entry[1];Kind=$entry[2];Value=$entry[3];Exists=$true}}
   $disableLogon=Read-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableLogonBackgroundImage'
   if($disableLogon.Exists -and [string]$disableLogon.Value -notin @('','0')){Write-RegistryValue @{Path=$disableLogon.Path;Name=$disableLogon.Name;Kind=$disableLogon.Kind;Value=0;Exists=$true}}
  }
  Set-DesktopImage $target
  if(!$DesktopOnly){Set-LockImage $target;Show-AShellSignInBackgroundStatus}
  foreach($value in $colors){Write-RegistryValue $value};Send-AShellColorChange
  Set-Content -LiteralPath (Join-Path $Root 'state\desired-background.txt') -Value $target -Encoding UTF8
 } catch {Restore-AShellBackground $checkpoint $Root;throw}
 Write-Output $(if($DesktopOnly){'Image saved for A-Shell and applied to the desktop. Screen customization is off, so the original Windows lock/login image and effects were left untouched.'}else{"Image set for desktop and lock/login screens through Windows' normal lock-screen image path. A-Shell removes logon acrylic blur and, on the verified build, the separate 45% black backdrop."})
}
function Restore-AShellOriginalWallpaper([string]$Root) {
 $baseline=Join-Path $Root 'state\baseline'
 $legacy=Join-Path $Root 'state\before-setup.clixml'
 $checkpoint=Join-Path $Root ('state\background-runs\'+[guid]::NewGuid().ToString('N'))
 Save-AShellBackground $checkpoint -OverrideManaged:(Test-AShellLockScreenOverrideConsent $Root)
 $colors=@(Get-AShellColorValues)
 try {
  if(Test-Path -LiteralPath (Join-Path $baseline 'checkpoint.clixml')){
   $saved=Import-Clixml -LiteralPath (Join-Path $baseline 'checkpoint.clixml');Assert-AShellAccount $saved
   $desktop=Join-Path $baseline 'desktop.img'
   $lock=Join-Path $baseline $(if($saved.LockOriginal){$saved.LockOriginal}else{'lock.img'})
  } elseif(Test-Path -LiteralPath $legacy) {
   $saved=Import-Clixml -LiteralPath $legacy;Assert-AShellAccount $saved
   $desktop=Join-Path $Root 'state\desktop-before.img';$lock=Join-Path $Root 'state\lock-before.img'
  } elseif(Test-Path -LiteralPath (Join-Path $Root 'state\background-before\background.clixml')) {
   Restore-AShellBackground (Join-Path $Root 'state\background-before')
   foreach($value in $colors){Write-RegistryValue $value};Send-AShellColorChange
   Write-Output '[OK] Original backgrounds restored. Your accent and other A-Shell features are unchanged.';return
  } else {throw 'No original background backup exists. Run Setup or set a background first.'}
  if(Test-Path -LiteralPath $desktop) {
   if($saved.Wallpaper -and (Test-Path -LiteralPath $saved.Wallpaper) -and (Get-FileHash -LiteralPath $saved.Wallpaper).Hash -eq (Get-FileHash -LiteralPath $desktop).Hash){$desktop=$saved.Wallpaper}
   Set-DesktopImage $desktop
  } else {Set-DesktopImage ''}
  if(!(Test-Path -LiteralPath $lock)){throw 'Original lock-screen backup is missing.'}
  # Keep the lock and sign-in framing identical to the normal Windows lock-screen
  # path. Do not force a machine/CSP image, which uses a different crop/cache path.
  [void](Restore-AShellLegacyMachineLockScreenPin $Root)
  [void](Release-AShellLockScreenPolicyBlockers)
  Set-LockImage $lock
  foreach($value in $saved.Values){if($value.Name -in @('WallpaperStyle','TileWallpaper','SlideshowEnabled','RotatingLockScreenEnabled','RotatingLockScreenOverlayEnabled','DisableLogonBackgroundImage')){Write-RegistryValue $value}}
  foreach($value in $colors){Write-RegistryValue $value};Send-AShellColorChange
  Write-Output '[OK] Pre-setup desktop and lock backgrounds restored; sign-in follows the restored Windows preference. Accent, icons and rain remain enabled.'
 } catch {Restore-AShellBackground $checkpoint $Root;throw}
}
