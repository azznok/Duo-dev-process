# THE MEDIATOR: called by orchestrator.ps1 on ONE incident of ONE stopped duo. The model judges
# (solves a conflict, or names the cause); this script does the mechanics: forbidden paths, gate
# if code was in conflict, commit, push, resume of the duo, trace for the reviewer.
#   powershell -File bin\harness\mediator.ps1 -Duo B -DuoRoot <worktree> -Incident "merge blocked"
# Codes: 0 solved (the orchestrator restarts the duo) | 1 question asked or guard tripped (duo stopped).
# Models: operations MODEL_MID medium (ESCALATE -> CODER_MODEL high); documents conflict
# CODER_MODEL high; code conflict MODEL_TOP high; top model exhausted -> CODER_MODEL high.
# Test without a model: bin\harness\test\test-mediator.ps1.
param([Parameter(Mandatory = $true)][string]$Duo, [Parameter(Mandatory = $true)][string]$DuoRoot,
      [Parameter(Mandatory = $true)][string]$Incident)

. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\autonomy.ps1")
. (Join-Path $PSScriptRoot "lib\shared.ps1")
# Paths the mediator never touches: the harness itself, the owner's protected docs, the secrets.
$prot = @((("" + $Cfg["PROTECTED_DOCS"]) -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { '^' + [regex]::Escape($_) + '$' })
$Forbidden = (@('^bin/harness/', '(^|/)\.mcp\.json$', '^config/project\.env$') + $prot) -join '|'
function NoteM([string]$M) {
    # In the journal of the TREATED duo (the orchestrator reads incidents there: never the
    # orchestrator's uppercase incident words here).
    $l = "[{0}] mediator (duo {1}) : {2}" -f (Get-Date -Format "dd/MM HH:mm:ss"), $Duo, $M
    Write-Host $l
    $d = Join-Path $DuoRoot "logs"
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
    try { Add-Utf8 (Join-Path $d ("harness-{0}.log" -f (Get-Date -Format "yyMMdd"))) ($l + "`r`n") } catch {}
}
function GitD { & git -C $DuoRoot @args 2>&1 | Out-String }
function Exit-Run([int]$Code, [string]$Why) {
    NoteM $Why
    if ($Code -ne 0) { Send-Ntfy "duo $Duo stopped" "Mediator: $Why" "high" }
    Exit-SharedLock "merge"; Exit-SharedLock "mediator"
    exit $Code
}

if (-not (Enter-SharedLock "mediator" 1800)) { NoteM "another mediator has been running for 30 min: giving up"; exit 1 }

# --- 1. The incident and its context ---------------------------------------------------------
$journal = Get-ChildItem (Join-Path $DuoRoot "logs") -Filter "harness-*.log" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
$tail = if ($journal) { (Get-Content $journal.FullName -Tail 60 -Encoding UTF8) -join "`n" } else { "(no journal)" }
$merge = $Incident -match 'merge blocked'
$branch = ""; $conflicts = @()
if ($merge) {
    $m = [regex]::Matches($tail, 'merge of (task/\S+) failed')
    if ($m.Count) { $branch = $m[$m.Count - 1].Groups[1].Value }
    if (-not $branch) { Exit-Run 1 "merge blocked, but no branch named in the journal" }
    $mt = @(& git -C $DuoRoot --attr-source=main merge-tree --write-tree --name-only main $branch 2>$null)
    $conflicts = @($mt | Select-Object -Skip 1 | Where-Object { $_ -and $_ -notmatch '^(Auto-merging|CONFLICT)' })
}
$code = @($conflicts | Where-Object { $_ -notmatch '\.md$' })
if ($merge -and $code.Count) { $models = @($Cfg["MODEL_TOP"], $Cfg["CODER_MODEL"]); $effort = "high"; $kind = "code conflict" }
elseif ($merge) { $models = @($Cfg["CODER_MODEL"], $Cfg["MODEL_TOP"]); $effort = "high"; $kind = "documents conflict" }
else { $models = @($Cfg["MODEL_MID"], $Cfg["CODER_MODEL"]); $effort = "medium"; $kind = "operations" }
$models = @($models | Where-Object { $_ } | Select-Object -Unique)
NoteM "$Incident ($kind$(if ($branch) { ", $branch" })$(if ($conflicts.Count) { ", conflicts: $($conflicts -join ', ')" }))"

# The duo's own build folder (config\duos.txt), so a gate run here does not lock the other duo's files.
foreach ($t in (Get-Content (Join-Path $Root "config\duos.txt") -Encoding UTF8 -ErrorAction SilentlyContinue)) {
    $c = $t.Trim() -split '\s+'
    if ($c[0] -eq $Duo -and $c.Count -ge 3 -and $c[2] -ne "-") {
        $build = Join-Path (Split-Path $Root -Parent) $c[2]
        $env:HARNESS_BUILD_DIR = $build
        $bde = ("" + $Cfg["BUILD_DIR_ENV"]).Trim()
        if ($bde) { Set-Item -Path "Env:$bde" -Value $build }
    }
}

# --- 2. The model (a merge happens under the shared merge lock) ---------------------------------
if ($merge -and -not (Enter-SharedLock "merge" 900)) { Exit-Run 1 "merge lock unavailable" }
$before = (GitD rev-parse HEAD).Trim()
$packet = "`n---`n## INCIDENT`n`nDuo: $Duo`nWorktree: $DuoRoot`nIncident: $Incident`n"
if ($branch) { $packet += "BRANCH: $branch`nFiles in conflict with main: $($conflicts -join ', ')`n" }
$packet += "`n## DUO JOURNAL (end)`n`n$tail`n`n## GIT`n`n$(GitD status --short --branch)`n$(GitD log --oneline -5)`n"
$prompt = (Read-Utf8 (Join-Path $PSScriptRoot "prompts\mediator.md")) + "`nROLE: MEDIATOR`n" + $packet
$env:HARNESS_ROLE = "mediator"
$result = ""
for ($try = 0; $try -lt 2 -and -not $result; $try++) {
    $m = Select-Model $models
    if (-not $m) { Exit-Run 1 "quota closed on $($models -join ', ')" }
    $e = if ($m -eq $Cfg["MODEL_TOP"] -or $effort -eq "high") { "high" } else { $effort }
    # The top model exhausted: the next one works at high effort, never medium.
    if ($m -ne $models[0] -and $models[0] -eq $Cfg["MODEL_TOP"]) { $e = "high" }
    $a = @("-p", "--output-format", "stream-json", "--verbose", "--dangerously-skip-permissions", "--model", $m,
           "--effort", $e, "--strict-mcp-config", "--setting-sources", "project,local")
    $log = New-LogPath "mediator-$Duo"
    NoteM "$m effort $e -> $(Split-Path $log -Leaf)"
    Push-Location $DuoRoot
    try { $raw = Invoke-Claude -Prompt $prompt -Arguments $a -LogPath $log } finally { Pop-Location }
    $j = Read-Result $raw
    $cl = Get-FailureClass $j $raw
    if ($cl -eq "quota") { Set-QuotaBlocked $m (Get-FailureText $j $raw); continue }
    if ($cl -ne "ok") { Exit-Run 1 "model call failed ($cl, $(Split-Path $log -Leaf))" }
    $r = [regex]::Match(("" + $j.result), 'RESULT:\s*(SOLVED|QUESTION|ESCALATE)')
    $result = if ($r.Success) { $r.Groups[1].Value } else { "QUESTION" }
    if ($result -eq "ESCALATE" -and -not $merge) {
        NoteM "escalation asked: $($Cfg['CODER_MODEL']), high effort"
        $models = @($Cfg["CODER_MODEL"]); $effort = "high"; $result = ""
    }
}
Remove-Item Env:HARNESS_ROLE -ErrorAction SilentlyContinue

# --- 3. The guard: no forbidden path, committed or staged ----------------------------------------
# During a merge: only the files that differ from BOTH sides are the mediator's work (the other
# duo's normal changes differ from one side only). Otherwise: its commits and its staged files.
$gitDir = (GitD rev-parse --absolute-git-dir).Trim()
$merging = Test-Path (Join-Path $gitDir "MERGE_HEAD")
if ($merging) {
    $cH = @(& git -C $DuoRoot diff --cached --name-only HEAD 2>$null)
    $cM = @(& git -C $DuoRoot diff --cached --name-only MERGE_HEAD 2>$null)
    $touched = @($cH | Where-Object { $cM -contains $_ })
} else {
    $touched = @(& git -C $DuoRoot diff --name-only $before HEAD 2>$null) + @(& git -C $DuoRoot diff --name-only HEAD 2>$null)
}
$bad = @($touched | Where-Object { $_ -match $Forbidden } | Select-Object -Unique)
if ($bad.Count) {
    if ($merging) { GitD merge --abort | Out-Null }
    Exit-Run 1 "guard: forbidden paths touched ($($bad -join ', ')); nothing is pushed"
}
if ($result -ne "SOLVED") { Exit-Run 1 "$result : the duo stays stopped (docs/QUESTIONS.md)" }
if (-not $merge) { Exit-Run 0 "solved" }

# --- 4. The merge: check, gate if code, commit, push, resume the duo -------------------------------
if ($merging) {
    $left = @(& git -C $DuoRoot diff --name-only --diff-filter=U 2>$null | Where-Object { $_ })
    if ($left.Count) { GitD merge --abort | Out-Null; Exit-Run 1 "unresolved conflicts ($($left -join ', ')): merge aborted" }
    if ($code.Count) {
        # A resolved code conflict is new code nobody tested: the full gate, before the commit.
        foreach ($c in @(Get-GateCmds)) {
            Push-Location $DuoRoot
            try { & cmd /c $c 2>&1 | Out-Null; $rc = $LASTEXITCODE } finally { Pop-Location }
            if ($rc -ne 0) { GitD merge --abort | Out-Null; Exit-Run 1 "gate KO after resolution ($c, code $rc): merge aborted" }
        }
        NoteM "full gate green after resolving the code"
    }
    $r = GitD commit --no-edit -q
    if ($LASTEXITCODE -ne 0) { GitD merge --abort | Out-Null; Exit-Run 1 "cannot commit the merge: $r" }
} else {
    & git -C $DuoRoot merge-base --is-ancestor $branch HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -or (GitD rev-parse --abbrev-ref HEAD).Trim() -ne "main") { Exit-Run 1 "SOLVED announced, but $branch is not merged into main" }
}
$resolution = (GitD show --cc --format="%H %s" HEAD) -split "`n" | Select-Object -First 300
Write-Utf8 (Join-Path $DuoRoot "pipeline\mediation.md") ("# Mediator resolution ($(Get-Date -Format 'dd/MM HH:mm'), $Incident)`n`nBranch: $branch ; files: $($conflicts -join ', ')`n`n``````diff`n" + ($resolution -join "`n") + "`n```````n")
$r = GitD push -q origin main
if ($LASTEXITCODE -ne 0) { NoteM "push of main failed (not blocking): $r" }
# The merge lock stays ours during the resume (main is still checked out HERE); the resume, a
# child process, inherits it. Releasing it before let the other duo take it and wait for main:
# a 10-minute deadlock.
$env:HARNESS_INHERITED_LOCK = "$PID"
$r = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $DuoRoot "bin\harness\resume-merge.ps1") -Branch $branch 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { Exit-Run 1 "cannot resume the duo: $($r.Trim())" }
Exit-Run 0 "$branch merged after resolution ($kind); duo ready"
