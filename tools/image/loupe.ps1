# LOUPE: crops an area of a capture and enlarges it, pixel for pixel.
#   .\tools\image\loupe.ps1 -In proofs\capture.png -Out zoom.png
#   .\tools\image\loupe.ps1 -In x.png -Out z.png -X 360 -Y 440 -W 600 -H 300 -Zoom 3
#
# WHY THIS TOOL EXISTS. The rule is that a gate is passed only if an IMAGE proves it. But a 1320 px
# capture renders a small label seen from a distance on some forty pixels: enough to see that there is
# something, not enough to read it, nor to tell whether the text is missing or only washed out on a wall
# of the same hue. Twice in a row, a capture was read as "no text" when the honest answer was
# "I cannot know".
#
# Without an area, it takes the CENTRE: that is where a framed shot puts its target.
# Nearest-neighbour interpolation, on purpose: we want to see the pixels as they are, not a smoothed
# version that invents edges.
param(
  [Parameter(Mandatory = $true)][string]$In,
  [Parameter(Mandatory = $true)][string]$Out,
  [int]$X = -1,
  [int]$Y = -1,
  [int]$W = 480,
  [int]$H = 300,
  [int]$Zoom = 3
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$path = (Resolve-Path $In).Path
$img = [System.Drawing.Bitmap]::FromFile($path)
try {
  if ($X -lt 0) { $X = [int](($img.Width - $W) / 2) }
  if ($Y -lt 0) { $Y = [int](($img.Height - $H) / 2) }
  # Clamp instead of refusing: an area that overflows by a hair must not cost a round trip.
  if ($X -lt 0) { $X = 0 }
  if ($Y -lt 0) { $Y = 0 }
  if ($X + $W -gt $img.Width)  { $W = $img.Width  - $X }
  if ($Y + $H -gt $img.Height) { $H = $img.Height - $Y }

  $src = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
  $dst = New-Object System.Drawing.Bitmap ($W * $Zoom), ($H * $Zoom)
  $g = [System.Drawing.Graphics]::FromImage($dst)
  try {
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, ($W * $Zoom), ($H * $Zoom)),
                 $src, [System.Drawing.GraphicsUnit]::Pixel)
  } finally { $g.Dispose() }

  $target = $Out
  if (-not [System.IO.Path]::IsPathRooted($target)) {
    $target = Join-Path (Get-Location).Path $target
  }
  $dst.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
  $dst.Dispose()
  Write-Output ("loupe: {0} [{1},{2} {3}x{4}] x{5} -> {6}" -f
    (Split-Path $path -Leaf), $X, $Y, $W, $H, $Zoom, $target)
} finally { $img.Dispose() }
