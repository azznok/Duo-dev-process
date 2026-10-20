# VERIFICATION GATE - dot-source it AFTER lib\common.ps1 (uses $Root, $Cfg, $Pipe, Note).
# The harness, not the coder, runs the checks on the task branch and writes pipeline/gate.md
# (one OK/KO line per check), put in the reviewer's packet. The reviewer has no build tools:
# without the gate, it judged the tests on the word of the report.
#   GATE_CMDS     : ";"-separated commands (cmd.exe), each with GATE_TIMEOUT_S. Those matching
#                   GATE_HEAVY_MATCH wait for the other duo's heavy build and run one at a time.
#   Extra checks  : readable harness (GATE_LINT_HARNESS_CMD), goldens and input scenarios in a
#                   window (GATE_VISUAL_CMD), benchmarks against the base (GATE_BENCH_CMD, {BASE}
#                   replaced; IN THE BACKGROUND if GATE_BENCH_BACKGROUND=1: Start-BackgroundBench,
#                   verdict in pipeline/bench.md); the last two skipped when only docs changed
#                   (except at the end of a milestone).
#   END OF MILESTONE: Invoke-MilestoneGate, full benchmarks then load test, machine idle;
#                   on each task, no benchmarks by default (GATE_BENCH_CMD empty).
#   Fixed checks  : commit messages, files > 10 MB, protected docs untouched, generated ADR
#                   index not edited, report size.
# Placeholders in background commands: {HEAD} (frozen revision), {TASK} (task number),
# {OUT} (pipeline/bench.md or pipeline/load.md), {HEAVY} ("--heavy" at the end of a milestone).

# Shared "suite" lock (lib\shared.ps1) around heavy suites.
if (-not (Get-Command Enter-SharedLock -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "shared.ps1") }

function Get-LargeFiles([string]$Repo, [string]$Base) {
    # Files added or modified since $Base whose git BLOB exceeds 10 MB: what really enters the
    # history forever. A file tracked by LFS only stores a pointer (~130 bytes): it passes,
    # whatever its size on disk (it caused false KOs when the size on disk was measured).
    $touched = @{}
    foreach ($f in @(git -C $Repo -c core.quotepath=off diff --name-only --diff-filter=AM "$Base..HEAD" 2>$null)) { $touched[$f] = $true }
    $large = @()
    foreach ($l in @(git -C $Repo -c core.quotepath=off ls-tree -r -l HEAD 2>$null)) {
        if ($l -match '^\S+\s+blob\s+\S+\s+(\d+)\t(.+)$' -and $touched.ContainsKey($Matches[2]) -and [long]$Matches[1] -gt 10MB) { $large += $Matches[2] }
    }
    return $large
}

# Removed assertion lines and added skip markers, whatever the language (information only).
$RemovedAssertRx = '^-(?!--)(?:.*\W)?(?:\w*assert\w*!?\s*\(|assert\s|Assert\.\w+\s*\(|#\[test\]|#\[should_panic|@Test\b)|^-(?!--)(?:.*[^\w.])?(?:expect|it|test)\s*\('
$AddedSkipRx = '^\+(?!\+\+).*(?:#\[ignore|@skip|@Ignore|@Disabled|\.skip\s*\(|\bxit\s*\(|\bxdescribe\s*\(|pytest\.mark\.skip|unittest\.skip|\bt\.Skip\w*\s*\()'

