@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
title DBC Sweeper - PURGE REGISTRY (Admin)
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Requesting administrator rights, click YES in the UAC prompt...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo.
echo   PURGE REGISTRY: delete promo registry keys only.
echo   Each key is exported to a .reg backup first. Double-click it to restore.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%DBC_Sweeper.ps1" -PurgeReg -IAcknowledge %*
pause
