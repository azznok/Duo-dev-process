@echo off
rem Checks everything before starting the duos. Starts nothing, pays nothing.
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0doctor.ps1"
pause
