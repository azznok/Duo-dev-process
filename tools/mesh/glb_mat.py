# -*- coding: utf-8 -*-
# Makes a generated GLB (Meshy...) MATTE before import, and cuts off a base if needed.
#   python tools/mesh/glb_mat.py INPUT.glb OUTPUT.glb [--roughness 0.9] [--disc CX,CY,R,YCUT] [--zmin Z]
# Materials: removes the metal/roughness map and the emission (the generator paints them: metal
# up to 0.69 on an object meant to be matte), sets metal 0 and a fixed roughness: "everything
# is matte" can then be READ on two numbers of the imported instance. Normal and colour stay.
# --disc: keeps a triangle if its centre is above YCUT (glTF Y, m) OR inside the
# circle (CX, CY, R) of the XY plane; the rest (the base the generator puts on the ground) goes.
# --zmin Z: and only if its centre is in front of Z.
import argparse
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gltf_lib import accessor, read_glb, write_raw  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Make a GLB matte (metal 0, fixed roughness) and optionally cut its base.")
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--roughness", type=float, default=0.9)
    ap.add_argument("--disc", default=None, help="CX,CY,R,YCUT")
    ap.add_argument("--zmin", type=float, default=None)
    a = ap.parse_args()
    js, binc = read_glb(a.input)
    for m in js.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        pbr.pop("metallicRoughnessTexture", None)
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = a.roughness
        m.pop("emissiveTexture", None)
        m.pop("emissiveFactor", None)
        print("material", m.get("name"), "-> metal 0, roughness", a.roughness)
    if a.disc:
        cx, cy, r, ycut = (float(x) for x in a.disc.split(","))
        for me in js["meshes"]:
            for pr in me["primitives"]:
                if "indices" not in pr:
                    print("cut: primitive without indices skipped")
                    continue
                P = accessor(js, binc, pr["attributes"]["POSITION"]).astype(np.float64)
                T = accessor(js, binc, pr["indices"]).astype(np.int64).reshape(-1, 3)
                c = P[T].mean(axis=1)
                keep = (c[:, 1] >= ycut) | (np.hypot(c[:, 0] - cx, c[:, 1] - cy) <= r)
                if a.zmin is not None:
                    keep &= c[:, 2] >= a.zmin
                # orphan vertices go too (otherwise they still count in the mesh bounds)
                used = np.unique(T[keep])
                renum = np.full(len(P), -1, dtype=np.int64)
                renum[used] = np.arange(len(used))

                def push(arr, target=None):
                    off = len(binc) + (-len(binc)) % 4
                    binc.extend(b"\0" * (off - len(binc)) + arr.tobytes())
                    v = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
                    if target:
                        v["target"] = target
                    js["bufferViews"].append(v)
                    return len(js["bufferViews"]) - 1

                for name, i in list(pr["attributes"].items()):
                    src = js["accessors"][i]
                    arr = np.ascontiguousarray(accessor(js, binc, i)[used])
                    acc = {"bufferView": push(arr, 34962), "componentType": src["componentType"],
                           "count": int(len(used)), "type": src["type"]}
                    if src.get("normalized"):
                        acc["normalized"] = True
                    if name == "POSITION":
                        acc["min"], acc["max"] = arr.min(0).tolist(), arr.max(0).tolist()
                    js["accessors"].append(acc)
                    pr["attributes"][name] = len(js["accessors"]) - 1
                T2 = renum[T[keep]].astype(np.uint32).ravel()
                js["accessors"].append({"bufferView": push(T2, 34963), "componentType": 5125,
                                        "count": int(T2.size), "type": "SCALAR"})
                pr["indices"] = len(js["accessors"]) - 1
                print("cut: %d triangles kept out of %d" % (keep.sum(), len(T)))
    write_raw(a.output, js, binc)
    print("WRITTEN", a.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
