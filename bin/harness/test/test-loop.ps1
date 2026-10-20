# TEST OF THE DUO LOOP, without a model nor any cost.
#   powershell -File bin\harness\test\test-loop.ps1     (~5 min; one OK/KO line per check)
# Copies THIS working tree into a throwaway repo in %TEMP% with a local "GitHub" (bare repo), runs
# duo.ps1 with the fake claude and a scenario: first pass, ACCEPT (merge), milestone change, model
# tier, rejections up to the circuit breaker (branch set aside, question), ACCEPT, then TASK: NONE
# (asleep) and STOP. Notifications go to a file. Touches neither this repo nor GitHub.
# Exit code 1 on any KO.
param([int]$TimeoutS = 600)
$ErrorActionPreference = "Continue"
$env:GIT_TERMINAL_PROMPT = "0"; $env:GIT_LFS_SKIP_SMUDGE = "1"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-loop-" + (Get-Date -Format "yyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $T | Out-Null
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }
function G { & git @args 2>&1 | Out-String }

# The working tree (committed or not) becomes the first commit of a throwaway repo, then its "GitHub".
$seed = Join-Path $T "seed"
& robocopy $Source $seed /E /XD .git .state logs __pycache__ /XF STOP STOP-ALL project.env .mcp.json /NFL /NDL /NJH /NJS /NP | Out-Null
G -C $seed init -q -b main | Out-Null
G -C $seed add -A | Out-Null
G -C $seed -c user.email=t@t -c user.name=t commit -q -m "test: seed" | Out-Null
G clone -q --bare $seed (Join-Path $T "github.git") | Out-Null
$D = Join-Path $T "repo"
G clone -q (Join-Path $T "github.git") $D | Out-Null
Push-Location $D
G config user.email "test@harness" | Out-Null; G config user.name "test harness" | Out-Null
G checkout -q -B main origin/main | Out-Null
Set-Content -Path "docs\TASTE.md" -Value "# Taste (test)`r`n- prefers green tests." -Encoding UTF8
G add docs/TASTE.md | Out-Null; G commit -q -m "test: taste" | Out-Null
# The start milestone is the one of the copied repo.
$startMilestone = [regex]::Match((Get-Content "docs\PLAN.md" -Raw), '(?m)^MILESTONE\s*:\s*(\S+)').Groups[1].Value
Pop-Location
# The owner pushes to "GitHub" a change the local main does not have.
$P = Join-Path $T "owner"
G clone -q (Join-Path $T "github.git") $P | Out-Null
G -C $P checkout -q -B main origin/main | Out-Null
Set-Content -Path (Join-Path $P "OWNER.txt") -Value "change pushed by the owner" -Encoding UTF8
G -C $P add OWNER.txt | Out-Null
G -C $P -c user.email=p@p -c user.name=owner commit -q -m "owner: pushed change" | Out-Null
G -C $P push -q origin main | Out-Null

# The reviewer's scenario, one pass per line: VERDICT NEXT [MILESTONE=x] [MODEL=tier] [END=1]
$scen = Join-Path $T "scenario.txt"
@(
    "NONE TASK",                                # 1: first pass -> task 1 (branch task/001-m1-01)
    "ACCEPT TASK MILESTONE=M2 MODEL=mid END=1", # 2: merge of 1, milestone change (notif), task 2 mid, "End of M1"
    "REJECT TASK MODEL=mid",                    # 3: rejection 1 of task/002; fix mid -> default
    "REJECT TASK MODEL=mid",                    # 4: rejection 2 = REJECT_MAX (notif); fix -> top
    "REJECT TASK",                              # 5: under CIRCUIT BREAKER, rejection 3 -> set aside, question, task 5
    "ACCEPT NONE"                               # 6: merge of task/005, then asleep
) | Set-Content -Path $scen -Encoding UTF8
# A fake bench/load tool: writes its arguments (placeholders replaced) to its output file.
$tool = Join-Path $T "fake-bench.py"
Set-Content -Path $tool -Encoding ASCII -Value "import sys`nopen(sys.argv[-1], 'a').write('FAKE ' + ' '.join(sys.argv[1:-1]) + ' : OK\n')"

