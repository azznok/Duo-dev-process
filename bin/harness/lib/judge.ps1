# BLIND ART JUDGE: a SEPARATE `claude -p` call, before the reviewer.
# It receives ONLY the images: each capture and its reference, named by the task
# ("- art-judge: <capture> | <reference>" lines of PROOFS). No task, no report, no code:
# nothing steers it. Its only instruction: list every difference (prompts/blind-judge.md).
# The reviewer gets its output in the packet; a NO = REJECT (the reviewer may contest a gap
# with loupe evidence: "BLIND-JUDGE CONTESTED: gap <n>, <evidence>").
# Why blind: a judge that reads the report is talked into seeing what the coder claims.

function Get-JudgePairs([string]$TaskText) {
    # "- art-judge: proofs/280/seat.png | docs/art/refs/seat.png" (backticks tolerated)
    $pairs = @()
    foreach ($m in [regex]::Matches($TaskText, '(?im)^\s*-\s*art-judge\s*:\s*`?([^`|\s]+)`?\s*\|\s*`?([^`|\s]+)`?')) {
        $pairs += , @($m.Groups[1].Value, $m.Groups[2].Value)
    }
    return , $pairs
}

function Get-JudgeVerdict([string]$Text) {
    # The last "BLIND-JUDGE: YES|NO" line wins; absent = NOT JUDGED.
    $ms = [regex]::Matches($Text, '(?im)^\s*\**BLIND-JUDGE\s*:\s*(YES|NO)\b')
    if ($ms.Count) { return $ms[$ms.Count - 1].Groups[1].Value.ToUpper() }
    return "NOT JUDGED"
}

# Returns @{ Section = <text for the reviewer's packet> ; Verdict = YES | NO | NOT JUDGED | "" (nothing to judge) }
function Invoke-BlindJudge([string]$TaskText, [string]$ReportText, [string]$Tag, [string[]]$Candidates, [string]$Effort) {
    $pairs = Get-JudgePairs $TaskText
    $citesRef = $TaskText -match 'docs/art/refs/[^\s`|]+\.(png|jpe?g)'
    $hasImages = $ReportText -match '\.(png|jpe?g)'
    if (-not $pairs.Count) {
        if ($citesRef -and $hasImages) {
            # A task that cites a reference but forgets the art-judge lines would otherwise be
            # judged by nobody: block the ACCEPT until the fix task carries them.
            return @{ Verdict = "NOT JUDGED"; Section = ("The task cites a reference (docs/art/refs) but has NO ``- art-judge: <capture> | <reference>`` line " +
                "in PROOFS: the blind judge could not run. NOT JUDGED: no ACCEPT on this pass; " +
                "your fix task carries the art-judge lines (one per element: the capture the coder produces and ITS reference).") }
        }
        return @{ Verdict = ""; Section = "" }
    }
    $r = Invoke-JudgePairs $pairs $Tag $Candidates $Effort
    Write-Utf8 (Join-Path $Pipe "blind-judge.md") $r.Text
    Note "blind judge : $($r.Verdict)"
    return @{ Verdict = $r.Verdict; Section = $r.Text }
}

# The core, shared with the coder's self-check (self-judge.ps1): thumbnails outside the repo,
# a call that sees only them. Returns @{ Verdict = YES | NO | NOT JUDGED ; Text = judge output }.
function Invoke-JudgePairs($pairs, [string]$Tag, [string[]]$Candidates, [string]$Effort) {
    # Thumbnails: capture and reference, the same size (<= 1280 px), in a folder OUTSIDE the repo:
    # the judge runs there (cwd), and in dontAsk mode it can read nothing else (no task, no
    # report, no code).
    $project = ("" + $Cfg["PROJECT"]).Trim(); if (-not $project) { $project = "project" }
    $dv = Join-Path $env:TEMP "$project-judge-$Tag"
    Remove-Item $dv -Recurse -Force -ErrorAction SilentlyContinue
    $lines = @(); $missing = @(); $k = 0
    foreach ($p in $pairs) {
        $k++
        $abs = @()
        foreach ($c in $p) {
            $a = if ([IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $Root $c }
            if (-not (Test-Path -LiteralPath $a)) { $missing += $c }
            $abs += $a
        }
        if ($missing.Count) { continue }
        $out = (& python (Join-Path $Root "tools\image\vignette.py") --out (Join-Path $dv "$k") @abs 2>&1 | Out-String)
        $v = @([regex]::Matches($out, '(?m)^THUMB .+ -> (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
        if ($v.Count -ne 2) { $missing += "thumbnails of pair $k"; continue }
        $lines += "PAIR $k`n- CAPTURE (the product) : $($v[0])`n- REFERENCE (the target) : $($v[1])"
    }
    if ($missing.Count) {
        return @{ Verdict = "NOT JUDGED"; Text = ("Images not found for the blind judge : " + ($missing -join ", ") +
            ". NOT JUDGED : no ACCEPT on this pass.") }
    }
    $prompt = (Read-Utf8 (Join-Path $PSScriptRoot "..\prompts\blind-judge.md")) + "`n`n---`n## THE PAIRS`n`n" + ($lines -join "`n`n")
    $text = ""
    for ($try = 1; $try -le 3; $try++) {
        $m = Select-Model $Candidates
        if (-not $m) { break }
        $a = @("-p", "--output-format", "stream-json", "--verbose", "--model", $m, "--effort", $Effort,
               "--permission-mode", "dontAsk", "--strict-mcp-config", "--disable-slash-commands",
               "--setting-sources", "project", "--tools", "Read", "--allowedTools", "Read")
        $log = New-LogPath "judge-$Tag"
        Note "blind judge : $($pairs.Count) pair(s), try $try ($m, effort $Effort)"
        Push-Location $dv
        try { $raw = Invoke-Claude -Prompt $prompt -Arguments $a -LogPath $log } finally { Pop-Location }
        $j = Read-Result $raw
        $c = Get-FailureClass $j $raw
        if ($c -eq "ok") { $text = "" + $j.result; break }
        if ($c -eq "quota") { Set-QuotaBlocked $m (Get-FailureText $j $raw); continue }
        if ($c -eq "auth") { break }
        Start-Sleep -Seconds (Get-Backoff $try)
    }
    $verdict = Get-JudgeVerdict $text
    if (-not $text) { $text = "(the blind judge did not answer : see logs/*judge-$Tag*)" }
    return @{ Verdict = $verdict; Text = $text }
}
