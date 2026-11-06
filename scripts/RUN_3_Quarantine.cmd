@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
title DBC Sweeper - QUARANTINE (Admin)
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Requesting administrator rights, click YES in the UAC prompt...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo.
echo   QUARANTINE MODE: move promo folders / PE payload folders / unattend.xml
echo   into the quarantine area. This is MOVE, not DELETE. Fully reversible.
echo   Max 10 targets per batch, each asks for YES.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%DBC_Sweeper.ps1" -Quarantine -IAcknowledge %*
echo.
echo   Quarantine: %HERE%DBC_Sweeper_Report\Quarantine_*
echo   Disk space is freed only after you empty the quarantine folder manually.
pause
