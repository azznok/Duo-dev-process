# THE ORCHESTRATOR: runs the duos of config\duos.txt, without any model.
#   powershell -File "<absolute path>\bin\harness\orchestrator.ps1" [-Active N] [-RoundS 300] [-Once]
# START IT FROM THE SUPERVISOR SESSION (Start-Process): the duos inherit the app's login (a plain
# PowerShell window fails on "login", supervisor/SUPERVISOR.md).
# What it does:
#   - creates each duo's worktree if needed (detached on main) and starts it (duo.ps1, absolute
#     path) with its environment: HARNESS_DUO, its build folder, its background load;
#   - assigns LANES (tools/lanes.py) so two duos never work on the same zones;
#   - makes a ROUND every $RoundS s, without a model: duo alive, duo journal (blocked merge, fatal
#     error, task set aside), silent duo, disk;
#   - on an incident, calls the mediator (bin\harness\mediator.ps1) if it exists, otherwise tells
#     the owner (ntfy) and leaves the duo stopped;
#   - restarts a dead duo without STOP nor pending incident.
# Stop: a STOP-ALL file at the root (writes STOP in every duo, then exits).
# Test without a model: bin\harness\test\test-orchestrator.ps1.
param([int]$Active = 0, [int]$RoundS = 300, [switch]$Once)

. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\autonomy.ps1")
. (Join-Path $PSScriptRoot "lib\shared.ps1")
$Parent = Split-Path $Root -Parent
$Project = "" + $Cfg["PROJECT"]
$LoadOrigin = $env:HARNESS_BACKGROUND_LOAD_CMD   # before Start-Duo changes it duo by duo
$StopAll = Join-Path $Root "STOP-ALL"
function NoteO([string]$M) {
    $l = "[{0}] {1}" -f (Get-Date -Format "dd/MM HH:mm:ss"), $M
    Write-Host $l
    try { Add-Utf8 (Join-Path $Logs ("orchestrator-{0}.log" -f (Get-Date -Format "yyMMdd"))) ($l + "`r`n") } catch {}
}

function Read-Duos {
    # "<name> <folder> <build-folder|-> <background-load yes|no>", folders relative to the PARENT of
    # the main repo; "." = the main repo itself.
    $l = @()
    foreach ($t in (Get-Content (Join-Path $Root "config\duos.txt") -Encoding UTF8)) {
        $t = $t.Trim(); if (-not $t -or $t.StartsWith("#")) { continue }
        $c = $t -split '\s+'
        if ($c.Count -lt 2) { continue }
        $dir = if ($c[1] -eq ".") { $Root } else { Join-Path $Parent $c[1] }
        $build = if ($c.Count -ge 3 -and $c[2] -ne "-") { Join-Path $Parent $c[2] } else { "" }
        $l += [pscustomobject]@{ Name = $c[0]; Dir = $dir; Build = $build; Load = ($c.Count -ge 4 -and $c[3] -eq "yes");
                                 Offset = -1; File = ""; Incident = ""; Mediator = $null; Restarts = @(); Lane = ""; IncidentHead = "" }
    }
    return $l
}

