#!/bin/sh
# The project config loads and names the gate commands (the smallest bench: copy it to start a new one).
#   bash bin/benches/bench_example.sh        -> "EXAMPLE ok (n gate command(s))" or "EXAMPLE KO (...)"
# Format of a bench: line 1 = what it PROVES, line 2 = how to call it (both read by bin/benches/benches.py
# for docs/BENCHES.md). ONE verdict line on stdout, exit code 0/1, the detail in logs/benches/<name>.log.
. "$(dirname "$0")/bench_pid.sh"
. "$(dirname "$0")/common.sh"
LOG="$BENCH_LOGS/bench_example.log"
{
  echo "root: $R"
  echo "GATE_CMDS: $(cfg GATE_CMDS)"
} > "$LOG" 2>&1
CMDS=$(cfg GATE_CMDS)
if [ -n "$CMDS" ]; then
  N=$(printf '%s' "$CMDS" | tr ';' '\n' | grep -c .)
  echo "EXAMPLE ok ($N gate command(s))"
else
  echo "EXAMPLE KO (GATE_CMDS empty in config/project.env and its example; detail: logs/benches/bench_example.log)"
  exit 1
fi
