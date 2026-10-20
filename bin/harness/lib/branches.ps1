# TASK BRANCHES - dot-source it AFTER lib\common.ps1 (uses $Root, Note).
#   Get-Branch, Get-BranchName, New-TaskBranch, Merge-Task, Set-AsideTask
. (Join-Path $PSScriptRoot "shared.ps1")   # merge lock shared by the duos
# --- Task branches -------------------------------------------------------------------
# One task = one branch task/<nnn>-<entry>, created from main by run-reviewer.ps1 when the
# reviewer writes a new task; merged into main (--no-ff) and pushed ONLY after
# VERDICT: ACCEPT. A rejection: the fix goes on in the same branch. Agents neither create
# nor merge branches: the harness does.
function Invoke-GitQuiet([string[]]$A) {
    $env:GIT_TERMINAL_PROMPT = "0"
    $o = (& git @A 2>&1 | Out-String)
    return [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = $o.TrimEnd() }
}

function Get-Branch {
    Push-Location $Root
    $b = (git rev-parse --abbrev-ref HEAD 2>$null)
    Pop-Location
    return ("" + $b).Trim()
}

function Get-BranchName([string]$Tag, [string]$FirstLine) {
    # "TASK: 004 - [M0-03] seeded rng" -> task/004-m0-03
    $m = [regex]::Match($FirstLine, '\[([A-Za-z0-9-]+)\]')
    if ($m.Success) { return "task/$Tag-" + $m.Groups[1].Value.ToLower() }
    return "task/$Tag"
}

