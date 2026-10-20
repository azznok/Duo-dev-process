# TEST OF THE MEDIATOR, without a model nor any cost, ~3 min.
#   powershell -File bin\harness\test\test-mediator.ps1     (one OK/KO line per check)
# For each case, a clone of a throwaway copy of THIS working tree in %TEMP% (with a local "GitHub")
# where an accepted task does not merge (conflict with main), then mediator.ps1 with the fake claude:
#   documents solved -> default model, high effort, merge, push, duo resumed, resolution for the reviewer;
#   code solved -> top model, high effort (credit exhausted: default model, high effort), green gate -> merge;
#   code, red gate -> merge aborted; forbidden path -> guard; question; escalation mid -> default.
# Touches neither this repo nor GitHub. Exit code 1 on any KO.
$ErrorActionPreference = "Continue"
$env:GIT_TERMINAL_PROMPT = "0"; $env:GIT_LFS_SKIP_SMUDGE = "1"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-mediator-" + (Get-Date -Format "yyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $T | Out-Null
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }
function G { & git @args 2>&1 | Out-String }
$utf8 = New-Object System.Text.UTF8Encoding $false

# The working tree (committed or not) becomes the first commit of a throwaway "GitHub".
$seed = Join-Path $T "seed"
& robocopy $Source $seed /E /XD .git .state logs __pycache__ /XF STOP STOP-ALL project.env .mcp.json /NFL /NDL /NJH /NJS /NP | Out-Null
G -C $seed init -q -b main | Out-Null
G -C $seed add -A | Out-Null
G -C $seed -c user.email=t@t -c user.name=t commit -q -m "test: seed" | Out-Null
G clone -q --bare $seed (Join-Path $T "github.git") | Out-Null

function New-Case([string]$Name, [string]$File) {
    # A repo where task/007-test (accepted) and main changed the same line of $File.
    $D = Join-Path $T $Name
    G clone -q (Join-Path $T "github.git") $D | Out-Null
    G -C $D config user.email "t@t" | Out-Null; G -C $D config user.name "t" | Out-Null
    G -C $D checkout -q -B main origin/main | Out-Null
    $p = Join-Path $D $File
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    [IO.File]::WriteAllText($p, "start`r`ncommon line`r`nend`r`n", $utf8)
    G -C $D add -- $File | Out-Null; G -C $D commit -q -m "test: base" | Out-Null; G -C $D push -q origin main | Out-Null
    G -C $D checkout -q -b task/007-test | Out-Null
    [IO.File]::WriteAllText($p, "start`r`nline of task 7`r`nend`r`n", $utf8)
    G -C $D commit -q -am "test(fake): task side (TASK 007)" | Out-Null
    G -C $D checkout -q main | Out-Null
    [IO.File]::WriteAllText($p, "start`r`nline of the other duo`r`nend`r`n", $utf8)
    G -C $D commit -q -am "test: other duo side" | Out-Null; G -C $D push -q origin main | Out-Null
    G -C $D checkout -q task/007-test | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $D "logs"), (Join-Path $D "pipeline") | Out-Null
    [IO.File]::WriteAllText((Join-Path $D ("logs\harness-{0}.log" -f (Get-Date -Format "yyMMdd"))), "[x] harness : merge of task/007-test failed (conflict?) : CONFLICT`r`n[x] reviewer : MERGE BLOCKED - a human must look (git status)`r`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $D "pipeline\.n"), "8", $utf8)
    [IO.File]::WriteAllText((Join-Path $D "pipeline\task.md"), "TASK: 8 - [M9-01] next`r`n", $utf8)
    return $D
}
function Invoke-Case([string]$D, [string]$Incident, [string]$Action, [string]$Gate = "git --version", [string]$Quota = "") {
    $env:FAKE_MEDIATOR = $Action; $env:FAKE_QUOTA = $Quota
    $env:HARNESS_CLAUDE_CLI = Join-Path $D "bin\harness\test\fake-claude.cmd"
    $env:HARNESS_GATE_CMDS = $Gate
    $env:NTFY_TOPIC = "FILE:" + (Join-Path $D "ntfy.txt")
    $env:HARNESS_CODER_MODEL = "default-test"; $env:HARNESS_MODEL_TOP = "top-test"; $env:HARNESS_MODEL_MID = "mid-test"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $D "bin\harness\mediator.ps1") -Duo A -DuoRoot $D -Incident $Incident 2>&1 | Out-Null
    return $LASTEXITCODE
}
function Get-Trace([string]$D) { "" + (Get-Content (Join-Path $D ".state\fake-trace.txt") -Raw -ErrorAction SilentlyContinue) }
function Test-InMain([string]$D) { G -C $D merge-base --is-ancestor task/007-test main | Out-Null; return ($LASTEXITCODE -eq 0) }

