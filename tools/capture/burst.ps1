# BURST OF PHOTOS IN ONE PROCESS. snap.ps1 costs ~0.5 s per photo (PowerShell start + Add-Type): two
# windows at a 0.5 s cadence do not fit in snap.ps1. Here we compile once, then each tick captures ALL
# the windows (PrintWindow, ~20-60 ms each) and writes the LOCAL start and end time of each shot (epoch
# seconds, in milliseconds) to -Times, so a capture can be matched with the app's own log.
# Usage: burst.ps1 -Handles "123,456" -Names "host,guest" -Out logs/burst -N 18 -Step 0.5 -Times logs/burst/times.txt
param(
  [string]$Handles,
  [string]$Names,
  [string]$Out,
  [int]$N = 10,
  [double]$Step = 0.5,
  [string]$Times
)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BurstWin {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@ -ReferencedAssemblies System.Drawing
Add-Type -AssemblyName System.Drawing
[void][BurstWin]::SetThreadDpiAwarenessContext([IntPtr](-4))   # see snap.ps1: REAL pixels
$hs = $Handles.Split(',') | ForEach-Object { [IntPtr][long]$_ }
$ns = $Names.Split(',')
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).Path $Out }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }
if (-not [System.IO.Path]::IsPathRooted($Times)) { $Times = Join-Path (Get-Location).Path $Times }
$lines = New-Object System.Collections.Generic.List[string]
$t0 = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0
for ($k = 0; $k -lt $N; $k++) {
  for ($i = 0; $i -lt $hs.Count; $i++) {
    $a = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0
    $r = New-Object BurstWin+RECT
    [BurstWin]::GetWindowRect($hs[$i], [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc()
    [BurstWin]::PrintWindow($hs[$i], $dc, 2) | Out-Null
    $g.ReleaseHdc($dc); $g.Dispose()
    $b = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0
    $f = Join-Path $Out ("{0}_{1:D2}.png" -f $ns[$i], $k)
    $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $lines.Add(("{0} {1:D2} {2:F3} {3:F3}" -f $ns[$i], $k, $a, $b))
  }
  $target = $t0 + ($k + 1) * $Step
  while (([DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0) -lt $target) { Start-Sleep -Milliseconds 5 }
}
[System.IO.File]::WriteAllLines($Times, $lines)
"burst: $N ticks x $($hs.Count) window(s) -> $Out ; times -> $Times"
