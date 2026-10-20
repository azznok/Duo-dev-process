# HARNESS COMMON LIBRARY - dot-source it, never run it:
#     . (Join-Path $PSScriptRoot "lib\common.ps1")
# SILENT when loaded (no output): a script that loads it can still be read as JSON.
#
# What it provides:
#   $Root, $Cfg (config/project.env), $State (.state/), $Logs (logs/), $Pipe (pipeline/)
#   Set-Utf8          : UTF-8 everywhere, including the prompt sent through stdin
#                       (without it, every non-ASCII character became "??")
#   Get-Secret        : reads a key from the environment, never prints it
#   lib\claude.ps1 (loaded here) : Invoke-Claude (`claude -p`, dated UTF-8 log in logs/),
#                       Get-FailureClass (ok | quota | auth | api), Get-Backoff, and the quota
#                       memory (Set-QuotaBlocked / Select-Model: a usage limit is REMEMBERED
#                       until its reset)
#   Get-Domains / New-CoderMcp : MCP servers on demand, from the task's DOMAINS line
#   Get-StackLib      : the stack adapter (STACK=<name> -> lib/stacks/<name>.ps1) to dot-source
#   Stack interface   : Start-Stack, Get-StackCrashNote, Get-StackMcp, Get-StackHealth,
#                       Get-AppProcesses, Stop-StackActivity, Stop-StackEditor, $StackKillPatterns
#                       (defaults here = no stack; an adapter replaces them, see lib/stacks/README.md)
#   Test-Port / Ensure-Blender : the Blender bridge (3d tasks), whatever the stack
#   Enter-Lock / Exit-Lock, Get-HeartbeatAge, Get-LiveBenches, Get-Fingerprint
#
# Exit codes shared by the whole harness:
#   0 ok | 2 infrastructure failure (retryable) | 3 FATAL (login, key, merge blocked) |
#   4 refused: another session is alive | 5 quota closed on every model of the chain |
#   10 reviewer: TASK: NONE

$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$State = Join-Path $Root ".state"
$Logs = Join-Path $Root "logs"
$Pipe = Join-Path $Root "pipeline"
foreach ($d in @($State, $Logs)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null } }

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Set-Utf8 {
    # Three settings, not one: the console (output read back), the input, and $OutputEncoding,
    # which is the encoding of text PIPED to a native executable. Without the last one,
    # PowerShell 5.1 sends the prompt as ASCII and every non-ASCII character becomes "?".
    try { [Console]::OutputEncoding = $script:Utf8NoBom } catch {}
    try { [Console]::InputEncoding = $script:Utf8NoBom } catch {}
    $global:OutputEncoding = $script:Utf8NoBom
}
Set-Utf8

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}
function Add-Utf8([string]$Path, [string]$Text) {
    [IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom)
}
function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

