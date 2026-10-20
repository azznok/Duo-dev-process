# TEST OF THE MODELS AND THE QUOTA, without a model nor any cost, in a few seconds.
#   powershell -File bin\harness\test\test-models.ps1     (one OK/KO line per check)
# Checks Get-QuotaReset (reset time read in the message) and Get-CoderChoice (tier, raise after a
# rejection, fallback chain, effort). The library is copied to %TEMP%: nothing is written in this
# repo. Exit code 1 on any KO.
$ErrorActionPreference = "Continue"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-models-" + (Get-Date -Format "yyMMdd-HHmmss"))
New-Item -ItemType Directory -Force (Join-Path $T "bin\harness") | Out-Null
Copy-Item (Join-Path $Source "bin\harness\lib") (Join-Path $T "bin\harness\lib") -Recurse
$env:HARNESS_CODER_MODEL = "o"; $env:HARNESS_CODER_FALLBACK = "t"; $env:HARNESS_MODEL_TOP = "t"
$env:HARNESS_MODEL_MID = "m"; $env:HARNESS_MODEL_SMALL = "s"
$env:HARNESS_CODER_EFFORT = "medium"; $env:HARNESS_CODER_EFFORT_REJECTED = "high"
. (Join-Path $T "bin\harness\lib\common.ps1")
. (Join-Path $T "bin\harness\lib\autonomy.ps1")
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }

# --- Get-QuotaReset ------------------------------------------------------------------------
$t0 = Get-Date -Year 2026 -Month 10 -Day 4 -Hour 13 -Minute 10 -Second 0 -Millisecond 0
$r = Get-QuotaReset "You've hit your session limit - resets 3pm (Europe/Paris)" $t0
L ($r -eq $t0.Date.AddHours(15)) "resets 3pm -> 15:00 the same day ($r)"
$r = Get-QuotaReset "5-hour limit reached - resets 4:30pm" $t0
L ($r -eq $t0.Date.AddHours(16.5)) "resets 4:30pm -> 16:30 ($r)"
$r = Get-QuotaReset "limit reached, resets 9am" $t0
L ($r -eq $t0.Date.AddDays(1).AddHours(9)) "resets 9am already past -> tomorrow 09:00 ($r)"
$r = Get-QuotaReset "Weekly limit reached - resets Oct 7, 3pm" $t0
L ($r -eq (Get-Date -Year 2026 -Month 10 -Day 7 -Hour 15 -Minute 0 -Second 0 -Millisecond 0)) "resets Oct 7, 3pm -> 07/10 15:00 ($r)"
$ep = [DateTimeOffset]::new($t0.AddHours(2)).ToUnixTimeSeconds()
$r = Get-QuotaReset "Claude AI usage limit reached|$ep" $t0
L ($r -eq $t0.AddHours(2)) "epoch format -> +2 h ($r)"
L ($null -eq (Get-QuotaReset "rate_limit_error" $t0)) "no announced reset -> nothing (new try)"
L ($null -eq (Get-QuotaReset "resets 3" $t0)) "vague hour -> nothing"

# --- Get-CoderChoice -----------------------------------------------------------------------
function C([string]$Line, [int]$Rej) { $c = Get-CoderChoice "TASK: 1`r`nMODEL: $Line`r`n" $Rej; return "$($c.Tier) $($c.Models -join '>') $($c.Effort)" }
L ((C "default" 0) -eq "default o>t medium") "default: o then t, effort medium ($(C 'default' 0))"
L ((C "mid" 0) -eq "mid m>o>t medium") "mid: m then o then t ($(C 'mid' 0))"
L ((C "small" 0) -eq "small s>m>o medium") "small: s then m then o ($(C 'small' 0))"
L ((C "top" 0) -eq "top t>o medium") "top: t then o ($(C 'top' 0))"
L ((C "mid" 1) -eq "default o>t medium") "1 rejection: mid -> default ($(C 'mid' 1))"
L ((C "default" 1) -eq "default o>t high") "1 rejection: default -> effort high ($(C 'default' 1))"
L ((C "small" 2) -eq "top t>o medium") "2 rejections: -> top ($(C 'small' 2))"
$ct = Get-CoderChoice "TASK: 1`r`nMODEL: top`r`n" 0
L ((Get-CoderEffort $ct "t") -eq "medium") "top on the top model: the task's effort ($(Get-CoderEffort $ct 't'))"
L ((Get-CoderEffort $ct "o") -eq "high") "top without top credit -> default model at effort high ($(Get-CoderEffort $ct 'o'))"
$cd = Get-CoderChoice "TASK: 1`r`nMODEL: default`r`n" 0
L ((Get-CoderEffort $cd "t") -eq "medium") "default that falls back to t: effort unchanged ($(Get-CoderEffort $cd 't'))"
$none = Get-CoderChoice "TASK: 1`r`n" 0
L ($none.Tier -eq "default") "no MODEL line: default"
L ((Get-TaskModel "MODEL: mid") -eq "m") "Get-TaskModel keeps its contract"

foreach ($k in @("CODER_MODEL", "CODER_FALLBACK", "MODEL_TOP", "MODEL_MID", "MODEL_SMALL", "CODER_EFFORT", "CODER_EFFORT_REJECTED")) { Remove-Item "Env:HARNESS_$k" -ErrorAction SilentlyContinue }
Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("TEST MODELS : {0} checks" -f $n)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
