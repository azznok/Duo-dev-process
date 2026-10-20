---
name: game-feel
description: Feel of the controls - camera (mouse, FOV, shake), character movement (walk, jump, gravity, collisions), vehicles, and the feedback of every action, with MEASURED criteria; for apps, the same latency and motion rules for gestures and transitions. Use for every task with DOMAINS feel or that touches input, camera, movement or action feedback. Do NOT use to judge the feel (the owner plays) or for menus and HUD (skill ui-ux).
---

# Game feel

Feel is **tuned** and **measured** here; it is **judged** by the owner, playing (`docs/RULES.md`
§ 1, The proof). The agent delivers values in data, curves and measures, never "it feels good".

## The rules

1. **Input -> image latency <= 100 ms** (flag above 100, refuse above 200). Measure: the input script
   counts frames between the injected key and the first visible change; the figure goes in the report.
2. **Mouse look on the client, every frame**, no smoothing or acceleration by default (options in
   data). Movement goes to the simulation as a `Command` at the tick, with client prediction. A look
   that waits for the tick = refused.
3. **Input -> tick bridge**: edges (press, release) keep their order; relative mouse motion accumulates
   and is consumed once, at the first tick.
4. **Frame-rate independent smoothing**: `t = 1 - exp(-lambda * dt)`, never `lerp(a, b, 0.1)` per frame.
   Test: same trajectory at 30, 60 and 144 fps within 1 %.
5. **Fixed step + render interpolation** for every simulated entity: no stutter at 144 Hz with a
   slower simulation tick.
6. **Values in data**: walk, run, acceleration, braking, jump height, time to apex, step height. Write
   the genre's reference values next to ours (e.g. a well-known game's walk and jump).
7. **Jump defined by height and time to apex**; gravity follows (`g = 2h / t^2`). Fall faster than rise
   (multiplier in data).
8. **Forgiveness**: coyote time after an edge and jump buffering, ~0.1 s each.
9. **Collisions**: never stuck on a corner; slide along walls; a small step is climbed without jumping
   if the design says so (step height in data, tested at every distance, walking and running).
10. **Vehicles**: acceleration = force / mass, never an imposed velocity; "time to stop from max speed"
    measured by a scenario and written in the report.
11. **Camera**: pitch clamped (+-89 deg); settles at 95 % of target in <= 250 ms; horizontal FOV in data
    with a range; speed FOV effect <= +10 deg and switchable; head bob switchable (accessibility).
12. **Shake** = trauma^2 applied to smooth noise, additive and decaying; camera only, never the
    simulation; switchable.
13. **Every verb has feedback** in the same frame: visual + sound event; three levels (small, medium,
    strong) in data.
14. **Dead time**: more than 0.5 s without any feedback after an action is a defect to report.

## The proof

- Raw input script (skill `proofs`) + capture + the measures of the rules involved, in numbers.
- A tuned value: before / after, and the curve or measure that explains it.

## Review (reviewer)

Refuse: mouse look at the tick; frame-rate dependent smoothing; imposed velocity on a vehicle; a
tuning value in code; latency not measured on a controls task; "the feel is good" written by an agent.

## Pitfalls already paid

- Input scripts count FRAMES, not ticks: time a jump on the log line that reports it and on the debug
  overlay's position, never by eye.
- Changing a movement value (step height, speed) changes window goldens driven by input scripts: a
  script that walked into a wall now climbs it. Fix the key-hold duration, never add a gesture.
- A "movement bug" (ends 2 m too far) was a key changing ANOTHER axis than the one read: log the
  position step by step in a logic scenario before accusing the simulation.
- A control law computed in exact kinematics drifted forever: the physics engine integrates in
  sub-steps (velocity then position). Derive control laws against the real integrator; a factor that
  "works" empirically must find its formula before being accepted.
- A criterion that depends on a third-party default (sleep delay, tolerance) must quote that value or
  have it verified first.
- Owner, first playtest: "moving the mouse does nothing" is the worst defect - a control that does not
  answer or is not discoverable. Always an on-screen hint.

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->

Sources (paraphrased): S. Swink, *Game Feel*; M. Nesky, "50 Game Camera Mistakes"; K. Pittman,
"Building a Better Jump"; S. Eiserloh, "Juicing Your Cameras With Math"; G. Fiedler, "Fix Your
Timestep!"; Jonasson and Purho, "Juice it or lose it"; Game Accessibility Guidelines.
