REPORT: <nnn> — <title>
STATUS: DONE | FALLBACK DELIVERED | IMPOSSIBLE (why, in one sentence)

DONE:
- 3 to 6 lines, what changed for the user (or for the next agent) first.

ACCEPTANCE CRITERIA:
- [x] criterion 1 — proof (test `module::name`, command, image)
- [ ] criterion 3 — open: why (e.g. waits for Q09, a device to test on)

COMMITS:
- <short hash> feat(core): <summary> (TASK <nnn>)

CHECKS:
- `<format command>` -> ok
- `<lint command>` -> ok
- `<touched tests command>` -> <n> passed, 0 failed

PROOFS:
- proofs/<nnn>/<x>.png — what it shows, next to tests/golden/<x>.png
- scenario: `<scenario command>` -> `<verdict line>`
- SELF-JUDGE: YES | NO (n gaps) (try k/2) — if the task has art-judge lines

DEPENDENCIES ADDED: none | <name> <version> (licence, why)

DOUBTS:
- what is not sure, honestly. It is what avoids a rejection.

PROPOSED QUESTION: none | Qnn — options a/b/c, proposed default (if STATUS IMPOSSIBLE)
MISSING DOMAIN: none
PROCESS: none | skill <name> created / updated | lesson added (docs/UPSTREAM.md)

<!-- <= 3 KB. Image paths are read by the harness: it makes thumbnails of them for the reviewer. -->