function Initialize-Worktree($D) {
    if (Test-Path (Join-Path $D.Dir ".git")) { return $true }
    $r = (& git -C $Root worktree add --detach $D.Dir main 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { NoteO "duo $($D.Name) : worktree $($D.Dir) not created : $r"; return $false }
    NoteO "duo $($D.Name) : worktree created ($($D.Dir), detached on main)"
    return $true
}

function Test-DuoAlive($D) {
    $f = Join-Path $D.Dir ".state\duo.pid"
    if (-not (Test-Path $f)) { return $false }
    $p = ("" + (Get-Content $f -Raw)).Trim()
    return ($p -match '^\d+$' -and [bool](Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue))
}

function Start-Duo($D) {
    # A child copies the environment when it starts: we set it right before, duo by duo.
    $env:HARNESS_DUO = $D.Name
    $env:HARNESS_PROJECT = "$Project-$($D.Name)"   # notifications: we know which duo speaks
    $env:HARNESS_BUILD_DIR = $D.Build
    # Its own build folder: two duos building in one folder lock each other's files.
    $bde = ("" + $Cfg["BUILD_DIR_ENV"]).Trim()
    if ($bde -and $D.Build) { Set-Item -Path "Env:$bde" -Value $D.Build }
    # No benchmark at each task while several duos share the machine: the measures would be noise.
    $env:HARNESS_GATE_BENCH_CMD = "empty"
    # Background load: the orchestrator's original value (the config, or a test's), else "off".
    if ($D.Load -and $LoadOrigin) { $env:HARNESS_BACKGROUND_LOAD_CMD = $LoadOrigin }
    elseif ($D.Load) { Remove-Item Env:HARNESS_BACKGROUND_LOAD_CMD -ErrorAction SilentlyContinue }
    else { $env:HARNESS_BACKGROUND_LOAD_CMD = "off" }
    $loop = Join-Path $D.Dir "bin\harness\duo.ps1"
    $p = Start-Process powershell -PassThru -WorkingDirectory $D.Dir -WindowStyle Minimized -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$loop`"")
    NoteO "duo $($D.Name) : started (pid $($p.Id), build $(if ($D.Build) { $D.Build } else { '-' }), background load $(if ($D.Load) { 'yes' } else { 'no' }))"
}

function Read-NewLogLines($D) {
    # Lines added to the duo's harness journal since the previous round (its name changes at midnight).
    $f = Join-Path $D.Dir ("logs\harness-{0}.log" -f (Get-Date -Format "yyMMdd"))
    if ($f -ne $D.File) { $D.File = $f; if ($D.Offset -lt 0 -and (Test-Path $f)) { $D.Offset = (Get-Item $f).Length } else { $D.Offset = 0 } }
    if (-not (Test-Path $f)) { return @() }
    $size = (Get-Item $f).Length
    if ($size -le $D.Offset) { return @() }
    $s = [IO.File]::Open($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { [void]$s.Seek($D.Offset, [IO.SeekOrigin]::Begin); $b = New-Object byte[] ($size - $D.Offset); [void]$s.Read($b, 0, $b.Length) } finally { $s.Close() }
    $D.Offset = $size
    return @(([Text.Encoding]::UTF8.GetString($b)) -split "`r?`n" | Where-Object { $_ })
}

function Get-Incident([string[]]$Lines) {
    # The first incident that needs the mediator; "" if none.
    # The EXACT harness lines, case included (-cmatch): the journal also carries the mediator's
    # lines, which talk about a "blocked merge" without being one.
    foreach ($l in $Lines) {
        if ($l -cmatch '\] reviewer : MERGE BLOCKED') { return "merge blocked" }
        if ($l -cmatch '\] duo : (reviewer|coder) FATAL') { return "fatal error : $($l -replace '^\[[^\]]*\]\s*', '')" }
        if ($l -cmatch '\] harness : \S+ SET ASIDE') { return "task set aside" }
    }
    return ""
}

function Invoke-Mediator($D, [string]$What) {
    $m = Join-Path $Root "bin\harness\mediator.ps1"
    if (-not (Test-Path $m)) {
        NoteO "duo $($D.Name) : INCIDENT ($What) - no mediator: duo left stopped, owner told"
        Send-Ntfy "duo $($D.Name) stopped" "$What. No mediator: someone must step in." "high"
        return
    }
    $p = Start-Process powershell -PassThru -WorkingDirectory $Root -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$m`"", "-Duo", $D.Name, "-DuoRoot", "`"$($D.Dir)`"", "-Incident", "`"$What`"")
    $D.Mediator = $p
    # Remember HEAD: a branch that changes later means the incident was solved by hand.
    $D.IncidentHead = ("" + (git -C $D.Dir rev-parse HEAD 2>$null)).Trim()
    NoteO "duo $($D.Name) : INCIDENT ($What) - mediator called (pid $($p.Id))"
}

function Update-Lanes($Duos) {
    # tools/lanes.py gives the ready lanes of the milestone; a duo keeps its lane while it is
    # ready, a duo without a lane takes the first free ready one. Writes <duo>\pipeline\lane.txt
    # (read by its reviewer; a sleeping duo wakes up when it changes). Invalid backlog (shared
    # zones, entry without a lane): the first duo alone, the whole backlog ("*"), its reviewer fixes it.
    $planTxt = Read-Utf8 (Join-Path $Root "docs\PLAN.md")
    $milestone = [regex]::Match($planTxt, '(?im)^\s*MILESTONE\s*:\s*(M\d+[a-z]?)').Groups[1].Value
    # A milestone started in parallel (line "PARALLEL_MILESTONE: M5" of docs/PLAN.md) adds its lanes,
    # except its "end" (the end of the current milestone goes first) and a name already taken.
    $milestones = @($milestone) + @([regex]::Matches($planTxt, '(?im)^\s*PARALLEL_MILESTONE\s*:\s*(M\d+[a-z]?)') | ForEach-Object { $_.Groups[1].Value })
    $ready = @(); $errors = @(); $lanes = [ordered]@{}
    foreach ($ml in $milestones) {
        if (-not $ml) { $errors += "docs/PLAN.md has no MILESTONE line"; continue }
        try {
            $j = (& python (Join-Path $Root "tools\lanes.py") --milestone $ml --ref main --json 2>$null | Out-String) | ConvertFrom-Json
            foreach ($p in $j.lanes.PSObject.Properties) {
                if ($lanes.Contains($p.Name) -or ($ml -ne $milestone -and $p.Name -eq "end")) { continue }
                $lanes[$p.Name] = $p.Value
                if ($p.Value.state -eq "ready") { $ready += $p.Name }
            }
            $errors += @($j.errors | Where-Object { $_ })
        } catch { $errors += @("lanes.py unreadable ($ml)") }
    }
    $before = @($Duos | ForEach-Object { "$($_.Name)=$($_.Lane)" }) -join " "
    if ($errors.Count) {
        foreach ($D in $Duos) { $D.Lane = "" }
        $Duos[0].Lane = "*"
    } else {
        foreach ($D in $Duos) { if ($ready -notcontains $D.Lane) { $D.Lane = "" } }
        # A duo keeps the lane of the TASK it has in progress (entry cited in its task.md): otherwise
        # another duo could pick up the same entry (seen when lanes were first assigned).
        foreach ($D in $Duos) {
            $t = "" + (Get-Content (Join-Path $D.Dir "pipeline\task.md") -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue)
            if ($t -cmatch '^TASK:\s*NONE') { continue }
            $e = [regex]::Match($t, '\[(M\d+[a-z]?-\d+)').Groups[1].Value
            if (-not $e) { continue }
            foreach ($p in @($lanes.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = $_.Key; Value = $_.Value } })) {
                if ($ready -contains $p.Name -and @($p.Value.entries) -contains $e) {
                    $held = $Duos | Where-Object { $_.Name -ne $D.Name -and $_.Lane -eq $p.Name }
                    foreach ($x in @($held)) { $x.Lane = "" }
                    $D.Lane = $p.Name
                }
            }
        }
        foreach ($D in $Duos) {
            if ($D.Lane) { continue }
            $free = @($ready | Where-Object { $c = $_; -not ($Duos | Where-Object { $_.Lane -eq $c }) })
            # The "end" lane (machine idle) only goes to the first duo.
            if ($free.Count -and ($free[0] -ne "end" -or $D.Name -eq $Duos[0].Name)) { $D.Lane = $free[0] }
        }
    }
    foreach ($D in $Duos) {
        $f = Join-Path $D.Dir "pipeline\lane.txt"
        if (-not (Test-Path (Split-Path $f))) { continue }
        $text = if ($D.Lane) { "$($D.Lane)`r`n" + ($(if ($errors.Count) { "ERRORS: " + ($errors -join " ; ") } else { "" })) } else { "" }
        if ((Read-Utf8 $f) -ne $text) { Write-Utf8 $f $text }
    }
    $after = @($Duos | ForEach-Object { "$($_.Name)=$($_.Lane)" }) -join " "
    if ($after -ne $before) { NoteO "lanes ($($milestones -join '+')) : $after$(if ($errors.Count) { ' ; ERRORS: ' + ($errors -join ' ; ') })" }
}

