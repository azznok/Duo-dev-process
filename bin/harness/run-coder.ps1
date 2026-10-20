# THE CODER: does ONE task (pipeline/task.md), proves it, commits it, writes
# pipeline/report.md, then stops. Called by duo.ps1.
#
#   powershell -File bin\harness\run-coder.ps1
#
# Lessons kept:
#   - A NEW SESSION PER TASK. Resuming (--resume) only serves the SAME task (transient error,
#     quota, nudge). Measured: ~237k tokens of average context per call with a perpetual resume,
#     ~66k when starting cold.
#   - MCP ON DEMAND: the task's DOMAINS line chooses the servers (none for most tasks; blender +
#     meshy for 3d), with --strict-mcp-config. Every MCP server costs its tool definitions on
#     EVERY model call.
#   - pipeline/.in_progress is written only AFTER taking the lock: a refused task (another
#     session alive) no longer goes to the reviewer without having been done.
#   - No nudge if report.md exists (most nudges only answered "DONE" while re-reading ~300k
#     tokens). MAX_NUDGES = 1 by default.
#   - Benches still alive at the end of the turn: we nudge "wait for them" instead of killing
#     them (the end of the turn kills everything running in the background).
#
# Codes: 0 task tried | 2 infra (stack not ready) | 3 FATAL | 4 refused (another session
#        alive) | 5 quota closed on the whole model chain

. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\autonomy.ps1")
. (Join-Path $PSScriptRoot "lib\branches.ps1")
. (Join-Path $PSScriptRoot "lib\gate.ps1")
$StackLib = Get-StackLib; if ($StackLib) { . $StackLib }   # STACK: lib\stacks\<name>.ps1 or nothing
Set-Location $Root
Install-CommitMsgHook   # a bad commit message is refused at commit time, not found at the gate

$TaskFile = Join-Path $Pipe "task.md"
$ReportFile = Join-Path $Pipe "report.md"
$ReviewFile = Join-Path $Pipe "review.md"
$InProgress = Join-Path $Pipe ".in_progress"
$SessFile = Join-Path $State "coder-session.txt"   # "<task fingerprint> <session_id> <iso date>"

if (-not (Test-Path $TaskFile) -or ((Get-Content $TaskFile -TotalCount 1) -cmatch '^TASK:\s*NONE')) {
    Note "coder : no task to do"; exit 2
}

# --- 1. ONE coder session only, and the proof that no other one is alive ----------------------
if (-not (Enter-Lock "coder")) { Note "coder : REFUSED, a coder session holds the lock"; exit 4 }
$age = Get-HeartbeatAge
if (($null -ne $age) -and ($age -lt 20)) {
    # A dead pid does not mean a dead session: the heartbeat (the coder's PostToolUse hook)
    # says an agent called a tool less than 20 min ago.
    Note ("coder : REFUSED, a coder acted {0:N1} min ago (delete .state/heartbeat to override)" -f $age)
    Exit-Lock "coder"; exit 4
}
$script:Tried = $false

