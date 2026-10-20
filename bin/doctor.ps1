# DOCTOR: everything needed BEFORE starting the duos. Starts nothing, pays nothing.
#   powershell -File bin\doctor.ps1      (or bin\doctor.bat)
# One line per check: [OK ] / [KO ] / [-- ] (optional). Exit code = number of KO.
# Keys are said PRESENT or ABSENT, never shown.
# Stack checks come from the stack adapter (STACK in config/project.env; Get-StackHealth).
. (Join-Path $PSScriptRoot "harness\lib\common.ps1")
$StackLib = Get-StackLib; if ($StackLib) { . $StackLib }
$ko = 0
function L([string]$E, [string]$T) { Write-Host ("[{0}] {1}" -f $E, $T); if ($E -eq "KO ") { $script:ko++ } }
function Cmd([string]$Name) { $g = Get-Command $Name -ErrorAction SilentlyContinue; if ($g) { return $g.Source } else { return "" } }

# 1. Windows PowerShell 5.1: the harness is written for it (it reads BOM-less .ps1 as ANSI: ASCII only).
$wps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if ($PSVersionTable.PSEdition -ne "Core" -and $PSVersionTable.PSVersion -ge [version]"5.1") { L "OK " "Windows PowerShell $($PSVersionTable.PSVersion)" }
elseif (Test-Path $wps) { L "OK " "Windows PowerShell present ($wps); this check ran in $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" }
else { L "KO " "Windows PowerShell 5.1 not found (the harness calls 'powershell')" }

# 2. Configuration
if ($Cfg["CONFIG_SOURCE"] -eq "project.env") { L "OK " "config/project.env" } else { L "KO " "config/project.env missing: copy config/project.env.example (the onboarding fills it)" }
if ($Cfg["ONBOARDED"] -eq "1") { L "OK " "ONBOARDED=1 (project $($Cfg['PROJECT']))" } else { L "KO " "ONBOARDED is not 1: run the onboarding: open the supervisor session (supervisor/ONBOARDING.md)" }
$gc = @(Get-GateCmds)
if ($gc.Count) { L "OK " "GATE_CMDS : $($gc.Count) command(s) ($($gc -join ' ; '))" } else { L "KO " "GATE_CMDS empty: the gate would check nothing (build, lint, tests of the stack; set at onboarding)" }
if ($Stack -eq "none") { L "-- " "STACK=none: no stack adapter (the coder runs the build tools itself)" }
elseif ($StackLib) { L "OK " "STACK=$Stack (adapter $(Split-Path $StackLib -Leaf))" }
else { L "KO " "STACK=$Stack but no adapter bin/harness/lib/stacks/$Stack.ps1 (see lib/stacks/README.md)" }
foreach ($x in @(Get-StackHealth)) { if ($x -and $x.Count -ge 2) { L $x[0] $x[1] } }
if (Test-Path (Join-Path $Root "config\duos.txt")) { L "OK " "config/duos.txt" } else { L "KO " "config/duos.txt missing (the orchestrator reads the duos there)" }

# 3. Tools
$exe = Resolve-ClaudeCli
if ($exe) {
    $v = ("" + (& $exe --version 2>&1 | Select-Object -First 1)).Trim()
    L "OK " "claude CLI : $v"
    # Logged in? Only the presence of the credentials file is checked (never read: it is a secret).
    $cred = Join-Path $env:USERPROFILE ".claude\.credentials.json"
    if (Test-Path $cred) { L "OK " "claude CLI credentials present" }
    else { L "-- " "claude CLI login not checkable here: if a duo stops on 'Not logged in', run 'claude /login'" }
} else { L "KO " "claude CLI not found (npm install -g @anthropic-ai/claude-code, or CLAUDE_CLI)" }
foreach ($c in @("git", "python")) { if (Cmd $c) { L "OK " "$c" } else { L "KO " "$c missing from PATH" } }
# Git Bash, not WSL: C:\Windows\System32\bash.exe is WSL's, and the benches would run in Linux.
$bash = Cmd "bash"
$gitBash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
if ($bash -and $bash -notmatch '\\System32\\') { L "OK " "Git Bash ($bash)" }
elseif (Test-Path $gitBash) { L "KO " "'bash' in PATH is $(if ($bash) { $bash } else { 'missing' }), not Git Bash: put $(Split-Path $gitBash) first in PATH" }
else { L "KO " "Git Bash missing (Git for Windows): the benches and hooks are bash scripts" }
$lfs = ("" + (git lfs version 2>&1))
if ($lfs -match "git-lfs") { L "OK " ($lfs.Trim()) } else { L "KO " "git-lfs missing (binaries would bloat the history forever)" }
Push-Location $Root
$filter = ("" + (git config --local --get filter.lfs.process 2>$null)).Trim()
Pop-Location
if ($filter) { L "OK " "LFS installed in this repo" } else { L "-- " "LFS not installed here yet: git lfs install --local" }
if (Cmd "uvx") { L "OK " "uvx (blender MCP server)" } else { L "-- " "uvx missing from PATH: no Blender MCP (pip install uv)" }
if ((Cmd "node") -and (Cmd "npx")) { L "OK " "node / npx (meshy MCP server)" } else { L "-- " "node/npx missing: no Meshy MCP (install Node.js)" }
$bl = $Cfg["BLENDER_EXE"]
if ($bl -and (Test-Path $bl)) { L "OK " "Blender : $bl" } else { L "-- " "Blender not found (BLENDER_EXE): 3d tasks without Blender" }

