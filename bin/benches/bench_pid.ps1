# RECORDS THE PID OF THE CURRENT BENCH in .state/benches.pids.
#   . (Join-Path $PSScriptRoot "bench_pid.ps1")   (dot-source, right after param)
# Benches live OUTSIDE the Claude session: ending a turn does not stop them. Each bench declares itself
# here; bin/harness/stop-all.ps1 kills these PIDs first, and run-coder.ps1 refuses to close a task while
# a declared bench is still alive (it sends the coder back to "wait").
# Silent and never fatal. Line: "<pid> <date> <script>".
try {
  $regDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ".state"
  if (-not (Test-Path $regDir)) { New-Item -ItemType Directory -Path $regDir -Force | Out-Null }
  $who = ""
  try { $who = (Get-PSCallStack)[1].ScriptName } catch {}
  if (-not $who) { $who = "?" }
  [IO.File]::AppendAllText((Join-Path $regDir "benches.pids"),
    ("{0} {1} {2}`r`n" -f $PID, (Get-Date -Format s), (Split-Path -Leaf $who)), (New-Object Text.UTF8Encoding $false))
} catch {}
