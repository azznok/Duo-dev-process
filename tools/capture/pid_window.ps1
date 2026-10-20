# THE PROCESS BEHIND A WINDOW.
#   powershell -File tools/capture/pid_window.ps1 -Handle 4065074      -> prints the PID, nothing else
# Why this script exists: `Get-Process MyGame | Sort StartTime | Select -First 1` picks the LAUNCHER
# (a small exe with MainWindowHandle 0), not the game itself. A bench that killed "the first one" killed
# nothing, and the host kept running - which made us believe for an evening that the local loop answered
# for a dead peer. ALWAYS start from the window.
param([Parameter(Mandatory=$true)][string]$Handle)
$ErrorActionPreference = 'Stop'
$h64 = [int64]$Handle

# THE NO-COMPILE PATH FIRST (paid for with a twelve-minute bench). `Add-Type` compiles C# at each call:
# under load (four games starting at once) it fails intermittently - seen "Add-Type : (0) :" then the
# script dead, so no PID, so "alive=0" on games that were alive. For a MAIN window, .NET gives the answer
# without P/Invoke: every process carries its MainWindowHandle. We try that first; the C# only serves a
# window that is not the main one of its process.
$proc = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and [int64]$_.MainWindowHandle -eq $h64 } | Select-Object -First 1
if ($proc) { Write-Output $proc.Id; exit 0 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinPid {
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
"@
$h = [IntPtr]::new($h64)
if (-not [WinPid]::IsWindow($h)) { Write-Error "window $Handle does not exist"; exit 1 }
$p = 0
[void][WinPid]::GetWindowThreadProcessId($h, [ref]$p)
if ($p -eq 0) { Write-Error "no process behind $Handle"; exit 1 }
Write-Output $p
