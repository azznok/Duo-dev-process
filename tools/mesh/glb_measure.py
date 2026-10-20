# -*- coding: utf-8 -*-
# MEASURE A GLB WITHOUT BLENDER: triangles, vertices, bounding box in meters, materials.
#   python tools/mesh/glb_measure.py path.glb [...] [--budget 3000] [--nodes]
# glTF frame: meters, Y up (convert yourself if your engine is Z up or in cm). The triangle
# budget (docs/parking/ASSET-PIPELINE.md) prints "BUDGET KO" above it, exit code 1.
# The global box is the union of the POSITION min/max and IGNORES the node transforms
# (translation, rotation, scale): a part moved by its node is not where the box says.
# --nodes prints the TRUE box of each mesh node, transforms (and parents) applied.
# No dependency. A measurement is not an acceptance: the image says whether it is good.
import json
import struct
import sys


def read_json(path):
    with open(path, "rb") as f:
        magic, _version, _length = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise ValueError("not a GLB: %s" % path)
        clen, _ctype = struct.unpack("<II", f.read(8))
        return json.loads(f.read(clen).decode("utf-8"))


def measure(path):
    doc = read_json(path)
    mn = [1e9] * 3
    mx = [-1e9] * 3
    tris = 0
    verts = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            verts += acc["count"]
            for i in range(3):
                mn[i] = min(mn[i], acc["min"][i])
                mx[i] = max(mx[i], acc["max"][i])
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
            else:
                tris += acc["count"] // 3
    size = [round(mx[i] - mn[i], 3) for i in range(3)]
    return dict(tris=tris, verts=verts, size_m=size, ymin_m=round(mn[1], 3),
                mats=len(doc.get("materials", [])), meshes=len(doc.get("meshes", [])))


def _matrix(n):
    """4x4 matrix (rows) of a glTF node."""
    if "matrix" in n:
        m = n["matrix"]   # column-major in glTF
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = n.get("translation", [0, 0, 0])
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_boxes(path):
    """[(name, min, max)] of the mesh nodes, file order, from the 8 corners of each POSITION box."""
    doc = read_json(path)
    nodes = doc.get("nodes", [])
    children = {c for n in nodes for c in n.get("children", [])}
    out = []

    def walk(i, parent):
        n = nodes[i]
        m = _mul(parent, _matrix(n))
        if "mesh" in n:
            lo, hi = [1e9] * 3, [-1e9] * 3
            for p in doc["meshes"][n["mesh"]]["primitives"]:
                acc = doc["accessors"][p["attributes"]["POSITION"]]
                for c in range(8):
                    q = [acc["max"][a] if c >> a & 1 else acc["min"][a] for a in range(3)]
                    w = [sum(m[r][k] * q[k] for k in range(3)) + m[r][3] for r in range(3)]
                    lo = [min(lo[a], w[a]) for a in range(3)]
                    hi = [max(hi[a], w[a]) for a in range(3)]
            out.append((n.get("name", "#%d" % i), lo, hi))
        for c in n.get("children", []):
            walk(c, m)

    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    for i in range(len(nodes)):
        if i not in children:
            walk(i, ident)
    return out


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print("usage: python tools/mesh/glb_measure.py path.glb [...] [--budget N] [--nodes]")
        return 0 if argv else 2
    budget = None
    nodes = "--nodes" in argv
    argv = [x for x in argv if x != "--nodes"]
    if "--budget" in argv:
        i = argv.index("--budget")
        budget = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    ko = 0
    for c in argv:
        m = measure(c)
        verdict = ""
        if budget is not None:
            verdict = " BUDGET OK" if m["tris"] <= budget else " BUDGET KO (%d > %d)" % (m["tris"], budget)
            ko += m["tris"] > budget
        print("GLB %s : %d tris, %d vertices, %s m (x y z), y min %s m, %d material(s)%s"
              % (c, m["tris"], m["verts"], m["size_m"], m["ymin_m"], m["mats"], verdict))
        if nodes:
            for name, lo, hi in node_boxes(c):
                print("  %-16s x %6.3f %6.3f  y %6.3f %6.3f  z %6.3f %6.3f"
                      % (name, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    return 1 if ko else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
