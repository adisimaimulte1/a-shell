param([string]$Expected)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime] | Out-Null
$settings=New-Object Windows.UI.ViewManagement.UISettings
$color=$settings.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Accent)
$actual='{0:X2}{1:X2}{2:X2}' -f $color.R,$color.G,$color.B
if($Expected -and $actual -ne $Expected){throw "Windows UISettings accent: expected $Expected, received $actual"}
Write-Output "Windows UISettings accent: #$actual"
