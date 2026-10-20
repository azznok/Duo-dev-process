# Assembles N images into ONE contact sheet (grid), numbered: the capture NEXT TO its reference is how
# a visual proof is judged (never a capture alone). No Python dependency.
#   .\tools\image\sheet.ps1 -In capture.png,reference.png -Out proofs\012\sheet.png [-Cols 2]
# System.Drawing ships with .NET, so this works on a machine where Pillow is not installed.
# Cells keep their source size (the captures of one bench all share a format).
param(
  [Parameter(Mandatory = $true)][string[]]$In,
  [Parameter(Mandatory = $true)][string]$Out,
  [int]$Cols = 3
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# powershell -File flattens an array passed from bash into ONE comma-separated string, and a path
# may be a wildcard: split again and expand.
$lists = @()
foreach ($item in $In) { $lists += ($item -split ',') | Where-Object { $_ -ne '' } }
$imgs = @()
foreach ($p in $lists) {
  foreach ($f in (Resolve-Path $p)) {
    $imgs += [System.Drawing.Image]::FromFile($f.Path)
  }
}
if ($imgs.Count -eq 0) { Write-Host "NO IMAGE"; exit 1 }

# [int] everywhere: Measure-Object and [math]::Ceiling return DOUBLE, and the constructor
# Bitmap(double,double) does not exist ("Parameter is not valid").
$w = [int]($imgs | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum
$h = [int]($imgs | ForEach-Object { $_.Height } | Measure-Object -Maximum).Maximum
$rows = [int][math]::Ceiling($imgs.Count / [double]$Cols)
$bmp = New-Object System.Drawing.Bitmap ([int]($w * $Cols)), ([int]($h * $rows))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font("Consolas", 28, [System.Drawing.FontStyle]::Bold)
$brush = [System.Drawing.Brushes]::Yellow
for ($i = 0; $i -lt $imgs.Count; $i++) {
  $cx = ($i % $Cols) * $w
  $cy = [math]::Floor($i / $Cols) * $h
  $g.DrawImage($imgs[$i], $cx, $cy, $imgs[$i].Width, $imgs[$i].Height)
  $g.DrawString(("{0}" -f ($i + 1)), $font, $brush, ($cx + 12), ($cy + 12))
}
$g.Dispose()
# An absolute -Out must not be joined to the current folder ("C:\a\C:\b": path format not supported).
$outFull = $Out
if (-not [System.IO.Path]::IsPathRooted($outFull)) { $outFull = Join-Path (Get-Location).Path $outFull }
$outFull = [System.IO.Path]::GetFullPath($outFull)
$dir = Split-Path -Parent $outFull
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($outFull, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
foreach ($im in $imgs) { $im.Dispose() }
Write-Host ("sheet : {0} images -> {1} ({2}x{3})" -f $imgs.Count, $outFull, ($w * $Cols), ($h * $rows))
