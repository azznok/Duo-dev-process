# THE REVIEWER: one `claude -p` pass. Judges the previous task on its proofs and writes the
# next one. Instructions: bin\harness\prompts\reviewer.md.
#
#   powershell -File bin\harness\run-reviewer.ps1
#
# Lessons kept:
#   - A JUDGMENT PACKET is built HERE and put in the prompt: task, report, git log + --stat
#     since base.txt, bounded diff, gate, proof thumbnails, PLAN and STATE, and the DIFF of
#     docs/PLAN.md / pipeline/owner.md as soon as their fingerprint changed since the last pass.
#     An owner's answer can no longer be taken as "already read" (real incident: hours of pause
#     in front of a decision that was already made).
#   - The packet also carries the CURRENT MILESTONE (line "MILESTONE: Mn" of docs/PLAN.md): its
#     section of docs/ROADMAP.md and its backlog docs/backlog/Mn-*.md in full. ADRs (index
#     docs/DECISIONS.md, one file each in docs/adr/) stay to be read on demand.
#   - Default model REVIEWER_MODEL / REVIEWER_EFFORT. ESCALATION (REVIEWER_ESCALATION, effort
#     REVIEWER_EFFORT_VISUAL) ONLY to judge an IMAGE: planning and re-judging after a rejection
#     stay on the default model (escalating them cost a lot for no better verdict). Credit of
#     one exhausted: the other, same effort.
#   - No MCP (--strict-mcp-config without --mcp-config), no skill (--disable-slash-commands),
#     project settings only (--setting-sources), reduced tools (--tools), a wide read-only git
#     allowlist (a narrow one produced dozens of refused calls per pass).
#
# Codes: 0 task ready | 10 TASK: NONE | 2 failure | 3 FATAL | 5 quota closed

. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\branches.ps1")
. (Join-Path $PSScriptRoot "lib\autonomy.ps1")
. (Join-Path $PSScriptRoot "lib\shared.ps1")
. (Join-Path $PSScriptRoot "lib\judge.ps1")
Set-Location $Root
# Several duos: a detached duo (end of lane, or new) reads the freshest main before building its
# packet, otherwise it would judge on a stale backlog.
if ($Cfg["DUO"] -and (Get-Branch) -eq "HEAD") { Invoke-GitQuiet @("checkout", "-q", "--detach", "main") | Out-Null }

$Hist = Join-Path $Pipe "history"
$Snap = Join-Path $Pipe ".snapshots"
foreach ($d in @($Hist, $Snap)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null } }
$TaskFile = Join-Path $Pipe "task.md"
$ReportFile = Join-Path $Pipe "report.md"
$ReviewFile = Join-Path $Pipe "review.md"
$Plan = Join-Path $Root "docs\PLAN.md"
$OwnerBox = Join-Path $Pipe "owner.md"
$HashFile = Join-Path $Pipe ".hashes"

# Pass number = number of the task that will be written.
$nFile = Join-Path $Pipe ".n"
$n = 0; if (Test-Path $nFile) { $n = [int]((Get-Content $nFile -Raw).Trim()) }
$n++
# Several duos: one shared counter, never below the local one. ALWAYS, even without HARNESS_DUO:
# two duos started by hand without it once drew the same task number.
$c = Get-SharedNumber "task" ($n - 1); if ($c -gt 0) { $n = $c }
$tag = "{0:D3}" -f $n

# Snapshot of what is judged, BEFORE task.md is overwritten.
if (Test-Path $TaskFile)   { Copy-Item $TaskFile   (Join-Path $Hist "$tag-judged-task.md")   -Force }
if (Test-Path $ReportFile) { Copy-Item $ReportFile (Join-Path $Hist "$tag-judged-report.md") -Force }

function Invoke-Git([string[]]$A) {
    $o = (& git @A 2>&1 | Out-String)
    return $o.TrimEnd()
}

