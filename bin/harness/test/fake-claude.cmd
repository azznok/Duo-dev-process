@echo off
rem Fake "claude" to test the harness without any model call (bin\harness\test\test-loop.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-claude.ps1" %*
