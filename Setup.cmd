@echo off
setlocal
rem Prefer Windows PowerShell modules when launched from PowerShell 7.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Setup.ps1" -Action Apply
if errorlevel 1 (echo Setup needs attention. See state\setup.log.) else (echo Setup complete.)
pause
