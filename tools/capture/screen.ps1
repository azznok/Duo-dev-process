# WHOLE SCREEN: one capture of the entire primary screen, in real pixels (PER_MONITOR_AWARE_V2: with
# Windows at 125 % scaling, we would otherwise capture LOGICAL pixels). Why: snap.ps1 captures only ONE
# window, and the proof "the window fits on the screen, title bar included" needs the screen around it.
# Usage: screen.ps1 -Out path.png   -> "screen W x H -> path"
param([string]$Out)
if (-not $Out) { "need -Out"; exit 1 }
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ScreenWin {
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
'@
[void][ScreenWin]::SetThreadDpiAwarenessContext([IntPtr](-4))
$w = [ScreenWin]::GetSystemMetrics(0)
$h = [ScreenWin]::GetSystemMetrics(1)
# Relative path and missing folder: same trap as snap.ps1 (.NET resolves against the PROCESS folder).
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).Path $Out }
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
if (-not (Test-Path $Out)) { "screen: FAILED, nothing written to $Out"; exit 1 }
"screen $w x $h -> $Out"
