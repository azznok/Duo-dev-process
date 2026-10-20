# CLAUDE CALLS - dot-sourced BY lib\common.ps1 (never directly; split out to keep files short).
# Uses $Cfg, $State, Note, Write-Utf8/Add-Utf8/Read-Utf8, Set-Utf8 from common.ps1.
#   Resolve-ClaudeCli, Invoke-Claude, Read-Result
#   Get-FailureClass  : ok | quota | auth | api  (the ONE place that classifies failures)
#   Get-FailureText, Get-Backoff
#   Quota memory      : Get-QuotaReset, Get-Quotas, Set-/Test-QuotaBlocked, Select-Model,
#                       Get-QuotaReopen, Set-/Get-QuotaWait

# --- Claude CLI ------------------------------------------------------------------
function Resolve-ClaudeCli {
    # Never depend on PATH (truncated depending on the parent shell). The .cmd before the .ps1:
    # the .ps1 depends on the execution policy.
    if ($Cfg["CLAUDE_CLI"]) { return $Cfg["CLAUDE_CLI"] }
    $cands = @()
    foreach ($r in @($env:APPDATA, (Join-Path $env:USERPROFILE "AppData\Roaming"))) {
        if ($r) { $cands += @((Join-Path $r "npm\claude.cmd"), (Join-Path $r "npm\claude")) }
    }
    $cands += @((Join-Path $env:USERPROFILE ".local\bin\claude.exe"),
                (Join-Path $env:LOCALAPPDATA "Programs\claude\claude.exe"),
                (Join-Path $env:ProgramFiles "nodejs\claude.cmd"))
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c -ErrorAction SilentlyContinue)) { return $c } }
    $g = Get-Command claude -ErrorAction SilentlyContinue
    if ($g -and $g.Source) { return $g.Source }
    return ""
}

function Invoke-Claude {
    # Prompt through STDIN (a Windows command line cannot carry a long prompt), output
    # captured then written as UTF-8 in logs/ (never Tee-Object: UTF-16 in 5.1).
    param([string]$Prompt, [string[]]$Arguments, [string]$LogPath)
    Set-Utf8
    $exe = Resolve-ClaudeCli
    if (-not $exe) { return "HARNESS: claude CLI not found (config CLAUDE_CLI)" }
    $ErrorActionPreference = "Continue"
    # Log created BEFORE the call: a call that dies still leaves a trace.
    $header = "HARNESS: call started $(Get-Date -Format s) ; no type=result line below = call interrupted, cost unknown`r`n"
    Write-Utf8 $LogPath $header
    # stream-json: each event is written AS SOON AS it arrives. A call that dies keeps its whole
    # log; .state/progress.txt names the last tool called (health, supervisor).
    $sb = New-Object System.Text.StringBuilder
    $progress = Join-Path $State "progress.txt"
    $Prompt | & $exe @Arguments 2>&1 | ForEach-Object {
        $l = "" + $_
        [void]$sb.AppendLine($l)
        Add-Utf8 $LogPath ($l + "`r`n")
        $m = [regex]::Match($l, '"type":"tool_use","id":"[^"]*","name":"([^"]+)"')
        if ($m.Success) {
            try { Write-Utf8 $progress ("{0} {1} {2}" -f (Get-Date -Format s), (Split-Path $LogPath -Leaf), $m.Groups[1].Value) } catch {}
        }
    }
    return $sb.ToString()
}

function Read-Result([string]$Raw) {
    # The final result: in stream-json, the {"type":"result",...} line; in (old) json, the only
    # object. An intermediate event (assistant, user) is NEVER the result.
    if (-not $Raw) { return $null }
    $lines = $Raw -split "`r?`n"
    for ($k = $lines.Count - 1; $k -ge 0; $k--) {
        $l = $lines[$k].Trim()
        if (-not $l.StartsWith("{")) { continue }
        try { $j = $l | ConvertFrom-Json } catch { continue }
        if (($j.type -eq "result") -or (-not $j.type -and $j.session_id)) { return $j }
    }
    return $null
}

$AuthPatterns = @("Not logged in", "Please run /login", "OAuth token has expired", "Invalid API key",
                  "authentication_error", "credit balance is too low", "claude CLI not found")
$QuotaPatterns = @("hit your session limit", "hit your usage limit", "out of usage credits",
                   "usage limit reached", "usage limit", "session limit", "rate limit", "rate_limit")

function Get-FailureText($J, [string]$Raw) {
    # stream-json: $Raw = the whole session; only the result and the non-JSON lines are read.
    $nonJson = @(("" + $Raw) -split "`r?`n" | Where-Object { -not $_.TrimStart().StartsWith("{") }) -join "`n"
    if ($J) { return ("" + $J.result) + "`n" + $nonJson }
    return $nonJson
}

function Get-FailureClass($J, [string]$Raw) {
    # ONE PLACE decides what a failure is. auth BEFORE anything: retrying "Not logged in"
    # fails in 80 ms and loops forever (seen: 19 retries x 90 s).
    if ($J -and -not $J.is_error -and $J.subtype -eq "success") { return "ok" }
    $text = Get-FailureText $J $Raw
    foreach ($m in $AuthPatterns) { if ($text -like "*$m*") { return "auth" } }
    if ($J -and $J.api_error_status -eq 429) { return "quota" }
    foreach ($m in $QuotaPatterns) { if ($text -like "*$m*") { return "quota" } }
    return "api"
}

