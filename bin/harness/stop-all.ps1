# STOP everything the agent may have started. Benches live OUTSIDE the Claude session: without
# this script, the app keeps running on its own after the stop (seen for real): here, an exe of
# the duo's build folder (app, headless server, tools) that survives.
#
#   .\bin\harness\stop-all.ps1               # benches + build-folder exes + coder session
#   .\bin\harness\stop-all.ps1 -Benches      # ONLY benches and exes (called by run-coder)
#   .\bin\harness\stop-all.ps1 -Editor       # + the stack's editor (adapter, e.g. a game editor)
#   .\bin\harness\stop-all.ps1 -Definitive   # + writes STOP and kills this folder's duo loop
#
# Order: 1. the declared PIDs (.state/benches.pids, via bin/benches/bench_pid.*),
# 2. command-line patterns (safety net), 3. the app (exes of the build folder),
# 4. the editor's activity, 5. the claude -p session.
# What depends on the stack comes from the stack interface (common.ps1, lib/stacks/<name>.ps1).
param([switch]$Editor, [switch]$Definitive, [switch]$Benches)

. (Join-Path $PSScriptRoot "lib\common.ps1")
$StackLib = Get-StackLib; if ($StackLib) { . $StackLib }   # STACK: lib\stacks\<name>.ps1 or nothing
$killed = @()

function Stop-Pid([int]$Id, [string]$Why) {
    if ($Id -eq $PID) { return }
    try { Stop-Process -Id $Id -Force -ErrorAction Stop; $script:killed += "$Why (pid $Id)" } catch {}
}

# Several harnesses on the machine (two duos, a loop test in %TEMP%): every net spares the
# processes of ANOTHER harness (lib\shared.ps1: Test-OtherHarness).
. (Join-Path $PSScriptRoot "lib\shared.ps1")
$AllProcs = @{}
foreach ($q in @(Get-CimInstance Win32_Process)) { $AllProcs[[int]$q.ProcessId] = $q }
function Test-OtherDuo($P) { return (Test-OtherHarness $P $AllProcs) }

if ($Definitive) {
    Write-Utf8 (Join-Path $Root "STOP") ("full stop " + (Get-Date -Format s))
    $AllProcs.Values | Where-Object {
        $_.CommandLine -match 'bin[\/]harness[\/]duo\.ps1' -and $_.ProcessId -ne $PID -and -not (Test-OtherDuo $_)
    } | ForEach-Object { Stop-Pid $_.ProcessId "duo loop" }
}

# 1. The PIDs declared by the benches themselves ("<pid> <date> <script>").
if (Test-Path $BenchesFile) {
    foreach ($l in (Get-Content $BenchesFile)) { if ($l -match '^\s*(\d+)\b') { Stop-Pid ([int]$Matches[1]) "declared bench" } }
    Remove-Item $BenchesFile -Force -ErrorAction SilentlyContinue
}

# 2. Safety net: any bench or driving script of the repo. Separators are written [\/]: a bare
#    backslash gets eaten by some writing tools.
$patterns = @('bin[\/]benches[\/]') + @($StackKillPatterns)
if (-not $Benches) { $patterns += 'run-coder\.ps1' }
$procs = $AllProcs.Values | Where-Object {
    $_.CommandLine -and $_.CommandLine -notlike '*stop-all.ps1*' -and $_.ProcessId -ne $PID -and -not (Test-OtherDuo $_)
}
foreach ($p in $procs) {
    foreach ($m in $patterns) { if ($p.CommandLine -match $m) { Stop-Pid $p.ProcessId "script $m"; break } }
}

# 3. The app: Start-Process sometimes returns a LAUNCHER, the real exe survives and holds the
#    port. Gentle close first (some files are only flushed that way). Same Test-OtherDuo filter
#    as 2 and 5: an exe started by the OTHER duo is never killed.
#    The duo's build folder: HARNESS_BUILD_DIR (set by the orchestrator), else this folder's line
#    of config\duos.txt, else none.
$BuildDir = ("" + $env:HARNESS_BUILD_DIR).Trim()
if (-not $BuildDir) {
    $parent = Split-Path $Root -Parent
    foreach ($t in (Get-Content (Join-Path $Root "config\duos.txt") -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $c = $t.Trim() -split '\s+'
        if ($c.Count -lt 3 -or $c[0].StartsWith("#") -or $c[2] -eq "-") { continue }
        $dir = if ($c[1] -eq ".") { $Root } else { Join-Path $parent $c[1] }
        if ([IO.Path]::GetFullPath($dir).TrimEnd('\') -eq $Root.TrimEnd('\')) { $BuildDir = Join-Path $parent $c[2] }
    }
}
if ($BuildDir -and -not [IO.Path]::IsPathRooted($BuildDir)) { $BuildDir = Join-Path $Root $BuildDir }
function Get-DuoApps {
    $l = @(Get-AppProcesses)
    if ($BuildDir) {
        $t = ([IO.Path]::GetFullPath($BuildDir)).TrimEnd('\') + "\"
        $l += @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($t, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
    }
    return @($l | Where-Object { $_ -and $_.Id -ne $PID } | Sort-Object Id -Unique |
        Where-Object { $q = $AllProcs[[int]$_.Id]; -not ($q -and (Test-OtherDuo $q)) })
}
$apps = @(Get-DuoApps)
if ($apps.Count) {
    $apps | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch {} }
    Start-Sleep -Seconds 3
    Get-DuoApps | ForEach-Object { Stop-Pid $_.Id "app" }
}

# 4. The editor's running activity (play sessions, ticks...): stack interface, empty by default.
if (-not $Editor) { $t = Stop-StackActivity; if ($t) { $killed += $t } }

if (-not $Benches) {
    # 5. The coder's CLI session (claude -p) - never the supervisor's interactive session.
    $AllProcs.Values | Where-Object { $_.Name -match '^(claude|node)\.exe$' -and $_.CommandLine -match ' -p ' -and $_.CommandLine -match 'skip-permissions' -and -not (Test-OtherDuo $_) } |
        ForEach-Object { Stop-Pid $_.ProcessId "coder session" }
    Exit-Lock "coder"
    Remove-Item $HeartbeatFile -Force -ErrorAction SilentlyContinue
}

if ($Editor) {
    foreach ($e in @(Stop-StackEditor)) { Stop-Pid $e "stack editor" }
}

if ($killed.Count -gt 0) { Write-Host ("Stopped: " + ($killed -join ", ")) } else { Write-Host "Nothing to stop." }