$ntfy = Join-Path $T "ntfy.txt"
$env:FAKE_SCENARIO = $scen
$env:NTFY_TOPIC = "FILE:$ntfy"
$env:HARNESS_CLAUDE_CLI = Join-Path $D "bin\harness\test\fake-claude.cmd"
$env:HARNESS_POLL_IDLE_S = "2"
$env:HARNESS_REJECT_MAX = "2"
$env:HARNESS_CODER_MODEL = "default-test"; $env:HARNESS_CODER_FALLBACK = "top-test"
$env:HARNESS_REVIEWER_MODEL = "reviewer-test"; $env:HARNESS_REVIEWER_ESCALATION = "top-reviewer-test"
$env:HARNESS_MODEL_MID = "mid-test"; $env:HARNESS_MODEL_TOP = "top-test"
$env:FAKE_QUOTA = "reviewer-test"   # credit of the current model exhausted: the reviewer switches models
$env:HARNESS_GATE_CMDS = "git --version;exit 1"
$env:HARNESS_GATE_TIMEOUT_S = "60"
# Extra gate checks, cheap in the test: the real harness lint, a dummy visual command, the fake
# bench tool (checks the placeholders) in the background, the end-of-milestone gate and the
# background load test.
$env:HARNESS_GATE_VISUAL_CMD = "git --version"
$env:HARNESS_GATE_BENCH_CMD = "python `"$tool`" base={BASE} head={HEAD} task={TASK} {HEAVY} {OUT}"
$env:HARNESS_MILESTONE_BENCH_CMD = "python `"$tool`" milestone={BASE_MILESTONE} logs/milestone-bench.txt"
$env:HARNESS_MILESTONE_LOAD_CMD = "python `"$tool`" load={MILESTONE} logs/milestone-load.txt"
$env:HARNESS_BACKGROUND_LOAD_CMD = "python `"$tool`" seeds head={HEAD} task={TASK} {OUT}"

