# CODER SELF-CHECK: the SAME blind judge the reviewer will get, run by the coder on its captures
# BEFORE its report. The judge sees only the images.
#   powershell -File bin\harness\self-judge.ps1                     (pairs "- art-judge:" of pipeline/task.md)
#   powershell -File bin\harness\self-judge.ps1 -Pair "proofs/280/x.png|docs/art/refs/x.png"
# Prints the list of gaps and ONE last line: SELF-JUDGE: YES | NO | NOT JUDGED | LIMIT (try k/2).
# Codes: 0 YES | 1 NO | 2 NOT JUDGED (missing image, silent judge) | 4 limit reached (2 tries per task).
# Full output kept in .state/self-judge/<task>-<k>.md. Blocking: 1 to 4 min.
param([string[]]$Pair = @())
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\judge.ps1")
$MaxTries = 2   # judge, fix, judge again: a third green try proves nothing more
$taskTxt = "" + (Read-Utf8 (Join-Path $Pipe "task.md"))
$num = [regex]::Match($taskTxt, 'TASK:\s*(\d+)').Groups[1].Value
if (-not $num) { $num = "000" }
if ($Pair.Count) {
    $pairs = @(); foreach ($p in $Pair) { $x = $p -split '\|'; if ($x.Count -eq 2) { $pairs += , @($x[0].Trim(), $x[1].Trim()) } }
} else { $pairs = Get-JudgePairs $taskTxt }
if (-not $pairs.Count) { Write-Host "No pair: neither -Pair nor a line '- art-judge: <capture> | <reference>' in pipeline/task.md."; Write-Host "SELF-JUDGE: NOT JUDGED"; exit 2 }

# A missing image costs no try: it is a path to fix, not a judgment.
$missing = @(); foreach ($p in $pairs) { foreach ($c in $p) { $a = if ([IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $Root $c }; if (-not (Test-Path -LiteralPath $a)) { $missing += $c } } }
if ($missing.Count) { Write-Host ("Images not found: " + ($missing -join ", ")); Write-Host "SELF-JUDGE: NOT JUDGED (no try counted)"; exit 2 }

$dir = Join-Path $State "self-judge"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$counter = Join-Path $dir "$num.n"
$k = 0; if (Test-Path $counter) { $k = [int]((Get-Content $counter -Raw).Trim()) }
if ($k -ge $MaxTries) {
    Write-Host "Limit reached: $MaxTries tries for task $num (a repeated check proves nothing more). Write the remaining gaps in the report's doubts."
    Write-Host "SELF-JUDGE: LIMIT ($k/$MaxTries)"; exit 4
}
$k++; Write-Utf8 $counter "$k"
$cand = @($Cfg["REVIEWER_ESCALATION"], $Cfg["REVIEWER_MODEL"]) | Where-Object { $_ } | Select-Object -Unique
$r = Invoke-JudgePairs $pairs "self-$num-$k" $cand $Cfg["REVIEWER_EFFORT_VISUAL"]
Write-Utf8 (Join-Path $dir "$num-$k.md") $r.Text
Note "self-judge : coder, task $num : $($r.Verdict), try $k/$MaxTries"
Write-Host $r.Text
Write-Host ""
Write-Host "SELF-JUDGE: $($r.Verdict) (try $k/$MaxTries)"
if ($r.Verdict -eq "YES") { exit 0 }
if ($r.Verdict -eq "NO") { exit 1 }
exit 2