# --- 1. The judgment packet ---------------------------------------------------------------
$P = New-Object System.Text.StringBuilder
function Section([string]$Title, [string]$Body) {
    [void]$P.AppendLine("`n---`n## $Title`n")
    [void]$P.AppendLine($Body)
}

$taskText = Read-Utf8 $TaskFile
$reportText = Read-Utf8 $ReportFile
if ($taskText) { Section "JUDGED TASK (pipeline/task.md)" $taskText }
else { Section "JUDGED TASK" "NONE (first pass): write VERDICT: NONE (first pass) in pipeline/review.md." }
if ($taskText -and -not ($taskText -match "^TASK:\s*NONE")) {
    if ($reportText) { Section "CODER REPORT (pipeline/report.md)" $reportText }
    else { Section "CODER REPORT" "ABSENT: the task was not delivered." }
}

$base = ""
$bf = Join-Path $Pipe "base.txt"
if (Test-Path $bf) { $base = (Get-Content $bf -Raw).Trim() }
if ($base) {
    Section "COMMITS SINCE THE BASE ($($base.Substring(0, [Math]::Min(10, $base.Length))))" (Invoke-Git @("log", "--oneline", "-n", "30", "$base..HEAD"))
    Section "TOUCHED FILES (git diff --stat)" (Invoke-Git @("diff", "--stat", "$base..HEAD"))
    # The code diff, bounded, without tests, lockfiles and generated files: the reviewer reads the
    # code, not only the report's description of it. The rest: git diff.
    $excluded = @(":(exclude)Cargo.lock", ":(exclude)**/Cargo.lock", ":(exclude)**/package-lock.json", ":(exclude)**/yarn.lock",
                  ":(exclude)**/pnpm-lock.yaml", ":(exclude)**/poetry.lock", ":(exclude)**/tests/**", ":(exclude)tests/golden/**",
                  ":(exclude)docs/journal/**", ":(exclude)pipeline/**")
    $diff = Invoke-Git (@("diff", "--no-color", "-U2", "$base..HEAD", "--", ".") + $excluded)
    $dl = @($diff -split "`r?`n")
    $max = [int]$Cfg["DIFF_MAX_LINES"]
    if ($dl.Count -gt $max) { $diff = (($dl | Select-Object -First $max) -join "`n") + "`n[... $($dl.Count - $max) more lines: git diff $base..HEAD -- <path>]" }
    if ($diff) { Section "CODE DIFF (without tests, $max lines at most)" $diff }
}
# What the HARNESS checked after the coder. A KO here weighs more than the report.
$gate = Join-Path $Pipe "gate.md"
if ((Test-Path $gate) -and $reportText) { Section "VERIFICATION GATE (run by the harness, not declared by the coder)" (Read-Utf8 $gate) }

