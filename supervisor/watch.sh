#!/bin/bash
# Watches ONE duo for the supervisor session: returns as soon as there is something to relay.
#   bash supervisor/watch.sh [period_s] [duo_root]   (defaults: 15 ; this repo)
#   e.g. duo B: bash supervisor/watch.sh 15 "../myproject-b"     (run it in the background)
# Follows the tail of the duo's harness journal (new lines only, no model call) and returns (one
# line, code 0) on: a task MERGED into main (verdict already written, nothing to wait for), a
# REJECT or NONE verdict, a blocked merge, an error, a STOP, TASK: NONE, a sleep or a quota; or
# when no duo loop runs any more (SUP=0, counts every duo: checked every 5 min).
D=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P="${1:-15}"
R=$(cd "${2:-$D/..}" && (pwd -W 2>/dev/null || pwd))
journal() { ls -t "$R"/logs/harness-*.log 2>/dev/null | head -1; }
j_before="$(journal)"
lines_before=$(wc -l < "$j_before" 2>/dev/null || echo 0)
rounds=0
while true; do
  sleep "$P"
  j="$(journal)"
  [ "$j" != "$j_before" ] && { j_before="$j"; lines_before=0; }   # new day, new journal
  if [ -n "$j" ]; then
    n=$(wc -l < "$j")
    if [ "$n" -gt "$lines_before" ] 2>/dev/null; then
      # Raw JSON lines (claude -p output) are dropped; the events are kept.
      new=$(tail -n +"$((lines_before+1))" "$j" | head -n "$((n-lines_before))" | grep -av '^{')
      lines_before=$n
      alert=$(echo "$new" | grep -aiE 'error|fail|STOP$|STOP file|STOP-ALL|TASK: NONE|asleep|paused|FATAL|quota|MERGE BLOCKED|verdict (REJECT|NONE)' | tail -3)
      if [ -n "$alert" ]; then echo "JOURNAL : $alert"; exit 0; fi
      merged=$(echo "$new" | grep -aE 'harness : \S+ merged into main' | tail -1)
      if [ -n "$merged" ]; then
        echo "MERGED : $merged"
        echo "$new" | grep -aE 'reviewer : verdict' | tail -1
        echo "NEXT : $(head -1 "$R/pipeline/task.md" 2>/dev/null | tr -d '\r')"
        exit 0
      fi
    fi
  fi
  rounds=$((rounds+1))
  if [ $((rounds * P)) -ge 300 ]; then
    rounds=0
    alive=$(powershell -NoProfile -ExecutionPolicy Bypass -File "$D/sup_alive.ps1" 2>/dev/null | tr -d '\r')
    if [ "$alive" = "SUP=0" ]; then echo "DUO STOPPED (SUP=0)"; exit 0; fi
  fi
done