# 4. Python: what the tools really import (requirements.txt, mapped to import names)
$req = Join-Path $Root "requirements.txt"
$mods = @()
$map = @{ "pillow" = "PIL"; "pyyaml" = "yaml"; "opencv-python" = "cv2"; "scikit-image" = "skimage" }
if (Test-Path $req) {
    foreach ($l in (Get-Content $req)) {
        $t = ($l -replace '#.*$', '').Trim(); if (-not $t) { continue }
        $name = ($t -split '[<>=!~\[; ]')[0].Trim().ToLower()
        if ($map.ContainsKey($name)) { $mods += $map[$name] } else { $mods += ($name -replace '-', '_') }
    }
}
if ($mods.Count -and (Cmd "python")) {
    $py = "import importlib,sys`nfor m in sys.argv[1:]:`n    try: importlib.import_module(m); print('OK', m)`n    except Exception as e: print('KO', m)"
    $res = @(("" + (& python -c $py @mods 2>&1 | Out-String)) -split "`r?`n" | Where-Object { $_ })
    $miss = @($res | Where-Object { $_ -match '^KO ' } | ForEach-Object { $_.Substring(3) })
    if ($miss.Count -eq 0 -and ($res -match '^OK ')) { L "OK " ("python modules (" + ($mods -join ", ") + ")") }
    else { L "KO " ("python modules missing: " + ($miss -join ", ") + " -> python -m pip install -r requirements.txt") }
} elseif (-not $mods.Count) { L "-- " "requirements.txt: no module to check" }

# 5. Ports: free, or held by the right program
$port = [int]$Cfg["BLENDER_PORT"]
$cn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cn) { L "OK " "port $port free (expected: blender)" }
else {
    $n = (Get-Process -Id $cn.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    if ($n -match "blender") { L "OK " "port $port held by $n" } else { L "KO " "port $port SQUATTED by $n (expected blender)" }
}

# 6. Secrets: present or not, never shown
if (Get-Secret "NTFY_TOPIC") { L "OK " "NTFY_TOPIC PRESENT (phone notifications)" } else { L "-- " "NTFY_TOPIC ABSENT: no notification on the phone" }
foreach ($k in @("MESHY_API_KEY", "ELEVENLABS_API_KEY")) { if (Get-Secret $k) { L "OK " "$k PRESENT" } else { L "-- " "$k ABSENT (paid generation unavailable)" } }

# 7. Harness files
$mcp = Join-Path $Root ".mcp.json"
if (Test-Path $mcp) {
    $t = Read-Utf8 $mcp
    if ($t -match 'Bearer\s+[A-Za-z0-9_\-\.]{12,}' -or $t -match '"[A-Z_]*KEY"\s*:\s*"[A-Za-z0-9_\-]{12,}"') { L "KO " ".mcp.json holds a key IN CLEAR: use `${VAR} (see .mcp.json.example)" }
    else { L "OK " ".mcp.json (keys through `${VAR})" }
} else { L "-- " ".mcp.json missing: no MCP (only 3d tasks need it: copy .mcp.json.example)" }
if (Test-Path (Join-Path $Root ".claude\settings.json")) { L "OK " ".claude/settings.json (secrets read denied, heartbeat)" } else { L "KO " ".claude/settings.json missing" }
Push-Location $Root
$tracked = @(git ls-files .mcp.json config/project.env 2>$null)
Pop-Location
if ($tracked.Count) { L "KO " ("secret file TRACKED by git: " + ($tracked -join ", ")) } else { L "OK " "no secret file tracked by git" }

# 8. Disk: a duo's build folder grows fast, two duos twice as fast.
$min = 60; if ($Cfg["DISK_MIN_GB"]) { $min = [int]$Cfg["DISK_MIN_GB"] }
try {
    $free = [int](((Get-PSDrive -Name ($Root.Substring(0, 1))).Free) / 1GB)
    if ($free -ge $min) { L "OK " "disk : $free GB free" } else { L "-- " "disk : $free GB free (< $min, DISK_MIN_GB): the orchestrator will alert" }
} catch { L "-- " "disk : free space unknown" }

Write-Host ""
if ($ko -eq 0) { Write-Host "DOCTOR: 0 KO, all ready. Start the duos from the supervisor session (supervisor/SUPERVISOR.md)." }
else { Write-Host "DOCTOR: $ko KO to fix before starting." }
exit $ko
