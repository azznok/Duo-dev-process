# BASE OF THE SHELL BENCHES - to be sourced, never run:
#   . "$(dirname "$0")/common.sh"
# Gives: $R (repository root, derived from this file), cfg KEY (config/project.env, else the example
# file; HARNESS_<KEY> overrides, the value `empty` clears - same rule as tools/project.py), $PY (a working
# Python), $BENCH_LOGS (logs/benches). A bench prints ONLY its verdict line; the detail goes to its log
# (a 300-line output read by an agent costs context at every later call).
_C_D=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
# pwd -W (Git Bash) returns C:/... : readable by bash AND by Windows executables.
R=$(cd "$_C_D/../.." && (pwd -W 2>/dev/null || pwd))
cfg() {
  _v=$(printenv "HARNESS_$1")
  if [ -z "$_v" ]; then
    _f="$R/config/project.env"
    [ -f "$_f" ] || _f="$R/config/project.env.example"
    _v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$_f" 2>/dev/null | tr -d '\r' | head -1)
  fi
  [ "$_v" = "empty" ] && _v=""
  printf '%s' "$_v"
}
# `python3` is the Windows Store stub on some machines (prints an ad, exits 9): test that it runs.
PY=python
for _p in python python3; do
  if "$_p" -c "import sys" >/dev/null 2>&1; then PY=$_p; break; fi
done
BENCH_LOGS="$R/logs/benches"
mkdir -p "$BENCH_LOGS"
