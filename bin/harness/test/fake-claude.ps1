# FAKE CLAUDE: plays the reviewer, the coder, the blind judge and the mediator without a model,
# to test the harness loop. Started by fake-claude.cmd (CLAUDE_CLI), from the test repo root (the
# harness's cwd).
#   Reviewer (no --dangerously-skip-permissions): reads the next line of the scenario
#     ($env:FAKE_SCENARIO: "<VERDICT> <NEXT> [MILESTONE=Mn] [MODEL=tier] [END=1]"), writes
#     pipeline/review.md and pipeline/task.md (or TASK: NONE); under CIRCUIT BREAKER, adds a question.
#   Coder: commits a dummy file and writes pipeline/report.md.
#   Blind judge ($env:FAKE_JUDGE = YES | NO) and mediator ($env:FAKE_MEDIATOR = union | forbidden |
#     question | escalate).
#   $env:FAKE_QUOTA: the named model answers "session limit" (the role switches to the next model).
# Output in stream-json format (init, one tool_use, result). Trace: .state/fake-trace.txt.
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $utf8
$prompt = [Console]::In.ReadToEnd()
$coder = $args -contains "--dangerously-skip-permissions"
$model = ""; for ($i = 0; $i -lt $args.Count - 1; $i++) { if ($args[$i] -eq "--model") { $model = $args[$i + 1] } }
New-Item -ItemType Directory -Force ".state" | Out-Null
function Trace([string]$t) { [IO.File]::AppendAllText((Join-Path (Get-Location) ".state\fake-trace.txt"), "$t`r`n", $utf8) }
function Write-Text([string]$p, [string]$t) { [IO.File]::WriteAllText((Join-Path (Get-Location) $p), $t, $utf8) }
function Evt($o) { [Console]::Out.WriteLine(($o | ConvertTo-Json -Depth 8 -Compress)) }

Evt ([ordered]@{ type = "system"; subtype = "init"; session_id = "fake-$PID"; model = $model })

# Credit exhausted on this model: $env:FAKE_QUOTA = "<model>", message with a reset time.
if ($env:FAKE_QUOTA -and $model -eq $env:FAKE_QUOTA) {
    Trace "QUOTA model=$model coder=$coder"
    Evt ([ordered]@{ type = "result"; subtype = "error_during_execution"; is_error = $true; session_id = "fake-$PID"; result = "You've hit your session limit - resets 11:59pm" })
    exit 1
}

if ($prompt -match "ROLE: BLIND ART JUDGE") {
    # Blind judge: $env:FAKE_JUDGE = YES | NO (default NO).
    $v = if ($env:FAKE_JUDGE -eq "YES") { "YES (0 gaps)" } else { "NO (1 gaps)" }
    $g = if ($env:FAKE_JUDGE -eq "YES") { 0 } else { 1 }
    Trace "JUDGE model=$model verdict=$v"
    Evt ([ordered]@{ type = "result"; subtype = "success"; is_error = $false; total_cost_usd = 0.01; session_id = "fake-$PID"; num_turns = 1; result = "GAPS: $g`nBLIND-JUDGE: $v" })
    exit 0
}

if ($prompt -match "ROLE: MEDIATOR") {
    # Mediator: $env:FAKE_MEDIATOR = union | forbidden | question | escalate.
    $effort = ""; for ($i = 0; $i -lt $args.Count - 1; $i++) { if ($args[$i] -eq "--effort") { $effort = $args[$i + 1] } }
    $action = "" + $env:FAKE_MEDIATOR
    Trace "MEDIATOR model=$model effort=$effort action=$action"
    $res = "SOLVED"
    $br = [regex]::Match($prompt, 'BRANCH: (task/\S+)').Groups[1].Value
    if ($action -in @("union", "forbidden") -and $br) {
        git checkout -q main 2>&1 | Out-Null
        git merge --no-ff -q -m "chore(git): merge $br after review" $br 2>&1 | Out-Null
        foreach ($f in @(git diff --name-only --diff-filter=U)) {
            $t = [IO.File]::ReadAllText((Join-Path (Get-Location) $f), $utf8) -split "`r?`n" | Where-Object { $_ -notmatch '^(<<<<<<<|=======|>>>>>>>)' }
            Write-Text $f (($t -join "`r`n"))
            git add -- $f 2>&1 | Out-Null
        }
        if ($action -eq "forbidden") { Write-Text "bin\harness\intruder.txt" "forbidden"; git add -- "bin/harness/intruder.txt" 2>&1 | Out-Null }
    } elseif ($action -eq "question") { $res = "QUESTION" }
    elseif ($action -eq "escalate" -and $model -match "mid") { $res = "ESCALATE" }
    Evt ([ordered]@{ type = "result"; subtype = "success"; is_error = $false; total_cost_usd = 0.01; session_id = "fake-$PID"; num_turns = 2; result = "RESULT: $res`nfake mediator" })
    exit 0
}

