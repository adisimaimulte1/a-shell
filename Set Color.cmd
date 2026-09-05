@echo off
setlocal
rem Prefer Windows PowerShell modules when launched from PowerShell 7.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
if "%~1"=="" (
  echo Usage: "Set Color.cmd" 00AAFF
  echo        "Set Color.cmd" default
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Color.ps1" -Color "%~1"
exit /b %errorlevel%
