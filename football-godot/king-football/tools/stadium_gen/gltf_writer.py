"""Minimal glTF 2.0 (.glb) writer for flat-shaded, untextured architecture.

No third-party dependencies: geometry is collected as quads / triangles per material,
written with flat normals (one normal per face, vertices duplicated per face).
Materials are plain PBR factors, optionally emissive (KHR_materials_emissive_strength).
"""

import json
import math
import struct


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(v):
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)


class Material:
    def __init__(self, name, color, roughness=0.85, metallic=0.0, emissive=None, emissive_strength=1.0,
                 double_sided=True):
        self.name = name
        self.color = color                    # (r, g, b) linear 0..1
        self.roughness = roughness
        self.metallic = metallic
        self.emissive = emissive              # (r, g, b) or None
        self.emissive_strength = emissive_strength
        self.double_sided = double_sided

    def to_json(self):
        m = {
            "name": self.name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [self.color[0], self.color[1], self.color[2], 1.0],
                "metallicFactor": self.metallic,
                "roughnessFactor": self.roughness,
            },
            "doubleSided": self.double_sided,
        }
        if self.emissive is not None:
            m["emissiveFactor"] = list(self.emissive)
            if self.emissive_strength != 1.0:
                m["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": self.emissive_strength}}
        return m


class MeshBuilder:
    """Triangles grouped by material. `quad` / `tri` take points counter-clockwise seen from the front."""

    def __init__(self, name):
        self.name = name
        self.groups = {}      # material name -> [positions, normals]
        self.order = []

    def _group(self, mat):
        if mat not in self.groups:
            self.groups[mat] = [[], []]
            self.order.append(mat)
        return self.groups[mat]

    def tri(self, mat, a, b, c):
        n = _norm(_cross(_sub(b, a), _sub(c, a)))
        g = self._group(mat)
        g[0].extend([a, b, c])
        g[1].extend([n, n, n])

    def quad(self, mat, a, b, c, d):
        """a-b-c-d counter-clockwise seen from the side the face points to."""
        self.tri(mat, a, b, c)
        self.tri(mat, a, c, d)

    def oquad(self, mat, a, b, c, d, want):
        """Quad whose front faces the direction `want` (winding fixed automatically)."""
        n = _cross(_sub(b, a), _sub(c, a))
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            self.quad(mat, d, c, b, a)
        else:
            self.quad(mat, a, b, c, d)

    def box(self, mat, center, size):
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        p = [(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        # index = (sx>0)*4 + (sy>0)*2 + (sz>0)
        self.quad(mat, p[4], p[6], p[7], p[5])   # +x
        self.quad(mat, p[0], p[1], p[3], p[2])   # -x
        self.quad(mat, p[2], p[3], p[7], p[6])   # +y
        self.quad(mat, p[0], p[4], p[5], p[1])   # -y
        self.quad(mat, p[1], p[5], p[7], p[3])   # +z
        self.quad(mat, p[0], p[2], p[6], p[4])   # -z

    def triangle_count(self):
        return sum(len(g[0]) // 3 for g in self.groups.values())

    def is_empty(self):
        return self.triangle_count() == 0


def write_glb(path, meshes, materials):
    """meshes: list of MeshBuilder (one node each, named like the mesh). materials: list of Material."""
    mat_index = {m.name: i for i, m in enumerate(materials)}
    used_ext = any(m.emissive is not None and m.emissive_strength != 1.0 for m in materials)
    blob = bytearray()
    buffer_views = []
    accessors = []
    gl_meshes = []
    nodes = []

    def add_view(data, target):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(buffer_views) - 1

    for mesh in meshes:
        if mesh.is_empty():
            continue
        prims = []
        for mat in mesh.order:
            pos, nor = mesh.groups[mat]
            if not pos:
                continue
            pdata = b"".join(struct.pack("<3f", *p) for p in pos)
            ndata = b"".join(struct.pack("<3f", *n) for n in nor)
            idata = b"".join(struct.pack("<I", i) for i in range(len(pos)))
            mins = [min(p[k] for p in pos) for k in range(3)]
            maxs = [max(p[k] for p in pos) for k in range(3)]
            pv = add_view(pdata, 34962)
            accessors.append({"bufferView": pv, "componentType": 5126, "count": len(pos), "type": "VEC3",
                              "min": mins, "max": maxs})
            pa = len(accessors) - 1
            nv = add_view(ndata, 34962)
            accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nor), "type": "VEC3"})
            na = len(accessors) - 1
            iv = add_view(idata, 34963)
            accessors.append({"bufferView": iv, "componentType": 5125, "count": len(pos), "type": "SCALAR"})
            ia = len(accessors) - 1
            prims.append({"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia,
                          "material": mat_index[mat], "mode": 4})
        gl_meshes.append({"name": mesh.name, "primitives": prims})
        nodes.append({"name": mesh.name, "mesh": len(gl_meshes) - 1})

    gltf = {
        "asset": {"version": "2.0", "generator": "king-football stadium_gen"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "materials": [m.to_json() for m in materials],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    if used_ext:
        gltf["extensionsUsed"] = ["KHR_materials_emissive_strength"]
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00"))
        f.write(bytes(blob))
