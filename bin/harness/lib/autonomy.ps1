# DUO AUTONOMY - dot-source it AFTER lib\common.ps1 (uses $Root, $Cfg, $State, Note).
#   Send-Ntfy        : notification on the owner's phone (ntfy), topic = NTFY_TOPIC
#                      (User environment variable, never in a versioned file).
#                      Absent: nothing. "FILE:<path>": appends to that file (harness tests).
#                      The title is prefixed with the PROJECT config value; callers pass the rest.
#   Get-TaskModel    : the task line "MODEL: top|default|mid|small" -> model id.
#   Get-CoderChoice  : tier after rejections, fallback chain and coder effort.
#   Get-Milestone    : the line "MILESTONE: Mn" of docs/PLAN.md.
#   Rejections       : count of rejections in a row on the current task branch (circuit breaker).

function Send-Ntfy([string]$Title, [string]$Message, [string]$Priority = "default") {
    $topic = Get-Secret "NTFY_TOPIC"
    if (-not $topic) { return }
    $project = ("" + $Cfg["PROJECT"]).Trim()
    if ($project) { $Title = "$project : $Title" }
    $text = "$Message`n($(Get-Date -Format 'dd/MM HH:mm'), $project)"
    if ($topic.StartsWith("FILE:")) {
        try { Add-Utf8 $topic.Substring(5) ("[$Priority] $Title | $text`r`n") } catch {}
        return
    }
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
        # ASCII title: an HTTP header does not carry non-ASCII characters reliably.
        $asciiTitle = ($Title.Normalize([Text.NormalizationForm]::FormD) -replace '[^\x20-\x7E]', '')
        Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$topic" -Body $bytes -TimeoutSec 15 `
            -ContentType "text/plain; charset=utf-8" -Headers @{ Title = $asciiTitle; Priority = $Priority } | Out-Null
        Note "ntfy : $Title"
    } catch { Note "ntfy : sending failed ($($_.Exception.Message))" }
}

function Get-TaskModel([string]$TaskText) {
    return (Get-CoderChoice $TaskText 0).Models[0]
}

function Get-CoderChoice([string]$TaskText, [int]$Rejections) {
    # The MODEL line, raised one tier after a rejection, then the fallback chain when a credit
    # runs out. Returns @{ Tier ; Models (in order) ; Effort }.
    #   1 rejection : mid/small -> default ; default -> effort CODER_EFFORT_REJECTED
    #   2 rejections: top
    $m = [regex]::Match($TaskText, '(?im)^\s*MODEL\s*:\s*(top|default|mid|small)\b')
    $tier = if ($m.Success) { $m.Groups[1].Value.ToLower() } else { "default" }
    $effort = $Cfg["CODER_EFFORT"]
    if ($Rejections -ge 2) { $tier = "top" }
    elseif ($Rejections -ge 1) {
        if ($tier -in @("mid", "small")) { $tier = "default" }
        elseif ($tier -eq "default") { $effort = $Cfg["CODER_EFFORT_REJECTED"] }
    }
    $t = $Cfg["MODEL_TOP"]; $d = $Cfg["CODER_MODEL"]; $mi = $Cfg["MODEL_MID"]; $s = $Cfg["MODEL_SMALL"]
    $chain = switch ($tier) {
        "top" { @($t, $d) }
        "mid" { @($mi, $d, $t) }
        "small" { @($s, $mi, $d) }
        default { @($d, $Cfg["CODER_FALLBACK"], $t) }
    }
    return @{ Tier = $tier; Models = @($chain | Where-Object { $_ } | Select-Object -Unique); Effort = $effort }
}

function Get-CoderEffort($Choice, [string]$Model) {
    # A "top" task that runs on another model (top credit exhausted) does it at high effort,
    # never medium: the weaker model needs the extra thinking.
    if ($Choice.Tier -eq "top" -and $Model -ne $Cfg["MODEL_TOP"]) { return $Cfg["CODER_EFFORT_REJECTED"] }
    return $Choice.Effort
}

function Get-Milestone {
    $plan = Join-Path $Root "docs\PLAN.md"
    if (-not (Test-Path $plan)) { return "" }
    $m = [regex]::Match((Read-Utf8 $plan), '(?m)^MILESTONE\s*:\s*(\S+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

# --- Rejection circuit breaker: "<branch> <count>" in .state/rejections.txt --------------
$RejectionsFile = Join-Path $State "rejections.txt"
function Get-Rejections([string]$Branch) {
    if (-not (Test-Path $RejectionsFile)) { return 0 }
    $p = ((Get-Content $RejectionsFile -Raw) + "").Trim() -split "\s+"
    if ($p.Count -eq 2 -and $p[0] -eq $Branch) { return [int]$p[1] }
    return 0
}
function Set-Rejections([string]$Branch, [int]$Count) {
    if ($Count -le 0) { Remove-Item $RejectionsFile -Force -ErrorAction SilentlyContinue; return }
    Write-Utf8 $RejectionsFile "$Branch $Count"
}
