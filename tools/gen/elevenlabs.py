# -*- coding: utf-8 -*-
# ElevenLabs: sound effects (sound-generation, eleven_text_to_sound_v2). DRY RUN by default: nothing is spent without --pay.
#   python tools/gen/elevenlabs.py balance
#   python tools/gen/elevenlabs.py sound --prompt "..." --seconds 3 --out assets_src/audio/<name>/raw_a.mp3 [--loop] [--influence 0.5] [--pay]
#   python tools/gen/elevenlabs.py batch jobs.json [--pay]   (each job: {"prompt", "seconds", "out", "loop"})
# Rules (docs/parking/ASSET-PIPELINE.md, a PROPOSAL until the owner validates it):
#  - NEVER "quiet", "faint", "near-silent"...: the generator then returns background hiss
#    or a hum. Always an AUDIBLE sound, and this suffix (added automatically):
#    "No music, no background ambience, no electrical hum, no sub-bass, silence between sounds."
#  - Every file goes through the GATE (tools/audio/gate.py); REJECTED = never offered.
#  - Agents never listen: the owner listens on the listening page (tools/audio/listen_page.py).
import argparse
import concurrent.futures as cf
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "audio"))
import _common as C  # noqa: E402

API = "https://api.elevenlabs.io"
SUFFIX = " No music, no background ambience, no electrical hum, no sub-bass, silence between sounds."
# Words that made the generator return hiss, hum or inaudible sub-bass, rejected by the owner as "broken".
FORBIDDEN = re.compile(r"\b(quiet|faint|near[- ]silent|barely audible|subtle hum|whisper[- ]quiet|very soft)\b", re.I)
# Estimate for the cap (credits per sound); the REAL cost is measured on the subscription before/after.
ESTIMATE_PER_SOUND = 200
PARALLEL = 3
# The API bounds the duration (check its docs if it refuses); a game effect is usually <= 5 s, a loop <= 10 s.
MAX_SECONDS = 30


def headers():
    return {"xi-api-key": C.required_key("ELEVENLABS_API_KEY")}


def subscription():
    try:
        s = C.http("GET", API + "/v1/user/subscription", headers())
        return s.get("character_count"), s.get("character_limit")
    except Exception as e:
        print("(subscription unreadable: %s)" % e)
        return None, None


def final_prompt(p):
    m = FORBIDDEN.search(p)
    if m:
        raise ValueError("forbidden word in the prompt (%s): describe an AUDIBLE sound "
                         "(source, material, gesture, distance, count)" % m.group(0))
    p = p.strip()
    if "no sub-bass" in p.lower():
        return p
    return (p if p.endswith((".", "!")) else p + ".") + SUFFIX


def params_of(t, text):
    return {"text": text, "seconds": t.get("seconds"), "loop": bool(t.get("loop")),
            "influence": t.get("influence", 0.5)}


def refusal(t):
    if not t.get("out"):
        return "no out path"
    s = t.get("seconds")
    if s is not None and not (0.5 <= float(s) <= MAX_SECONDS):
        return "seconds %s outside [0.5, %d]" % (s, MAX_SECONDS)
    try:
        final_prompt(t.get("prompt", ""))
    except ValueError as e:
        return str(e)
    return None


def launch(t, pay):
    why = refusal(t)
    if why:
        return "%s : REFUSED - %s" % (t.get("out", "?"), why)
    text = final_prompt(t["prompt"])
    params = params_of(t, text)
    h = C.fingerprint("elevenlabs", params)
    done = C.already_done(t["out"], h)
    if done:
        return "%s : ALREADY DONE -> %s (nothing spent)" % (t["out"], done)
    if not pay:
        return "%s : DRY RUN - ~%d credits (add --pay)\n    prompt: %s" % (t["out"], ESTIMATE_PER_SOUND, text)
    body = {"text": text, "prompt_influence": params["influence"], "model_id": "eleven_text_to_sound_v2"}
    if params["seconds"]:
        body["duration_seconds"] = params["seconds"]
    if params["loop"]:
        body["loop"] = True
    data = C.http("POST", API + "/v1/sound-generation?output_format=mp3_44100_128", headers(), body, raw=True)
    out = pathlib.Path(t["out"])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    C.remember(h, out)
    verdict = "gate not run"
    try:
        import gate
        verdict = gate.line(str(out))
    except Exception as e:   # the gate needs numpy + soundfile
        verdict = "gate unavailable (%s)" % e
    C.log_credits("elevenlabs", "sound-generation", "~%d" % ESTIMATE_PER_SOUND, out, verdict)
    return "%s : OK - %s" % (out, verdict)


def run(jobs, pay):
    todo = [t for t in jobs if not refusal(t)
            and not C.already_done(t["out"], C.fingerprint("elevenlabs", params_of(t, final_prompt(t["prompt"]))))]
    total = len(todo) * ESTIMATE_PER_SOUND
    print("BATCH: %d sound(s), %d to generate, ~%d credits estimated" % (len(jobs), len(todo), total))
    u0 = None
    if pay and todo:
        C.check_cap("eleven", total)
        u0, lim = subscription()
        if u0 is not None and lim is not None and lim - u0 < total:
            print("REFUSED: %d credits left on the subscription, %d estimated" % (lim - u0, total))
            return 2
    with cf.ThreadPoolExecutor(PARALLEL) as ex:
        for r in ex.map(lambda t: launch(t, pay), jobs):
            print(r)
    if pay and todo:
        u1, _ = subscription()
        if u0 is not None and u1 is not None:
            print("SUBSCRIPTION: %s -> %s credits used (measured spend %s)" % (u0, u1, u1 - u0))
    # a refused job is a failure of the batch: the caller must see it in the exit code
    return 1 if any(refusal(t) for t in jobs) else 0


def main():
    ap = argparse.ArgumentParser(description="ElevenLabs sound generator (dry run unless --pay).")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("balance")
    p = sp.add_parser("sound")
    p.add_argument("--prompt", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--seconds", type=float, default=None)
    p.add_argument("--loop", action="store_true")
    p.add_argument("--influence", type=float, default=0.5)
    p.add_argument("--pay", action="store_true")
    p = sp.add_parser("batch")
    p.add_argument("file")
    p.add_argument("--pay", action="store_true")
    a = ap.parse_args()
    if a.cmd == "balance":
        u, lim = subscription()
        print("ELEVENLABS: %s / %s credits used" % (u, lim))
        return 0
    if a.cmd == "batch":
        return run(C.read_batch(a.file), a.pay)
    t = {"prompt": a.prompt, "out": a.out, "seconds": a.seconds, "loop": a.loop, "influence": a.influence}
    why = refusal(t)
    if why:
        print("REFUSED: " + why)
        return 1
    return run([t], a.pay)


if __name__ == "__main__":
    sys.exit(main())
