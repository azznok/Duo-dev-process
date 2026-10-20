# Resizes a window found by a substring of its title (or by handle).
# Usage: tools/capture/window.ps1 -Title "MyGame" -W 1280 -H 720 [-X 0 -Y 0]
#
# WHY THIS SCRIPT EXISTS: a proof by image is judged at the size it is looked at. After a rebuild, the
# game window came back at 518 x 424 and a HUD hint looked unreadable - while the measured defect was
# already fixed. A photo taken in a postage stamp proves neither the defect nor the repair.
param(
  [string]$Title,
  [long]$Handle = 0,
  [int]$W = 1320,
  [int]$H = 800,
  # Position (optional). Two game windows are born at the same spot; a keyboard bench refuses to type
  # if the point it aims at belongs to the other one. We move one of them away.
  [int]$X = -1,
  [int]$Y = -1
)
if (-not $Title -and $Handle -eq 0) { "need -Title or -Handle"; exit 1 }
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class WinSize {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  // A MAXIMISED WINDOW SILENTLY IGNORES MoveWindow: the script reported "-> 1320 x 1222" after asking
  // for 830, without an error. It must be RESTORED first. Without that, two palette readings taken at
  // two window heights do not frame the same thing.
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  // WINDOWS DISPLAY SCALING CROPPED THE FRAME. Without this, GetWindowRect returns LOGICAL pixels (1320)
  // while the window has 1650 real ones, and PrintWindow fills only a corner of the bitmap: the photo
  // silently lost the right and bottom fifth of the render. Per THREAD and not per process: the process
  // call fails if awareness is already set, this one always succeeds. -4 = PER_MONITOR_AWARE_V2.
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<KeyValuePair<long,string>> Windows() {
    var list = new List<KeyValuePair<long,string>>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if (!IsWindowVisible(h)) return true;
      var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
      if (sb.Length > 0) list.Add(new KeyValuePair<long,string>(h.ToInt64(), sb.ToString()));
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
'@
[void][WinSize]::SetThreadDpiAwarenessContext([IntPtr](-4))
# -like treats BRACKETS as a character class: a title with brackets ("Game [Client 1]") could never
# be targeted. We escape it.
$wins = [WinSize]::Windows()
if ($Handle -ne 0) {
  $hit = $wins | Where-Object { $_.Key -eq $Handle } | Select-Object -First 1
  if (-not $hit) { "no window with handle $Handle"; exit 1 }
} else {
  $pattern = "*" + [System.Management.Automation.WildcardPattern]::Escape($Title) + "*"
  $hit = $wins | Where-Object { $_.Value -like $pattern } | Select-Object -First 1
  if (-not $hit) { "no window '$pattern'"; exit 1 }
}
# $hwnd, NOT $h: PowerShell variable names are case-insensitive. `$h = [IntPtr]$hit.Key` OVERWROTE the
# `-H` parameter (the height) with the window HANDLE, so MoveWindow received 31130946 as height. The
# window kept its size, the script proudly reported "-> 1320 x 1222", and two rounds of palette measures
# were taken in a frame believed to be set. A measuring tool that lies is worse than no tool.
$hwnd = [IntPtr]$hit.Key
$r = New-Object 'WinSize+RECT'
if ([WinSize]::IsZoomed($hwnd)) { [void][WinSize]::ShowWindow($hwnd, 9); Start-Sleep -Milliseconds 300 }  # 9 = SW_RESTORE
[void][WinSize]::GetWindowRect($hwnd, [ref]$r)
$px = $r.L; $py = $r.T
if ($X -ge 0) { $px = $X }
if ($Y -ge 0) { $py = $Y }
[void][WinSize]::MoveWindow($hwnd, $px, $py, $W, $H, $true)
[void][WinSize]::GetWindowRect($hwnd, [ref]$r)
$gw, $gh = ($r.R - $r.L), ($r.B - $r.T)
"window '{0}' -> {1} x {2}" -f $hit.Value, $gw, $gh
# AND WE SAY WHEN WE DID NOT GET WHAT WE ASKED FOR. This guard exists because this script LIED for two
# rounds (see the $hwnd comment above) and nothing reported it. A window may also refuse a size for good
# reasons (minimum size, the framework restoring its own size on the next frame): then the real setting
# is UPSTREAM - the window size requested when the app is launched - before the window opens.
if ($gw -ne $W -or $gh -ne $H) {
  "  !! asked {0} x {1}, got {2} x {3}. Set the size when launching the app, or measure at the size obtained." -f $W, $H, $gw, $gh
  exit 2
}
