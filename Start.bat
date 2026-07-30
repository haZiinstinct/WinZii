@echo off
title WinZii
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0src\launcher.ps1" %*
if errorlevel 1 (
    echo.
    echo WinZii wurde mit einem Fehler beendet. Fenster schliesst in 15 Sekunden.
    timeout /t 15 >nul
)
