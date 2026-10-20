#!/bin/sh
# The whole harness still PARSES (bash -n, PowerShell parser, Python compile, benches table up to date).
#   bash bin/benches/harness_lint.sh     -> "HARNESS shell=n/n powershell=n/n python=n/n table=yes|no"
# Runs nothing. A script that no longer parses fails at the worst moment: in the middle of a night run,
# after twenty minutes of waiting. Cheap enough for every gate (GATE_LINT_HARNESS_CMD).
# Detail (each KO file and its error) in logs/benches/harness_lint.log.
. "$(dirname "$0")/common.sh"
cd "$R" || exit 1
LOG="$BENCH_LOGS/harness_lint.log"
: > "$LOG"
DIRS="bin tools supervisor"

sh_total=0; sh_ok=0
for f in $(find $DIRS -name '*.sh' 2>/dev/null); do
  sh_total=$((sh_total+1))
  if bash -n "$f" >> "$LOG" 2>&1; then sh_ok=$((sh_ok+1)); else echo "KO (shell) $f" >> "$LOG"; fi
done

py_total=0; py_ok=0
for f in $(find $DIRS -name '*.py' 2>/dev/null); do
  py_total=$((py_total+1))
  # compile() and not py_compile: same syntax check, no __pycache__ written into the tree.
  if "$PY" -c "import io,sys; compile(io.open(sys.argv[1],encoding='utf-8-sig').read(), sys.argv[1], 'exec')" "$f" >> "$LOG" 2>&1; then
    py_ok=$((py_ok+1))
  else
    echo "KO (python) $f" >> "$LOG"
  fi
done

# Windows PowerShell 5.1 first (what the harness runs), pwsh elsewhere; none = not counted (n/a).
PSH=""
command -v powershell >/dev/null 2>&1 && PSH=powershell
[ -z "$PSH" ] && command -v pwsh >/dev/null 2>&1 && PSH=pwsh
ps_ok=0; ps_total=0; PSRES="n/a"
if [ -n "$PSH" ]; then
  PS=$("$PSH" -NoProfile -Command "
\$ok = 0; \$tot = 0
foreach (\$f in (Get-ChildItem -Recurse -Include *.ps1 bin, tools, supervisor -ErrorAction SilentlyContinue)) {
  \$tot++
  \$errs = \$null
  [void][System.Management.Automation.Language.Parser]::ParseFile(\$f.FullName, [ref]\$null, [ref]\$errs)
  if (-not \$errs -or \$errs.Count -eq 0) { \$ok++ } else {
    Write-Output ('KO (powershell) ' + \$f.FullName)
    foreach (\$e in \$errs) { Write-Output ('   line ' + \$e.Extent.StartLineNumber + ': ' + \$e.Message) }
  }
}
Write-Output ('TOTAL ' + \$ok + ' ' + \$tot)" 2>&1)
  echo "$PS" | grep -av "^TOTAL" >> "$LOG"
  ps_ok=$(echo "$PS" | grep -a "^TOTAL" | awk '{print $2}')
  ps_total=$(echo "$PS" | grep -a "^TOTAL" | awk '{print $3}')
  PSRES="$ps_ok/$ps_total"
fi

TABLE=no
"$PY" bin/benches/benches.py --check >> "$LOG" 2>&1 && TABLE=yes

echo "HARNESS shell=$sh_ok/$sh_total powershell=$PSRES python=$py_ok/$py_total table=$TABLE"
[ "$sh_ok" = "$sh_total" ] && [ "$py_ok" = "$py_total" ] && [ "$ps_ok" = "$ps_total" ] && [ "$TABLE" = "yes" ]
