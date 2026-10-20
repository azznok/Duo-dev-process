# RECORDS THE PID OF THE CURRENT SHELL BENCH in .state/benches.pids.
#   . "$(dirname "$0")/bench_pid.sh"     (SOURCED at the top of a shell bench)
# Under Git Bash, $$ is an MSYS pid that Stop-Process cannot use: the Windows pid is read from
# /proc/$$/winpid. Elsewhere (Linux, macOS) $$ is the real pid. Silent and never fatal.
{
  _BP_D=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
  _BP_R=$(cd "$_BP_D/../.." && pwd)
  mkdir -p "$_BP_R/.state"
  _BP_W=$(cat /proc/$$/winpid 2>/dev/null)
  [ -n "$_BP_W" ] || _BP_W=$$
  printf '%s %s %s\n' "$_BP_W" "$(date +%Y-%m-%dT%H:%M:%S)" "$(basename "$0")" >> "$_BP_R/.state/benches.pids"
} 2>/dev/null || true
