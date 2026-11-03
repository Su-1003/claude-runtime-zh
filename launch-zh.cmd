@echo off
setlocal
powershell.exe -NoProfile -MTA -ExecutionPolicy Bypass -File "%~dp0launch-zh.ps1" -AllWindows %*
if errorlevel 1 (
  echo.
  echo See the STOPPED message above. Press any key to close.
  pause >nul
  exit /b 1
)
