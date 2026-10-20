# TEST OF WHAT THE DUOS SHARE (lib\shared.ps1), without a model nor any cost, ~30 s.
#   powershell -File bin\harness\test\test-shared.ps1     (one OK/KO line per check)
# Small throwaway repo in %TEMP% (the harness lib\ copied, two worktrees): common folder seen from
# both, exclusive lock between processes, lock of a dead PID taken over, counter without duplicates
# under concurrency, ADR floor, processes of another harness recognised. Touches neither this repo
# nor its counters. Exit code 1 on any KO.
$ErrorActionPreference = "Continue"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$T = Join-Path $env:TEMP ("harness-test-shared-" + (Get-Date -Format "yyMMdd-HHmmss"))
$D1 = Join-Path $T "duo1"; $D2 = Join-Path $T "duo2"
New-Item -ItemType Directory -Force (Join-Path $D1 "bin\harness\lib"), (Join-Path $D1 "docs\adr") | Out-Null
Copy-Item (Join-Path $Source "bin\harness\lib\*.ps1") (Join-Path $D1 "bin\harness\lib")
# One ADR = one file: the floor is the highest NNNN of docs/adr/ (the generated index does not count).
foreach ($f in @("0243-c.md", "0241-d.md")) { Set-Content (Join-Path $D1 "docs\adr\$f") "## ADR-x" -Encoding UTF8 }
Set-Content (Join-Path $D1 "docs\DECISIONS.md") "## ADR-0300 - generated index, not a source" -Encoding UTF8
Set-Content (Join-Path $D1 ".gitignore") ".state/`r`nlogs/" -Encoding UTF8
git -C $D1 init -q 2>&1 | Out-Null
git -C $D1 add -A 2>&1 | Out-Null
git -C $D1 -c user.email=t@t -c user.name=t commit -q -m "test repo" 2>&1 | Out-Null
git -C $D1 worktree add -q -b duo2 $D2 2>&1 | Out-Null
$ko = 0; $n = 0
function L([bool]$ok, [string]$t) { $script:n++; Write-Host ("[{0}] {1}" -f $(if ($ok) { "OK " } else { "KO " }), $t); if (-not $ok) { $script:ko++ } }
function New-Script([string]$R, [string]$Code) {
    $f = Join-Path $T ("s-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".ps1")
    $head = ". '$R\bin\harness\lib\common.ps1'`r`n. '$R\bin\harness\lib\shared.ps1'`r`n"
    [IO.File]::WriteAllText($f, $head + $Code, (New-Object System.Text.UTF8Encoding $false))
    return $f
}
function In([string]$R, [string]$Code) {
    return ((& powershell -NoProfile -ExecutionPolicy Bypass -File (New-Script $R $Code) 2>&1 | Out-String).Trim())
}
function Start-In([string]$R, [string]$Code, [string]$Out) {
    return (Start-Process powershell -PassThru -WindowStyle Hidden -RedirectStandardOutput $Out `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (New-Script $R $Code)))
}

# 1. The common folder is the same seen from both worktrees, outside their .state/.
$c1 = In $D1 'Get-SharedDir'; $c2 = In $D2 'Get-SharedDir'
L (($c1 -eq $c2) -and ($c1 -like "*\.git\harness")) "common folder identical from both worktrees ($c1)"

# 2. Exclusive lock between processes: duo1 holds it 8 s, duo2 does not get it in 2 s, then does.
$hold = Start-In $D1 'if (Enter-SharedLock "merge" 5) { "TAKEN"; Start-Sleep -Seconds 8; Exit-SharedLock "merge" }' (Join-Path $T "hold.txt")
Start-Sleep -Seconds 3
$r = In $D2 'Enter-SharedLock "merge" 2'
L ($r -match 'False$') "lock held by duo1: duo2 does not get it ($($r -replace '\s+', ' '))"
$hold.WaitForExit(20000) | Out-Null
$r = In $D2 'if (Enter-SharedLock "merge" 5) { "GOT"; Exit-SharedLock "merge" }'
L ($r -match 'GOT') "lock released by duo1: duo2 gets it"
L (-not (Test-Path (Join-Path $c1 "merge.lock"))) "Exit-SharedLock removes the lock file"

# 3. Lock of a dead PID: taken over.
Set-Content (Join-Path $c1 "merge.lock") "999999 2026-01-01T00:00:00 elsewhere" -Encoding ASCII
$r = In $D2 'if (Enter-SharedLock "merge" 5) { "GOT"; Exit-SharedLock "merge" }'
L ($r -match 'GOT') "lock of a dead pid taken over"

# 4. Counter under concurrency: 2 processes x 15 numbers, no duplicate nor gap.
$code = '$l = @(); for ($i = 0; $i -lt 15; $i++) { $l += Get-SharedNumber "task" 0 }; $l -join " "'
$a = Start-In $D1 $code (Join-Path $T "a.txt"); $b = Start-In $D2 $code (Join-Path $T "b.txt")
$a.WaitForExit(60000) | Out-Null; $b.WaitForExit(60000) | Out-Null
$all = @(((Get-Content (Join-Path $T "a.txt") -Raw) + " " + (Get-Content (Join-Path $T "b.txt") -Raw)) -split '\s+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
$uniq = @($all | Sort-Object -Unique)
L (($all.Count -eq 30) -and ($uniq.Count -eq 30) -and ($uniq[0] -eq 1) -and ($uniq[29] -eq 30)) "shared counter: 30 numbers, 1 to 30, no duplicate ($($all.Count) read, $($uniq.Count) unique)"
$r = In $D1 'Get-SharedNumber "task" 100'
L ($r -eq "101") "the local floor wins over a lower counter ($r)"

# 5. ADR floor: the highest NNNN of docs/adr/ (docs/DECISIONS.md is generated: ignored).
$r = In $D1 'Get-SharedNumber "adr" (Get-AdrFloor)'
L ($r -eq "244") "next ADR = 0244 (0243 is the highest of docs/adr, the index's 0300 ignored) ($r)"

# 6. Processes of another harness (fake processes, nothing killed).
$code = @'
$r1 = ("$Root\bin\harness\run-coder.ps1")
$p = @{
  1 = [pscustomobject]@{ CommandLine = "powershell -File `"$r1`""; ParentProcessId = 0 }
  2 = [pscustomobject]@{ CommandLine = "claude.exe -p"; ParentProcessId = 1 }
  3 = [pscustomobject]@{ CommandLine = "bash bin/benches/x.sh"; ParentProcessId = 2 }
  11 = [pscustomobject]@{ CommandLine = "C:\Windows\powershell.exe -File C:\elsewhere\other duo\bin\harness\run-coder.ps1"; ParentProcessId = 0 }
  12 = [pscustomobject]@{ CommandLine = "claude.exe -p"; ParentProcessId = 11 }
  13 = [pscustomobject]@{ CommandLine = "bash bin/benches/x.sh"; ParentProcessId = 12 }
  20 = [pscustomobject]@{ CommandLine = "bash bin/benches/orphan.sh"; ParentProcessId = 99 }
  30 = [pscustomobject]@{ CommandLine = "powershell -File bin\harness\duo.ps1"; ParentProcessId = 0 }
  31 = [pscustomobject]@{ CommandLine = "bash bin/benches/y.sh"; ParentProcessId = 30 }
}
"mine=" + (Test-OtherHarness $p[3] $p) + " other=" + (Test-OtherHarness $p[13] $p) + " orphan=" + (Test-OtherHarness $p[20] $p) + " relative=" + (Test-OtherHarness $p[31] $p)
'@
$r = In $D1 $code
L ($r -eq "mine=False other=True orphan=False relative=False") "Test-OtherHarness: ours and the orphan killable, the other spared ($r)"

git -C $D1 worktree remove --force $D2 2>&1 | Out-Null
Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("TEST SHARED : {0} checks" -f $n)
Write-Host ("TOTAL: {0} KO" -f $ko)
if ($ko) { exit 1 }
exit 0
