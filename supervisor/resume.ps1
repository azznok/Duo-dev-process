# RESUME OF A BLOCKED MERGE done by hand: one gesture for the supervisor.
#   powershell -File supervisor\resume.ps1 -Root <duo worktree> -Branch task/<nnn>
# Before: in the worktree, the accepted branch is checked out, `git merge main` done, conflicts
# solved, touched tests green, merge committed. This script: checks, goes to main, replays the end
# of run-reviewer (bin\harness\resume-merge.ps1), checks the duo LEFT main (otherwise the other
# duo can no longer merge). The orchestrator sees the branch change and restarts the duo alone.
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Branch)
$ErrorActionPreference = "Stop"
function G { & git -C $Root @args 2>&1 | Out-String }
if ((G branch --show-current).Trim() -ne $Branch) { Write-Host "not on $Branch : nothing done"; exit 1 }
if ((G status --porcelain --untracked-files=no).Trim()) { Write-Host "dirty tree: nothing done"; G status --short; exit 1 }
& git -C $Root merge-base --is-ancestor main HEAD
if ($LASTEXITCODE -ne 0) { Write-Host "main is not merged into $Branch (git merge main first): nothing done"; exit 1 }
G checkout -q main | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "bin\harness\resume-merge.ps1") -Branch $Branch
$b = (G branch --show-current).Trim()
if ($b -eq "main") { G switch -q --detach | Out-Null; Write-Host "WARNING: the resume failed, worktree detached from main; see the journal"; exit 1 }
Write-Host "ok : $Root on $b ; the orchestrator restarts the duo at its next round (<= 5 min)"