# Verdicts of the benchmarks started in the background after the previous gates.
$benchBg = Join-Path $Pipe "bench.md"
if (Test-Path $benchBg) { Section "BACKGROUND BENCHMARKS (previous tasks: not a gate KO)" (Read-Utf8 $benchBg) }
# Load test on new seeds started after the previous gates. A KO = a task.
$loadBg = Join-Path $Pipe "load.md"
if (Test-Path $loadBg) { Section "LOAD TEST ON NEW SEEDS (previous tasks: not a gate KO; a KO seed becomes a task and a test)" (Read-Utf8 $loadBg) }
# Several duos (docs/HARNESS.md, Lanes): the lane given by the orchestrator bounds the choice of the task.
if ($Cfg["DUO"]) {
    $lane = ("" + (Read-Utf8 (Join-Path $Pipe "lane.txt"))).Trim()
    $milestoneL = [regex]::Match((Read-Utf8 $Plan), '(?im)^\s*MILESTONE\s*:\s*(M\d+[a-z]?)').Groups[1].Value
    $laneState = (& python (Join-Path $Root "tools\lanes.py") --milestone $milestoneL --ref main 2>&1 | Out-String).Trim()
    $l1 = ($lane -split "`r?`n")[0].Trim()
    if (-not $l1) { $order = "No lane ready for you: write TASK: NONE (the orchestrator will wake you up)." }
    elseif ($l1 -eq "*") { $order = "The whole backlog: its lanes must be fixed (errors below). Your next task has the coder label the backlog (**Lane** and **Zones**; a closed entry carries a closed sign (U+2705)) until 0 errors; the other duo waits." }
    elseif ($l1 -eq "end") { $order = "Lane END: the task 'End of $milestoneL' (machine idle: the other duo is stopped)." }
    elseif ($l1 -eq "single") { $order = "The backlog of $milestoneL is not split into lanes yet: one duo runs. Your NEXT task has the coder label it (each OPEN entry: **Lane** and **Zones**; a closed entry carries a closed sign (U+2705) in its title) until ``python tools/lanes.py --milestone $milestoneL`` reports 0 errors with at least two ready lanes: the other duo then starts on its own. Then choose in your lane." }
    else { $order = "Your lane: **$l1**. Choose ONLY entries of this lane (a ready one, in backlog order). None ready: TASK: NONE." }
    Section "YOUR LANE (duo $($Cfg['DUO']), docs/HARNESS.md Lanes)" ("YOUR LANE: $(if ($l1) { $l1 } else { '-' })`n$order`n`n``````text`n$laneState`n``````")
}
# A merge solved by the mediator is re-read at the next pass (a fix is asked as a task).
$mediation = Join-Path $Pipe "mediation.md"
if (Test-Path $mediation) { Section "MEDIATOR RESOLUTION (previous merge: check it keeps the work of both sides; otherwise, a fix task)" (Read-Utf8 $mediation) }