function Get-DuoProgressAge($D) {
    $f = Join-Path $D.Dir ".state\progress.txt"
    if (-not (Test-Path $f)) { return $null }
    if (-not (Test-Path (Join-Path $D.Dir "pipeline\.in_progress"))) { return $null }
    return ((Get-Date) - (Get-Item $f).LastWriteTime).TotalMinutes
}

function Invoke-Round($Duos) {
    Update-Lanes $Duos
    $min = 60; if ($Cfg["DISK_MIN_GB"]) { $min = [int]$Cfg["DISK_MIN_GB"] }
    $free = [int](((Get-PSDrive -Name ($Root.Substring(0, 1))).Free) / 1GB)
    if ($free -lt $min) { NoteO "DISK ALERT : $free GB free (< $min)"; Send-Ntfy "disk" "$free GB free on the duos' disk." "high" }
    foreach ($D in $Duos) {
        $new = Read-NewLogLines $D
        $inc = Get-Incident $new
        if ($inc -and -not $D.Incident) { $D.Incident = $inc; Invoke-Mediator $D $inc }
        # The mediator finished: code 0 = solved, the duo can restart; otherwise it stays stopped (question asked).
        if ($D.Mediator -and $D.Mediator.HasExited) {
            $code = $D.Mediator.ExitCode; $D.Mediator = $null
            NoteO "duo $($D.Name) : mediator finished (code $code)"
            if ($code -eq 0) {
                $D.Incident = ""
                # A restart asked by the mediator: outside the count of deaths in a loop.
                if (-not (Test-DuoAlive $D) -and -not (Test-Path (Join-Path $D.Dir "STOP"))) { Start-Duo $D; continue }
            }
        }
        # Incident solved by hand (supervisor/resume.ps1): the duo's branch changed and main is free;
        # forget it, the rest of the round restarts the duo.
        if ($D.Incident -and -not $D.Mediator -and $D.IncidentHead -and -not (Test-DuoAlive $D)) {
            $h = ("" + (git -C $D.Dir rev-parse HEAD 2>$null)).Trim()
            $b = ("" + (git -C $D.Dir branch --show-current 2>$null)).Trim()
            if ($h -and $h -ne $D.IncidentHead -and $b -ne "main") {
                NoteO "duo $($D.Name) : incident solved outside the mediator ($b), restart"
                $D.Incident = ""; $D.IncidentHead = ""
            }
        }
        if ($D.Incident) { continue }
        if (Test-Path (Join-Path $D.Dir "STOP")) { continue }
        if (-not $D.Lane) { continue }   # no ready lane: it stays stopped (or asleep, at no cost)
        if (-not (Test-DuoAlive $D)) {
            $D.Restarts = @($D.Restarts | Where-Object { $_ -gt (Get-Date).AddHours(-1) })
            if ($D.Restarts.Count -ge 3) {
                $D.Incident = "duo dead 3 times in 1 h"; Invoke-Mediator $D $D.Incident; continue
            }
            $D.Restarts += (Get-Date)
            Start-Duo $D
            continue
        }
        $age = Get-DuoProgressAge $D
        if (($null -ne $age) -and $age -gt 25) { NoteO "duo $($D.Name) : no tool called for $([int]$age) min (to watch)" }
    }
}

