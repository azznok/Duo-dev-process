# THE DUO LOOP: reviewer -> coder -> reviewer..., forever.
#
#   powershell -File "<absolute path>\bin\harness\duo.ps1"
#
# Normally started by bin\harness\orchestrator.ps1 (one per line of config\duos.txt), FROM the
# supervisor session: a duo inherits the app's login (a plain PowerShell window fails on "login").
# The ABSOLUTE path matters: stop-all.ps1 recognises a process's duo by the root that appears in
# the command line of its ancestors.
# Clean stop: a STOP file at the root (STOP-ALL stops every duo: bin\harness\stop.bat).
# The reviewer judges and writes the task; the coder does it. Never both at once: the repo has
# one pilot at a time.
#
# Models and efforts come from config\project.env (REVIEWER_*, CODER_*, MODEL_*): nothing here.
# Lessons kept:
#   - After TASK: NONE, no blind one-hour pause and no empty passes: every POLL_IDLE_S seconds we
#     check whether HEAD, docs/PLAN.md, pipeline/owner.md or pipeline/lane.txt changed, and only
#     then run the reviewer again (empty "NONE" passes cost real money for nothing).
#   - Coder code 4 (another session is alive): the task was NOT done, it does not go to the
#     reviewer; we wait and hand it to the coder again.
#   - Quota closed (code 5): sleep until the remembered reopening of the role's model chain
#     (announced reset, or a new try every QUOTA_PROBE_MIN min). One notification at the pause,
#     one at the resume, nothing in between.
#   - No cold rotation every N hours: each task starts cold anyway.
# NB: no `switch` here. In PowerShell, break/continue inside a switch act on the switch, not on
# the loop: plain ifs are safer.

. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\autonomy.ps1")
Set-Location $Root
$StopFile = Join-Path $Root "STOP"
$StopAllFile = Join-Path $Root "STOP-ALL"
$Ps = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File")
$backoff = 60; $backoffMax = 3600
$Project = "" + $Cfg["PROJECT"]
$DuoName = ("" + $Cfg["DUO"]).Trim()
try { $host.UI.RawUI.WindowTitle = "$Project - duo $(if ($DuoName) { $DuoName } else { 'solo' })" } catch {}

function Test-Stop {
    # STOP-ALL is the orchestrator's; a duo started alone honours it too (stop.bat writes it).
    $f = $null
    foreach ($c in @($StopFile, $StopAllFile)) { if (Test-Path $c) { $f = $c; break } }
    if (-not $f) { return $false }
    $why = ((Get-Content $f -Raw -ErrorAction SilentlyContinue) + "").Trim()
    Note ("duo : STOP file - stopping. Reason: " + $(if ($why) { $why } else { "(none written)" }))
    return $true
}
function Test-StopQuiet { return ((Test-Path $StopFile) -or (Test-Path $StopAllFile)) }

$QuotaPauseFile = Join-Path $State "quota-pause.txt"
$QuotaWaitFile = Join-Path $State "quota-wait.txt"
function Wait-Quota([string[]]$Default) {
    $models = @(Get-QuotaWait); if (-not $models.Count) { $models = $Default }
    Remove-Item $QuotaWaitFile -Force -ErrorAction SilentlyContinue
    $q = Get-QuotaReopen $models
    $s = 60 * [int]$Cfg["QUOTA_PROBE_MIN"]
    if ($q) { $s = [int][Math]::Max(60, [Math]::Min(8 * 86400, ($q - (Get-Date)).TotalSeconds + 30)) }
    $at = (Get-Date).AddSeconds($s).ToString("dd/MM HH:mm")
    Note "duo : quota closed ($($models -join ', ')), sleeping $([int]($s / 60)) min, retry around $at"
    if (-not (Test-Path $QuotaPauseFile)) {
        Write-Utf8 $QuotaPauseFile (Get-Date -Format s)
        Send-Ntfy "quota reached" "Paused, automatic retry around $at (then every $($Cfg['QUOTA_PROBE_MIN']) min if needed)." "low"
    }
    # Sleep in slices: a STOP written during the pause is seen in under a minute.
    $end = (Get-Date).AddSeconds($s)
    while ((Get-Date) -lt $end -and -not (Test-StopQuiet)) { Start-Sleep -Seconds 30 }
}
function Clear-QuotaPause {
    if (-not (Test-Path $QuotaPauseFile)) { return }
    $since = Read-Utf8 $QuotaPauseFile
    Remove-Item $QuotaPauseFile -Force -ErrorAction SilentlyContinue
    Note "duo : resumed after quota (paused since $since)"
    Send-Ntfy "resumed" "The quota reopened, the duo is working again." "low"
}

