@echo off
rem Asks EVERY duo to stop cleanly: writes STOP-ALL at the root. The orchestrator then writes
rem STOP in each duo and exits; a duo started alone also honours STOP-ALL. Each duo stops at
rem the end of its current step.
rem Immediate stop of everything: powershell -File bin\harness\stop-all.ps1 -Definitive
cd /d "%~dp0..\.."
set /p REASON=Reason for the stop (one line, optional): 
echo %DATE% %TIME% - %REASON%> STOP-ALL
echo STOP-ALL written. Every duo stops at the end of its current step.
echo BEFORE RELAUNCHING: delete STOP-ALL at the root, and the STOP file of each duo folder.
pause
