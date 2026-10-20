# TEST OF THE ORCHESTRATOR WITH TWO DUOS, without a model nor any cost, ~5 min.
#   powershell -File bin\harness\test\test-orchestrator.ps1     (one OK/KO line per check)
# Copies THIS working tree into a throwaway repo in %TEMP% (with a local "GitHub"), runs
# orchestrator.ps1 there with the fake claude for two duos (A = the repo, B = a worktree the
# orchestrator creates): shared and distinct task numbers, merges without blocking under the shared
# lock, duo loop killed then restarted, a duo without a task detached from main, STOP-ALL.
# Touches neither this repo nor GitHub. Exit code 1 on any KO.
param([int]$TimeoutS = 600)
$ErrorActionPreference = "Continue"
$env:GIT_TERMINAL_PROMPT = "0"; $env:GIT_LFS_SKIP_SMUDGE = "1"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-orchestrator-" + (Get-Date -Format "yyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $T | Out-Null
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }
function G { & git @args 2>&1 | Out-String }

# The working tree (committed or not) becomes the first commit of a throwaway "GitHub".
$seed = Join-Path $T "seed"
& robocopy $Source $seed /E /XD .git .state logs __pycache__ /XF STOP STOP-ALL project.env .mcp.json /NFL /NDL /NJH /NJS /NP | Out-Null
G -C $seed init -q -b main | Out-Null
G -C $seed add -A | Out-Null
G -C $seed -c user.email=t@t -c user.name=t commit -q -m "test: seed" | Out-Null
G clone -q --bare $seed (Join-Path $T "github.git") | Out-Null
$D = Join-Path $T "repo"; $DB = Join-Path $T "repo-b"
G clone -q (Join-Path $T "github.git") $D | Out-Null
Push-Location $D
G config user.email "test@harness" | Out-Null; G config user.name "test harness" | Out-Null
G checkout -q -B main origin/main | Out-Null
"A   .        build-a   yes`r`nB   repo-b   build-b   no" | Set-Content "config\duos.txt" -Encoding ASCII
# A test milestone with two ready lanes: without them, one duo only would run (wanted).
$u8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText("$D\docs\PLAN.md", ([IO.File]::ReadAllText("$D\docs\PLAN.md", $u8) -replace '(?m)^MILESTONE\s*:\s*\S+', 'MILESTONE: M9' -replace '(?m)^PARALLEL_MILESTONE\s*:.*\r?\n', ''), $u8)
[IO.File]::WriteAllText("$D\docs\backlog\M9-test.md", "# M9 (test)`n`n## M9-01 - one`n`n**Lane**: one. **Zones**: src/sim.`n- [ ] a`n`n## M9-02 - two`n`n**Lane**: two. **Zones**: tools/image.`n- [ ] a`n", $u8)
G add -A config docs | Out-Null; G commit -q -m "test: duos and lanes" | Out-Null; G push -q origin main | Out-Null
Pop-Location

