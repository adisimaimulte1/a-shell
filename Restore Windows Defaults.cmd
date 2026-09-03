@echo off
setlocal
rem Prefer Windows PowerShell modules when launched from PowerShell 7.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Setup.ps1" -Action Restore
if errorlevel 1 (
 echo Restore did not finish. See state\setup.log.
 pause
 exit /b 1
)
echo Your saved pre-setup appearance was restored. This legacy filename no longer applies factory defaults.
pause