if ($coder) {
    $task = [IO.File]::ReadAllText((Join-Path (Get-Location) "pipeline\task.md"), $utf8)
    $num = [regex]::Match($task, 'TASK:\s*(\d+)').Groups[1].Value
    Trace "CODER task=$num model=$model"
    Evt ([ordered]@{ type = "assistant"; message = [ordered]@{ content = @([ordered]@{ type = "tool_use"; id = "t1"; name = "Skill"; input = [ordered]@{ skill = "game-feel" } }) } })
    New-Item -ItemType Directory -Force "fake" | Out-Null
    Write-Text "fake\$num-$PID.txt" "dummy work of task $num"
    git add -- "fake" 2>&1 | Out-Null
    # $env:FAKE_CONFLICT: every task appends a line at the END of docs/OWNER.md, like two reviewers
    # writing to the owner at once: two duos in parallel collide at the merge.
    if ($env:FAKE_CONFLICT) {
        [IO.File]::AppendAllText((Join-Path (Get-Location) "docs\OWNER.md"), "- note of task $num`r`n", $utf8)
        git add -- "docs/OWNER.md" 2>&1 | Out-Null
    }
    git commit -q -m "test(fake): fake work (TASK $num)" 2>&1 | Out-Null
    Write-Text "pipeline\report.md" "REPORT: $num - fake task`r`nSTATUS: DONE`r`n`r`nPROOFS:`r`n- images: none`r`n"
} else {
    $n = [regex]::Match($prompt, 'carries the number (\d+)').Groups[1].Value
    $lines = @(Get-Content $env:FAKE_SCENARIO | Where-Object { $_.Trim() -and -not $_.StartsWith("#") })
    $k = [int]$n - 1
    if ($k -ge $lines.Count) { $k = $lines.Count - 1 }
    $line = $lines[$k] -split "\s+"
    $verdict = $line[0]; $next = $line[1]
    # Markers of the packet sections (headings, never words of the reviewer's instructions).
    $breaker = $prompt -match "## CIRCUIT BREAKER:"; $taste = $prompt -match "## docs/TASTE\.md \("
    $gate = $prompt -match "## VERIFICATION GATE \("; $diff = $prompt -match "## CODE DIFF"
    $bench = $prompt -match "## BACKGROUND BENCHMARKS"; $load = $prompt -match "## LOAD TEST ON NEW SEEDS"
    # Several duos: the reviewer keeps to its lane; without a lane, nothing to do.
    $lane = [regex]::Match($prompt, '(?m)^YOUR LANE: (\S+)').Groups[1].Value
    if ($lane -eq "-") { $next = "NONE" }
    $mediation = $prompt -match "## MEDIATOR RESOLUTION"
    Trace "REVIEW pass=$n verdict=$verdict next=$next breaker=$breaker taste=$taste gate=$gate diff=$diff bench=$bench load=$load model=$model lane=$lane mediation=$mediation"
    Evt ([ordered]@{ type = "assistant"; message = [ordered]@{ content = @([ordered]@{ type = "tool_use"; id = "t1"; name = "Read"; input = [ordered]@{ file_path = "pipeline\report.md" } }) } })
    if ($verdict -eq "NONE") { Write-Text "pipeline\review.md" "VERDICT: NONE (first pass)`r`n" }
    else { Write-Text "pipeline\review.md" "VERDICT: $verdict`r`n`r`nfake verdict of pass $n`r`n" }
    if ($breaker -and $verdict -eq "REJECT") {
        [IO.File]::AppendAllText((Join-Path (Get-Location) "docs\QUESTIONS.md"), "`r`n``````r`nQtest (test) - circuit breaker question, pass $n`r`n``````r`n", $utf8)
    }
    foreach ($opt in $line[2..($line.Count)]) {
        if ($opt -match '^MILESTONE=(\S+)$') {
            $plan = Join-Path (Get-Location) "docs\PLAN.md"
            $t = [IO.File]::ReadAllText($plan, $utf8) -replace '(?m)^MILESTONE\s*:\s*\S+', ("MILESTONE: " + $Matches[1])
            [IO.File]::WriteAllText($plan, $t, $utf8)
        }
    }
    $tier = ($line | Where-Object { $_ -match '^MODEL=' }) -replace '^MODEL=', ''
    if ($next -eq "NONE") { Write-Text "pipeline\task.md" "TASK: NONE`r`n`r`nNothing to do (harness test).`r`n" }
    else {
        $bracket = if ($line -contains "END=1") { "[End of M1]" } else { "[M1-0$n]" }
        $l = "TASK: $n - $bracket fake task $n`r`nDOMAINS: code`r`n"
        if ($tier) { $l += "MODEL: $tier`r`n" }
        Write-Text "pipeline\task.md" ($l + "`r`n## Goal`r`nNothing.`r`n`r`nPROOFS:`r`n- images: none`r`n")
    }
}
Evt ([ordered]@{ type = "result"; subtype = "success"; is_error = $false; total_cost_usd = 0.01; session_id = "fake-$PID"; num_turns = 2; result = "fake done" })
# The real CLI still writes a line AFTER the result.
Evt ([ordered]@{ type = "system"; subtype = "task_summary"; detail = $null; session_id = "fake-$PID" })
exit 0
