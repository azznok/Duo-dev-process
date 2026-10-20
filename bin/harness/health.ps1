# DUO HEALTH: is the work MOVING, not only "a process runs".
#   powershell -File bin\harness\health.ps1      (or health.bat)
# One line per check: [OK ] / [KO ] / [?? ]. Never shows a secret.

. (Join-Path $PSScriptRoot "lib\common.ps1")
$StackLib = Get-StackLib; if ($StackLib) { . $StackLib }   # STACK: lib\stacks\<name>.ps1 or nothing

function L([string]$S, [string]$Text) { Write-Host ("[{0}] {1}" -f $S, $Text) }

# 1. The duo loop
$loops = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '\bin\harness\duo\.ps1' })
$pidFile = Join-Path $State "duo.pid"
if (Test-Path $pidFile) {
    # The loop writes its PID when it starts and deletes it on a clean stop.
    $sp = [int]((Get-Content $pidFile -Raw) + "").Trim()
    $loops = @($loops | Where-Object { $_.ProcessId -eq $sp })
    if (-not $loops.Count) { L "KO " "duo loop dead (pid $sp gone without a clean stop)" }
} else {
    # No PID file: only the loops of THIS folder count (another duo's loop is not ours).
    $me = (($Root -replace '/', '\').TrimEnd('\') + '\bin\harness\').ToLower()
    $loops = @($loops | Where-Object { ("" + $_.CommandLine).ToLower().Contains($me) })
}
if ($loops.Count -eq 1) { L "OK " "duo loop alive (pid $($loops[0].ProcessId))" }
elseif ($loops.Count -gt 1) { L "KO " "$($loops.Count) duo loops at once - keep one (stop-all -Definitive then relaunch)" }
else { L "KO " "no duo loop" }
if (Test-Path (Join-Path $Root "STOP")) { L "?? " "STOP file present: the duo will stop" }
if (Test-Path (Join-Path $Root "STOP-ALL")) { L "?? " "STOP-ALL file present: delete it before relaunching" }

# 2. The pipeline
$e = Get-PipelineState
if ($e.Task) { L "OK " ("task : " + $e.First) } else { L "?? " "no pipeline/task.md (first pass?)" }
L "OK " ("report written : {0} | task tried : {1}" -f $e.Report, $e.InProgress)
if ($e.None) { L "?? " "TASK: NONE - a question waits for the owner (docs/QUESTIONS.md)" }

# 3. Is the agent acting? (heartbeat of the coder's PostToolUse hook)
$b = Get-HeartbeatAge
if ($null -eq $b) { L "?? " "no heartbeat (no coder running)" }
elseif ($b -lt 20) { L "OK " ("coder active {0:N1} min ago" -f $b) }
else { L "?? " ("last coder tool {0:N0} min ago" -f $b) }

# 4. The last claude -p calls: error? login?
foreach ($role in @("coder", "reviewer")) {
    $f = Get-ChildItem (Join-Path $Logs "*-$role*.log") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { L "?? " "no $role journal"; continue }
    $raw = Read-Utf8 $f.FullName
    $j = Read-Result $raw
    $c = Get-FailureClass $j $raw
    # stream-json: a journal without a result line, written less than 30 min ago = call IN PROGRESS.
    if (-not $j -and ((Get-Date) - $f.LastWriteTime).TotalMinutes -lt 30) { L "OK " "$role : call in progress ($($f.Name))"; continue }
    $cost = ""; if ($j -and $j.total_cost_usd) { $cost = (" , {0:N2} USD" -f $j.total_cost_usd) }
    if ($c -eq "ok") { L "OK " "$role : last call without error ($($f.Name)$cost)" }
    elseif ($c -eq "auth") { L "KO " "$role : the CLI is no longer logged in - run 'claude /login' ($($f.Name))" }
    else { L "KO " "$role : last call ended in $c ($($f.Name))" }
}
$q = Get-Quotas
foreach ($k in $q.Keys) { if ($q[$k] -gt (Get-Date)) { L "?? " "quota remembered closed : $k until $($q[$k].ToString('dd/MM HH:mm'))" } }

# 5. The work: did a file of the repo move?
# Code, data, docs, tools; never the build folders (too big to walk).
$dirs = @("docs", "tools", "bin", "pipeline", "src", "source", "lib", "app", "apps", "game", "engine",
          "assets", "data", "scenarios", "tests", "test") |
    ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path $_ }
$recent = Get-ChildItem $dirs -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\(node_modules|target|build|dist|__pycache__)\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($recent) {
    $a = [int]((Get-Date) - $recent.LastWriteTime).TotalMinutes
    $rel = $recent.FullName.Substring($Root.Length + 1)
    if ($a -lt 90) { L "OK " "last touched file $a min ago ($rel)" } else { L "KO " "nothing moved for $a min ($rel)" }
}

# 6. The stack and the bridges
L "OK " "STACK=$Stack"
foreach ($x in @(Get-StackHealth)) { L $x[0] $x[1] }
if (Test-Port ([int]$Cfg["BLENDER_PORT"])) { L "OK " "Blender MCP answers (port $($Cfg['BLENDER_PORT']))" } else { L "?? " "Blender MCP silent (started only for 3d tasks)" }
foreach ($k in @("NTFY_TOPIC", "MESHY_API_KEY", "ELEVENLABS_API_KEY")) {
    if (Get-Secret $k) { L "OK " "$k PRESENT" } else { L "?? " "$k ABSENT" }
}
$bv = @(Get-LiveBenches)
if ($bv.Count) { L "?? " ("live benches : " + (($bv | ForEach-Object { "$($_.Script) ($($_.Pid))" }) -join ", ")) }