# 1. Documents conflict, solved.
$D = New-Case "docs" "docs\TEST-CONFLICT.md"
$rc = Invoke-Case $D "merge blocked" "union"
L ($rc -eq 0) "documents: mediator solved (code $rc)"
L ((Get-Trace $D) -match "MEDIATOR model=default-test effort=high action=union") "documents: default model, high effort"
L (Test-InMain $D) "documents: task 7 is merged into main"
L ((G -C $D rev-parse main).Trim() -eq (G --git-dir (Join-Path $T "github.git") rev-parse main).Trim()) "documents: main pushed"
L ((G -C $D rev-parse --abbrev-ref HEAD).Trim() -eq "task/008-m9-01") "documents: the duo is resumed on the branch of task 8"
L (Test-Path (Join-Path $D "pipeline\mediation.md")) "documents: the resolution waits for the next reviewer (pipeline/mediation.md)"
$c = Get-Content (Join-Path $D "docs\TEST-CONFLICT.md") -Raw
L (($c -match "task 7") -and ($c -match "other duo")) "documents: both sides are kept"
$j = Get-Content (Join-Path $D "logs\harness-$(Get-Date -Format 'yyMMdd').log") -Raw
L (($j -match "mediator \(duo A\) : task/007-test merged after resolution") -and -not ($j -cmatch "mediator \(duo A\) :.*(MERGE BLOCKED|FATAL|SET ASIDE)")) "documents: mediator lines in the duo journal, without the orchestrator's incident words"

# 2. Code conflict, solved, green gate; top credit exhausted -> default model, high effort.
$D = New-Case "code" "src\test_conflict.txt"
$rc = Invoke-Case $D "merge blocked" "union" "git --version" "top-test"
$tr = Get-Trace $D
L ($rc -eq 0) "code: mediator solved, green gate (code $rc)"
L ($tr -match "MEDIATOR model=default-test effort=high") "code: top model exhausted -> default model, high effort"
L (Test-InMain $D) "code: task 7 is merged into main"

# 3. Code conflict, red gate: merge aborted, main intact.
$D = New-Case "gate" "src\test_conflict.txt"
$before = (G -C $D rev-parse main).Trim()
$rc = Invoke-Case $D "merge blocked" "union" "exit 1"
L ($rc -eq 1) "red gate: duo stopped (code $rc)"
L ((G -C $D rev-parse main).Trim() -eq $before -and -not (Test-InMain $D)) "red gate: main intact, nothing merged"
L ((Get-Trace $D) -match "MEDIATOR model=top-test effort=high") "code: top model, high effort"

# 4. Forbidden path: guard.
$D = New-Case "guard" "docs\TEST-CONFLICT.md"
$before = (G -C $D rev-parse main).Trim()
$rc = Invoke-Case $D "merge blocked" "forbidden"
L ($rc -eq 1) "guard: forbidden path -> duo stopped (code $rc)"
L ((G -C $D rev-parse main).Trim() -eq $before -and -not (Test-Path (Join-Path $D "bin\harness\intruder.txt"))) "guard: merge aborted, nothing left"
L ((Get-Content (Join-Path $D "logs\harness-$(Get-Date -Format 'yyMMdd').log") -Raw) -match "guard: forbidden paths") "guard: written to the journal"
L ((Get-Content (Join-Path $D "ntfy.txt") -Raw -ErrorAction SilentlyContinue) -match "stopped") "guard: owner told"

# 5. Operations: question.
$D = New-Case "question" "docs\TEST-CONFLICT.md"
$rc = Invoke-Case $D "fatal error : coder FATAL" "question"
L ($rc -eq 1) "question: duo stopped (code $rc)"
L ((Get-Trace $D) -match "MEDIATOR model=mid-test effort=medium action=question") "operations: mid model"

# 6. Operations: escalation mid -> default model, high effort.
$D = New-Case "escalate" "docs\TEST-CONFLICT.md"
$rc = Invoke-Case $D "duo dead 3 times in 1 h" "escalate"
$tr = Get-Trace $D
L ($rc -eq 0) "escalation: solved at the second call (code $rc)"
L (($tr -match "model=mid-test effort=medium") -and ($tr -match "model=default-test effort=high")) "escalation: mid then default model, high effort"

L (-not (Test-Path (Join-Path (G -C $D rev-parse --path-format=absolute --git-common-dir).Trim() "harness\merge.lock"))) "no merge lock is left taken"
foreach ($k in @("FAKE_MEDIATOR", "FAKE_QUOTA", "NTFY_TOPIC")) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
Get-ChildItem Env: | Where-Object { $_.Name -like "HARNESS_*" } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
Write-Host ("TEST MEDIATOR : {0} checks ; test repo : {1}" -f $n, $T)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