# Shared scenario (shared numbers): 6 accepted tasks, then nothing to do.
$scen = Join-Path $T "scenario.txt"
@("ACCEPT TASK") * 6 + @("ACCEPT NONE") * 6 | Set-Content $scen -Encoding UTF8
$tool = Join-Path $T "fake-load.py"
Set-Content -Path $tool -Encoding ASCII -Value "import sys`nopen(sys.argv[-1], 'a').write('FAKE ' + ' '.join(sys.argv[1:-1]) + ' : OK\n')"
$env:FAKE_SCENARIO = $scen
$env:NTFY_TOPIC = "FILE:" + (Join-Path $T "ntfy.txt")
$env:HARNESS_CLAUDE_CLI = Join-Path $D "bin\harness\test\fake-claude.cmd"
$env:HARNESS_POLL_IDLE_S = "2"
$env:HARNESS_GATE_CMDS = "git --version"
$env:HARNESS_GATE_TIMEOUT_S = "60"
$env:HARNESS_GATE_VISUAL_CMD = "git --version"
$env:HARNESS_GATE_LINT_HARNESS_CMD = "git --version"
# A fake background load (duo A only, config/duos.txt): the real one would build the test repo.
$env:HARNESS_BACKGROUND_LOAD_CMD = "python `"$tool`" head={HEAD} task={TASK} {OUT}"
Remove-Item Env:FAKE_QUOTA -ErrorAction SilentlyContinue

$orch = Start-Process powershell -PassThru -WindowStyle Hidden -WorkingDirectory $D -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$D\bin\harness\orchestrator.ps1`"", "-RoundS", "5")
function Read-Journal([string]$R) { (Get-ChildItem (Join-Path $R "logs") -Filter "harness-*.log" -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n" }
$start = Get-Date; $killed = $false; $done = $false
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutS) {
    Start-Sleep -Seconds 3
    # Once, kill B's duo loop: the orchestrator must restart it.
    if (-not $killed -and (Test-Path "$DB\.state\duo.pid")) {
        $p = (Get-Content "$DB\.state\duo.pid" -Raw).Trim()
        if ($p -match '^\d+$' -and (Read-Journal $DB) -match "merged into main") {
            Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue; $killed = $true
        }
    }
    $ja = Read-Journal $D; $jb = Read-Journal $DB
    if ($killed -and ($ja -match "asleep") -and ($jb -match "asleep") -and ($jb -match "duo : started[\s\S]*duo : started")) { $done = $true; break }
}
Set-Content (Join-Path $D "STOP-ALL") "end of test"
if (-not $orch.WaitForExit(30000)) { Stop-Process -Id $orch.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 8
$ja = Read-Journal $D; $jb = Read-Journal $DB
$jo = (Get-ChildItem (Join-Path $D "logs") -Filter "orchestrator-*.log" | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$tasks = @([regex]::Matches($ja + "`n" + $jb, 'reviewer : TASK: (\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
$merges = @([regex]::Matches($ja + "`n" + $jb, 'harness : (task/\d+\S*) merged into main') | ForEach-Object { $_.Groups[1].Value })
$mainLog = G -C $D log --oneline main

L $done "both duos run until asleep in less than $TimeoutS s"
L ($jo -match "lanes \(M9\) : A=one B=two") "two ready lanes: A=one, B=two"
L ($jo -match "duo A : started" -and $jo -match "duo B : started") "the orchestrator starts A and B"
L ($jo -match "duo B : worktree created") "the orchestrator creates B's worktree"
L (($ja -match "reviewer : TASK: \d") -and ($jb -match "reviewer : TASK: \d")) "both duos write tasks"
L (($tasks.Count -ge 6) -and (@($tasks | Sort-Object -Unique).Count -eq $tasks.Count)) "shared and distinct task numbers ($($tasks -join ', '))"
L (($merges.Count -ge 5) -and -not (($ja + $jb) -match "MERGE BLOCKED")) "$($merges.Count) merges into main, none blocked"
L (@($merges | ForEach-Object { $mainLog -match [regex]::Escape("merge $_") } | Where-Object { -not $_ }).Count -eq 0) "every announced merge is in main"
L ($jo -match "duo B : started[\s\S]*duo B : started") "B's duo loop killed: the orchestrator restarts it"
L (($ja + $jb) -match "has no task: detached from main") "a duo without a task detaches from main"
L ((G -C $DB rev-parse --abbrev-ref HEAD).Trim() -ne "main") "B does not hold main at the end"
L ($ja -match "gate : load test on new seeds started in the background" -and -not ($jb -match "load test on new seeds")) "background load: duo A only (config/duos.txt)"
L ($jo -match "STOP-ALL") "STOP-ALL stops the orchestrator"
L ((Test-Path "$D\STOP") -and (Test-Path "$DB\STOP")) "STOP-ALL puts STOP in every duo"
$left = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($T) })
$left | ForEach-Object { & taskkill /PID $_.ProcessId /T /F 2>&1 | Out-Null }
L ($left.Count -eq 0) "no process of the test repo survives ($(@($left | ForEach-Object { $_.Name }) -join ', '))"
foreach ($k in @("FAKE_SCENARIO", "NTFY_TOPIC")) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
Get-ChildItem Env: | Where-Object { $_.Name -like "HARNESS_*" } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
Write-Host ("TEST ORCHESTRATOR : {0} checks ; test repo : {1}" -f $n, $T)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
