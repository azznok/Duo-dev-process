# -*- coding: utf-8 -*-
"""Write and read GLB files by hand (json + struct, numpy to read back) - no Blender.

Build a kit of primitives at exact dimensions (zero generation credits): a flat-faced prop
(box, panel, frame, pipe) is often better and cheaper built by code than generated.

    from gltf_lib import Mesh, Material, write_glb
    m = Mesh("Crate")
    m.box("Wood", (0, 0.5, 0), (1, 1, 1), tile=0.5)
    write_glb([m], {"Wood": Material((120, 90, 60), roughness=0.9)}, "assets_src/kit/crate.glb")

Read / modify an existing GLB (e.g. a Meshy output): read_glb, accessor, write_raw.
glTF frame: meters, Y up. Blender is Z up: its glTF import maps X->X, Y->-Z, Z->Y and the export
the reverse; reason in glTF. Other engines convert on import (check their axis and unit).
"Everything matte" rule: metal 0 and a fixed roughness can be READ on two numbers of the instance.
"""
import json
import math
import os
import struct


# --- vectors -------------------------------------------------------------------
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    n = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def srgb2lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class Material:
    """tint sRGB 0-255; texture: PNG/JPG path (base colour); normal: path; emissive (r, g, b) + strength."""

    def __init__(self, tint=(200, 200, 200), roughness=0.9, texture=None, normal=None, emissive=None, strength=1.0):
        self.tint, self.roughness, self.texture, self.normal = tint, roughness, texture, normal
        self.emissive, self.strength = emissive, strength


