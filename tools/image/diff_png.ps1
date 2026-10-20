# How many PIXELS moved between two shots - the numeric witness of the rule
# "one single thing changes, on the same image".
#   powershell -File tools/image/diff_png.ps1 -A before.png -B after.png [-Threshold 24]
param([string]$A, [string]$B, [int]$Threshold = 24)
Add-Type -AssemblyName System.Drawing
$ba = New-Object System.Drawing.Bitmap $A
$bb = New-Object System.Drawing.Bitmap $B
$w = [Math]::Min($ba.Width, $bb.Width); $h = [Math]::Min($ba.Height, $bb.Height)
$rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$fmt = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
$da = $ba.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $fmt)
$db = $bb.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $fmt)
$n = $da.Stride * $h
$pa = New-Object byte[] $n; $pb = New-Object byte[] $n
[System.Runtime.InteropServices.Marshal]::Copy($da.Scan0, $pa, 0, $n)
[System.Runtime.InteropServices.Marshal]::Copy($db.Scan0, $pb, 0, $n)
$ba.UnlockBits($da); $bb.UnlockBits($db)
$changed = 0; $total = $w * $h
for ($y = 0; $y -lt $h; $y++) {
  $o = $y * $da.Stride
  for ($x = 0; $x -lt $w; $x++) {
    $i = $o + $x * 3
    $d = [Math]::Abs([int]$pa[$i] - [int]$pb[$i]) + [Math]::Abs([int]$pa[$i+1] - [int]$pb[$i+1]) + [Math]::Abs([int]$pa[$i+2] - [int]$pb[$i+2])
    if ($d -gt $Threshold * 3) { $changed++ }
  }
}
$ba.Dispose(); $bb.Dispose()
"DIFF {0} vs {1} : {2} pixels changed out of {3} ({4:N2} %)" -f (Split-Path $A -Leaf), (Split-Path $B -Leaf), $changed, $total, (100.0 * $changed / $total)
