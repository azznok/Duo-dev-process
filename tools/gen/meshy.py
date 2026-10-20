# -*- coding: utf-8 -*-
# Meshy: concept images (image-to-image, text-to-image) and 3D (multi-view, single image or text -> GLB).
# DRY RUN by default: nothing is spent without --pay.
#   python tools/gen/meshy.py balance
#   python tools/gen/meshy.py image --prompt "..." --ref sheet.png [--ref b.png] --out docs/art/refs/x.png [--ratio 16:9] [--pay]
#   python tools/gen/meshy.py text-image --prompt "..." --out docs/art/mockups/x.png [--pay]
#   python tools/gen/meshy.py 3d --view front.png --view side.png --view back.png --out assets_src/x/x.glb [--polycount 15000] [--texture] [--pay]
#   python tools/gen/meshy.py image-3d --view front.png --out assets_src/x/x.glb [--texture] [--pay]
#   python tools/gen/meshy.py text-3d --prompt "..." --out assets_src/x/x.glb [--polycount 3000] [--pay]
#   python tools/gen/meshy.py batch jobs.json [--pay]   (each job: {"type": "image", "prompt", "ref": [..], "out"};
#                                                        3d jobs: {"type": "3d", "views": [..], "out", "api": {...}})
#   python tools/gen/meshy.py resume                    (harvests paid jobs left in flight)
# Rules (docs/parking/ASSET-PIPELINE.md, a PROPOSAL until the owner validates it):
#  - iterate on the IMAGE (a few credits), not on the 3D (tens); never texture a rejected silhouette;
#  - 2 Meshy jobs in parallel at most; never poll a status in a loop by hand: `resume`;
#  - look for a free asset BEFORE generating;
#  - image-to-image needs at least one reference (the reference is what keeps the style) and
#    takes 5 at most (HTTP 400 beyond, nothing billed): paste more into ONE strip image instead;
#  - 3D from FLAT views only (front, side, back): a three-quarter view comes out squashed.
# Endpoints follow the Meshy docs; the image-to-image one was verified in use, the others may have
# moved: check the docs before the first paid call and fix this file in the same commit.
import argparse
import base64
import concurrent.futures as cf
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _common as C  # noqa: E402

API = "https://api.meshy.ai/openapi"
# Estimated costs (credits) for the cap; the REAL cost is measured on the balance before/after.
COST = {"image": 6, "text-image": 6, "3d": 20, "3d+texture": 30, "text-3d": 20,
        "image-3d": 20, "image-3d+texture": 30}
TYPES = ("image", "text-image", "3d", "image-3d", "text-3d")
PARALLEL = 2
MAX_REFS = 5


def headers():
    return {"Authorization": "Bearer " + C.required_key("MESHY_API_KEY")}


def data_uri(p):
    p = pathlib.Path(p)
    mime = "image/png" if p.suffix.lower() == ".png" else "image/jpeg"
    return "data:%s;base64,%s" % (mime, base64.b64encode(p.read_bytes()).decode())


def balance():
    try:
        return C.http("GET", API + "/v1/balance", headers()).get("balance")
    except Exception as e:
        print("(balance unreadable: %s)" % e)
        return None


def request(t):
    """(creation path, body, status path) of a job."""
    if t["type"] == "image":
        return ("/v1/image-to-image", {"ai_model": "nano-banana-2", "prompt": t["prompt"],
                                       "reference_image_urls": [data_uri(r) for r in t.get("ref", [])],
                                       "aspect_ratio": t.get("ratio", "16:9")}, "/v1/image-to-image/")
    if t["type"] == "text-image":
        return ("/v1/text-to-image", {"ai_model": "nano-banana-2", "prompt": t["prompt"],
                                      "aspect_ratio": t.get("ratio", "16:9")}, "/v1/text-to-image/")
    if t["type"] == "3d":
        # "api" (batch only): Meshy parameters passed as is (ai_model, should_remesh,
        # geometry_resolution, model_type...). Without it, the quad remesh, which comes out
        # mushy on hard-surface objects: for those, pass {"should_remesh": false} and clean in Blender.
        body = {"image_urls": [data_uri(v) for v in t["views"]], "should_texture": bool(t.get("texture"))}
        if "api" in t:
            body.update(t["api"])
        else:
            body.update({"topology": "quad", "target_polycount": int(t.get("polycount", 15000)),
                         "should_remesh": True})
        return ("/v1/multi-image-to-3d", body, "/v1/multi-image-to-3d/")
    if t["type"] == "image-3d":
        body = {"image_url": data_uri(t["views"][0]), "should_texture": bool(t.get("texture"))}
        body.update(t.get("api", {}))
        return ("/v1/image-to-3d", body, "/v1/image-to-3d/")
    if t["type"] == "text-3d":
        return ("/v2/text-to-3d", {"mode": "preview", "prompt": t["prompt"], "topology": "quad",
                                   "target_polycount": int(t.get("polycount", 3000))}, "/v2/text-to-3d/")
    raise ValueError("unknown type: %s" % t["type"])


def cost(t):
    k = t["type"] + "+texture" if t["type"] in ("3d", "image-3d") and t.get("texture") else t["type"]
    return COST[k]


def params_of(t):
    return {k: v for k, v in t.items() if k != "out"}


