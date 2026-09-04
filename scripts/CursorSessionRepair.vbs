Option Explicit

Dim shell, ps1, powershell, command, exitCode
If WScript.Arguments.Count <> 1 Then WScript.Quit 2

ps1 = WScript.Arguments(0)
Set shell = CreateObject("WScript.Shell")
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = Chr(34) & powershell & Chr(34) & _
          " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & _
          Chr(34) & ps1 & Chr(34) & " -Action SessionApply -DelayMilliseconds 3500"

' 0 = hidden. Waiting keeps Task Scheduler from launching overlapping repair instances.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
