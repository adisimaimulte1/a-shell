@echo off
setlocal
rem Prefer Windows PowerShell modules when launched from PowerShell 7.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\SignIn-Backdrop.ps1" -Action Apply
if errorlevel 1 pause
