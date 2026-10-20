# SHARED BETWEEN DUOS - dot-source it AFTER lib\common.ps1 (uses $Root, $State, Note).
# What two duos (two worktrees) must see together lives in the COMMON git folder
# (`git rev-parse --git-common-dir`)/harness, never in .state/ (private to each worktree):
#   Enter-SharedLock / Exit-SharedLock : lock by name, exclusive file creation, dead PID = taken over
#   Get-SharedNumber : shared counter (tasks, ADRs), never below a local floor
#   Get-AdrFloor     : the highest NNNN of docs/adr/
#   Test-OtherHarness : does a process belong to the harness of ANOTHER folder (stop-all.ps1)?
# Model-free test: bin\harness\test\test-shared.ps1.

function Get-SharedDir {
    $d = ("" + (git -C $Root rev-parse --git-common-dir 2>$null)).Trim()
    if (-not $d) { $c = Join-Path $State "shared" }
    else {
        if (-not [IO.Path]::IsPathRooted($d)) { $d = Join-Path $Root $d }
        $c = Join-Path ([IO.Path]::GetFullPath($d)) "harness"
    }
    if (-not (Test-Path $c)) { New-Item -ItemType Directory -Force $c | Out-Null }
    return $c
}

function Enter-SharedLock([string]$Name, [int]$WaitS = 600) {
    # True if the lock is taken (waits by 2 s slices, $WaitS at most). The file holds
    # "<pid> <date> <root>"; a dead PID (killed harness) leaves the lock to be taken over.
    $f = Join-Path (Get-SharedDir) "$Name.lock"
    $end = (Get-Date).AddSeconds($WaitS); $said = $false
    while ($true) {
        try {
            $s = [IO.File]::Open($f, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $o = [Text.Encoding]::UTF8.GetBytes("$PID $(Get-Date -Format s) $Root")
            $s.Write($o, 0, $o.Length); $s.Close()
            return $true
        } catch {
            $old = ("" + (Get-Content $f -Raw -ErrorAction SilentlyContinue)).Trim()
            $p = ($old -split '\s+')[0]
            # A lock held by the parent process (mediator -> resumed merge) is ours; never release it here.
            if ($env:HARNESS_INHERITED_LOCK -and $p -eq $env:HARNESS_INHERITED_LOCK) { return $true }
            if ($p -match '^\d+$' -and -not (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue)) {
                Remove-Item $f -Force -ErrorAction SilentlyContinue
                Note "harness : shared lock '$Name' taken over (pid $p dead)"
                continue
            }
            if ((Get-Date) -gt $end) { Note "harness : shared lock '$Name' still held ($old) after $WaitS s"; return $false }
            if (-not $said) { Note "harness : shared lock '$Name' held ($old) : waiting"; $said = $true }
            Start-Sleep -Seconds 2
        }
    }
}

function Exit-SharedLock([string]$Name) {
    $f = Join-Path (Get-SharedDir) "$Name.lock"
    $p = ("" + (Get-Content $f -Raw -ErrorAction SilentlyContinue)).Trim() -split '\s+'
    if ($p[0] -eq "$PID") { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

function Get-SharedNumber([string]$Counter, [int]$Floor = 0) {
    # The next number of the shared counter, at least $Floor + 1; 0 if the lock does not come.
    if (-not (Enter-SharedLock "counters" 60)) { return 0 }
    try {
        $f = Join-Path (Get-SharedDir) "counter-$Counter.txt"
        $v = 0
        if (Test-Path $f) { $t = ("" + (Get-Content $f -Raw)).Trim(); if ($t -match '^\d+$') { $v = [int]$t } }
        $n = [Math]::Max($v, $Floor) + 1
        Write-Utf8 $f "$n"
        return $n
    } finally { Exit-SharedLock "counters" }
}

function Test-OtherHarness($P, [hashtable]$Procs) {
    # True if the closest ancestor of $P that runs a harness script (absolute path
    # "\bin\harness\<script>") belongs to ANOTHER folder. Ours, or no harness in the lineage
    # (orphan): false. $Procs: pid -> object with CommandLine and ParentProcessId (Win32_Process).
    $me = (($Root -replace '/', '\').TrimEnd('\') + '\bin\harness\').ToLower()
    $q = $P
    for ($k = 0; $q -and $k -lt 30; $k++) {
        $cl = ("" + $q.CommandLine).ToLower() -replace '/', '\'
        if ($cl.Contains($me)) { return $false }
        if ($cl -match '[a-z]:\\[^"]*\\bin\\harness\\(run-coder|run-reviewer|duo|orchestrator|mediator)') { return $true }
        $q = $Procs[[int]$q.ParentProcessId]
    }
    return $false
}

function Get-AdrFloor {
    # One ADR = one file docs/adr/NNNN-<title>.md; the floor is the highest NNNN found.
    $max = 0
    foreach ($f in @(Get-ChildItem (Join-Path $Root "docs\adr") -Filter "*.md" -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($f.Name, '^(\d{4})')
        if ($m.Success -and [int]$m.Groups[1].Value -gt $max) { $max = [int]$m.Groups[1].Value }
    }
    return $max
}
