# TEST OF THE CODER'S SELF-CHECK (self-judge.ps1), with the fake claude, without a model (~30 s).
#   powershell -File bin\harness\test\test-self-judge.ps1     (one OK/KO line per check)
# Copies bin/harness and tools/image into a throwaway folder (the real task counter is not
# touched), then: NO (code 1), YES (code 0), missing pair image (code 2), limit of 2 tries (code 4).
# Exit code 1 on any KO.
$ErrorActionPreference = "Continue"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-self-judge-" + (Get-Date -Format "yyMMdd-HHmmss"))
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }
foreach ($d in @("bin\harness", "tools\image")) { New-Item -ItemType Directory -Force (Join-Path $T (Split-Path $d)) | Out-Null; Copy-Item (Join-Path $Source $d) (Join-Path $T $d) -Recurse }
New-Item -ItemType Directory -Force (Join-Path $T "config"), (Join-Path $T "pipeline"), (Join-Path $T "img") | Out-Null
Copy-Item (Join-Path $Source "config\project.env.example") (Join-Path $T "config\project.env.example")
& python -c "import sys; from PIL import Image; Image.new('RGB', (64, 48), (200, 40, 40)).save(sys.argv[1]); Image.new('RGB', (64, 48), (40, 40, 200)).save(sys.argv[2])" `
    (Join-Path $T "img\cap.png") (Join-Path $T "img\ref.png")
[IO.File]::WriteAllText((Join-Path $T "pipeline\task.md"), "TASK: 777 - test`r`nPROOFS:`r`n- art-judge: img/cap.png | img/ref.png`r`n")
$env:HARNESS_CLAUDE_CLI = Join-Path $T "bin\harness\test\fake-claude.cmd"
$script = Join-Path $T "bin\harness\self-judge.ps1"
function Run([string[]]$a) { $o = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script @a 2>&1 | Out-String); return @{ Code = $LASTEXITCODE; Out = $o } }

$env:FAKE_JUDGE = "NO"; $r = Run @()
L ($r.Code -eq 1 -and $r.Out -match "SELF-JUDGE: NO \(try 1/2\)") "NO: code 1, try 1/2 (pairs read in the task)"
L (Test-Path (Join-Path $T ".state\self-judge\777-1.md")) "output kept in .state/self-judge/777-1.md"
$env:FAKE_JUDGE = "YES"; $r = Run @("-Pair", "img/cap.png|img/ref.png")
L ($r.Code -eq 0 -and $r.Out -match "SELF-JUDGE: YES \(try 2/2\)") "YES: code 0, pair given as an argument"
$r = Run @("-Pair", "img/missing.png|img/ref.png")
L ($r.Code -eq 2 -and $r.Out -match "NOT JUDGED \(no try counted\)") "missing image: NOT JUDGED, code 2, no try counted"
$r = Run @()
L ($r.Code -eq 4 -and $r.Out -match "SELF-JUDGE: LIMIT") "3rd try: limit, code 4 (2 tries per task)"
L (-not (Test-Path (Join-Path $T "pipeline\blind-judge.md"))) "the self-check does not write the reviewer's verdict (pipeline/blind-judge.md)"
Remove-Item Env:\HARNESS_CLAUDE_CLI, Env:\FAKE_JUDGE -ErrorAction SilentlyContinue
Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem $env:TEMP -Directory -Filter "*-judge-self-777-*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("TEST SELF-JUDGE : {0} checks" -f $n)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
