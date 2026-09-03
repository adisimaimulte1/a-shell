@echo off
setlocal
rem Prefer Windows PowerShell modules when launched from PowerShell 7.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Setup.ps1" -Action Apply -Core
if errorlevel 1 (
 echo Setup did not finish. See state\setup.log.
 pause
 exit /b 1
)
echo Core appearance installed.
pause