# --- Configuration -------------------------------------------------------------
$ConfigDefaults = @{
    STACK = "none"; PROJECT = "project"; LANGUAGE = "en"
    BLENDER_EXE = ""; BLENDER_PORT = "9876"; CLAUDE_CLI = ""
    CODER_MODEL = "claude-opus-5-5"; CODER_FALLBACK = "claude-fable-5-1"
    CODER_EFFORT = "medium"; CODER_EFFORT_REJECTED = "high"; CODER_SETTING_SOURCES = "project,local"
    # Model tiers (task line MODEL: top|default|mid|small) ; "default" = CODER_MODEL.
    MODEL_TOP = "claude-fable-5-1"; MODEL_MID = "claude-sonnet-5-5"; MODEL_SMALL = "claude-haiku-5-5"
    REVIEWER_MODEL = "claude-opus-5-5"; REVIEWER_EFFORT = "medium"
    REVIEWER_ESCALATION = "claude-fable-5-1"; REVIEWER_EFFORT_VISUAL = "high"; REVIEWER_SETTING_SOURCES = "project"
    MAX_NUDGES = "1"; MAX_WAITS = "3"; COMPACT_WINDOW = "200000"; RESUME_MAX_H = "12"
    POLL_IDLE_S = "300"
    # Several duos: this duo's name ("" = single duo, local numbering).
    DUO = ""
    # Quota: reset time read from the message (+ margin), else a new try every
    # QUOTA_PROBE_MIN minutes. A call refused for quota costs nothing.
    QUOTA_PROBE_MIN = "15"; QUOTA_MARGIN_MIN = "2"
    REJECT_MAX = "3"; DIFF_MAX_LINES = "400"
    # Gate (lib\gate.ps1). GATE_CMDS is filled at onboarding (build, lint, tests of the stack).
    GATE_CMDS = ""; GATE_TIMEOUT_S = "2400"
    GATE_LINT_HARNESS_CMD = "bash bin/benches/harness_lint.sh"
    GATE_VISUAL_CMD = ""; GATE_VISUAL_TIMEOUT_S = "1800"
    # No benchmark on every task by default: they run at the END OF A MILESTONE, machine idle.
    GATE_BENCH_CMD = ""; GATE_BENCH_TIMEOUT_S = "3600"; GATE_BENCH_BACKGROUND = "1"
    MILESTONE_BENCH_CMD = ""; MILESTONE_LOAD_CMD = ""; LOAD_TIMEOUT_S = "3600"
    # Load test on NEW seeds while the reviewer works ("off" = disabled).
    BACKGROUND_LOAD_CMD = "off"
    # Heavy gate commands (matching GATE_HEAVY_MATCH) wait for the OTHER duo's heavy build.
    GATE_HEAVY_MATCH = "test"; HEAVY_PROCESS_REGEX = ""
    TEST_PATH_REGEX = '(^|/)(tests?|__tests__|spec)/|[._-](test|spec)s?\.[a-z]+$|^tests/golden/|^scenarios/'
    PROTECTED_DOCS = "docs/VISION.md;docs/PROJECT-RULES.md"
    MCP_BY_DOMAIN = "3d:blender,meshy"
    BUILD_DIR_ENV = ""
    REPORT_MAX_KB = "6"; TASK_MAX_KB = "5"
    GEN_CAP_MESHY = "100"; GEN_CAP_ELEVEN = "4000"
    ONBOARDED = "0"; DISK_MIN_GB = "60"
}

function Import-Config {
    $f = Join-Path $Root "config\project.env"
    $source = "project.env"
    if (-not (Test-Path $f)) { $f = Join-Path $Root "config\project.env.example"; $source = "EXAMPLE" }
    $c = @{}
    foreach ($k in $ConfigDefaults.Keys) { $c[$k] = $ConfigDefaults[$k] }
    if (Test-Path $f) {
        foreach ($l in [IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8)) {
            $t = $l.Trim()
            if (-not $t -or $t.StartsWith("#")) { continue }
            $i = $t.IndexOf("=")
            if ($i -lt 1) { continue }
            $c[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
        }
    }
    # One-off override: HARNESS_<KEY> in the environment; the value "empty" clears the key
    # (e.g. a second duo without per-task benchmarks, without touching config/project.env).
    foreach ($k in @($c.Keys)) {
        $v = [Environment]::GetEnvironmentVariable("HARNESS_$k")
        if ($v -eq "empty") { $c[$k] = "" } elseif ($v) { $c[$k] = $v }
    }
    $c["ROOT"] = $Root
    $c["CONFIG_SOURCE"] = $source
    return $c
}
$Cfg = Import-Config

# --- Stack adapter -------------------------------------------------------------------
# STACK=none (default: the coder runs the build tools itself) or the name of an adapter
# lib/stacks/<name>.ps1 (a long-running editor, emulator, dev server: lib/stacks/README.md).
# Every script does
#     . (Join-Path $PSScriptRoot "lib\common.ps1")
#     $StackLib = Get-StackLib; if ($StackLib) { . $StackLib }
# at SCRIPT level (a dot-source inside a function would only live inside that function).
$Stack = ("" + $Cfg["STACK"]).Trim().ToLower()
if (-not $Stack) { $Stack = "none" }

$LibDir = $PSScriptRoot
function Get-StackLib {
    if ($Stack -eq "none" -or $Stack -notmatch '^[a-z0-9_-]+$') { return "" }
    $p = Join-Path $LibDir "stacks\$Stack.ps1"
    if (-not (Test-Path $p)) { return "" }   # the doctor reports a missing adapter as KO
    return $p
}

# Stack interface defaults (= STACK=none). An adapter loaded AFTER this file replaces them.
$StackKillPatterns = @()                              # command lines to kill (stop-all)
function Start-Stack { return $true }                 # ready for the coder?
function Get-StackCrashNote { return "" }             # recent crash to inject on resume
function Get-StackMcp { return @() }                  # MCP servers ALWAYS given to the coder
function Get-StackHealth { return @() }               # lines @(state, text) for health.ps1
function Get-AppProcesses { return @(Get-Process -Name $Cfg["PROJECT"] -ErrorAction SilentlyContinue) }
function Stop-StackActivity { return "" }             # what was stopped inside the editor
function Stop-StackEditor { return @() }              # editor pids to kill (stop-all -Editor)

# --- Harness journal -----------------------------------------------------------------
function Note([string]$Message) {
    $l = "[{0}] {1}" -f (Get-Date -Format "dd/MM HH:mm:ss"), $Message
    Write-Host $l
    try { Add-Utf8 (Join-Path $Logs ("harness-{0}.log" -f (Get-Date -Format "yyMMdd"))) ($l + "`r`n") } catch {}
}

function New-LogPath([string]$Role) {
    # Always in logs/, never at the root; the name sorts by date.
    return (Join-Path $Logs ("{0}-{1}.log" -f (Get-Date -Format "yyMMdd-HHmmss"), $Role))
}

# --- Secrets ---------------------------------------------------------------------
function Get-Secret([string]$Name) {
    # Process first, then the User registry: a duo started BEFORE the key was set does
    # not inherit it (children copy the parent's environment, not the registry).
    $v = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "User") }
    if ($v) { return $v.Trim() }
    return ""
}
function Copy-SecretsToEnv {
    # Keys reach the MCP servers through the environment (.mcp.json: ${VAR}).
    foreach ($k in @("MESHY_API_KEY", "ELEVENLABS_API_KEY")) {
        $v = Get-Secret $k; if ($v) { Set-Item -Path "Env:$k" -Value $v }
    }
}