# --- Loop -------------------------------------------------------------------------------------
if (-not (Enter-Lock "orchestrator")) { Write-Host "an orchestrator is already running"; exit 4 }
$Duos = @(Read-Duos)
if ($Active -gt 0) { $Duos = @($Duos | Select-Object -First $Active) }
if (-not $Duos.Count) { NoteO "orchestrator : no duo in config\duos.txt"; Exit-Lock "orchestrator"; exit 2 }
NoteO "orchestrator started (pid $PID) : duos $(($Duos | ForEach-Object { $_.Name }) -join ', ')"
foreach ($D in $Duos) {
    if (-not (Initialize-Worktree $D)) { $D.Incident = "worktree missing" }
    New-Item -ItemType Directory -Force (Join-Path $D.Dir "pipeline") -ErrorAction SilentlyContinue | Out-Null
    # The assignment survives an orchestrator restart.
    $D.Lane = ("" + (Get-Content (Join-Path $D.Dir "pipeline\lane.txt") -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue)).Trim()
}
Update-Lanes $Duos
foreach ($D in $Duos) {
    if ($D.Incident) { continue }
    [void](Read-NewLogLines $D)
    if (Test-DuoAlive $D) { NoteO "duo $($D.Name) : already alive, taken as is"; continue }
    if (-not $D.Lane) { NoteO "duo $($D.Name) : no ready lane, not started"; continue }
    Start-Duo $D
}
while ($true) {
    if (Test-Path $StopAll) {
        foreach ($D in $Duos) { Write-Utf8 (Join-Path $D.Dir "STOP") ("stopped by the orchestrator " + (Get-Date -Format s)) }
        NoteO "orchestrator : STOP-ALL - STOP written in every duo, exiting"
        break
    }
    if ($Once) { Start-Sleep -Seconds 5; Invoke-Round $Duos; break }
    Start-Sleep -Seconds $RoundS
    Invoke-Round $Duos
}
Exit-Lock "orchestrator"
