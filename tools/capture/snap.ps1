# PrintWindow capture of a window found by a substring of its title.
# Usage: snap.ps1 -List            -> lists the visible windows
#        snap.ps1 -Title "MyGame" -Out path.png
#        snap.ps1 -Handle 123456 -Out path.png
# -Handle is for when TWO windows share the same title (two instances of the packaged build, host and
# guest): -Title would always take the first one.
param(
  [switch]$List,
  [string]$Title,
  [long]$Handle = 0,
  [string]$Out
)
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class SnapWin {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
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
'@ -ReferencedAssemblies System.Drawing

[void][SnapWin]::SetThreadDpiAwarenessContext([IntPtr](-4))
$wins = [SnapWin]::Windows()
if ($List) { $wins | ForEach-Object { "{0}  {1}" -f $_.Key, $_.Value }; exit 0 }
if (-not $Out -or (-not $Title -and $Handle -eq 0)) { "need -Out and (-Title or -Handle)"; exit 1 }
if ($Handle -ne 0) {
  $hit = $wins | Where-Object { $_.Key -eq $Handle } | Select-Object -First 1
  if (-not $hit) { $hit = New-Object 'System.Collections.Generic.KeyValuePair[long,string]' ($Handle, "handle $Handle") }
} else {
  # Escaped: -like treats brackets in a title as a character class (see window.ps1).
  $pattern = "*" + [System.Management.Automation.WildcardPattern]::Escape($Title) + "*"
  $hit = $wins | Where-Object { $_.Value -like $pattern } | Select-Object -First 1
}
if (-not $hit) { "no window '*$Title*'"; exit 2 }
$h = [IntPtr]$hit.Key
$r = New-Object SnapWin+RECT
[SnapWin]::GetWindowRect($h, [ref]$r) | Out-Null
$wd = $r.R - $r.L; $ht = $r.B - $r.T
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap $wd, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
[SnapWin]::PrintWindow($h, $dc, 2) | Out-Null   # 2 = PW_RENDERFULLCONTENT
$g.ReleaseHdc($dc); $g.Dispose()
# RELATIVE PATH AND MISSING FOLDER. .NET resolves a relative path against the PROCESS folder, not the
# shell's, and Save() into a missing folder fails. Both happened the same day: `-Out proofs/x.png` wrote
# nothing anywhere, AND THE SCRIPT STILL REPORTED SUCCESS - the report line followed Save without ever
# checking that a file existed. We make the path absolute, create the folder, and say "snap:" only if
# the file is there.
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).Path $Out }
$Out = [System.IO.Path]::GetFullPath($Out)
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
if (-not (Test-Path $Out)) { "snap: FAILED, nothing written to $Out"; exit 1 }
"snap: $($hit.Value) ($wd x $ht) -> $Out"