def refusal(t):
    """Why a job is refused before any spending; None if it may go."""
    if t.get("type") not in TYPES:
        return "unknown type %r (one of %s)" % (t.get("type"), ", ".join(TYPES))
    if not t.get("out"):
        return "no out path"
    if t["type"] == "image":
        refs = t.get("ref", [])
        if not refs:
            return "image-to-image needs at least one reference (ref); without one: text-image"
        if len(refs) > MAX_REFS:
            return "%d references, Meshy takes %d at most (HTTP 400): paste them into one strip" % (len(refs), MAX_REFS)
        missing = [r for r in refs if not pathlib.Path(r).exists()]
        if missing:
            return "reference not found: %s" % ", ".join(missing)
    if t["type"] in ("3d", "image-3d"):
        views = t.get("views", [])
        if not views:
            return "no view given"
        missing = [v for v in views if not pathlib.Path(v).exists()]
        if missing:
            return "view not found: %s" % ", ".join(missing)
    return None


def wait(status_path, tid, out, info):
    t0 = time.time()
    r = {}
    while time.time() - t0 < 1800:
        time.sleep(8)
        r = C.http("GET", API + status_path + tid, headers())
        if r.get("status") in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            break
    else:
        return "IN FLIGHT (still running after 30 min: `resume` later)"
    st = r.get("status")
    if st != "SUCCEEDED":
        C.in_flight_remove(tid)
        return "%s (%s)" % (st, (r.get("task_error") or {}).get("message", ""))
    if "image_urls" in r:
        C.download(r["image_urls"][0], out)
    else:
        C.download((r.get("model_urls") or {})["glb"], out)
    C.remember(info["fingerprint"], out)
    C.log_credits("meshy", info["type"], "~%d" % info["cost"], out, "job " + tid[:13])
    C.in_flight_remove(tid)
    return "OK"


def launch(t, pay):
    why = refusal(t)
    if why:
        return "%s : REFUSED - %s" % (t.get("out", "?"), why)
    h = C.fingerprint("meshy", params_of(t))
    done = C.already_done(t["out"], h)
    if done:
        return "%s : ALREADY DONE -> %s (nothing spent)" % (t["out"], done)
    if not pay:
        return "%s : DRY RUN - %s, ~%d credits (add --pay)" % (t["out"], t["type"], cost(t))
    path, body, status_path = request(t)
    tid = C.http("POST", API + path, headers(), body)["result"]
    info = {"type": t["type"], "out": t["out"], "status_path": status_path, "fingerprint": h, "cost": cost(t)}
    C.in_flight_add(tid, info)   # written BEFORE waiting: a paid job is never lost
    return "%s : %s" % (t["out"], wait(status_path, tid, t["out"], info))


def run(jobs, pay):
    todo = [t for t in jobs if not refusal(t) and not C.already_done(t["out"], C.fingerprint("meshy", params_of(t)))]
    total = sum(cost(t) for t in todo)
    print("BATCH: %d job(s), %d to generate, ~%d credits estimated" % (len(jobs), len(todo), total))
    s0 = None
    if pay and total:
        C.check_cap("meshy", total)
        s0 = balance()
        if s0 is not None and s0 < total:
            print("REFUSED: balance %s < %d estimated" % (s0, total))
            return 2
    with cf.ThreadPoolExecutor(PARALLEL) as ex:
        for r in ex.map(lambda t: launch(t, pay), jobs):
            print(r)
    if pay and total:
        s1 = balance()
        if s0 is not None and s1 is not None:
            print("BALANCE: %s -> %s (measured spend %s)" % (s0, s1, s0 - s1))
    # a refused job is a failure of the batch: the caller must see it in the exit code
    return 1 if any(refusal(t) for t in jobs) else 0


def main():
    ap = argparse.ArgumentParser(description="Meshy generator (dry run unless --pay).")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("balance")
    sp.add_parser("resume")
    for name in ("image", "text-image", "text-3d"):
        p = sp.add_parser(name)
        p.add_argument("--prompt", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--ratio", default="16:9")
        p.add_argument("--ref", action="append", default=[])
        p.add_argument("--polycount", type=int, default=3000)
        p.add_argument("--pay", action="store_true")
    for name in ("3d", "image-3d"):
        p = sp.add_parser(name)
        p.add_argument("--view", action="append", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--polycount", type=int, default=15000)
        p.add_argument("--texture", action="store_true")
        p.add_argument("--pay", action="store_true")
    p = sp.add_parser("batch")
    p.add_argument("file")
    p.add_argument("--pay", action="store_true")
    a = ap.parse_args()
    if a.cmd == "balance":
        print("MESHY BALANCE:", balance())
        return 0
    if a.cmd == "resume":
        for tid, info in C.in_flight().items():
            print("%s : %s" % (info["out"], wait(info["status_path"], tid, info["out"], info)))
        return 0
    if a.cmd == "batch":
        return run(C.read_batch(a.file), a.pay)
    t = {"type": a.cmd, "out": a.out}
    if a.cmd in ("3d", "image-3d"):
        t.update(views=a.view, polycount=a.polycount, texture=a.texture)
    else:
        t.update(prompt=a.prompt, ratio=a.ratio, ref=a.ref, polycount=a.polycount)
    why = refusal(t)
    if why:
        print("REFUSED: " + why)
        return 1
    return run([t], a.pay)


if __name__ == "__main__":
    sys.exit(main())
