@echo off
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0copy-script.ps1" %*
if errorlevel 1 (
  echo Copy failed. See README.md for manual use.
  pause
  exit /b 1
)
echo Read README.md for the setup steps.
pause
