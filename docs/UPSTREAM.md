# Lessons for the template

> WRITTEN BY: the duo (one line per lesson); read by the supervisor at each milestone end. BUDGET: 60 lines.
Only GENERIC lessons (true for any game or app built with this template). The supervisor proposes them
to the owner for the template; a lesson taken up is marked `[taken YYYY-MM-DD]`. Over budget: the oldest
go verbatim to `docs/journal/`. `[seed]` = lesson inherited from the project this template came from.

Format: `YYYY-MM-DD · lesson · proposed change (file)`

[seed] · In .gitattributes the LAST matching rule wins: `* text=auto` after the LFS lines puts `text` back on LFS binaries. · Line-ending section first, LFS lines after; `git check-attr -a <binary>` -> `text: unset` in the first-binary checklist (.gitattributes, skill proofs).
[seed] · An input injected into the engine does not prove the OS path: scripts were green while the owner said "the mouse does nothing". · Add a real-window bench with synthetic OS events, and an on-screen hint for hidden gestures from the first build (skill proofs).
[seed] · A fixed-step proof mode freezes the same FPS counter as real time: it always showed 60. · Budgets are measured by a separate real-time bench (skill build-release).
[seed] · The sum of an engine's trace spans is not CPU time per frame (nested schedules counted twice, swapchain wait added: 17 ms for a 5.7 ms frame). · Require a direct frame-time measure before claiming a CPU budget (skill stack, perf section).
[seed] · A trace span created before the global subscriber is installed stays silent forever; a measure anchored on it reads another thread. · Count a span's real entries per thread in the real executable before building a measure on it.
[seed] · A README-to-play copied from a previous build is stale by default. · Re-check every sentence at every build (skill build-release).
[seed] · A process proposal flagged by two reviews in a row without being wired stayed a copied line. · It becomes a mandatory harness backlog entry at the next review (skill build-release).
[seed] · A review claimed a check did not cover something; the script had been extended meanwhile. · Re-read the script itself before any coverage claim (skill build-release).
[seed] · A criterion assumed a third-party default (sleep delay) the library does not have. · A criterion that depends on a library default quotes its value or has it verified first.
[seed] · A scripted ray along an exact grid edge hits nothing. · Aim at the middle of a cell and check the target on the debug overlay (skill proofs).
[seed] · A `\b` written by an agent tool (heredoc, `python -c`, edit string) becomes byte 0x08; a Windows path got truncated. · Use `/` or explicit bytes; check with `cat -A` or a byte dump.
[seed] · The first seeded load test found, on its first run, a defect dozens of hand scenarios never touched. · A seeded load test as soon as there are several systems; an invariant is never weakened (skill load-test).
[seed] · Changing a body's frame of reference (edge, grid boundary, boarding) let it slip into a wall by 0.3 mm. · Every frame change keeps the collision cells under the body, proved by a per-tick "box is free" invariant.
[seed] · A physics restart triggered by WRITING the save made the live game diverge from its reloaded twin. · What must be equal between live, reloaded and witness runs is a function of the tick, never of I/O (skill determinism).
[seed] · A budget on a supposed cause (shapes per chunk) pointed at the wrong optimisation: 91 % of the time was elsewhere. · Budgets on measured cost per phase; a per-phase probe before the first optimisation.
[seed] · An input-driven golden failed 1 time in 20 in the parallel suite: another window stole focus and keys were released. · In proof mode the script is the ONLY input source; reproduce by opening a 2nd window during the capture (skill proofs).
[seed] · A metrics tool that classifies rejections and fixes from task TITLES is repeatedly wrong. · Read the real `VERDICT:` lines and "fixes NNN"; keep a test on synthetic logs (tools/costs).
[seed] · A control law in exact kinematics drifted forever: the engine integrates in sub-steps (5/8, not 1/2, of a*dt^2). · Derive control laws against the real integrator; an empirical factor must find its formula (skill game-feel).
[seed] · A render artefact ("black dashes") was T-junction cracks of merged quads, not shadows. · Measure a render defect by replaying the same view with the optimisation off (diff + changed pixels) before touching it.
[seed] · Counting "holes" with a wide colour threshold mixed shadows and HUD text (19 announced, 0 real). · Count at the exact background colour (+-2) and look with the loupe first (skill proofs).
[seed] · A zone fixed by its material did not change: the cause was its inherited colour. · Render the subject WITH the reference's data in the same scene to split data from render path (skill proofs).
[seed] · Two parallel agents: a tool binary taken from a path in the build config belonged to the OTHER agent. · Each agent calls its tools through its own build-folder variable and checks a recent marker in the binary (skill stack).
[seed] · A cost table reading one working folder under-counted a two-duo process and blamed code for a locked-binary gate refusal. · Tag each log with its duo and refusal cause; run the review once per folder (skill build-release).
[seed] · A "movement bug" was a key changing another axis than the one read. · Log the position step by step in a logic scenario before accusing the simulation (skill game-feel).
[seed] · A test killed from outside (code -1, leaked handles) looked flaky. · Compare the failure time with the OTHER agents' logs on the machine before debugging the test.
[seed] · A model export from a 3D tool is not byte-reproducible. · Prove a generation script by its measurement line (sizes, triangles, bounds), never a hash; re-pose goldens after the LAST export.
[seed] · A part that "lights up" by changing COLOUR cannot use emissive alone (tonemapping whitens emissive on light albedo). · One albedo per state; measure first what nearby effects' light already puts on the surface.
[seed] · Two thumbnails with the same name in a shared folder overwrote each other; a proof read was another task's. · Name thumbnails with the task number or keep them in the task's proof folder (skill proofs).
[seed] · A test temp folder named with the pid and removed only before the run piled up to 92 GB. · Fixed name + removal guard at creation and exit; measure the scratch folder before/after two runs (skill stack).