function Exit-Run([int]$Code) {
    Exit-Lock "coder"
    Remove-Item $HeartbeatFile -Force -ErrorAction SilentlyContinue
    # A task never handed to the agent goes back to the coder, not to the reviewer.
    if (-not $script:Tried) { Remove-Item $InProgress -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:HARNESS_ROLE -ErrorAction SilentlyContinue
    exit $Code
}

# The lock is taken: the task is now "in progress".
Write-Utf8 $InProgress (Get-Date -Format s)

# --- 2. The stack (an adapter may start an editor or a server; nothing long by default) --------
if (-not (Start-Stack)) {
    Note "coder : the stack is not ready (STACK=$Stack)"
    Exit-Run 2
}

# --- 3. Session environment ------------------------------------------------------------------
$env:HARNESS_ROLE = "coder"                          # the heartbeat hook only beats for it
$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = $Cfg["COMPACT_WINDOW"]
$env:CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS = "0"      # long background jobs are not cut at 600 s
Copy-SecretsToEnv
$TaskText = Read-Utf8 $TaskFile
$Domains = Get-Domains $TaskText
$McpCfg = New-CoderMcp $Domains
Note ("coder : domains {0} -> MCP {1}" -f ($Domains -join ","), $(if ($McpCfg) { Split-Path $McpCfg -Leaf } else { "none" }))
# Model tier: the task's MODEL line, raised one notch after a rejection on this branch
# (1 rejection: mid/small -> default, default -> effort CODER_EFFORT_REJECTED; 2: top),
# then the fallback chain when a credit runs out.
$Choice = Get-CoderChoice $TaskText (Get-Rejections (Get-Branch))
$Models = $Choice.Models; $Effort = $Choice.Effort
Note "coder : tier $($Choice.Tier), effort $Effort -> $($Models -join ' > ')"

function Invoke-Coder([string]$Prompt, [string]$ResumeId) {
    if ($script:Domains -contains "3d") { Ensure-Blender }
    $m = Select-Model $Models
    if (-not $m) { return @{ Class = "quota_all" } }
    $a = @("-p", "--output-format", "stream-json", "--verbose", "--dangerously-skip-permissions", "--model", $m, "--strict-mcp-config")
    if ($McpCfg) { $a += @("--mcp-config", $McpCfg) }
    if ($Cfg["CODER_SETTING_SOURCES"]) { $a += @("--setting-sources", $Cfg["CODER_SETTING_SOURCES"]) }
    $e = Get-CoderEffort $Choice $m
    if ($e -and $e -ne "off") { $a += @("--effort", $e) }
    $others = @($Models | Where-Object { $_ -and $_ -ne $m -and -not (Test-QuotaBlocked $_) })
    # No mid-call fallback from the top model (the fallback would keep the top model's effort);
    # top credit exhausted = quota noted, the next call takes the default model at high effort.
    if ($Choice.Tier -eq "top" -and $m -eq $Cfg["MODEL_TOP"]) { $others = @() }
    if ($others.Count) { $a += @("--fallback-model", ($others -join ",")) }
    if ($ResumeId) { $a += @("--resume", $ResumeId) }
    $log = New-LogPath "coder"
    Note "coder : $m$(if ($ResumeId) { ' (resume)' } else { ' (new session)' }) -> $(Split-Path $log -Leaf)"
    $script:Tried = $true
    $raw = Invoke-Claude -Prompt $Prompt -Arguments $a -LogPath $log
    $j = Read-Result $raw
    $c = Get-FailureClass $j $raw
    if ($j -and $j.session_id) {
        $script:SessionId = "" + $j.session_id
        Write-Utf8 $SessFile ("{0} {1} {2}" -f (Get-Fingerprint $TaskFile), $script:SessionId, (Get-Date -Format s))
    }
    if ($c -eq "quota") { Set-QuotaBlocked $m (Get-FailureText $j $raw) }
    return @{ Class = $c; J = $j; Log = $log; Model = $m }
}

function Invoke-Turn([string]$Prompt, [string]$ResumeId) {
    # One turn, plus everything that is NOT the agent stopping: quota, API error.
    # Neither costs a nudge.
    $r = Invoke-Coder $Prompt $ResumeId
    $tries = 0
    while ($r.Class -ne "ok" -and $tries -lt 12) {
        $tries++
        if ($r.Class -eq "auth") { Note "coder : FATAL ERROR (login/key) - run 'claude /login' then relaunch the duo"; Exit-Run 3 }
        if ($r.Class -eq "quota_all") { Note "coder : quota closed on $($Models -join ', ')"; Set-QuotaWait $Models; Exit-Run 5 }
        if ($r.Class -eq "quota") { Start-Sleep -Seconds 5 }
        else {
            $s = Get-Backoff $tries
            Note "coder : unclean end (API error), new try in $s s ($tries/12)"
            Start-Sleep -Seconds $s
        }
        Start-Stack | Out-Null
        if ($script:SessionId) {
            $p = "Resume exactly where you were. Nobody will answer a question."
            $crash = Get-StackCrashNote; if ($crash) { $p = $crash + "`n`n" + $p }
        } else {
            $p = $Prompt   # no session started: send the full prompt again
        }
        $r = Invoke-Coder $p $script:SessionId
    }
    if ($r.Class -ne "ok") { Note "coder : 12 transient failures in a row"; Exit-Run 2 }
    return $r
}

# --- 4. New session, or resume of the SAME task --------------------------------------------------
$script:SessionId = ""
$resume = ""
if (Test-Path $SessFile) {
    $p = (Get-Content $SessFile -Raw).Trim() -split "\s+"
    if ($p.Count -ge 3 -and $p[0] -eq (Get-Fingerprint $TaskFile)) {
        $ageH = ((Get-Date) - [datetime]::Parse($p[2])).TotalHours
        if ($ageH -lt [double]$Cfg["RESUME_MAX_H"]) { $resume = $p[1] }
    }
}

if ($resume) {
    $script:SessionId = $resume
    $prompt = "Resume of the SAME task (pipeline/task.md did not change). Finish it, prove it, commit, write pipeline/report.md, then stop."
    $crash = Get-StackCrashNote; if ($crash) { $prompt = $crash + "`n`n" + $prompt }
    $turn = Invoke-Turn $prompt $resume
} else {
    $instructions = Read-Utf8 (Join-Path $PSScriptRoot "prompts\coder.md")
    $prompt = $instructions + "`n`n---`n## YOUR TASK (copy of pipeline/task.md)`n`n" + $TaskText
    if (Test-Path $ReviewFile) {
        $rv = (Get-Content $ReviewFile -Encoding UTF8 -TotalCount 60) -join "`n"
        $prompt += "`n`n---`n## THE VERDICT ON THE PREVIOUS TASK (pipeline/review.md, start)`n`n" + $rv
    }
    $turn = Invoke-Turn $prompt ""
}

# --- 5. Benches still running? Wait, do not kill ---------------------------------------------
$w = 0
while ($w -lt [int]$Cfg["MAX_WAITS"]) {
    $alive = @(Get-LiveBenches)
    if ($alive.Count -eq 0) { break }
    $w++
    $list = ($alive | ForEach-Object { "$($_.Script) (pid $($_.Pid), since $($_.Since))" }) -join ", "
    Note "coder : $($alive.Count) bench(es) still alive - nudge 'wait' $w/$($Cfg['MAX_WAITS'])"
    $p = "Your turn ended but these benches are still running: $list. The end of your turn would kill them. Wait for them INSIDE this turn (blocking command with a timeout, or waits of 10 min at most re-reading their log), use the result, finish the task, then stop."
    $turn = Invoke-Turn $p $script:SessionId
}

# --- 6. No report? One nudge, not twenty ----------------------------------------------------------
$k = 0
while (-not (Test-Path $ReportFile) -and $k -lt [int]$Cfg["MAX_NUDGES"]) {
    $k++
    Note "coder : stopped without pipeline/report.md - nudge $k/$($Cfg['MAX_NUDGES'])"
    $p = "You stopped without writing pipeline/report.md. Finish the task of pipeline/task.md (and only it), prove it, commit, write the report, then stop."
    $turn = Invoke-Turn $p $script:SessionId
}
if (Test-Path $ReportFile) { Note "coder : report written" } else { Note "coder : NO report - the reviewer will judge the task not delivered" }

# --- 6b. Verification gate: the HARNESS runs the checks, not the coder -------------------------
if (Test-Path $ReportFile) {
    $taskBase = ""; $bf = Join-Path $Pipe "base.txt"
    if (Test-Path $bf) { $taskBase = (Get-Content $bf -Raw).Trim() }
    Invoke-Gate $taskBase $ReportFile | Out-Null
}

# --- 7. Cleanup: benches and leftover exes of the build folder ----------------------------------
& (Join-Path $PSScriptRoot "stop-all.ps1") -Benches
Start-BackgroundBench   # benchmarks in the background, during the reviewer's pass
Start-BackgroundLoad    # load test on new seeds, during the reviewer's pass
Exit-Run 0
