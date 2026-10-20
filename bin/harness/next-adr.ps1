# NEXT FREE ADR NUMBER, shared by every duo.
#   powershell -File bin\harness\next-adr.ps1      (prints "0042" for instance, and reserves it)
# The reviewer reserves the number it cites in the task this way; the coder, the one of an
# unplanned ADR. Two duos guessing "the next number" from their own checkout collide.
# Never below the highest ADR already written in docs/adr/ (one file per ADR).
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\shared.ps1")
$n = Get-SharedNumber "adr" (Get-AdrFloor)
if ($n -le 0) { Write-Host "counters lock unavailable: try again"; exit 2 }
Write-Host ("{0:D4}" -f $n)