function Get-TouchedTests([string]$Repo, [string]$Base) {
    # An agent facing a hard task tends to touch the tests instead of the code (seen in public
    # benchmarks of coding agents). Lists, for the reviewer, what MODIFIES or REMOVES an existing
    # test: golden images, test files, scenarios, removed assertions, added skip markers.
    # Adding tests stays free (not listed).
    $l = @()
    $rx = "" + $Cfg["TEST_PATH_REGEX"]
    foreach ($x in @(git -C $Repo -c core.quotepath=off diff --name-status --diff-filter=MDR "$Base..HEAD" 2>$null)) {
        $p = $x -split "`t"; $s = $p[0].Substring(0, 1); $f = $p[$p.Count - 1]
        if ($f -match '(^|/)golden/') { $l += "golden $s : $f" }
        elseif ($rx -and $f -match $rx) { $l += "test $s : $f" }
    }
    $cur = ""; $n = [ordered]@{}
    foreach ($d in @(git -C $Repo -c core.quotepath=off diff -U0 "$Base..HEAD" -- . ':(exclude)*.md' 2>$null)) {
        if ($d -match '^\+\+\+ (?:b/)?(.+)$') { $cur = $Matches[1]; continue }
        if ($d -match '^---') { continue }
        if ($d -cmatch $RemovedAssertRx -or $d -cmatch $AddedSkipRx) { $n[$cur] = 1 + [int]$n[$cur] }
    }
    foreach ($k in $n.Keys) { $l += "assertions removed or changed, or skip marker added : $k ($($n[$k]) line(s))" }
    return $l
}

function Wait-OtherDuoHeavy([int]$MaxS = 1800) {
    # The test suite does not start while the OTHER duo runs its heavy build (processes matching
    # HEAVY_PROCESS_REGEX under another harness), else it overruns its timeout; 30 min wait at
    # most, then it starts anyway. Empty regex = never wait.
    $rx = ("" + $Cfg["HEAVY_PROCESS_REGEX"]).Trim()
    if (-not $rx) { return }
    if (-not (Get-Command Test-OtherHarness -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "shared.ps1") }
    $end = (Get-Date).AddSeconds($MaxS); $said = $false
    while ((Get-Date) -lt $end) {
        $all = @{}; foreach ($q in @(Get-CimInstance Win32_Process)) { $all[[int]$q.ProcessId] = $q }
        $others = @($all.Values | Where-Object { $_.Name -match $rx -and (Test-OtherHarness $_ $all) })
        if (-not $others.Count) { break }
        if (-not $said) { Note "gate : the other duo is building ($($others.Count) processes) : the tests wait"; $said = $true }
        Start-Sleep -Seconds 15
    }
}

