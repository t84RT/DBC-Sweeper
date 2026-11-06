@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
title DBC Sweeper - REVERSIBLE FIX (Admin)
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Requesting administrator rights, click YES in the UAC prompt...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo.
echo   REVERSIBLE FIX. Every step is backed up first, then asks for YES.
echo   Actions: rename / move / comment / disable. Nothing is deleted.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%DBC_Sweeper.ps1" -Fix -IAcknowledge %*
echo.
echo   Done. Re-run RUN_1_Scan.cmd to verify.
pause
