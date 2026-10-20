# END-TO-END TEST WITH TWO DUOS, without a model nor any cost, ~8 min.
#   powershell -File bin\harness\test\test-two-duos.ps1     (one OK/KO line per check)
# Copies THIS working tree into a throwaway repo in %TEMP%; a test milestone M9 with three lanes
# (sim and art independent; render waits for sim) and its end; orchestrator + mediator + two duos with
# the fake claude; every task appends a line at the end of docs/OWNER.md, so the merges collide.
# Checks: lanes assigned (A=sim, B=art), each reviewer bounded to its lane, merge blocked ->
# mediator -> resolution -> duo restarted, work of both sides kept, resolution read at the next
# pass, nothing survives. Touches neither this repo nor GitHub. Exit code 1 on any KO.
param([int]$TimeoutS = 900)
$ErrorActionPreference = "Continue"
$env:GIT_TERMINAL_PROMPT = "0"; $env:GIT_LFS_SKIP_SMUDGE = "1"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-two-duos-" + (Get-Date -Format "yyMMdd-HHmmss"))
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
$D = Join-Path $T "repo"; $DB = Join-Path $T "repo-b"
G clone -q (Join-Path $T "github.git") $D | Out-Null
Push-Location $D
G config user.email "test@harness" | Out-Null; G config user.name "test harness" | Out-Null
G checkout -q -B main origin/main | Out-Null
"A   .        build-a   no`r`nB   repo-b   build-b   no" | Set-Content "config\duos.txt" -Encoding ASCII
$plan = [IO.File]::ReadAllText("$D\docs\PLAN.md", $utf8) -replace '(?m)^MILESTONE\s*:\s*\S+', 'MILESTONE: M9'
[IO.File]::WriteAllText("$D\docs\PLAN.md", $plan, $utf8)
$bl = @"
# Backlog M9 (test)

## M9-01 - sim

**Prerequisites**: -. **Domains**: code.
**Lane**: sim. **Zones**: src/sim.
- [ ] a

## M9-02 - art

**Prerequisites**: -. **Domains**: code.
**Lane**: art. **Zones**: tools/image.
- [ ] a

## M9-03 - render, waits for sim

**Prerequisites**: M9-01. **Domains**: visual.
**Lane**: render. **Zones**: src/render.
- [ ] a

## End of M9

**Prerequisites**: M9-01 to M9-03.
- [ ] build
"@
[IO.File]::WriteAllText("$D\docs\backlog\M9-test.md", $bl, $utf8)
G add -A config docs | Out-Null; G commit -q -m "test: M9 with lanes" | Out-Null; G push -q origin main | Out-Null
Pop-Location

$scen = Join-Path $T "scenario.txt"
@("ACCEPT TASK") * 6 + @("ACCEPT NONE") * 8 | Set-Content $scen -Encoding UTF8
$env:FAKE_SCENARIO = $scen
$env:FAKE_CONFLICT = "1"
$env:FAKE_MEDIATOR = "union"
$env:NTFY_TOPIC = "FILE:" + (Join-Path $T "ntfy.txt")
$env:HARNESS_CLAUDE_CLI = Join-Path $D "bin\harness\test\fake-claude.cmd"
$env:HARNESS_POLL_IDLE_S = "2"
$env:HARNESS_GATE_CMDS = "git --version"
$env:HARNESS_GATE_TIMEOUT_S = "60"
$env:HARNESS_GATE_VISUAL_CMD = "git --version"
$env:HARNESS_GATE_LINT_HARNESS_CMD = "git --version"
Remove-Item Env:FAKE_QUOTA -ErrorAction SilentlyContinue