function Invoke-GateCommand([string]$Command, [int]$TimeoutS) {
    $log = Join-Path $Logs ("gate-{0}.log" -f (Get-Date -Format "yyMMdd-HHmmss-fff"))
    $p = Start-Process cmd -ArgumentList @("/c", "$Command > `"$log`" 2>&1") -WorkingDirectory $Root -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($TimeoutS * 1000)) {
        try { Stop-Process -Id $p.Id -Force } catch {}
        return [pscustomobject]@{ Ok = $false; Detail = "timeout ($TimeoutS s)"; Log = $log }
    }
    $tail = ""
    if (Test-Path $log) { $tail = ((Get-Content $log -Tail 3 -Encoding UTF8 -ErrorAction SilentlyContinue) -join " | ") }
    return [pscustomobject]@{ Ok = ($p.ExitCode -eq 0); Detail = "code $($p.ExitCode) : $tail"; Log = $log }
}

function Start-BackgroundBench {
    # Starts the benchmarks chosen by the gate without waiting for them (called by run-coder
    # AFTER the stop-all cleanup). The bench tool should take its own lock: one measure at a time.
    if (-not $script:BackgroundBench) { return }
    $log = Join-Path $Logs ("bench-bg-{0}.log" -f (Get-Date -Format "yyMMdd-HHmmss"))
    $p = Start-Process cmd -ArgumentList @("/c", "$($script:BackgroundBench) > `"$log`" 2>&1") -WorkingDirectory $Root -PassThru -WindowStyle Hidden
    Note "gate : benchmarks started in the background (pid $($p.Id), log logs/$(Split-Path $log -Leaf))"
    $script:BackgroundBench = ""
}

function Start-BackgroundLoad {
    # Load test on new seeds, frozen revision, while the reviewer works. Verdict APPENDED to
    # pipeline/load.md, shown to the next reviewer (run-reviewer) then archived.
    if (-not $script:BackgroundLoad) { return }
    $log = Join-Path $Logs ("load-bg-{0}.log" -f (Get-Date -Format "yyMMdd-HHmmss"))
    $p = Start-Process cmd -ArgumentList @("/c", "$($script:BackgroundLoad) > `"$log`" 2>&1") -WorkingDirectory $Root -PassThru -WindowStyle Hidden
    Note "gate : load test on new seeds started in the background (pid $($p.Id), log logs/$(Split-Path $log -Leaf))"
    $script:BackgroundLoad = ""
}

function Add-GateLine([bool]$Ok, [string]$Name, [string]$Detail) {
    $script:GateLines += ("- [{0}] {1} : {2}" -f $(if ($Ok) { "OK " } else { "KO " }), $Name, $Detail)
    if (-not $Ok) { $script:GateKo++ }
}

function Expand-GatePlaceholders([string]$Command, [string]$Head, [string]$Task, [string]$Out, [bool]$Heavy) {
    return $Command.Replace("{HEAD}", $Head).Replace("{TASK}", $Task).Replace("{OUT}", $Out).Replace("{HEAVY}", $(if ($Heavy) { "--heavy" } else { "" }))
}

function Invoke-MilestoneGate {
    # Machine idle: no background load test during the benchmarks (the load tool holds this lock).
    $lock = Join-Path $Logs "load-bg.lock"; $t0 = Get-Date
    while ((Test-Path $lock) -and ((Get-Date) - $t0).TotalMinutes -lt 45) { Start-Sleep -Seconds 15 }
    # END-OF-MILESTONE task. The coder is done, the reviewer has not started: the machine is
    # idle. 1. every benchmark against the end of the previous milestone (.state/milestone-bench.txt;
    # OK -> HEAD becomes the reference of the next milestone); 2. the load test. A KO = a
    # rejection: fixes first, then a new test. An empty key skips its step.
    $refFile = Join-Path $State "milestone-bench.txt"
    $head = ("" + (git -C $Root rev-parse HEAD 2>$null)).Trim()
    $ref = if (Test-Path $refFile) { (Read-Utf8 $refFile).Trim() } else { "" }
    $c = ("" + $Cfg["MILESTONE_BENCH_CMD"]).Trim()
    if ($c -and -not $ref) {
        Write-Utf8 $refFile $head
        Add-GateLine $true "end-of-milestone benchmarks" "first measure : reference set ($($head.Substring(0, [Math]::Min(10, $head.Length)))), compared at the next milestone"
    } elseif ($c) {
        $r = Invoke-GateCommand $c.Replace("{BASE_MILESTONE}", $ref) ([int]$Cfg["GATE_BENCH_TIMEOUT_S"])
        $d = $r.Detail; if ($d.Length -gt 400) { $d = $d.Substring($d.Length - 400) }
        Add-GateLine $r.Ok "end-of-milestone benchmarks (against $($ref.Substring(0, [Math]::Min(10, $ref.Length))))" "$d (log : logs/$(Split-Path $r.Log -Leaf))"
        if ($r.Ok) { Write-Utf8 $refFile $head }
    }
    $c = ("" + $Cfg["MILESTONE_LOAD_CMD"]).Trim()
    if ($c) {
        $r = Invoke-GateCommand $c.Replace("{MILESTONE}", (Get-Milestone)) ([int]$Cfg["LOAD_TIMEOUT_S"])
        $d = $r.Detail; if ($d.Length -gt 400) { $d = $d.Substring($d.Length - 400) }
        Add-GateLine $r.Ok "end-of-milestone load test" "$d (log : logs/$(Split-Path $r.Log -Leaf))"
    }
}

function Invoke-Gate([string]$Base, [string]$Report) {
    $script:BackgroundBench = ""; $script:BackgroundLoad = ""
    $script:GateLines = @(); $script:GateKo = 0
    $timeout = [int]$Cfg["GATE_TIMEOUT_S"]
    $heavyRx = ("" + $Cfg["GATE_HEAVY_MATCH"]).Trim()
    foreach ($c in @(Get-GateCmds)) {
        $heavy = $heavyRx -and ($c -match $heavyRx)
        # One heavy suite at a time across duos, and not during the other duo's build.
        if ($heavy) { Wait-OtherDuoHeavy; [void](Enter-SharedLock "suite" 3600) }
        try { $r = Invoke-GateCommand $c $timeout } finally { if ($heavy) { Exit-SharedLock "suite" } }
        $d = $r.Detail; if ($d.Length -gt 220) { $d = $d.Substring($d.Length - 220) }
        Add-GateLine $r.Ok $c "$d (log : logs/$(Split-Path $r.Log -Leaf))"
    }
    # Extra checks, each with its own timeout. Empty key = check disabled.
    $code = $true   # without a base we do not know: check everything
    if ($Base) {
        $touched = @(git -C $Root diff --name-only "$Base..HEAD" 2>$null | Where-Object { $_ })
        $code = @($touched | Where-Object { $_ -notmatch '^(docs|pipeline|\.claude|supervisor|logs)/' -and $_ -notmatch '\.md$' }).Count -gt 0
    }
    # End of milestone: the heavy benchmarks run too, even when only docs changed.
    $taskText = Read-Utf8 (Join-Path $Pipe "task.md")
    $milestoneEnd = $taskText -match '(?im)^TASK:[^\[\r\n]*\[\s*end of (M\d+|milestone)\b'
    $taskNum = [regex]::Match($taskText, '^TASK:\s*(\d+)').Groups[1].Value
    $extra = @(
        @{ Name = "readable harness"; Key = "GATE_LINT_HARNESS_CMD"; Timeout = $timeout; Always = $true },
        @{ Name = "goldens and input scenarios (window)"; Key = "GATE_VISUAL_CMD"; Timeout = [int]$Cfg["GATE_VISUAL_TIMEOUT_S"]; Always = $false },
        @{ Name = "benchmarks vs base"; Key = "GATE_BENCH_CMD"; Timeout = [int]$Cfg["GATE_BENCH_TIMEOUT_S"]; Always = $milestoneEnd }
    )
    foreach ($x in $extra) {
        $c = ("" + $Cfg[$x.Key]).Trim(); if (-not $c -or $c -eq "off") { continue }
        if (-not $x.Always -and -not $code) { Add-GateLine $true $x.Name "not applicable : only docs changed"; continue }
        if ($c -match '\{BASE\}') { if (-not $Base) { Add-GateLine $true $x.Name "not applicable : no base"; continue }; $c = $c.Replace("{BASE}", $Base) }
        $head = ("" + (git -C $Root rev-parse HEAD 2>$null)).Trim()
        if ($x.Key -eq "GATE_BENCH_CMD" -and $Cfg["GATE_BENCH_BACKGROUND"] -eq "1") {
            # Measures IN THE BACKGROUND, while the reviewer works (0 min of cycle); verdict in
            # pipeline/bench.md, read at the next pass. Frozen revision: HEAD will move.
            $script:BackgroundBench = Expand-GatePlaceholders $c $head $taskNum "pipeline/bench.md" $milestoneEnd
            Add-GateLine $true $x.Name "started in the background after the gate ; verdict at the reviewer's next pass"
            continue
        }
        $c = Expand-GatePlaceholders $c $head $taskNum "pipeline/bench.md" $milestoneEnd
        $heavy = $x.Key -eq "GATE_VISUAL_CMD"
        if ($heavy) { [void](Enter-SharedLock "suite" 3600) }
        try { $r = Invoke-GateCommand $c $x.Timeout } finally { if ($heavy) { Exit-SharedLock "suite" } }
        $d = $r.Detail; if ($d.Length -gt 300) { $d = $d.Substring($d.Length - 300) }
        Add-GateLine $r.Ok $x.Name "$d (log : logs/$(Split-Path $r.Log -Leaf))"
    }
    if ($milestoneEnd) { Invoke-MilestoneGate }
    $c = ("" + $Cfg["BACKGROUND_LOAD_CMD"]).Trim()
    if ($c -and $c -ne "off" -and $code -and $taskNum) {
        $head = ("" + (git -C $Root rev-parse HEAD 2>$null)).Trim()
        $script:BackgroundLoad = Expand-GatePlaceholders $c $head $taskNum "pipeline/load.md" $false
    }
    Push-Location $Root
    try {
        if ($Base) {
            $msgs = @(git log --no-merges --format=%s "$Base..HEAD" 2>$null | Where-Object { $_ -and $_ -notmatch '^[a-z]+\((review|owner|process|skills|harness|git)\)' })
            $bad = @($msgs | Where-Object { $_ -notmatch '^[a-z]+(\([a-z0-9_,/ .-]+\))?: .+\(TASK \d+\)$' })
            Add-GateLine ($bad.Count -eq 0) "commit messages" $(if ($bad.Count) { "wrong format : " + ($bad -join " / ") } else { "$($msgs.Count) commit(s) in format" })
            $large = @(Get-LargeFiles $Root $Base)
            Add-GateLine ($large.Count -eq 0) "no file > 10 MB" $(if ($large.Count) { $large -join ", " } else { "ok" })
            $protected = @((("" + $Cfg["PROTECTED_DOCS"]) -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($protected.Count) {
                $changed = @(git diff --name-only "$Base..HEAD" -- @protected 2>$null | Where-Object { $_ })
                Add-GateLine ($changed.Count -eq 0) "protected docs untouched" $(if ($changed.Count) { "MODIFIED : " + ($changed -join ", ") } else { "ok" })
            }
            # docs/DECISIONS.md is the index GENERATED by the harness on main; a new ADR = a file in docs/adr/.
            # main...HEAD: only what the branch did (a main merged into the branch does not count).
            $index = @(git diff --name-only "main...HEAD" -- docs/DECISIONS.md 2>$null | Where-Object { $_ })
            Add-GateLine ($index.Count -eq 0) "docs/DECISIONS.md (generated index) not edited" $(if ($index.Count) { "MODIFIED : a new ADR = a file docs/adr/NNNN-<title>.md, docs/DECISIONS.md regenerates itself" } else { "ok" })
        }
        $maxKb = [double]$Cfg["REPORT_MAX_KB"]; if ($maxKb -le 0) { $maxKb = 6 }
        if (Test-Path $Report) {
            $size = (Get-Item $Report).Length
            Add-GateLine ($size -le $maxKb * 1024) "report <= $maxKb KB" ("{0:N1} KB" -f ($size / 1024))
        } else { Add-GateLine $false "report" "absent" }
    } finally { Pop-Location }
    $header = "VERIFICATION GATE (run by the harness after the coder, $(Get-Date -Format 'dd/MM HH:mm'), HEAD $((git -C $Root rev-parse --short HEAD 2>$null)))"
    $text = $header + "`r`n" + ($script:GateLines -join "`r`n") + "`r`n" + "TOTAL: $($script:GateKo) KO`r`n"
    # Information, not a check: the reviewer justifies each line in its verdict.
    $tt = @(); if ($Base) { $tt = @(Get-TouchedTests $Root $Base) }
    $text += "TOUCHED TESTS (justify each line in the verdict): " + $(if ($tt.Count) { "`r`n" + (($tt | ForEach-Object { "- $_" }) -join "`r`n") } else { "none" }) + "`r`n"
    Write-Utf8 (Join-Path $Pipe "gate.md") $text
    Note "gate : $($script:GateKo) KO ($($script:GateLines.Count) checks)"
    return $script:GateKo
}