# --- Claude CLI, failure classes, quota memory: lib\claude.ps1 ----------------------
. (Join-Path $PSScriptRoot "claude.ps1")

# --- MCP on demand -------------------------------------------------------------------
# The task carries a line "DOMAINS: code|ui|visual|...|3d|audio". The coder ALWAYS gets the
# stack's MCP servers (Get-StackMcp), plus those of MCP_BY_DOMAIN ("3d:blender,meshy;audio:x").
# Every MCP server costs its tool definitions on EVERY model call: only what the task needs.
function Get-McpByDomain {
    $h = @{}
    foreach ($part in (("" + $Cfg["MCP_BY_DOMAIN"]) -split ';')) {
        $i = $part.IndexOf(":")
        if ($i -lt 1) { continue }
        $h[$part.Substring(0, $i).Trim().ToLower()] = @($part.Substring($i + 1) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    return $h
}

function Get-Domains([string]$TaskText) {
    $m = [regex]::Match($TaskText, '(?im)^\s*DOMAINS?\s*:\s*(.+)$')
    if (-not $m.Success) { return @("code") }
    return @($m.Groups[1].Value.ToLower() -split '[\s,|/;]+' | Where-Object { $_ })
}

function New-CoderMcp([string[]]$Domains) {
    # Writes .state/mcp-coder.json: the subset of .mcp.json the task needs.
    # The file keeps ${VAR} as is: the CLI expands them (no secret written).
    $src = Join-Path $Root ".mcp.json"
    if (-not (Test-Path $src)) { return "" }
    try { $j = (Read-Utf8 $src) | ConvertFrom-Json } catch { Note "(.mcp.json unreadable: full MCP)"; return $src }
    $wanted = @(Get-StackMcp)
    $map = Get-McpByDomain
    foreach ($d in $Domains) { if ($map.ContainsKey($d)) { $wanted += $map[$d] } }
    if ($wanted.Count -eq 0) { return "" }   # no MCP: --strict-mcp-config alone
    $keep = [ordered]@{}
    foreach ($p in $j.mcpServers.PSObject.Properties) { if ($wanted -contains $p.Name) { $keep[$p.Name] = $p.Value } }
    $dst = Join-Path $State "mcp-coder.json"
    Write-Utf8 $dst (@{ mcpServers = $keep } | ConvertTo-Json -Depth 8)
    return $dst
}

# --- Locks, heartbeat, benches -------------------------------------------------------
function Enter-Lock([string]$Name) {
    $f = Join-Path $State "$Name.lock"
    if (Test-Path $f) {
        $old = (Get-Content $f -Raw).Trim()
        if ($old -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) { return $false }
    }
    Write-Utf8 $f "$PID"
    return $true
}
function Exit-Lock([string]$Name) { Remove-Item (Join-Path $State "$Name.lock") -Force -ErrorAction SilentlyContinue }

$HeartbeatFile = Join-Path $State "heartbeat"
function Get-HeartbeatAge {
    # Minutes since the last tool called by a CODER (PostToolUse hook, .claude/settings.json).
    # A dead pid does not tell that a session is dead.
    if (-not (Test-Path $HeartbeatFile)) { return $null }
    return ((Get-Date) - (Get-Item $HeartbeatFile).LastWriteTime).TotalMinutes
}

$BenchesFile = Join-Path $State "benches.pids"
function Get-LiveBenches {
    # Lines "<pid> <date> <script>" written by bin/benches/bench_pid.*; only the live ones.
    $v = @()
    if (-not (Test-Path $BenchesFile)) { return $v }
    foreach ($l in (Get-Content $BenchesFile)) {
        if ($l -match '^\s*(\d+)\s+(\S+)\s+(.*)$') {
            if (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue) {
                $v += [pscustomobject]@{ Pid = [int]$Matches[1]; Since = $Matches[2]; Script = $Matches[3].Trim() }
            }
        }
    }
    return $v
}

function Get-Fingerprint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return "absent" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.Substring(0, 16)
}

function Get-Head {
    Push-Location $Root
    $h = (git rev-parse HEAD 2>$null)
    Pop-Location
    if ($h) { return ("" + $h).Trim() }
    return "none"
}

function Get-PipelineState {
    # What the duo loop looks at to choose: reviewer or coder.
    $t = Join-Path $Pipe "task.md"
    $first = ""
    if (Test-Path $t) { $first = "" + (Get-Content $t -TotalCount 1 -Encoding UTF8) }
    return [pscustomobject]@{
        Task = (Test-Path $t); First = $first
        None = ($first -match "TASK:\s*NONE")
        Report = (Test-Path (Join-Path $Pipe "report.md"))
        InProgress = (Test-Path (Join-Path $Pipe ".in_progress"))
    }
}

function Get-IdleFingerprints {
    # What can unblock a TASK: NONE: the plan, the owner's inbox, a lane that opens, HEAD.
    return @{
        "PLAN.md" = (Get-Fingerprint (Join-Path $Root "docs\PLAN.md"))
        "owner.md" = (Get-Fingerprint (Join-Path $Pipe "owner.md"))
        "lane.txt" = (Get-Fingerprint (Join-Path $Pipe "lane.txt"))
        "HEAD" = (Get-Head)
    }
}

# --- The Blender bridge (3d tasks), whatever the stack -------------------------------
function Test-Port([int]$Port) {
    try { return [bool](Test-NetConnection 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet) } catch { return $false }
}

function Ensure-Blender {
    # NOT FATAL: without Blender, the agent works on something else and says so.
    $port = [int]$Cfg["BLENDER_PORT"]
    if (Test-Port $port) { return }
    $exe = $Cfg["BLENDER_EXE"]
    if (-not $exe -or -not (Test-Path $exe)) { Note "(Blender not found: asset pipeline unavailable this cycle)"; return }
    # After a PC restart the addon no longer auto-enables, and each restart stacked up a
    # silent Blender: kill the silent ones, start WITH the boot script.
    Get-Process -Name blender -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $boot = Join-Path $Root "tools\blender\boot.py"
    Start-Process -FilePath $exe -ArgumentList @("--python", "`"$boot`"") -WindowStyle Minimized | Out-Null
    for ($k = 0; $k -lt 15; $k++) {
        Start-Sleep -Seconds 3
        if (Test-Port $port) { Note "Blender MCP ready"; return }
    }
    Note "(Blender started but MCP silent after 45 s: the agent will work without it)"
}

function Get-GateCmds {
    # Gate commands (GATE_CMDS, ";"-separated, each run by cmd.exe). A command that expands to a
    # huge argument list can exceed the Windows command line (os error 206): wrap it in a script.
    return @((("" + $Cfg["GATE_CMDS"]) -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