# Proof images cited in the report -> thumbnails (<= 1280 px, JPEG) to read.
$images = @()
foreach ($m in [regex]::Matches($reportText, '[A-Za-z0-9_./\\:-]+\.(?:png|jpe?g)')) {
    $c = $m.Value
    $abs = if ([IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $Root $c }
    if ((Test-Path -LiteralPath $abs) -and ($images -notcontains $abs)) { $images += $abs }
}
if ($images.Count) {
    $dv = Join-Path $State "thumbs\$tag"
    $lines = @()
    $out = (& python (Join-Path $Root "tools\image\vignette.py") --out $dv @images 2>&1 | Out-String)
    foreach ($l in ($out -split "`r?`n")) { if ($l -match '^THUMB (.+) -> (.+)$') { $lines += "- $($Matches[1]) -> read: $($Matches[2])" } }
    if (-not $lines.Count) { $lines = $images | ForEach-Object { "- $_" } }
    Section "PROOF IMAGES (read the THUMBNAILS; the original only for a detail, via tools/image/loupe.ps1)" ($lines -join "`n")
}

# The blind art judge: a separate call that sees only captures and references, so nothing in the
# task or the report can talk it into seeing what is not there.
$judgeVerdict = ""
if ($taskText -and $reportText) {
    $judgeCand = @($Cfg["REVIEWER_ESCALATION"], $Cfg["REVIEWER_MODEL"]) | Where-Object { $_ } | Select-Object -Unique
    $judge = Invoke-BlindJudge $taskText $reportText $tag $judgeCand $Cfg["REVIEWER_EFFORT_VISUAL"]
    $judgeVerdict = $judge.Verdict
    if ($judgeVerdict) {
        Section "BLIND ART JUDGE: $judgeVerdict (separate call: it saw ONLY the captures and their references)" ($judge.Section +
            "`n`nRule: the blind judge is an OPINION, not a veto (make it exist first). NO = its gaps go to the owner's " +
            "polish list, not a rejection by themselves. NOT JUDGED = the next task adds the missing '- art-judge: <capture> | <reference>' line. " +
            "A gap that the loupe (tools/image/loupe.ps1) shows WRONG (the detail is on the " +
            "capture): write in review.md one line 'BLIND-JUDGE CONTESTED: gap <n>, <loupe evidence>' per contested gap. " +
            "The owner is told of every contest.")
    }
}

# PLAN and STATE in full: you do not have to re-read them with a tool.
if (Test-Path $Plan) { Section "docs/PLAN.md (in full)" (Read-Utf8 $Plan) }
# The shared state (duo A or solo) then one part per duo, each in its own file.
foreach ($sf in @(Get-ChildItem (Join-Path $Root "docs") -Filter "STATE*.md" -ErrorAction SilentlyContinue | Sort-Object Name)) {
    Section "docs/$($sf.Name) (in full)" (Read-Utf8 $sf.FullName)
}
$qDoc = Join-Path $Root "docs\QUESTIONS.md"
if (Test-Path $qDoc) { Section "docs/QUESTIONS.md (open questions)" (Read-Utf8 $qDoc) }
# The owner's taste: their agreements and refusals, in their words. Judge like them.
$taste = Join-Path $Root "docs\TASTE.md"
if (Test-Path $taste) { Section "docs/TASTE.md (the owner's taste: judge and choose like them)" (Read-Utf8 $taste) }

# THE CURRENT MILESTONE (line "MILESTONE: Mn" of docs/PLAN.md): its acceptance in the roadmap and
# its backlog in full. The full roadmap and the ADRs stay to be read with a tool, where they matter.
$milestone = ""; $backlogMissing = $false; $ownerChanged = $false
$mj = [regex]::Match((Read-Utf8 $Plan), '(?im)^\s*MILESTONE\s*:\s*(M\d+[a-z]?)\b')
# "M" upper-cased, a sub-milestone letter kept as written ("M5a"): the roadmap regex is case-sensitive.
if ($mj.Success) { $milestone = "M" + $mj.Groups[1].Value.Substring(1) }
if ($milestone) {
    $roadmap = Read-Utf8 (Join-Path $Root "docs\ROADMAP.md")
    $ms = [regex]::Match($roadmap, "(?ms)^## $milestone\b.*?(?=^## |^---|\z)")
    if ($ms.Success) { Section "docs/ROADMAP.md - section $milestone (current milestone)" $ms.Value.Trim() }
    $bl = @(Get-ChildItem (Join-Path $Root "docs\backlog") -Filter "$milestone-*.md" -ErrorAction SilentlyContinue)
    if ($bl.Count) { foreach ($b in $bl) { Section "docs/backlog/$($b.Name) (backlog of the current milestone, in full)" (Read-Utf8 $b.FullName) } }
    else { $backlogMissing = $true; Section "BACKLOG $milestone MISSING: WRITE THE BACKLOG FIRST" "No docs/backlog/$milestone-*.md: the next task prepares it (architect role, docs/WORKFLOW.md)." }
} else {
    Section "CURRENT MILESTONE UNKNOWN" "docs/PLAN.md has no 'MILESTONE: Mn' line: write the question in docs/QUESTIONS.md."
}

# WHAT CHANGED SINCE YOUR LAST PASS: never "already read".
$old = @{}
if (Test-Path $HashFile) { foreach ($l in (Get-Content $HashFile)) { $kv = $l -split "\s+", 2; if ($kv.Count -eq 2) { $old[$kv[0]] = $kv[1] } } }
foreach ($f in @($Plan, $OwnerBox)) {
    $name = Split-Path $f -Leaf
    $h = Get-Fingerprint $f
    if ($old[$name] -eq $h) { continue }
    $sn = Join-Path $Snap $name
    if ((Test-Path $sn) -and (Test-Path $f)) { $d = Invoke-Git @("diff", "--no-index", "--no-color", "-U3", $sn, $f) }
    elseif (Test-Path $f) { $d = "(first reading)`n" + (Read-Utf8 $f) }
    else { $d = "(file deleted)" }
    $ownerChanged = $true
    Section "READ IN FULL - $name CHANGED SINCE YOUR LAST PASS" ("An answer or a decision of the owner wins over any pause.`n" + $d)
}

# Circuit breaker: too many rejections in a row on the same branch.
$judgedBranch = Get-Branch
$nRej = Get-Rejections $judgedBranch
if ($judgedBranch -like "task/*" -and $nRej -ge [int]$Cfg["REJECT_MAX"]) {
    Section "CIRCUIT BREAKER: $nRej REJECTIONS IN A ROW ON $judgedBranch" ("Judge the fix normally. If you reject it AGAIN, do NOT write one more fix: " +
        "write the question in docs/QUESTIONS.md (what blocks, options, a default that does not stop the duo) and choose ANOTHER task " +
        "(work queue, section 4). The harness then sets the branch aside (kept, not merged) and starts again from main.")
}
$milestoneBefore = Get-Milestone

# --- 2. Model: default; escalation ONLY for visual proofs -----------------------------------
# Visual = the "- images:" line of PROOFS asks for an image (not "none"), or the report cites one
# that exists, or the blind judge ran. A looser regex (any "image" after "PROOFS:", even in
# "images: none") once escalated 19 passes out of 21.
$imagesLine = [regex]::Match($taskText, '(?im)^\s*-\s*images?\s*:\s*(.*)$')
$asksImages = $imagesLine.Success -and ($imagesLine.Groups[1].Value -notmatch '^\s*none')
$visual = $asksImages -or ($images.Count -gt 0) -or [bool]$judgeVerdict
$rejected = (Test-Path $ReviewFile) -and ((Get-Content $ReviewFile -TotalCount 1 -Encoding UTF8) -match "VERDICT:\s*REJECT")
# Planning (backlog to write, milestone end, impossible task, owner decision) is only logged:
# it stays on the default model.
$milestoneEnd = $taskText -match '(?im)^TASK:[^\[\r\n]*\[\s*end of (M\d+|milestone)\b'
$impossible = $reportText -match '(?im)^\s*STATUS\s*:\s*IMPOSSIBLE'
$planning = $backlogMissing -or $milestoneEnd -or $impossible -or $ownerChanged
if ($visual) {
    $preferred = $Cfg["REVIEWER_ESCALATION"]; $effort = $Cfg["REVIEWER_EFFORT_VISUAL"]
    Note "reviewer : escalation (visual proofs$(if ($rejected) { ', after a rejection' })) -> $preferred / $effort"
} else {
    $preferred = $Cfg["REVIEWER_MODEL"]; $effort = $Cfg["REVIEWER_EFFORT"]
    if ($planning) { Note "reviewer : planning pass (default model)" }
}
$candidates = @($preferred, $Cfg["REVIEWER_MODEL"], $Cfg["REVIEWER_ESCALATION"]) | Where-Object { $_ } | Select-Object -Unique

$prompt = (Read-Utf8 (Join-Path $PSScriptRoot "prompts\reviewer.md")) + $P.ToString()
$prompt += "`n`n---`nPass number $n : the task you write carries the number $n. Date: " + (Get-Date -Format "yyyy-MM-dd HH:mm") + "."

$allowed = @("Read", "Glob", "Grep",
    "Bash(git log:*)", "Bash(git diff:*)", "Bash(git show:*)", "Bash(git status:*)",
    "Bash(git tag -l:*)", "Bash(git tag --list:*)", "Bash(git rev-parse:*)", "Bash(git ls-files:*)", "Bash(ls:*)",
    "PowerShell(git log:*)", "PowerShell(git diff:*)", "PowerShell(git show:*)", "PowerShell(Get-ChildItem:*)",
    "Write(pipeline/**)", "Edit(pipeline/**)",
    "Write(docs/QUESTIONS.md)", "Edit(docs/QUESTIONS.md)",
    "Edit(docs/PLAN.md)")   # the MILESTONE line only (continuous development)
# The owner's shared page belongs to duo A (or the single duo); every other duo has ITS own part:
# two duos never write the same file.
$duo = ("" + $Cfg["DUO"]).Trim()
$pages = if (-not $duo -or $duo -eq "A") { @("OWNER.md", "OWNER-A.md") } else { @("OWNER-$duo.md") }
foreach ($pg in $pages) { $allowed += @("Write(docs/$pg)", "Edit(docs/$pg)") }

# --- 3. The pass ------------------------------------------------------------------------------
$ok = $false
for ($try = 1; $try -le 4; $try++) {
    $m = Select-Model $candidates
    if (-not $m) {
        $when = Get-QuotaReopen $candidates
        Note "reviewer : quota closed on $($candidates -join ', ') (estimated reopening $when)"
        Set-QuotaWait $candidates
        exit 5
    }
    $others = @($candidates | Where-Object { $_ -ne $m -and -not (Test-QuotaBlocked $_) })
    $a = @("-p", "--output-format", "stream-json", "--verbose", "--model", $m, "--effort", $effort,
           "--permission-mode", "dontAsk", "--strict-mcp-config", "--disable-slash-commands",
           "--tools", "Read,Glob,Grep,Bash,Write,Edit")
    if ($Cfg["REVIEWER_SETTING_SOURCES"]) { $a += @("--setting-sources", $Cfg["REVIEWER_SETTING_SOURCES"]) }
    if ($others.Count) { $a += @("--fallback-model", ($others -join ",")) }
    $a += "--allowedTools"; $a += $allowed
    $log = New-LogPath "reviewer-$tag"
    Note "reviewer : pass $n, try $try ($m, effort $effort)"
    $raw = Invoke-Claude -Prompt $prompt -Arguments $a -LogPath $log
    $j = Read-Result $raw
    $c = Get-FailureClass $j $raw
    if ($c -eq "ok") { $ok = $true; break }
    if ($c -eq "auth") { Note "reviewer : FATAL ERROR (login/key) - 'claude /login'"; exit 3 }
    if ($c -eq "quota") { Set-QuotaBlocked $m (Get-FailureText $j $raw); continue }
    $s = Get-Backoff $try
    Note "reviewer : API error (log $(Split-Path $log -Leaf)) - new try in $s s"
    Start-Sleep -Seconds $s
}
if (-not $ok) { Note "reviewer : failed after 4 tries"; exit 2 }
if (-not (Test-Path $TaskFile)) { Note "reviewer : pipeline/task.md not written"; exit 2 }

# --- 4. The pass counts: number, history, fingerprints -----------------------------------------
Write-Utf8 $nFile "$n"
if (Test-Path $ReviewFile) { Copy-Item $ReviewFile (Join-Path $Hist "$tag-review.md") -Force }
if (Test-Path $benchBg) { Move-Item $benchBg (Join-Path $Hist "$tag-bench.md") -Force }   # read: archived
if (Test-Path $loadBg) { Move-Item $loadBg (Join-Path $Hist "$tag-load.md") -Force }   # read: archived
if (Test-Path $mediation) { Move-Item $mediation (Join-Path $Hist "$tag-mediation.md") -Force }   # read: archived
$judgeFile = Join-Path $Pipe "blind-judge.md"
if (Test-Path $judgeFile) { Move-Item $judgeFile (Join-Path $Hist "$tag-blind-judge.md") -Force }   # read: archived
Copy-Item $TaskFile (Join-Path $Hist "$tag-task.md") -Force
$first = (Get-Content $TaskFile -TotalCount 1 -Encoding UTF8)
Note "reviewer : $first"
$none = $first -match "TASK:\s*NONE"

# --- 5. Branches: merge after ACCEPT, a new branch for a new task ---------------------------------
$verdict = ""
if (Test-Path $ReviewFile) { $verdict = "" + (Get-Content $ReviewFile -TotalCount 1 -Encoding UTF8) }
$branch = Get-Branch
# One measurable line per pass (loop dashboard, tools/costs/loop.py).
$verdictWord = [regex]::Match($verdict, 'VERDICT:\s*(\w+)').Groups[1].Value
$gateKo = if (Test-Path $gate) { [regex]::Match((Read-Utf8 $gate), 'TOTAL:\s*(\d+) KO').Groups[1].Value } else { "" }
if ($verdictWord) { Note "reviewer : verdict $verdictWord on $branch (gate : $(if ($gateKo) { $gateKo } else { '?' }) KO)" }
# The blind judge is an opinion: an ACCEPT against it stays a journal line, without a notification.
if ($judgeVerdict -and $judgeVerdict -ne "YES" -and $verdictWord -eq "ACCEPT") {
    Note "reviewer : ACCEPT, blind judge $judgeVerdict (an opinion: gaps go to the polish list)"
}
if ($branch -like "task/*" -and $verdict -match "VERDICT:\s*ACCEPT") {
    if (-not (Merge-Task $branch)) {
        Note "reviewer : MERGE BLOCKED - a human must look (git status)"
        Send-Ntfy "merge blocked" "Branch $branch does not merge into main (conflict or dirty file). The duo is stopped." "high"
        exit 3
    }
    Set-Rejections $branch 0
} elseif ($branch -like "task/*" -and $verdict -match "VERDICT:\s*REJECT") {
    $nr = (Get-Rejections $branch) + 1
    if ($nr -gt [int]$Cfg["REJECT_MAX"]) {
        if (-not (Set-AsideTask $branch)) { Send-Ntfy "stopped" "Cannot set $branch aside (dirty tree)." "high"; exit 3 }
        Set-Rejections $branch 0
        Send-Ntfy "task set aside" "$branch rejected $nr times: kept for you, not merged. Question in docs/QUESTIONS.md; the duo goes on with something else."
    } else {
        Set-Rejections $branch $nr
        if ($nr -eq [int]$Cfg["REJECT_MAX"]) { Send-Ntfy "$nr rejections in a row" "$branch : $nr rejections. At the next one, the task is set aside and a question is asked." }
    }
}
$milestoneAfter = Get-Milestone
if ($milestoneBefore -and $milestoneAfter -and $milestoneAfter -ne $milestoneBefore) {
    Send-Ntfy "$milestoneBefore finished" "Milestone $milestoneBefore is done, build ready for your playtest (docs/OWNER.md). The duo goes on with $milestoneAfter."
}
if (-not $none -and (Get-Branch) -in @("main", "HEAD")) {
    if (-not (New-TaskBranch (Get-BranchName $tag $first))) { exit 3 }
}
# Several duos: a duo without a task does not hold main (the other could no longer merge).
if ($none -and $Cfg["DUO"] -and (Get-Branch) -eq "main") {
    Invoke-GitQuiet @("switch", "-q", "--detach") | Out-Null
    Note "harness : duo $($Cfg['DUO']) has no task: detached from main"
}

$lines = @(); $written = @{}
foreach ($f in @($Plan, $OwnerBox)) {
    $name = Split-Path $f -Leaf
    $lines += "$name $(Get-Fingerprint $f)"; $written[$name] = $true
    if (Test-Path $f) { Copy-Item $f (Join-Path $Snap $name) -Force }
}
# EVERY fingerprint of the idle watch (Get-IdleFingerprints), otherwise the watch believes in a
# change and runs the reviewer again forever (seen with two duos: lane.txt).
$fp = Get-IdleFingerprints
foreach ($k in $fp.Keys) { if (-not $written[$k]) { $lines += "$k $($fp[$k])" } }
Write-Utf8 $HashFile (($lines -join "`r`n") + "`r`n")

if ($none) { exit 10 }

# The new task starts from the current state: it is the base of the next diff.
Write-Utf8 (Join-Path $Pipe "base.txt") (Get-Head)
Remove-Item $ReportFile -Force -ErrorAction SilentlyContinue
Remove-Item $gate -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Pipe ".in_progress") -Force -ErrorAction SilentlyContinue
exit 0
