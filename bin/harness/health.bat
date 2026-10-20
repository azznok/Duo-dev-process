@echo off
rem Health of the duo: is the work moving?
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0health.ps1"
pause
