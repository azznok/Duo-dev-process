# RESUME AFTER A "MERGE BLOCKED" (see docs/INTERVENTIONS.md).
# When run-reviewer wrote VERDICT: ACCEPT and the next task, but Merge-Task failed (dirty file,
# line endings, conflict solved by hand), this script redoes EXACTLY the end of run-reviewer.ps1
# with its functions: merge, rejections reset, new branch, fingerprints, diff base, cleanup.
#   powershell -File bin\harness\resume-merge.ps1 -Branch task/162
# Then relaunch the duo (the orchestrator does it). The duo must be STOPPED.
# Also called by mediator.ps1 after it solved a conflict.
param([Parameter(Mandatory = $true)][string]$Branch)
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\branches.ps1")
. (Join-Path $PSScriptRoot "lib\autonomy.ps1")
$TaskFile = Join-Path $Pipe "task.md"; $Snap = Join-Path $Pipe ".snapshots"
$Plan = Join-Path $Root "docs\PLAN.md"; $OwnerBox = Join-Path $Pipe "owner.md"
$HashFile = Join-Path $Pipe ".hashes"
if (-not (Test-Path $Snap)) { New-Item -ItemType Directory -Force $Snap | Out-Null }
$tag = "{0:D3}" -f [int]((Get-Content (Join-Path $Pipe ".n") -Raw).Trim())
$first = (Get-Content $TaskFile -TotalCount 1 -Encoding UTF8)
if ((Get-Branch) -ne "main") { Write-Host "not on main ($(Get-Branch)): nothing done"; exit 1 }
if (@(git -C $Root status --porcelain --untracked-files=no).Count) { Write-Host "dirty tree: nothing done"; git -C $Root status --short; exit 1 }
if (-not (Merge-Task $Branch)) { Write-Host "merge still impossible"; exit 1 }
Set-Rejections $Branch 0
if (-not ($first -match "TASK:\s*NONE")) {
    if (-not (New-TaskBranch (Get-BranchName $tag $first))) { exit 1 }
}
$lines = @(); $written = @{}
foreach ($f in @($Plan, $OwnerBox)) {
    $name = Split-Path $f -Leaf
    $lines += "$name $(Get-Fingerprint $f)"; $written[$name] = $true
    if (Test-Path $f) { Copy-Item $f (Join-Path $Snap $name) -Force }
}
# Every fingerprint of the idle watch, like run-reviewer (else the watch wakes up forever).
$fp = Get-IdleFingerprints
foreach ($k in $fp.Keys) { if (-not $written[$k]) { $lines += "$k $($fp[$k])" } }
Write-Utf8 $HashFile (($lines -join "`r`n") + "`r`n")
Write-Utf8 (Join-Path $Pipe "base.txt") (Get-Head)
Remove-Item (Join-Path $Pipe "report.md") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Pipe "gate.md") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Pipe ".in_progress") -Force -ErrorAction SilentlyContinue
Note "harness : manual resume after a blocked merge of $Branch ; branch $(Get-Branch) ready for task $tag"
Write-Host "ok : $(Get-Branch), base $(Get-Head)"
