# Supervisor handoff

> WRITTEN BY: the supervisor, at each checkpoint with the owner and before ending a session. BUDGET: 80 lines.
> A new supervisor session starts HERE (then `supervisor/SUPERVISOR.md`), instead of a compaction.

**Last update: (never — the onboarding has not run yet).**

## Start a session
1. `powershell -NoProfile -ExecutionPolicy Bypass -File supervisor/sup_alive.ps1` -> `SUP=<number of duos>`
   expected once the duos run. `SUP=0` and no orchestrator: relaunch it (`SUPERVISOR.md` § Useful commands).
2. The watcher of each duo, in the background, relaunched at EVERY notification: `bash supervisor/watch.sh`
   (A) and `bash supervisor/watch.sh 15 "../<project>-b"` (B). Never end a turn without them.
3. Read the end of `logs/orchestrator-<yymmdd>.log` and `logs/harness-<yymmdd>.log` (A; B in its folder).

## Onboarding (checklist, `supervisor/ONBOARDING.md`)
- [ ] 0 Hello (language, plan, budget, doctor, own git remote)
- [ ] 1 Product (VISION validated, BRIEF, TASTE)
- [ ] 2 Stack (PROJECT-RULES validated, CLAUDE.md § Project, GATE_CMDS, skill `stack`)
- [ ] 3 Art direction (refs, board, one direction frozen)
- [ ] 4 Assets, services, notifications
- [ ] 5 Scope and milestones (ROADMAP, PLAN `MILESTONE: M0`)
- [ ] 6 Running (models, duos, cadence)
- [ ] 7 ADRs, README, `ONBOARDED=1`, commit, doctor, launch

## State
- (milestone, what each duo does, what the owner is doing)

## To do (decided, not done yet)
- (none)

## Pitfalls paid (details: SUPERVISOR.md § Lessons)
- (none yet)
