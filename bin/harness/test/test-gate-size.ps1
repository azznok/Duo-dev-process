# TEST OF THE GATE CHECK "no file > 10 MB" (docs/RULES.md, git), without a model, in a few seconds.
#   powershell -File bin\harness\test\test-gate-size.ps1     (one OK/KO line per check)
# Throwaway repo in %TEMP%: an ordinary 11 MB file must be reported; an 11 MB LFS file (only a
# pointer enters git) and a small file must not. Exit code 1 on any KO.
$ErrorActionPreference = "Continue"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-size-" + (Get-Date -Format "yyMMdd-HHmmss"))
# The library runs from a copy: its .state/ and logs/ land in %TEMP%, not in this repo.
New-Item -ItemType Directory -Force (Join-Path $T "bin\harness") | Out-Null
Copy-Item (Join-Path $Source "bin\harness\lib") (Join-Path $T "bin\harness\lib") -Recurse
. (Join-Path $T "bin\harness\lib\common.ps1")
. (Join-Path $T "bin\harness\lib\gate.ps1")
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }

$D = Join-Path $T "repo"
New-Item -ItemType Directory -Force $D | Out-Null
git -C $D init -q 2>&1 | Out-Null
git -C $D config user.email "t@t"; git -C $D config user.name "t"
git -C $D lfs install --local 2>&1 | Out-Null
Set-Content -Path (Join-Path $D ".gitattributes") -Value "*.png filter=lfs diff=lfs merge=lfs -text" -Encoding ASCII
Set-Content -Path (Join-Path $D "small.txt") -Value "small" -Encoding ASCII
git -C $D add -A 2>&1 | Out-Null; git -C $D commit -q -m "base" 2>&1 | Out-Null
$base = (git -C $D rev-parse HEAD).Trim()
$bytes = New-Object byte[] (11MB); (New-Object Random 7).NextBytes($bytes)
[IO.File]::WriteAllBytes((Join-Path $D "large.bin"), $bytes)
New-Item -ItemType Directory -Force (Join-Path $D "docs\art") | Out-Null
[IO.File]::WriteAllBytes((Join-Path $D "docs\art\sheet v1.png"), $bytes)
Add-Content -Path (Join-Path $D "small.txt") -Value "more"
git -C $D add -A 2>&1 | Out-Null; git -C $D commit -q -m "large" 2>&1 | Out-Null

$lfs = (git -C $D lfs ls-files 2>$null | Out-String)
L ($lfs -match "sheet v1.png") "the sheet is tracked by LFS in the test repo"
$large = @(Get-LargeFiles $D $base)
L ($large -contains "large.bin") "an ordinary 11 MB file is reported"
L (-not ($large -contains "docs/art/sheet v1.png")) "an 11 MB LFS file passes (only a pointer in git)"
L (-not ($large -contains "small.txt")) "a small modified file passes"
L ($large.Count -eq 1) "one file reported ($($large -join ', '))"
L (@(Get-LargeFiles $D "HEAD").Count -eq 0) "nothing reported outside the range base..HEAD"
Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
Write-Host ("TEST GATE SIZE : {0} checks" -f $n)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