class Mesh:
    """A mesh with several primitives (one per material); vertices not shared (hard normals)."""

    def __init__(self, name):
        self.name = name
        self.prims = {}

    def _p(self, mat):
        return self.prims.setdefault(mat, {"pos": [], "nor": [], "uv": [], "idx": []})

    def tri(self, mat, a, b, c, n=None, ua=(0, 0), ub=(0, 0), uc=(0, 0)):
        fn = norm(cross(sub(b, a), sub(c, a)))
        if n is None:
            n = fn
        elif dot(fn, n) < 0:   # winding follows the requested normal
            b, c, ub, uc = c, b, uc, ub
        p = self._p(mat)
        k = len(p["pos"])
        for v, u in ((a, ua), (b, ub), (c, uc)):
            p["pos"].append(v)
            p["nor"].append(n)
            p["uv"].append(u)
        p["idx"] += [k, k + 1, k + 2]

    def quad(self, mat, a, b, c, d, n=None, uv=None):
        uv = uv or ((0, 0), (1, 0), (1, 1), (0, 1))
        if n is None:
            n = norm(cross(sub(b, a), sub(d, a)))
        self.tri(mat, a, b, c, n, uv[0], uv[1], uv[2])
        self.tri(mat, a, c, d, n, uv[0], uv[2], uv[3])

    def box(self, mat, c, t, tile=1.0, without=()):
        """Axis-aligned box, centre c, size t; UV in meters / tile; `without`: faces left out ('-y'...)."""
        h = (t[0] / 2, t[1] / 2, t[2] / 2)
        for ax in range(3):
            for s in (-1, 1):
                if (("-" if s < 0 else "+") + "xyz"[ax]) in without:
                    continue
                n = [0.0, 0.0, 0.0]
                n[ax] = float(s)
                u_ax, v_ax = [(1, 2), (0, 2), (0, 1)][ax]
                pts = []
                for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = [0.0, 0.0, 0.0]
                    p[ax] = s * h[ax]
                    p[u_ax] = su * h[u_ax]
                    p[v_ax] = sv * h[v_ax]
                    pts.append(add(c, tuple(p)))
                uvs = [(p[u_ax] / tile, p[v_ax] / tile) for p in pts]
                self.quad(mat, *pts, n=tuple(n), uv=uvs)

    def cylinder_y(self, mat, r, y0, y1, sides=12, tile=1.0, caps=True, cx=0.0, cz=0.0):
        """Vertical cylinder (Y axis). Cost: sides x 2 triangles (+ sides x 2 with caps)."""
        for i in range(sides):
            a0, a1 = 2 * math.pi * i / sides, 2 * math.pi * (i + 1) / sides
            p0 = (cx + r * math.cos(a0), cz + r * math.sin(a0))
            p1 = (cx + r * math.cos(a1), cz + r * math.sin(a1))
            am = (a0 + a1) / 2
            n = (math.cos(am), 0.0, math.sin(am))
            u0, u1 = a0 * r / tile, a1 * r / tile
            self.quad(mat, (p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1]), n,
                      ((u0, y0 / tile), (u1, y0 / tile), (u1, y1 / tile), (u0, y1 / tile)))
            if caps:
                self.tri(mat, (cx, y1, cz), (p0[0], y1, p0[1]), (p1[0], y1, p1[1]), (0.0, 1.0, 0.0))
                self.tri(mat, (cx, y0, cz), (p1[0], y0, p1[1]), (p0[0], y0, p0[1]), (0.0, -1.0, 0.0))

    def torus_y(self, mat, R, r, y, n1=24, n2=6):
        """Horizontal ring (Y axis) of radius R, tube r, at height y. Cost: n1 x n2 x 2 triangles."""
        def P(i, j):
            a, b = 2 * math.pi * i / n1, 2 * math.pi * j / n2
            rr = R + r * math.cos(b)
            return (rr * math.cos(a), y + r * math.sin(b), rr * math.sin(a))

        def N(i, j):
            a, b = 2 * math.pi * (i + 0.5) / n1, 2 * math.pi * (j + 0.5) / n2
            return (math.cos(b) * math.cos(a), math.sin(b), math.cos(b) * math.sin(a))
        for i in range(n1):
            for j in range(n2):
                self.quad(mat, P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1), N(i, j))

    def triangles(self):
        return sum(len(p["idx"]) // 3 for p in self.prims.values())


def write_glb(meshes, materials, out, generator="tools/mesh/gltf_lib"):
    """Writes a GLB: one node per Mesh, one glTF material per name used."""
    binary = bytearray()
    views, acc, images, textures = [], [], [], []
    tex_cache = {}

    def view(data, target=None):
        while len(binary) % 4:
            binary.append(0)
        d = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
        if target:
            d["target"] = target
        views.append(d)
        binary.extend(data)
        return len(views) - 1

    def add_accessor(v, comp, count, typ, mn=None, mx=None):
        d = {"bufferView": v, "componentType": comp, "count": count, "type": typ}
        if mn is not None:
            d["min"], d["max"] = mn, mx
        acc.append(d)
        return len(acc) - 1

    def texture(path):
        if path not in tex_cache:
            with open(path, "rb") as f:
                data = f.read()
            mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
            images.append({"bufferView": view(data), "mimeType": mime,
                           "name": os.path.splitext(os.path.basename(path))[0]})
            textures.append({"sampler": 0, "source": len(images) - 1})
            tex_cache[path] = len(textures) - 1
        return tex_cache[path]

    mat_names = sorted({m for me in meshes for m in me.prims})
    gl_materials, extensions = [], set()
    for name in mat_names:
        mt = materials.get(name) or Material()
        pbr = {"metallicFactor": 0.0, "roughnessFactor": mt.roughness,
               "baseColorFactor": [srgb2lin(c) for c in mt.tint] + [1.0]}
        mat = {"name": "M_" + name, "pbrMetallicRoughness": pbr}
        if mt.texture:
            pbr["baseColorTexture"] = {"index": texture(mt.texture)}
        if mt.normal:
            mat["normalTexture"] = {"index": texture(mt.normal)}
        if mt.emissive:
            mat["emissiveFactor"] = list(mt.emissive)
            mat["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": mt.strength}}
            extensions.add("KHR_materials_emissive_strength")
        gl_materials.append(mat)

    gl_meshes, nodes = [], []
    for m in meshes:
        prims = []
        for mat, p in m.prims.items():
            fp = b"".join(struct.pack("<3f", *v) for v in p["pos"])
            fn = b"".join(struct.pack("<3f", *v) for v in p["nor"])
            fu = b"".join(struct.pack("<2f", *v) for v in p["uv"])
            fi = b"".join(struct.pack("<I", i) for i in p["idx"])
            mn = [min(v[k] for v in p["pos"]) for k in range(3)]
            mx = [max(v[k] for v in p["pos"]) for k in range(3)]
            prims.append({"attributes": {
                "POSITION": add_accessor(view(fp, 34962), 5126, len(p["pos"]), "VEC3", mn, mx),
                "NORMAL": add_accessor(view(fn, 34962), 5126, len(p["nor"]), "VEC3"),
                "TEXCOORD_0": add_accessor(view(fu, 34962), 5126, len(p["uv"]), "VEC2")},
                "indices": add_accessor(view(fi, 34963), 5125, len(p["idx"]), "SCALAR"),
                "material": mat_names.index(mat)})
        gl_meshes.append({"name": m.name, "primitives": prims})
        nodes.append({"name": m.name, "mesh": len(gl_meshes) - 1})

    gltf = {"asset": {"version": "2.0", "generator": generator},
            "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
            "nodes": nodes, "meshes": gl_meshes, "materials": gl_materials, "accessors": acc,
            "bufferViews": views, "buffers": [{"byteLength": 0}]}
    if images:
        gltf.update({"images": images, "textures": textures,
                     "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]})
    if extensions:
        gltf["extensionsUsed"] = sorted(extensions)
    write_raw(out, gltf, binary)
    for m in meshes:
        print("  %s : %d triangles" % (m.name, m.triangles()))
    print("WRITTEN", out)


# --- read / rewrite an existing GLB ----------------------------------------------
def read_glb(path):
    with open(path, "rb") as f:
        b = f.read()
    magic, _version, _total = struct.unpack("<III", b[:12])
    if magic != 0x46546C67:
        raise ValueError("not a GLB: " + path)
    jl = struct.unpack("<I", b[12:16])[0]
    js = json.loads(b[20:20 + jl])
    binc = bytearray()
    if len(b) > 20 + jl:
        bl = struct.unpack("<I", b[20 + jl:24 + jl])[0]
        binc = bytearray(b[28 + jl:28 + jl + bl])
    return js, binc


def write_raw(path, js, binc):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    binc = bytearray(binc)
    while len(binc) % 4:
        binc.append(0)
    js.setdefault("buffers", [{}])[0]["byteLength"] = len(binc)
    j = json.dumps(js, separators=(",", ":")).encode("utf-8")
    j += b" " * ((4 - len(j) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(binc)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(binc), 0x004E4942) + bytes(binc))


def accessor(js, binc, i):
    """The numpy array of an accessor (positions, indices...)."""
    import numpy as np
    a = js["accessors"][i]
    v = js["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
    r = np.frombuffer(bytes(binc), dtype=dt, count=a["count"] * n,
                      offset=v.get("byteOffset", 0) + a.get("byteOffset", 0))
    return r.reshape(-1, n) if n > 1 else r