$orch = Start-Process powershell -PassThru -WindowStyle Hidden -WorkingDirectory $D -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$D\bin\harness\orchestrator.ps1`"", "-RoundS", "5")
function Read-Logs([string]$R, [string]$Filter) { (Get-ChildItem (Join-Path $R "logs") -Filter $Filter -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n" }
$start = Get-Date; $done = $false
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutS) {
    Start-Sleep -Seconds 5
    $jo = Read-Logs $D "orchestrator-*.log"; $ja = Read-Logs $D "harness-*.log"; $jb = Read-Logs $DB "harness-*.log"
    $asleep = ($ja -match "asleep") -and ($jb -match "asleep")
    if ($asleep -and ($jo -match "mediator finished \(code 0\)") -and -not ($jo -match "mediator called[^\n]*\n(?![\s\S]*mediator finished)")) { $done = $true; break }
}
Set-Content (Join-Path $D "STOP-ALL") "end of test"
if (-not $orch.WaitForExit(30000)) { Stop-Process -Id $orch.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 10
$jo = Read-Logs $D "orchestrator-*.log"; $ja = Read-Logs $D "harness-*.log"; $jb = Read-Logs $DB "harness-*.log"
$ta = "" + (Get-Content "$D\.state\fake-trace.txt" -Raw -ErrorAction SilentlyContinue)
$tb = "" + (Get-Content "$DB\.state\fake-trace.txt" -Raw -ErrorAction SilentlyContinue)
$merges = @([regex]::Matches($ja + "`n" + $jb, 'harness : (task/\d+\S*) merged into main') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$owner = G -C $D show main:docs/OWNER.md
$notes = @([regex]::Matches($owner, 'note of task (\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

L $done "both duos run until asleep, mediations included, in less than $TimeoutS s"
L ($jo -match "lanes \(M9\) : A=sim B=art") "lanes assigned: A=sim, B=art (render waits for sim)"
L (($ta -match "lane=sim") -and -not ($ta -match "lane=art")) "A's reviewer is bounded to the lane sim"
L (($tb -match "lane=art") -and -not ($tb -match "lane=sim")) "B's reviewer is bounded to the lane art"
L (($ja + $jb) -match "reviewer : MERGE BLOCKED") "the merges collide (a line at the end of OWNER.md)"
L ($jo -match "mediator called") "the orchestrator calls the mediator"
L (($ja + $jb) -match "mediator \(duo [AB]\) : task/\S+ merged after resolution") "the mediator solves and merges"
L ($jo -match "mediator finished \(code 0\)[\s\S]*duo [AB] : started") "the duo is restarted after the mediation"
L (($ta + $tb) -match "mediation=True") "the next reviewer gets the mediator's resolution"
L (($merges.Count -ge 5) -and ($notes.Count -ge $merges.Count)) "work of both sides kept: $($merges.Count) merges, $($notes.Count) notes in main's OWNER.md"
L (-not ($owner -match '(?m)^(<<<<<<<|>>>>>>>)')) "no conflict marker on main"
L (-not (($jo + $ja + $jb) -match "guard:")) "the guard does not trip on a clean resolution"
$nones = [regex]::Matches($ja + "`n" + $jb, "reviewer : TASK: NONE").Count
L ($nones -le 6) "asleep does not run the reviewer in a loop ($nones TASK: NONE passes)"
L (-not ($jo -match "mediator finished \(code 1\)")) "no failed mediation (no false alarm)"
L ((G -C $D rev-parse main).Trim() -eq (G --git-dir (Join-Path $T "github.git") rev-parse main).Trim()) "main pushed to the remote"
$left = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($T) })
$left | ForEach-Object { & taskkill /PID $_.ProcessId /T /F 2>&1 | Out-Null }
L ($left.Count -eq 0) "no process of the test repo survives ($(@($left | ForEach-Object { $_.Name }) -join ', '))"
foreach ($k in @("FAKE_SCENARIO", "FAKE_CONFLICT", "FAKE_MEDIATOR", "NTFY_TOPIC")) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
Get-ChildItem Env: | Where-Object { $_.Name -like "HARNESS_*" } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
Write-Host ("TEST TWO DUOS : {0} checks ; test repo : {1}" -f $n, $T)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