function Wait-Change {
    # Cheap watch after TASK: NONE: no model call at all.
    $before = @{}
    $hf = Join-Path $Pipe ".hashes"
    if (Test-Path $hf) { foreach ($l in (Get-Content $hf)) { $p = $l -split "\s+", 2; if ($p.Count -eq 2) { $before[$p[0]] = $p[1] } } }
    Note "duo : TASK: NONE - asleep (question in docs/QUESTIONS.md), check every $($Cfg['POLL_IDLE_S']) s"
    $why = (Read-Utf8 (Join-Path $Pipe "task.md")) -replace '\s+', ' '
    Send-Ntfy "duo asleep" ("It waits for your answer (docs/QUESTIONS.md). " + $why.Substring(0, [Math]::Min(300, $why.Length))) "high"
    while ($true) {
        if (Test-StopQuiet) { return }
        Start-Sleep -Seconds ([int]$Cfg["POLL_IDLE_S"])
        $now = Get-IdleFingerprints
        foreach ($k in $now.Keys) {
            if ($before[$k] -ne $now[$k]) { Note "duo : $k changed - the reviewer runs again"; return }
        }
    }
}

function Wait-Failure([string]$Who, [int]$Code) {
    Note "duo : $Who failed (code $Code) - waiting $($script:backoff) s"
    Start-Sleep -Seconds $script:backoff
    $script:backoff = [Math]::Min($script:backoff * 2, $backoffMax)
}

Note "duo : started (pid $PID, config $($Cfg['CONFIG_SOURCE']))"
# The PID tells health.ps1 and the orchestrator which process REALLY runs the loop (a launcher
# window left open after a stop is not a duo).
$PidFile = Join-Path $State "duo.pid"
Write-Utf8 $PidFile "$PID"
while ($true) {
    if (Test-Stop) { break }
    $e = Get-PipelineState

    # A task written but NEVER tried goes straight to the coder: judging it now would call it
    # "not delivered" for nothing.
    $waiting = $e.Task -and -not $e.None -and -not $e.Report -and -not $e.InProgress
    if (-not $waiting) {
        Note "duo : REVIEWER"
        & powershell @Ps (Join-Path $PSScriptRoot "run-reviewer.ps1")
        $rc = $LASTEXITCODE
        if (Test-Stop) { break }
        if ($rc -eq 3) {
            Note "duo : reviewer FATAL (code 3) - fix it (claude /login, or the blocked merge) then relaunch."
            Send-Ntfy "duo stopped" "Reviewer fatal error (login, or blocked merge): someone must step in." "urgent"
            break
        }
        if ($rc -eq 10) { Wait-Change; continue }
        if ($rc -eq 5) { Wait-Quota @($Cfg["REVIEWER_MODEL"], $Cfg["REVIEWER_ESCALATION"]); continue }
        if ($rc -ne 0) { Wait-Failure "reviewer" $rc; continue }
        Clear-QuotaPause
        $backoff = 60
    } else {
        Note "duo : task waiting, never tried - straight to the coder"
    }

    Note "duo : CODER"
    & powershell @Ps (Join-Path $PSScriptRoot "run-coder.ps1")
    $rc = $LASTEXITCODE
    if (Test-Stop) { break }
    if ($rc -eq 3) {
        Note "duo : coder FATAL (code 3) - fix it (claude /login) then relaunch."
        Send-Ntfy "duo stopped" "Coder fatal error (login or key): someone must step in." "urgent"
        break
    }
    if ($rc -eq 4) { Note "duo : another coder session is alive - the task waits (5 min)"; Start-Sleep -Seconds 300; continue }
    if ($rc -eq 5) { Wait-Quota @($Cfg["CODER_MODEL"], $Cfg["CODER_FALLBACK"]); continue }
    if ($rc -ne 0) { Wait-Failure "coder" $rc; continue }
    Clear-QuotaPause
    $backoff = 60
    Start-Sleep -Seconds 10
}
Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
