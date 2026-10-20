# TEST OF THE BLIND ART JUDGE, without a model, in a few seconds.
#   powershell -File bin\harness\test\test-judge.ps1     (one OK/KO line per check)
# Pairs read in the task, verdict read in the answer, NOT JUDGED cases (reference cited without a
# pair, missing image), and the call runs OUTSIDE the repo with the thumbnails only, without task
# nor report. The library runs from a copy in %TEMP%. Exit code 1 on any KO.
$ErrorActionPreference = "Continue"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-judge-" + (Get-Date -Format "yyMMdd-HHmmss"))
foreach ($d in @("bin\harness\lib", "bin\harness\prompts", "tools\image")) {
    New-Item -ItemType Directory -Force (Join-Path $T (Split-Path $d)) | Out-Null
    Copy-Item (Join-Path $Source $d) (Join-Path $T $d) -Recurse
}
# Two small images: a capture and its reference.
New-Item -ItemType Directory -Force (Join-Path $T "proofs\990"), (Join-Path $T "docs\art\refs"), (Join-Path $T "pipeline") | Out-Null
& python -c "import sys; from PIL import Image; Image.new('RGB', (64, 48), (200, 40, 40)).save(sys.argv[1]); Image.new('RGB', (64, 48), (40, 40, 200)).save(sys.argv[2])" `
    (Join-Path $T "proofs\990\cap.png") (Join-Path $T "docs\art\refs\ref.png")
. (Join-Path $T "bin\harness\lib\common.ps1")
. (Join-Path $T "bin\harness\lib\judge.ps1")
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }
# Nothing writes in a real pipeline nor a real journal; no model is called.
function Note([string]$m) { }
function New-LogPath([string]$r) { return (Join-Path $T "$r.log") }
function Select-Model([string[]]$c) { return $c[0] }
$script:seen = @{}
function Invoke-Claude([string]$Prompt, [string[]]$Arguments, [string]$LogPath) {
    $script:seen = @{ Cwd = (Get-Location).Path; Prompt = $Prompt; Args = ($Arguments -join " ") }
    return '{"type":"result","subtype":"success","is_error":false,"session_id":"t","result":"| seat | x | absent |\nGAPS: 1\nBLIND-JUDGE: NO (1 gaps)"}'
}

$cap = "proofs/990/cap.png"; $ref = "docs/art/refs/ref.png"
$task = "TASK: 999 - test`r`nPROOFS:`r`n- art-judge: ``$cap`` | ``$ref```r`n- art-judge: proofs/x.png|docs/art/refs/y.png`r`n"
$p = Get-JudgePairs $task
L ($p.Count -eq 2 -and $p[0][0] -eq $cap -and $p[0][1] -eq $ref -and $p[1][1] -eq "docs/art/refs/y.png") "pairs read in the task (backticks and without spaces)"
L ((Get-JudgeVerdict "bla`nBLIND-JUDGE: YES (0 gaps)`nBLIND-JUDGE: NO (3 gaps)") -eq "NO") "the last verdict wins"
L ((Get-JudgeVerdict "no line") -eq "NOT JUDGED") "without a verdict line: NOT JUDGED"

$r = Invoke-BlindJudge "TASK: 1`r`nPROOFS:`r`n- images: none" "REPORT" "990" @("m") "high"
L ($r.Verdict -eq "") "task without reference nor pair: no judge"
$r = Invoke-BlindJudge "see docs/art/refs/ref.png" "proofs/990/a.png" "991" @("m") "high"
L ($r.Verdict -eq "NOT JUDGED") "reference cited without an art-judge line: NOT JUDGED"
$r = Invoke-BlindJudge "- art-judge: proofs/missing.png | $ref" "proofs/missing.png" "992" @("m") "high"
L ($r.Verdict -eq "NOT JUDGED" -and $r.Section -match "missing\.png") "missing capture: NOT JUDGED"

$r = Invoke-BlindJudge "TASK: 993 secret-of-the-task`r`n- art-judge: $cap | $ref" "REPORT secret-of-the-report $cap" "993" @("m") "high"
L ($r.Verdict -eq "NO") "verdict of the judge given (NO)"
$project = ("" + $Cfg["PROJECT"]).Trim(); if (-not $project) { $project = "project" }
$dv = Join-Path $env:TEMP "$project-judge-993"
L ($script:seen.Cwd -eq $dv) "the judge runs in the thumbnails folder, outside the repo ($($script:seen.Cwd))"
L ($script:seen.Prompt -notmatch "secret-of-the-task|secret-of-the-report") "the judge sees neither the task nor the report"
L ($script:seen.Prompt -match "CAPTURE \(the product\) : .*cap\.jpg" -and $script:seen.Prompt -match "REFERENCE \(the target\) : .*ref\.jpg") "thumbnails of the capture and the reference in the prompt"
L ($script:seen.Args -match "--tools Read " -and $script:seen.Args -match "--permission-mode dontAsk") "Read tool only, dontAsk"
L ((Test-Path (Join-Path $Pipe "blind-judge.md")) -and ((Read-Utf8 (Join-Path $Pipe "blind-judge.md")) -match "BLIND-JUDGE: NO")) "output written to pipeline/blind-judge.md"
Remove-Item $T, $dv -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("TEST JUDGE : {0} checks" -f $n)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
