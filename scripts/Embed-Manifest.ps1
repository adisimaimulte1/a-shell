param([string]$File=(Join-Path $PSScriptRoot '..\bin\MatrixDesktop.exe'))
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ManifestResource {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr BeginUpdateResource(string path,bool delete);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool UpdateResource(IntPtr update,IntPtr type,IntPtr name,ushort lang,byte[] data,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool EndUpdateResource(IntPtr update,bool discard);
}
'@
$xml='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity version="1.0.0.0" processorArchitecture="amd64" name="MatrixDesktop" type="win32"/><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security></trustInfo><compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/></application></compatibility><application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness></windowsSettings></application></assembly>'
$bytes=[Text.Encoding]::UTF8.GetBytes($xml)
$handle=[ManifestResource]::BeginUpdateResource($file,$false)
if($handle -eq [IntPtr]::Zero) {throw 'BeginUpdateResource failed'}
if(![ManifestResource]::UpdateResource($handle,[IntPtr]24,[IntPtr]1,0,$bytes,$bytes.Length)) { [ManifestResource]::EndUpdateResource($handle,$true); throw 'UpdateResource failed'}
if(![ManifestResource]::EndUpdateResource($handle,$false)) {throw 'EndUpdateResource failed'}
'Windows 10/11 layered-child manifest embedded.'