function Get-Backoff([int]$Try) {
    # Exponential backoff for API errors: 60, 120, 240, 480, then 900 s.
    return [int][Math]::Min(900, 60 * [Math]::Pow(2, [Math]::Max(0, $Try - 1)))
}

# --- Quota memory --------------------------------------------------------------------
# A model is recorded as closed until a given time, and the WHOLE harness (coder, reviewer)
# moves to the next model of its chain instead of rediscovering the limit on every call.
# The time: the reset announced by the message if any, else QUOTA_PROBE_MIN later (the next
# call is the probe). A fixed 5 h memory counted from the discovery, not from the reset:
# up to ~4 h lost.
$QuotaFile = Join-Path $State "quota.txt"   # lines "<model> <yyyy-MM-ddTHH:mm:ss>"

function Get-QuotaReset([string]$Text, [datetime]$Now = (Get-Date)) {
    # "...limit reached|1759600800" (epoch); "resets 3pm", "resets 4:30pm (Europe/Paris)",
    # "resets Oct 7, 3pm" (weekly). Time read in the machine's time zone. $null otherwise.
    $m = [regex]::Match($Text, '\|(\d{10})\b')
    if ($m.Success) {
        $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$m.Groups[1].Value).LocalDateTime
        if ($t -gt $Now.AddMinutes(-5) -and $t -lt $Now.AddDays(8)) { return $t }
    }
    $m = [regex]::Match($Text, '(?i)resets?\s+(?:at\s+)?(?:([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(?:at\s+)?)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b')
    if (-not $m.Success) { return $null }
    $h = [int]$m.Groups[3].Value; $mi = if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { 0 }
    $ap = $m.Groups[5].Value.ToLower()
    if ($ap -eq "pm" -and $h -lt 12) { $h += 12 }
    if ($ap -eq "am" -and $h -eq 12) { $h = 0 }
    if (-not $ap -and -not $m.Groups[4].Success) { return $null }   # "resets 3": too vague
    if ($h -gt 23 -or $mi -gt 59) { return $null }
    $day = $Now.Date
    if ($m.Groups[1].Success) {
        $month = [array]::IndexOf(@("jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"), $m.Groups[1].Value.ToLower()) + 1
        if ($month -lt 1) { return $null }
        try { $day = Get-Date -Year $Now.Year -Month $month -Day ([int]$m.Groups[2].Value) -Hour 0 -Minute 0 -Second 0 -Millisecond 0 } catch { return $null }
        if ($day -lt $Now.Date.AddDays(-1)) { $day = $day.AddYears(1) }
    }
    $t = $day.AddHours($h).AddMinutes($mi)
    if (-not $m.Groups[1].Success -and $t -le $Now) { $t = $t.AddDays(1) }
    if ($t -lt $Now.AddMinutes(-5) -or $t -gt $Now.AddDays(8)) { return $null }
    return $t
}

function Get-Quotas {
    $h = @{}
    if (Test-Path $QuotaFile) {
        foreach ($l in (Get-Content $QuotaFile)) {
            $p = $l.Trim() -split "\s+"
            if ($p.Count -ge 2) { try { $h[$p[0]] = [datetime]::Parse($p[1]) } catch {} }
        }
    }
    return $h
}
function Set-QuotaBlocked([string]$Model, [string]$Text = "") {
    $h = Get-Quotas
    $reset = Get-QuotaReset $Text
    if ($reset) {
        $h[$Model] = $reset.AddMinutes([double]$Cfg["QUOTA_MARGIN_MIN"]); $source = "announced reset"
    } else {
        $h[$Model] = (Get-Date).AddMinutes([double]$Cfg["QUOTA_PROBE_MIN"]); $source = "new try"
    }
    $lines = foreach ($k in $h.Keys) { "{0} {1}" -f $k, $h[$k].ToString("s") }
    Write-Utf8 $QuotaFile (($lines -join "`r`n") + "`r`n")
    Note "quota : $Model closed until $($h[$Model].ToString('dd/MM HH:mm')) ($source)"
}
function Test-QuotaBlocked([string]$Model) {
    $h = Get-Quotas
    return ($h.ContainsKey($Model) -and $h[$Model] -gt (Get-Date))
}
function Select-Model([string[]]$Candidates) {
    # The first candidate whose quota is not recorded as closed; $null if all are.
    foreach ($m in $Candidates) { if ($m -and -not (Test-QuotaBlocked $m)) { return $m } }
    return $null
}
function Get-QuotaReopen([string[]]$Candidates) {
    $h = Get-Quotas; $min = $null
    foreach ($m in $Candidates) { if ($h.ContainsKey($m) -and (($null -eq $min) -or $h[$m] -lt $min)) { $min = $h[$m] } }
    return $min
}
# Exit code 5: the role records ITS model chain; the duo loop sleeps until the first reopening.
$QuotaWaitFile = Join-Path $State "quota-wait.txt"
function Set-QuotaWait([string[]]$Models) { Write-Utf8 $QuotaWaitFile ($Models -join " ") }
function Get-QuotaWait {
    if (-not (Test-Path $QuotaWaitFile)) { return @() }
    return @(((Read-Utf8 $QuotaWaitFile).Trim() -split "\s+") | Where-Object { $_ })
}
