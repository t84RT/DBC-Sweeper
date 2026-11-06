@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
title DBC Sweeper - READ ONLY SCAN
echo.
echo   [READ ONLY] No file deleted, no registry changed, no task disabled.
echo   Report will be written to: %HERE%DBC_Sweeper_Report
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%DBC_Sweeper.ps1" %*
echo.
echo   Done. Open: %HERE%DBC_Sweeper_Report\report.html
pause