function Get-WorktreeMain {
    # ANOTHER worktree that holds main keeps the harness from switching to it (git refuses).
    $current = (Resolve-Path $Root).Path.TrimEnd('\').Replace('\', '/').ToLower()
    $path = ""
    foreach ($l in @(git -C $Root worktree list --porcelain 2>$null)) {
        if ($l -match '^worktree (.+)$') { $path = $Matches[1] }
        elseif ($l -eq "branch refs/heads/main" -and $path.TrimEnd('/').ToLower() -ne $current) { return $path }
    }
    return ""
}

function Test-MainFree {
    # Two duos in parallel: the other one only holds main for the length of a merge;
    # wait for it (10 min at most) before giving up.
    $wt = Get-WorktreeMain
    for ($k = 0; $wt -and $k -lt 60; $k++) {
        if ($k -eq 0) { Note "harness : main is held by the worktree $wt ; waiting (10 min at most)" }
        Start-Sleep -Seconds 10
        $wt = Get-WorktreeMain
    }
    if (-not $wt) { return $true }
    Note "harness : main is held by the worktree $wt ; run 'git switch --detach' (or a branch) there to free main"
    if (Get-Command Send-Ntfy -ErrorAction SilentlyContinue) {
        Send-Ntfy "main is busy" "The worktree $wt holds the main branch: the duo can neither merge nor create a branch. In that folder: git switch --detach." "high"
    }
    return $false
}

function Sync-Main {
    # On main: fetch what the owner pushed to the remote. Never blocking.
    $r = Invoke-GitQuiet @("fetch", "-q", "origin", "main")
    if (-not $r.Ok) { Note "harness : cannot fetch origin (going on with local main) : $($r.Output)"; return }
    if ((Invoke-GitQuiet @("merge-base", "--is-ancestor", "origin/main", "HEAD")).Ok) { return }
    $r = Invoke-GitQuiet @("merge", "--ff-only", "-q", "origin/main")
    if ($r.Ok) { Note "harness : main fast-forwarded to origin/main (changes pushed by the owner)"; return }
    $r = Invoke-GitQuiet @("merge", "--no-ff", "-q", "-m", "chore(git): merge origin/main (owner changes)", "origin/main")
    if ($r.Ok) { Note "harness : origin/main merged into main (changes pushed by the owner)"; return }
    Invoke-GitQuiet @("merge", "--abort") | Out-Null
    Note "harness : origin/main does not merge into main (conflict) : going on with local main"
    if (Get-Command Send-Ntfy -ErrorAction SilentlyContinue) {
        Send-Ntfy "conflict with the remote" "origin/main does not merge into local main: your pushed changes wait for a manual merge." "high"
    }
}

function New-TaskBranch([string]$Name) {
    Push-Location $Root
    $detached = (Get-Branch) -eq "HEAD"
    try {
        # A detached duo (end of its lane) starts again from the freshest main, under the merge lock.
        if ($detached) {
            if (-not (Enter-SharedLock "merge" 900)) { return $false }
            if (-not (Test-MainFree)) { return $false }
            $r = Invoke-GitQuiet @("checkout", "-q", "main")
            if (-not $r.Ok) { Note "harness : cannot go back to main (branch $Name not created) : $($r.Output)"; return $false }
        }
        # Every new task starts from the freshest main, remote included.
        if ((Get-Branch) -eq "main") { Sync-Main }
        $r = Invoke-GitQuiet @("checkout", "-b", $Name)
        if (-not $r.Ok) { Note "harness : branch $Name not created : $($r.Output)"; return $false }
        Note "harness : branch $Name created from main"
        return $true
    } finally {
        if ($detached) { Exit-SharedLock "merge" }
        Pop-Location
    }
}

function Get-ReviewerNotes {
    # The only tracked files the reviewer writes: questions, the owner's page and its per-duo parts.
    $l = @("docs/QUESTIONS.md")
    $l += @(Get-ChildItem (Join-Path $Root "docs") -Filter "OWNER*.md" -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { "docs/" + $_.Name })
    return @($l | Where-Object { Test-Path (Join-Path $Root $_) })
}

function Update-AdrIndex {
    # One ADR = one file in docs/adr/; docs/DECISIONS.md is their index, GENERATED here, on main,
    # after each merge (no duo writes it: two duos never share that file). Never blocking.
    if (-not (Test-Path (Join-Path $Root "tools\doc\adr.py"))) { return }
    $s = (& python (Join-Path $Root "tools\doc\adr.py") index 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { Note "harness : ADR index not regenerated (not blocking) : $s"; return }
    if ((Invoke-GitQuiet @("diff", "--quiet", "HEAD", "--", "docs/DECISIONS.md")).Ok) { return }
    Invoke-GitQuiet @("add", "--", "docs/DECISIONS.md") | Out-Null
    $r = Invoke-GitQuiet @("commit", "-q", "-m", "docs(harness): regenerate the ADR index")
    if ($r.Ok) { Note "harness : ADR index regenerated on main"; return }
    # Never leave a tracked file dirty on main: it would block the next checkout.
    Invoke-GitQuiet @("reset", "-q", "--", "docs/DECISIONS.md") | Out-Null
    Invoke-GitQuiet @("checkout", "-q", "--", "docs/DECISIONS.md") | Out-Null
    Note "harness : ADR index not committed (not blocking) : $($r.Output)"
}

function Resolve-MechanicalConflicts([string]$Branch) {
    # While merging $Branch into main, conflicts that have only one right answer: the generated
    # ADR index (regenerated). True if ALL conflicts are of that kind and the merge is committed;
    # false otherwise (nothing touched).
    # A backlog file where both duos only ADDED at the same place (empty base in each hunk): both
    # entries are kept (main first); an existing line changed on both sides stays a real conflict
    # (the mediator's job).
    $conf = @(git -C $Root -c core.quotepath=off diff --name-only --diff-filter=U 2>$null | Where-Object { $_ })
    $mech = @("docs/DECISIONS.md")
    $backlog = @($conf | Where-Object { $_ -match '^docs/backlog/[^/]+\.md$' })
    if (-not $conf.Count -or @($conf | Where-Object { $mech -notcontains $_ -and $backlog -notcontains $_ }).Count) { return $false }
    foreach ($b in $backlog) {
        Invoke-GitQuiet @("checkout", "--conflict=diff3", "--", $b) | Out-Null
        & python (Join-Path $Root "tools\doc\concurrent_appends.py") (Join-Path $Root $b) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    if ($conf -contains "docs/DECISIONS.md") {
        & python (Join-Path $Root "tools\doc\adr.py") index 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    Invoke-GitQuiet (@("add", "--") + $conf) | Out-Null
    $r = Invoke-GitQuiet @("commit", "-q", "--no-edit")
    if ($r.Ok) { Note "harness : mechanical conflict solved alone ($($conf -join ', ')) for $Branch" }
    return $r.Ok
}

function Set-AsideTask([string]$Branch) {
    # Circuit breaker: too many rejections in a row. The branch is KEPT as is (the owner looks
    # at it) and the duo starts again from main. The reviewer's notes (its question!) go to
    # main, not to the branch set aside.
    Push-Location $Root
    try {
        if (-not (Test-MainFree)) { return $false }
        $notes = @(Get-ReviewerNotes)
        $content = @{}
        foreach ($n in $notes) { $content[$n] = [IO.File]::ReadAllBytes((Join-Path $Root $n)) }
        Invoke-GitQuiet (@("checkout", "-q", "--") + $notes) | Out-Null
        $r = Invoke-GitQuiet @("checkout", "-q", "main")
        if (-not $r.Ok) {
            foreach ($n in $notes) { [IO.File]::WriteAllBytes((Join-Path $Root $n), $content[$n]) }
            Note "harness : cannot set $Branch aside (dirty tree?) : $($r.Output)"
            return $false
        }
        foreach ($n in $notes) { [IO.File]::WriteAllBytes((Join-Path $Root $n), $content[$n]) }
        if (-not (Invoke-GitQuiet (@("diff", "--quiet", "HEAD", "--") + $notes)).Ok) {
            Invoke-GitQuiet (@("add", "--") + $notes) | Out-Null
            Invoke-GitQuiet @("commit", "-q", "-m", "docs(review): reviewer notes, $Branch set aside") | Out-Null
        }
        Note "harness : $Branch SET ASIDE (not merged, kept) ; back on main"
        return $true
    } finally { Pop-Location }
}

function Repair-LineEndings([string]$Context) {
    # A tracked file with MIXED line endings stays "modified" for git (autocrlf + text
    # attribute) without any content change, and blocks checkout and merge (a merge was
    # blocked this way). Only files whose diff vanishes when CR is ignored are renormalized.
    $all = @(git -C $Root -c core.quotepath=off diff --name-only 2>$null | Where-Object { $_ })
    if (-not $all.Count) { return }
    $real = @(git -C $Root -c core.quotepath=off diff --ignore-cr-at-eol --name-only 2>$null | Where-Object { $_ })
    $eol = @($all | Where-Object { $real -notcontains $_ })
    if (-not $eol.Count) { return }
    Invoke-GitQuiet (@("add", "--renormalize", "--") + $eol) | Out-Null
    Invoke-GitQuiet @("commit", "-q", "-m", "chore(process): renormalize line endings ($Context)") | Out-Null
    Note "harness : line endings renormalized before the merge : $($eol -join ', ')"
}

function Merge-Task([string]$Branch) {
    # Called only after VERDICT: ACCEPT. False = nothing is merged, we stay on the branch;
    # a human looks (conflict, dirty file).
    Push-Location $Root
    try {
        # The reviewer's notes (the only tracked files it writes) leave with the branch.
        # pipeline/report.md is git-ignored: never committed (a tracked report, left dirty,
        # blocked the return to main, and both duos conflicted on it at every merge).
        $notes = @(Get-ReviewerNotes)
        # diff --quiet: code 1 = modified (the text output mixes in CRLF warnings).
        if ($notes.Count -and -not (Invoke-GitQuiet (@("diff", "--quiet", "HEAD", "--") + $notes)).Ok) {
            Invoke-GitQuiet (@("add", "--") + $notes) | Out-Null
            Invoke-GitQuiet @("commit", "-q", "-m", "docs(review): reviewer notes ($Branch)") | Out-Null
        }
        # One merge at a time between duos: the shared lock covers main from end to end.
        # The other duo's mediator can hold this lock during its whole gate (~30 min seen): wait
        # 40 min, and name the branch if it is too long, else THIS duo's mediator does not know
        # what to merge.
        if (-not (Enter-SharedLock "merge" 2400)) { Note "harness : merge of $Branch failed (merge lock held)"; return $false }
        try {
            if (-not (Test-MainFree)) { Note "harness : merge of $Branch failed (main busy)"; return $false }
            Repair-LineEndings $Branch
            $r = Invoke-GitQuiet @("checkout", "-q", "main")
            if (-not $r.Ok) { Note "harness : merge of $Branch failed (cannot go back to main, the branch stays active) : $($r.Output)"; return $false }
            Sync-Main
            Repair-LineEndings "main, before merging $Branch"
            $r = Invoke-GitQuiet @("merge", "--no-ff", "-q", "-m", "chore(git): merge $Branch after review", $Branch)
            if (-not $r.Ok -and (Resolve-MechanicalConflicts $Branch)) { $r = [pscustomobject]@{ Ok = $true; Output = "" } }
            if (-not $r.Ok) {
                Invoke-GitQuiet @("merge", "--abort") | Out-Null
                Invoke-GitQuiet @("checkout", "-q", $Branch) | Out-Null
                Note "harness : merge of $Branch failed (conflict?) : $($r.Output)"
                return $false
            }
            Note "harness : $Branch merged into main"
            Update-AdrIndex
            $r = Invoke-GitQuiet @("push", "-q", "origin", "main")
            if (-not $r.Ok) { Note "harness : push of main failed (not blocking) : $($r.Output)" }
            return $true
        } finally { Exit-SharedLock "merge" }
    } finally { Pop-Location }
}

function Install-CommitMsgHook {
    # The harness commit-msg hook, installed in the COMMON git folder (all worktrees).
    $src = Join-Path $PSScriptRoot "..\hooks\commit-msg"
    if (-not (Test-Path $src)) { return }
    $d = ("" + (git -C $Root rev-parse --git-common-dir 2>$null)).Trim(); if (-not $d) { return }
    if (-not [IO.Path]::IsPathRooted($d)) { $d = Join-Path $Root $d }
    $dst = Join-Path $d "hooks\commit-msg"
    $new = [IO.File]::ReadAllText($src) -replace "`r", ""
    if ((Test-Path $dst) -and (([IO.File]::ReadAllText($dst) -replace "`r", "") -eq $new)) { return }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    [IO.File]::WriteAllText($dst, $new, (New-Object Text.UTF8Encoding($false)))
    Note "harness : commit-msg hook installed ($dst)"
}