$duo = Start-Process powershell -PassThru -WindowStyle Hidden -WorkingDirectory $D -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $D 'bin\harness\duo.ps1')`"")
$start = Get-Date; $asleep = $false; $log = $null
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutS) {
    Start-Sleep -Seconds 3
    $log = Get-ChildItem (Join-Path $D "logs") -Filter "harness-*.log" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($log -and (Select-String -Path $log.FullName -Pattern "asleep" -Quiet)) { $asleep = $true; break }
    if ($duo.HasExited) { break }
}
Set-Content -Path (Join-Path $D "STOP") -Value "end of test"
if (-not $duo.WaitForExit(30000)) { Stop-Process -Id $duo.Id -Force -ErrorAction SilentlyContinue }

Push-Location $D
$journal = if ($log) { Get-Content $log.FullName -Raw } else { "" }
$trace = "" + (Get-Content ".state\fake-trace.txt" -Raw -ErrorAction SilentlyContinue)
$notifs = "" + (Get-Content $ntfy -Raw -ErrorAction SilentlyContinue)
$branches = G branch --list "task/*"
L $asleep "the loop runs until asleep (TASK: NONE) in less than $TimeoutS s"
L ($journal -match "duo : started \(pid \d+, config") "the duo journal starts with its pid and config"
L ($journal -match "harness : task/001-m1-01 merged into main") "ACCEPT: task/001 merged into main"
L ((G show "task/001-m1-01:OWNER.txt") -match "owner") "an owner push to GitHub reaches the branch of the next task"
L ($journal -match "harness : task/002 SET ASIDE") "circuit breaker: task/002 set aside after 3 rejections"
L ($branches -match "task/002\b") "the branch set aside is kept"
L (-not ((G branch --merged main) -match "task/002\b")) "the branch set aside is not merged"
L ($journal -match "harness : task/005-m1-05 merged into main") "after the set-aside, the next task starts from main and merges"
L ((G show main:docs/QUESTIONS.md) -match "Qtest") "the circuit breaker question is on main"
L ($trace -match "pass=5 verdict=REJECT next=TASK breaker=True") "the reviewer gets the CIRCUIT BREAKER section at the right pass"
L ($trace -match "taste=True") "the reviewer gets docs/TASTE.md"
L ($journal -match "gate : 1 KO") "gate: the harness runs the commands and counts one KO (exit 1)"
L ($trace -match "pass=2 .*gate=True diff=True") "the reviewer gets the gate and the code diff"
L ($journal -match "gate : 1 KO \(10 checks\)") "full gate: 10 checks (2 commands, 3 extra, 5 fixed), only the wanted KO"
L ($journal -match "gate : 1 KO \(12 checks\)") "end of milestone: the gate adds milestone benchmarks and load test (12 checks)"
L ((Test-Path ".state\milestone-bench.txt") -and ((Get-Content ".state\milestone-bench.txt" -Raw).Trim().Length -eq 40)) "end of milestone: the benchmark reference is set (.state/milestone-bench.txt)"
L ($journal -match "gate : benchmarks started in the background") "benchmarks started in the background after the gate"
L ($trace -match "bench=True") "the next reviewer gets the verdict of the background benchmarks"
$benchHist = @(Get-ChildItem "pipeline\history" -Filter "*-bench.md" -ErrorAction SilentlyContinue)
L ($benchHist.Count -ge 1) "verdict read then archived in pipeline/history"
$benchTxt = ($benchHist | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
L ($benchTxt -match "base=[0-9a-f]{40} head=[0-9a-f]{40} task=\d+ --heavy") "placeholders {BASE} {HEAD} {TASK} {HEAVY} replaced (end of milestone: --heavy)"
L ($journal -match "gate : load test on new seeds started in the background") "load test on new seeds started in the background"
L ($trace -match "load=True") "the next reviewer gets the background load test"
L ($journal -match "Reason: end of test") "the reason of a STOP is in the journal"
L ($trace -match "CODER task=2 model=mid-test") "tier: MODEL: mid -> the mid model"
L ($trace -match "CODER task=1 model=default-test") "default tier: the default model"
L ($trace -match "CODER task=3 model=default-test") "1 rejection of a mid task: the fix moves to the default model"
L ($trace -match "CODER task=4 model=top-test") "2 rejections: the fix moves to the top model"
L (-not ($journal -match "reviewer : escalation")) "planning does not escalate the reviewer (the top model only for images)"
L ($journal -match "quota : reviewer-test closed until .*announced reset") "quota: the reset time of the message is kept"
L ($trace -match "REVIEW pass=1 .*model=top-reviewer-test") "credit of the current model exhausted: the same pass switches to the other model"
L (-not ($journal -match "duo : quota closed")) "a credit switch does not pause the duo"
L ($notifs -match "$startMilestone finished") "notification: end of milestone ($startMilestone)"
L ($notifs -match "2 rejections in a row") "notification: rejections at the threshold"
L ($notifs -match "task set aside") "notification: task set aside"
L ($notifs -match "duo asleep") "notification: asleep"
L ((G rev-parse main).Trim() -eq (G --git-dir (Join-Path $T "github.git") rev-parse main).Trim()) "main is pushed to the remote"
$calls = @(Get-ChildItem "logs" -Filter "*-*-*.log" | Where-Object { $_.Name -match '-(coder|reviewer)' })
$noResult = @($calls | Where-Object { -not (Select-String -Path $_.FullName -Pattern '"type":"result"' -Quiet) })
L ($calls.Count -ge 10 -and $noResult.Count -eq 0) "stream-json: $($calls.Count) call logs, each with its result line"
L ((Test-Path ".state\progress.txt") -and ((Get-Content ".state\progress.txt" -Raw) -match "Skill|Read")) "live progress (.state/progress.txt)"
$agg = python tools/costs/agg_logs.py --logs logs 2>&1 | Out-String
L ($agg -match "game-feel") "agg_logs.py counts the skills loaded"
Pop-Location
foreach ($k in @("FAKE_SCENARIO", "FAKE_QUOTA", "NTFY_TOPIC")) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
Get-ChildItem Env: | Where-Object { $_.Name -like "HARNESS_*" } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
Write-Host ("TEST LOOP : {0} checks ; test repo : {1}" -f $n, $T)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
