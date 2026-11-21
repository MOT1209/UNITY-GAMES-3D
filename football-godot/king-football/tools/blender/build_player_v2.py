"""KING FOOTBALL — player character v2: base model, rig, skin weights, animation library, GLB export.

    blender -b --factory-startup --python tools/blender/build_player_v2.py -- <repo>/assets/models/characters/v2

Writes player_v2.glb and goalkeeper_v2.glb (+ the .blend sources in src/ and clips.json with the locomotion
clip speeds). Everything is generated from this file, so the result is reproducible and can be changed here.

Contract with the game (docs/PLAYER_CHARACTER_V2.md): 1 unit = 1 m, facing -Z in Godot (+Y in Blender), origin
between the feet; one armature `<Player|Goalkeeper>_Rig`; the 18 bones of the v1 rig keep their names, parents and
joint positions (face/hair builders and generated clips depend on them) and the rig adds shoulders, fingers, toes;
material names end with Skin Hair Jersey Trim Shorts Socks Boots Dark Number (+ Glove); hair meshes are
`*_Hair_<Short|Buzz|Afro|Long>` and `*_Beard`. Leg IK (IK_Foot_*, Pole_Knee_*) is used to author the clips and is
baked into the deform bones on export, so the GLB contains plain FK animation.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

FPS = 30
ANKLE = 0.09            # ankle joint height at rest (m)
LEG_REACH = 0.818       # hip joint -> ankle, slightly under the straight-leg length so the knee never locks

# ------------------------------------------------------------------------------------------------ skeleton
# name: (head, tail, parent, deform). Left side is -X (the model faces +Y in Blender).
V1 = {
    "Root": ((0, 0, 0), (0, 0, 0.93), None),
    "Hips": ((0, 0, 0.93), (0, 0, 1.02), "Root"),
    "Spine": ((0, 0, 1.02), (0, 0, 1.22), "Hips"),
    "Chest": ((0, 0, 1.22), (0, 0, 1.46), "Spine"),
    "Neck": ((0, 0, 1.46), (0, 0, 1.56), "Chest"),
    "Head": ((0, 0, 1.56), (0, 0, 1.66), "Neck"),
    "UpperArm_L": ((-0.2, 0, 1.43), (-0.303, 0, 1.148), "Shoulder_L"),
    "LowerArm_L": ((-0.303, 0, 1.148), (-0.359, 0, 0.884), "UpperArm_L"),
    "Hand_L": ((-0.359, 0, 0.884), (-0.371, 0, 0.815), "LowerArm_L"),
    "UpperLeg_L": ((-0.095, 0, 0.92), (-0.1, 0, 0.5), "Hips"),
    "LowerLeg_L": ((-0.1, 0, 0.5), (-0.1, 0, ANKLE), "UpperLeg_L"),
    "Foot_L": ((-0.1, 0, ANKLE), (-0.1, 0.13, 0.028), "LowerLeg_L"),
    "Toes_L": ((-0.1, 0.13, 0.028), (-0.1, 0.215, 0.022), "Foot_L"),
    "Shoulder_L": ((-0.035, 0, 1.425), (-0.2, 0, 1.43), "Chest"),
}
FINGERS = {  # name: (base offset from the palm end (y, x), segment lengths)
    "Index": (0.026, [0.032, 0.024, 0.019]), "Middle": (0.009, [0.034, 0.025, 0.02]),
    "Ring": (-0.008, [0.031, 0.023, 0.018]), "Pinky": (-0.024, [0.025, 0.018, 0.015]),
}


def bone_table():
    out = {}
    for name, (h, t, p) in V1.items():
        out[name] = (Vector(h), Vector(t), p, name != "Root" or True)
        if name.endswith("_L"):
            m = lambda v: Vector((-v[0], v[1], v[2]))
            out[name[:-2] + "_R"] = (m(h), m(t), p[:-2] + "_R" if p and p.endswith("_L") else p, True)
    for side, sx in (("L", -1), ("R", 1)):
        palm = Vector((0.374 * sx, 0, 0.812))
        for f, (dy, segs) in FINGERS.items():
            head = palm + Vector((0.002 * sx, dy, 0))
            d = Vector((0.06 * sx, 0, -1)).normalized()
            parent = "Hand_" + side
            for i, ln in enumerate(segs):
                name = "%s%d_%s" % (f, i + 1, side)
                out[name] = (head.copy(), head + d * ln, parent, True)
                parent, head = name, head + d * ln
        head = Vector((0.351 * sx, 0.026, 0.862))
        d = Vector((0.12 * sx, 0.55, -0.82)).normalized()
        parent = "Hand_" + side
        for i, ln in enumerate([0.032, 0.026]):
            name = "Thumb%d_%s" % (i + 1, side)
            out[name] = (head.copy(), head + d * ln, parent, True)
            parent, head = name, head + d * ln
        # controls (not exported): IK target with the Foot bone's rest, knee pole in front of the knee
        foot = out["Foot_" + side]
        out["IK_Foot_" + side] = (foot[0].copy(), foot[1].copy(), None, False)
        out["Pole_Knee_" + side] = (Vector((0.1 * sx, 0.55, 0.5)), Vector((0.1 * sx, 0.6, 0.5)), None, False)
    return out


def build_armature(rig_name):
    data = bpy.data.armatures.new(rig_name)
    arm = bpy.data.objects.new(rig_name, data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    table = bone_table()
    for name, (h, t, _p, deform) in table.items():
        eb = data.edit_bones.new(name)
        eb.head, eb.tail, eb.roll = h, t, 0.0
        eb.use_deform = deform
    for name, (_h, _t, p, _d) in table.items():
        if p:
            eb = data.edit_bones[name]
            eb.parent = data.edit_bones[p]
            eb.use_connect = (eb.head - eb.parent.tail).length < 1e-4 and not name.startswith(("Hips", "UpperLeg"))
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def setup_leg_ik(arm):
    for side in ("L", "R"):
        ll = arm.pose.bones["LowerLeg_" + side]
        c = ll.constraints.new("IK")
        c.name = "IK"
        c.target, c.subtarget = arm, "IK_Foot_" + side
        c.pole_target, c.pole_subtarget = arm, "Pole_Knee_" + side
        c.chain_count = 2
        c.use_tail = True
        foot = arm.pose.bones["Foot_" + side]
        cr = foot.constraints.new("COPY_ROTATION")
        cr.name = "IKRot"
        cr.target, cr.subtarget = arm, "IK_Foot_" + side
        # pole angle: bend the leg (target raised 25 cm) and keep the angle whose knee points straight forward
        ik = arm.pose.bones["IK_Foot_" + side]
        ik.location = arm.data.bones[ik.name].matrix_local.to_quaternion().inverted() @ Vector((0, 0, 0.25))
        best = None
        for ang in range(-180, 181, 15):
            c.pole_angle = math.radians(ang)
            bpy.context.view_layer.update()
            knee = arm.matrix_world @ ll.head
            foot_x = arm.data.bones[ll.name].tail_local.x
            score = knee.y - 4.0 * abs(knee.x - foot_x)
            if best is None or score > best[1]:
                best = (ang, score, knee.copy())
        c.pole_angle = math.radians(best[0])
        ik.location = Vector()
        bpy.context.view_layer.update()
        print("pole angle %s: %d deg (bent-knee test: knee at %s)" % (side, best[0], tuple(round(v, 3) for v in best[2])))


# ------------------------------------------------------------------------------------------------ meshes
def new_obj(name, me):
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def evaluated_copy(obj, name):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    me.name = name
    bpy.data.objects.remove(obj)
    return new_obj(name, me)


def skin_mesh(name, verts, edges, radii, root=0, subdiv=1):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, edges, [])
    o = new_obj(name, me)
    sk = o.modifiers.new("Skin", "SKIN")
    sk.branch_smoothing = 0.6
    sk.use_smooth_shade = True
    for i, r in enumerate(radii):
        sv = me.skin_vertices[0].data[i]
        sv.radius = r
        sv.use_root = (i == root)
    if subdiv:
        sd = o.modifiers.new("Sub", "SUBSURF")
        sd.levels = sd.render_levels = subdiv
    return evaluated_copy(o, name)


def ellipsoid(name, center, radii, segs=24, rings=16):
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(center)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return new_obj(name, me)


def cylinder_between(name, a, b, r, segs=8):
    import bmesh
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r * 0.9, depth=(b - a).length)
    rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return new_obj(name, me)


SKIN_SCALE = 1.24


def body_skin():
    """Torso, arms, legs and boots as one connected skin-modifier surface."""
    V, E, R = [], [], []

    def add(p, r, link=None):
        V.append(p)
        R.append((r[0] * SKIN_SCALE, r[1] * SKIN_SCALE))
        i = len(V) - 1
        if link is not None:
            E.append((link, i))
        return i

    pel = add((0, 0, 0.925), (0.150, 0.104))
    a = add((0, 0, 1.03), (0.139, 0.096), pel)
    a = add((0, 0, 1.12), (0.133, 0.092), a)
    a = add((0, 0.003, 1.24), (0.152, 0.1), a)
    chest = add((0, 0.006, 1.34), (0.17, 0.106), a)
    up = add((0, 0, 1.415), (0.163, 0.098), chest)
    a = add((0, 0, 1.48), (0.068, 0.064), up)
    a = add((0, 0.004, 1.55), (0.055, 0.055), a)
    add((0, 0.006, 1.61), (0.05, 0.052), a)
    for sx in (-1, 1):
        a = add((0.115 * sx, 0, 1.44), (0.066, 0.066), up)
        a = add((0.2 * sx, 0, 1.425), (0.06, 0.06), a)
        a = add((0.25 * sx, 0, 1.29), (0.049, 0.051), a)
        a = add((0.303 * sx, 0, 1.148), (0.039, 0.039), a)
        a = add((0.33 * sx, 0, 1.02), (0.036, 0.034), a)
        add((0.356 * sx, 0, 0.895), (0.026, 0.022), a)
        a = add((0.092 * sx, 0, 0.885), (0.088, 0.09), pel)
        a = add((0.097 * sx, 0.004, 0.74), (0.082, 0.084), a)
        a = add((0.1 * sx, 0.004, 0.585), (0.062, 0.064), a)
        a = add((0.1 * sx, 0.009, 0.5), (0.056, 0.058), a)
        a = add((0.1 * sx, -0.012, 0.36), (0.056, 0.064), a)
        a = add((0.1 * sx, -0.004, 0.22), (0.042, 0.045), a)
        ank = add((0.1 * sx, 0, 0.105), (0.038, 0.04), a)
        add((0.1 * sx, -0.04, 0.045), (0.04, 0.036), ank)           # heel
        a = add((0.1 * sx, 0.06, 0.045), (0.046, 0.034), ank)
        a = add((0.1 * sx, 0.135, 0.034), (0.045, 0.028), a)
        add((0.1 * sx, 0.205, 0.03), (0.034, 0.022), a)
    o = skin_mesh("BodySkin", V, E, R, root=pel, subdiv=1)
    for v in o.data.vertices:                                       # flat soles
        if v.co.z < 0.004:
            v.co.z = 0.0
    return o


def head_parts():
    head = ellipsoid("Head", (0, 0.002, 1.677), (0.093, 0.101, 0.122), 28, 18)
    for v in head.data.vertices:                                    # narrower jaw, flatter back
        if v.co.z < 1.65:
            k = 1.0 - 0.25 * min(1.0, (1.65 - v.co.z) / 0.09)
            v.co.x *= k
            if v.co.y > 0:
                v.co.y = v.co.y * (0.92 + 0.08 * k)
        if v.co.y < -0.06:
            v.co.y = -0.06 + (v.co.y + 0.06) * 0.85
    parts = [head,
             ellipsoid("Nose", (0, 0.101, 1.666), (0.012, 0.02, 0.021), 10, 8),
             ellipsoid("Ear_L", (-0.092, -0.002, 1.676), (0.011, 0.021, 0.03), 10, 8),
             ellipsoid("Ear_R", (0.092, -0.002, 1.676), (0.011, 0.021, 0.03), 10, 8)]
    dark = [ellipsoid("Eye_L", (-0.033, 0.091, 1.69), (0.0105, 0.006, 0.0095), 10, 8),
            ellipsoid("Eye_R", (0.033, 0.091, 1.69), (0.0105, 0.006, 0.0095), 10, 8),
            ellipsoid("Mouth", (0, 0.094, 1.628), (0.02, 0.005, 0.0055), 12, 6)]
    brows = [ellipsoid("Brow_L", (-0.034, 0.094, 1.716), (0.017, 0.005, 0.0045), 10, 6),
             ellipsoid("Brow_R", (0.034, 0.094, 1.716), (0.017, 0.005, 0.0045), 10, 6)]
    return parts, dark, brows


def hand_parts(side):
    sx = -1 if side == "L" else 1
    out = [ellipsoid("Palm_" + side, (0.366 * sx, 0.0, 0.846), (0.014, 0.04, 0.042), 14, 10)]
    table = bone_table()
    for name, (h, t, p, _d) in table.items():
        if name.endswith("_" + side) and name[:-2].rstrip("0123456789") in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
            r = 0.0095 if name.startswith("Thumb") else 0.0085
            if name.startswith("Pinky"):
                r = 0.0075
            out.append(cylinder_between("F_" + name, h, t + (t - h).normalized() * 0.004, r))
    return out


def join(objs, name):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


# ------------------------------------------------------------------------------------------------ materials
COLORS = {"Skin": (0.78, 0.57, 0.44), "Hair": (0.12, 0.08, 0.05), "Jersey": (0.92, 0.92, 0.92), "Trim": (0.1, 0.1, 0.12),
          "Shorts": (0.1, 0.1, 0.12), "Socks": (0.92, 0.92, 0.92), "Boots": (0.05, 0.05, 0.05), "Dark": (0.03, 0.02, 0.02),
          "Number": (1, 1, 1), "Glove": (0.9, 0.85, 0.2)}


def materials(prefix, keeper):
    out = {}
    for k, c in COLORS.items():
        if k == "Glove" and not keeper:
            continue
        m = bpy.data.materials.new(prefix + k)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*c, 1.0)
        m.diffuse_color = (*c, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.75 if k in ("Jersey", "Shorts", "Socks") else 0.55
        out[k] = m
    return out


def kit_region(c, keeper):
    """Material slot for a body-skin polygon centred at c (rest pose)."""
    ax = abs(c.x)
    arm = ax > 0.205 or (ax > 0.178 and c.z > 1.37)
    if arm:
        if keeper:
            return "Trim" if 0.905 < c.z < 0.925 else ("Jersey" if c.z >= 0.925 else "Skin")
        return "Trim" if 1.232 < c.z < 1.256 else ("Jersey" if c.z >= 1.256 else "Skin")
    if c.z < 0.125 or (c.z < 0.15 and c.y > 0.05):
        return "Boots"
    if c.z < 0.405:
        return "Socks"
    if c.z < 0.44:
        return "Trim"
    if c.z < (0.47 if keeper else 0.6):
        return "Skin"
    if c.z < 0.62 and not keeper:
        return "Trim"
    if keeper and c.z < 0.6:
        return "Shorts"         # keeper: long shorts
    if c.z < 0.985:
        return "Shorts"
    if c.z < 1.468 or (c.z < 1.5 and ax > 0.085):          # the shoulders stay jersey; the collar is a narrow band
        return "Jersey"
    if c.z < 1.5:
        return "Trim"
    return "Skin"


def assign(obj, mats, slot_of):
    obj.data.materials.clear()
    order = list(mats.keys())
    for k in order:
        obj.data.materials.append(mats[k])
    for p in obj.data.polygons:
        p.material_index = order.index(slot_of(p))


def uv_unwrap(obj):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")


def number_patch(body):
    """Curved quad on the back of the shirt, UV 0..1 (the game maps it into the number atlas)."""
    cols, rows = 6, 4
    x0, x1, z0, z1 = -0.142, 0.142, 1.12, 1.355
    vs = [body.matrix_world @ v.co for v in body.data.vertices]
    verts, faces, uvs = [], [], []
    for j in range(rows + 1):
        for i in range(cols + 1):
            x = x0 + (x1 - x0) * i / cols
            z = z0 + (z1 - z0) * j / rows
            near = [v.y for v in vs if abs(v.x - x) < 0.03 and abs(v.z - z) < 0.03 and v.y < 0]
            y = (min(near) if near else -0.1) - 0.004
            verts.append((x, y, z))
            uvs.append((i / cols, j / rows))
    for j in range(rows):
        for i in range(cols):
            a = j * (cols + 1) + i
            faces.append((a, a + cols + 1, a + cols + 2, a + 1))       # normals face -Y (backwards)
    me = bpy.data.meshes.new("NumberPatch")
    me.from_pydata(verts, [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        for li in p.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    return new_obj("NumberPatch", me)


def hair_meshes(prefix, mats):
    out = []

    def cap(name, center, radii, keep):
        o = ellipsoid(name, center, radii, 32, 20)
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(o.data)
        drop = [f for f in bm.faces if not keep(f.calc_center_median())]
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        bm.to_mesh(o.data)
        bm.free()
        o.data.materials.append(mats["Hair"])
        return o

    def line(c):                                                    # hairline height by front/back position
        return 1.645 + 0.075 * max(c.y, 0.0) / 0.1 - 0.05 * max(-c.y, 0.0) / 0.1

    out.append(cap(prefix + "Hair_Short", (0, -0.003, 1.686), (0.1, 0.108, 0.128), lambda c: c.z > line(c)))
    out.append(cap(prefix + "Hair_Buzz", (0, 0.0, 1.68), (0.096, 0.104, 0.125), lambda c: c.z > line(c) + 0.005))
    out.append(cap(prefix + "Hair_Afro", (0, -0.012, 1.72), (0.135, 0.142, 0.15), lambda c: c.z > line(c) + 0.012))
    out.append(cap(prefix + "Hair_Long", (0, -0.012, 1.668), (0.104, 0.114, 0.15),
                   lambda c: c.z > line(c) or (c.y < 0.01 and c.z > 1.5 and abs(c.x) < 0.11)))
    out.append(cap(prefix + "Beard", (0, 0.004, 1.672), (0.097, 0.106, 0.126),
                   lambda c: 1.55 < c.z < 1.662 and c.y > 0.012 and not (abs(c.x) < 0.026 and c.z > 1.612)))
    return out


# ------------------------------------------------------------------------------------------------ weights
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def distance_weights(obj, bones, arm, power=4.0, keep=3):
    """Smooth weights from the distance to each listed bone's segment (top `keep`, normalised)."""
    segs = {b: (arm.data.bones[b].head_local, arm.data.bones[b].tail_local) for b in bones}
    groups = {b: obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b) for b in bones}
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        w = sorted(((1.0 / max(seg_dist(p, *segs[b]), 0.004) ** power, b) for b in bones), reverse=True)[:keep]
        s = sum(x for x, _ in w)
        for x, b in w:
            if x / s > 0.02:
                groups[b].add([v.index], x / s, "REPLACE")


def rigid(obj, bone):
    g = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    g.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")


def auto_weights(obj, arm):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # remove weights of non-deform bones, find vertices bone heat missed
    deform = {b.name for b in arm.data.bones if b.use_deform}
    for g in list(obj.vertex_groups):
        # Root runs from the ground up through the crotch but never moves: vertices bound to it tear away from the
        # hips (spikes in dives and slides). It stays in the skeleton (v1 compatibility) without geometry.
        if g.name not in deform or g.name == "Root":
            obj.vertex_groups.remove(g)
    clean_regions(obj)
    missing = [v.index for v in obj.data.vertices if not v.groups]
    return missing


ARM_BONES = ("Shoulder", "UpperArm", "LowerArm", "Hand", "Thumb", "Index", "Middle", "Ring", "Pinky")
LEG_BONES = ("UpperLeg", "LowerLeg", "Foot", "Toes")


def clean_regions(obj):
    """Bone heat leaks between parts that touch at rest (the hands hang beside the hips). An arm vertex keeps only
    arm/upper-body bones, a torso or leg vertex never follows an arm bone, a leg never the other leg. The crotch is
    shared by both thighs and the hips, so it stretches evenly instead of tearing."""
    names = {g.index: g.name for g in obj.vertex_groups}
    for v in obj.data.vertices:
        c = v.co
        ax = abs(c.x)
        is_arm = ax > 0.205 or (ax > 0.178 and c.z > 1.37)
        side = "L" if c.x < 0 else "R"
        for g in list(v.groups):
            n = names[g.group]
            bad = False
            if is_arm:
                bad = n.startswith(LEG_BONES) or n == "Hips" or (n.startswith(ARM_BONES) and not n.endswith("_" + side))
            else:
                bad = n.startswith(ARM_BONES[1:]) or (n.startswith("Shoulder") and c.z < 1.3)
                if c.z < 0.86 and n.startswith(LEG_BONES) and ax > 0.035 and not n.endswith("_" + side):
                    bad = True
            if bad:
                obj.vertex_groups[g.group].remove([v.index])
        if not is_arm and ax < 0.035 and 0.78 < c.z < 0.93:              # crotch
            for b, w in (("UpperLeg_L", 0.35), ("UpperLeg_R", 0.35), ("Hips", 0.3)):
                (obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b)).add([v.index], w, "REPLACE")
            for g in list(v.groups):
                if names.get(g.group) not in ("UpperLeg_L", "UpperLeg_R", "Hips"):
                    obj.vertex_groups[g.group].remove([v.index])
        names = {g.index: g.name for g in obj.vertex_groups}


def limit_and_normalize(obj, limit=4):
    for v in obj.data.vertices:
        gs = sorted(((g.weight, g.group) for g in v.groups), reverse=True)
        for _w, gi in gs[limit:]:
            obj.vertex_groups[gi].remove([v.index])
        top = gs[:limit]
        s = sum(w for w, _ in top) or 1.0
        for w, gi in top:
            obj.vertex_groups[gi].add([v.index], w / s, "REPLACE")


# ------------------------------------------------------------------------------------------------ posing
def qm(p=0.0, r=0.0, y=0.0):
    """Rotation about model axes in degrees: pitch about X (+ swings a downward bone forward / leans an upward
    bone back), roll about Y (+ moves a downward bone toward -X, the character's left), yaw about Z (+ = turn left)."""
    return Euler((math.radians(p), math.radians(r), math.radians(y)), "XYZ").to_quaternion()


class Poser:
    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
        self.head = {b.name: b.head_local.copy() for b in arm.data.bones}
        self.keyed = [pb.name for pb in arm.pose.bones]

    def local(self, bone, q):
        r = self.rest[bone]
        return r.inverted() @ q @ r

    def apply(self, spec):
        """spec: fk {bone: (p, r, y)}, hips (dx, dy, dz, p, r, y), feet {L/R: (x, y, z, pitch, yaw)}, ik 0..1."""
        arm = self.arm
        for pb in arm.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        for b, e in spec.get("fk", {}).items():
            arm.pose.bones[b].rotation_quaternion = self.local(b, qm(*e))
        h = spec.get("hips", (0, 0, 0, 0, 0, 0))
        hb = arm.pose.bones["Hips"]
        hb.location = self.rest["Hips"].inverted() @ Vector(h[:3])
        hb.rotation_quaternion = self.local("Hips", qm(*h[3:]))
        hip_world = {s: self.hip_joint(s, h) for s in ("L", "R")}
        for s in ("L", "R"):
            f = spec.get("feet", {}).get(s)
            if f is None:
                f = (-0.105 if s == "L" else 0.105, 0.0, ANKLE, 0.0, 0.0)
            pos = Vector(f[:3])
            hw = hip_world[s]
            d = pos - hw
            if d.length > LEG_REACH:                       # out of reach: keep x/y, raise the ankle (heel/toe roll)
                horiz = Vector((d.x, d.y, 0.0))
                dz = math.sqrt(max(LEG_REACH ** 2 - horiz.length_squared, 0.0))
                pos.z = hw.z - dz if horiz.length < LEG_REACH else hw.z - 0.05
            ik = arm.pose.bones["IK_Foot_" + s]
            ik.location = self.rest["IK_Foot_" + s].inverted() @ (pos - self.head["IK_Foot_" + s])
            ik.rotation_quaternion = self.local("IK_Foot_" + s, qm(f[3], 0.0, f[4] if len(f) > 4 else 0.0))
            pole = arm.pose.bones["Pole_Knee_" + s]
            yaw = h[5] + (f[4] if len(f) > 4 else 0.0) * 0.5
            pole_pos = Vector((pos.x, pos.y, 0.5 + h[2])) + Quaternion(Vector((0, 0, 1)), math.radians(yaw)) @ Vector((0, 0.55, 0))
            pole.location = self.rest["Pole_Knee_" + s].inverted() @ (pole_pos - self.head["Pole_Knee_" + s])
            for cn in ("IK",):
                arm.pose.bones["LowerLeg_" + s].constraints[cn].influence = spec.get("ik", 1.0)
            arm.pose.bones["Foot_" + s].constraints["IKRot"].influence = spec.get("ik", 1.0)

    def hip_joint(self, side, h):
        q = qm(*h[3:])
        base = Vector((0, 0, 0.93))
        off = self.head["UpperLeg_" + side] - base
        return base + Vector(h[:3]) + q @ off

    def key(self, frame):
        for pb in self.arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
            if pb.name in ("Hips",) or pb.name.startswith(("IK_", "Pole_")):
                pb.keyframe_insert("location", frame=frame, group=pb.name)
        for s in ("L", "R"):
            self.arm.pose.bones["LowerLeg_" + s].constraints["IK"].keyframe_insert("influence", frame=frame)
            self.arm.pose.bones["Foot_" + s].constraints["IKRot"].keyframe_insert("influence", frame=frame)


def lerp(a, b, t):
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    return tuple(lerp(x, y, t) for x, y in zip(a, b))


def smooth(t):
    return t * t * (3 - 2 * t)


def blend_specs(a, b, t):
    out = {"fk": {}, "feet": {}}
    t = smooth(t)
    for k in set(a.get("fk", {})) | set(b.get("fk", {})):
        out["fk"][k] = lerp(a.get("fk", {}).get(k, (0, 0, 0)), b.get("fk", {}).get(k, (0, 0, 0)), t)
    out["hips"] = lerp(a.get("hips", (0,) * 6), b.get("hips", (0,) * 6), t)
    for s in ("L", "R"):
        da = a.get("feet", {}).get(s, STAND_FEET[s])
        db = b.get("feet", {}).get(s, STAND_FEET[s])
        out["feet"][s] = lerp(tuple(da) + (0,) * (5 - len(da)), tuple(db) + (0,) * (5 - len(db)), t)
    out["ik"] = lerp(a.get("ik", 1.0), b.get("ik", 1.0), t)
    return out


STAND_FEET = {"L": (-0.11, 0.0, ANKLE, 0.0, 6.0), "R": (0.11, 0.0, ANKLE, 0.0, -6.0)}
ARMS_DOWN = {"UpperArm_L": (2, -13, 0), "UpperArm_R": (2, 13, 0), "LowerArm_L": (12, 0, 0), "LowerArm_R": (12, 0, 0),
             "Hand_L": (0, 0, 0), "Hand_R": (0, 0, 0)}
RELAXED_FINGERS = {}
for _s, _curl in (("L", -1), ("R", 1)):            # left palm faces +X (curl = -roll), right palm faces -X (+roll)
    for _f in ("Index", "Middle", "Ring", "Pinky"):
        for _i, _a in enumerate((22, 28, 18)):
            RELAXED_FINGERS["%s%d_%s" % (_f, _i + 1, _s)] = (0, _curl * _a, 0)
    RELAXED_FINGERS["Thumb1_" + _s] = (0, _curl * 10, 0)


def pose(fk=None, hips=(0, 0, 0, 0, 0, 0), feet=None, ik=1.0, arms=True):
    d = dict(RELAXED_FINGERS)
    if arms:
        d.update(ARMS_DOWN)
    d.update(fk or {})
    f = dict(STAND_FEET)
    f.update(feet or {})
    return {"fk": d, "hips": hips, "feet": f, "ik": ik}


def keyed_clip(poser, name, keys, loop=False):
    """keys: [(time_s, spec)] - sampled every frame with smoothstep blends between key poses."""
    act = start_action(poser.arm, name)
    end = int(round(keys[-1][0] * FPS))
    for fr in range(end + 1):
        t = fr / FPS
        for i in range(len(keys) - 1):
            if keys[i][0] <= t <= keys[i + 1][0] + 1e-6:
                k = (t - keys[i][0]) / max(keys[i + 1][0] - keys[i][0], 1e-6)
                poser.apply(blend_specs(keys[i][1], keys[i + 1][1], k))
                break
        poser.key(fr)
    return finish_action(act, loop)


def start_action(arm, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    return act


def finish_action(act, loop):
    act["loop"] = loop
    return act


# ------------------------------------------------------------------------------------------------ clips
def gait_clip(poser, name, speed, period, duty, lift, bob, lean, arm_amp, elbow, hips_yaw, head=0.0, width=0.105,
              arm_out=0.0, knee_lift=0.0, sink=0.03):
    """Locomotion cycle in place. Each foot is planted for `duty` of the cycle and moves backwards at exactly
    `speed` while planted, so at that ground speed the feet do not slide (clips.json records the speed)."""
    act = start_action(poser.arm, name)
    frames = int(round(period * FPS))
    stride = speed * period                          # distance the body travels in one cycle
    half = duty * stride / 2.0
    for fr in range(frames + 1):
        t = fr / frames
        feet = {}
        legs_fwd = {}
        for s, ph in (("L", 0.0), ("R", 0.5)):
            u = (t + ph) % 1.0
            x = -width if s == "L" else width
            if u < duty:                              # stance: planted, moving back at `speed`
                k = u / duty
                y = half - 2 * half * k
                z = ANKLE
                pitch = 8.0 * (1 - k) ** 3 - 22.0 * k ** 4            # heel strike -> toe off
            else:                                     # swing: forward on an arc
                k = (u - duty) / (1 - duty)
                y = -half + 2 * half * (0.5 - 0.5 * math.cos(math.pi * k))
                z = ANKLE + lift * math.sin(math.pi * k) ** 1.3 + knee_lift * math.sin(math.pi * k) ** 2
                pitch = -25.0 * (1 - k) ** 2 + 12.0 * math.sin(math.pi * k) * k
            feet[s] = (x, y, z, pitch, 6.0 if s == "L" else -6.0)
            legs_fwd[s] = math.cos(2 * math.pi * u)  # +1 when this foot is furthest forward
        dz = -bob * (0.5 + 0.5 * math.cos(4 * math.pi * (t - duty / 2))) - sink
        yaw = hips_yaw * legs_fwd["R"] * -1.0
        fk = {
            "Spine": (-lean * 0.55, 0, -yaw * 0.6), "Chest": (-lean * 0.35, 0, -yaw * 0.9),
            "Neck": (lean * 0.4, 0, yaw * 0.6), "Head": (lean * 0.45 + head, 0, yaw * 0.4),
            "UpperArm_L": (-arm_amp * legs_fwd["L"], -9 + arm_out, 0), "UpperArm_R": (-arm_amp * legs_fwd["R"], 9 - arm_out, 0),
            "LowerArm_L": (elbow + elbow * 0.25 * legs_fwd["R"], 0, 0), "LowerArm_R": (elbow + elbow * 0.25 * legs_fwd["L"], 0, 0),
            "Toes_L": (max(0.0, -feet["L"][3]) * 0.8, 0, 0), "Toes_R": (max(0.0, -feet["R"][3]) * 0.8, 0, 0),
        }
        fk.update({k: v for k, v in RELAXED_FINGERS.items()})
        poser.apply({"fk": fk, "hips": (0, 0, dz, -lean * 0.25, 0, yaw), "feet": feet, "ik": 1.0})
        poser.key(fr)
    return finish_action(act, True)


def idle_clip(poser, name="Idle", crouch=0.0, wide=0.0, arms=None, period=2.4):
    act = start_action(poser.arm, name)
    frames = int(round(period * FPS))
    for fr in range(frames + 1):
        t = fr / frames
        br = math.sin(2 * math.pi * t)
        sway = math.sin(2 * math.pi * t + 0.6)
        fk = dict(arms or ARMS_DOWN)
        fk.update(RELAXED_FINGERS)
        fk.update({"Spine": (-1.5 - crouch * 60, 0, 0), "Chest": (1.2 * br - crouch * 40, 0, 0), "Head": (-1.0 * br + crouch * 70, 0, 1.5 * sway)})
        if arms is None:
            fk["UpperArm_L"] = (2 + 1.5 * br, -13, 0)
            fk["UpperArm_R"] = (2 + 1.5 * br, 13, 0)
        feet = {"L": (-0.11 - wide, 0.0, ANKLE, 0, 6), "R": (0.11 + wide, 0.0, ANKLE, 0, -6)}
        poser.apply({"fk": fk, "hips": (0.008 * sway, 0, -0.012 - crouch - 0.004 * br, -crouch * 30, -1.2 * sway, 0), "feet": feet})
        poser.key(fr)
    return finish_action(act, True)


def kick_keys(power, lean_back=0.0, lift=0.0, inside=False):
    """Right-foot strike: plant left beside the ball, back-swing, contact, follow-through."""
    plant = {"L": (-0.13, 0.12, ANKLE, 0, 10)}
    arms_open = {"UpperArm_L": (15, 22 + 12 * power, 0), "UpperArm_R": (-10, -12, 0), "LowerArm_L": (25, 0, 0), "LowerArm_R": (20, 0, 0)}
    yaw_foot = 55.0 if inside else 0.0
    toe = 0.0 if inside else -35.0 * power
    t = 0.7 + 0.25 * power
    return [
        (0.0, pose()),
        (0.18 * t, pose(fk={"Spine": (-4, 0, -6), **arms_open}, hips=(0, 0.05, -0.03, -3, 0, -6), feet={**plant, "R": (0.11, -0.05, 0.12, -10, -6)})),
        (0.38 * t, pose(fk={"Spine": (-2 + lean_back, -4, -12 * power), "Chest": (lean_back * 0.6, 0, -6), **arms_open},
                        hips=(0, 0.06, -0.05, -2, 4, -12 * power),
                        feet={**plant, "R": (0.13, -0.34 - 0.16 * power, 0.3 + 0.2 * power, -50, -6)})),
        (0.52 * t, pose(fk={"Spine": (-6 + lean_back, 0, 4), "Chest": (lean_back * 0.6, 0, 6), **arms_open},
                        hips=(0, 0.08, -0.04, -4, 0, 8),
                        feet={**plant, "R": (0.07, 0.16, 0.12 + lift * 0.3, toe, -yaw_foot)})),
        (0.68 * t, pose(fk={"Spine": (-8 + lean_back * 1.2, 0, 10), "Chest": (lean_back, 0, 8), **arms_open},
                        hips=(0, 0.1, -0.02, -6 + lean_back * 0.5, 0, 14),
                        feet={**plant, "R": (0.04, 0.38 + 0.16 * power, 0.32 + 0.38 * power + lift, toe * 0.5, -yaw_foot * 0.5)})),
        (1.0 * t, pose()),
    ]


def build_clips(poser, keeper):
    speeds = {}

    def g(name, speed, *a, **k):
        gait_clip(poser, name, speed, *a, **k)
        speeds[name] = speed

    idle_clip(poser)
    # (speed m/s, period s, duty, swing lift, bob, lean deg, arm swing deg, elbow deg, hips yaw deg); planted half-stance
    # = duty * speed * period / 2 stays <= ~0.33 m, which the leg reaches with the hips lowered by `sink`.
    g("Walk", 1.45, 1.0, 0.45, 0.07, 0.012, 2.0, 18, 12, 5, sink=0.03)
    g("Jog", 3.2, 0.72, 0.28, 0.13, 0.022, 6.0, 30, 60, 7, sink=0.05)
    g("Run", 5.0, 0.64, 0.2, 0.2, 0.03, 10.0, 42, 85, 9, knee_lift=0.05, sink=0.065)
    g("Sprint", 7.4, 0.58, 0.15, 0.26, 0.035, 16.0, 58, 95, 10, head=-6, knee_lift=0.09, sink=0.075)
    g("Dribble", 4.0, 0.62, 0.24, 0.12, 0.022, 9.0, 30, 70, 8, head=18, arm_out=10, sink=0.07)
    # one-shots
    keyed_clip(poser, "Shoot", kick_keys(1.0, lean_back=2.0))
    keyed_clip(poser, "Kick", kick_keys(0.9, lean_back=2.0))                    # v1 name, used as a fallback
    keyed_clip(poser, "Pass", kick_keys(0.45, inside=True))
    keyed_clip(poser, "LongPass", kick_keys(0.85, lean_back=9.0, lift=0.12))
    open_arms = {"UpperArm_L": (10, 20, 0), "UpperArm_R": (10, -20, 0), "LowerArm_L": (25, 0, 0), "LowerArm_R": (25, 0, 0)}
    keyed_clip(poser, "FirstTouch", [
        (0.0, pose()),
        (0.15, pose(fk={**open_arms, "Head": (12, 0, 0), "Spine": (-5, 0, 0)}, hips=(0, 0, -0.04, -3, 0, 0), feet={"R": (0.1, 0.14, 0.2, 12, -8)})),
        (0.32, pose(fk={**open_arms, "Head": (16, 0, 0), "Spine": (-6, 0, 0)}, hips=(0, 0, -0.06, -3, 0, 0), feet={"R": (0.1, 0.03, 0.13, 5, -8)})),
        (0.6, pose())])
    speeds["BallControl"] = 0.0
    act = bpy.data.actions["FirstTouch"].copy()
    act.name = "BallControl"
    act.use_fake_user = True
    keyed_clip(poser, "Tackle", [
        (0.0, pose()),
        (0.25, pose(fk={"Spine": (-14, 0, 8), "Chest": (-6, 0, 4), "UpperArm_L": (30, 15, 0), "UpperArm_R": (-15, -10, 0)},
                    hips=(0, 0.12, -0.13, -8, 3, 10), feet={"L": (-0.14, 0.38, ANKLE, 0, 12)})),
        (0.45, pose(fk={"Spine": (-18, 0, 10), "Chest": (-8, 0, 6), "UpperArm_L": (35, 20, 0), "UpperArm_R": (-20, -15, 0)},
                    hips=(0.03, 0.18, -0.16, -10, 6, 14), feet={"L": (-0.14, 0.38, ANKLE, 0, 12), "R": (0.32, 0.42, 0.11, 0, -60)})),
        (0.65, pose(fk={"Spine": (-10, 0, 4)}, hips=(0, 0.12, -0.1, -6, 2, 6), feet={"L": (-0.14, 0.38, ANKLE, 0, 12), "R": (0.18, 0.18, 0.12, 0, -20)})),
        (0.95, pose())])
    keyed_clip(poser, "SlideTackle", [
        (0.0, pose()),
        (0.2, pose(fk={"Spine": (-10, 0, 0)}, hips=(0, 0.15, -0.18, -6, 0, 0), feet={"L": (-0.12, 0.3, ANKLE, 0, 6)})),
        # sliding on the left hip: torso leans back ~40 deg in total, legs out in front on the ground
        (0.45, pose(fk={"Spine": (14, 0, 0), "Chest": (8, 0, 0), "Head": (-18, 0, 0), "UpperArm_L": (-35, 12, 0), "UpperArm_R": (-25, -12, 0)},
                    hips=(0, 0.42, -0.6, 18, 0, 0), feet={"L": (-0.13, 0.62, 0.1, 25, 6), "R": (0.12, 0.85, 0.16, 20, -6)})),
        (0.95, pose(fk={"Spine": (16, 0, 0), "Chest": (8, 0, 0), "Head": (-20, 0, 0), "UpperArm_L": (-40, 12, 0), "UpperArm_R": (-25, -12, 0)},
                    hips=(0, 0.62, -0.62, 20, 0, 0), feet={"L": (-0.13, 0.85, 0.1, 25, 6), "R": (0.12, 1.08, 0.14, 20, -6)})),
        (1.35, pose(fk={"Spine": (-10, 0, 0)}, hips=(0, 0.35, -0.3, -10, 0, 0), feet={"L": (-0.12, 0.55, ANKLE, 0, 6), "R": (0.12, 0.25, ANKLE, 0, -6)})),
        (1.7, pose())])
    up_arms = {"UpperArm_L": (60, 5, 0), "UpperArm_R": (60, -5, 0), "LowerArm_L": (35, 0, 0), "LowerArm_R": (35, 0, 0)}
    air = lambda h, extra=None: pose(fk={**up_arms, **(extra or {})}, hips=(0, 0, h, -4, 0, 0),
                                     feet={"L": (-0.11, 0.0, ANKLE + h + 0.05, -25, 6), "R": (0.11, 0.0, ANKLE + h + 0.05, -25, -6)})
    crouch = pose(fk={"Spine": (-12, 0, 0), "UpperArm_L": (-35, -15, 0), "UpperArm_R": (-35, 15, 0), "LowerArm_L": (30, 0, 0), "LowerArm_R": (30, 0, 0)},
                  hips=(0, -0.03, -0.17, -14, 0, 0))
    keyed_clip(poser, "Jump", [(0.0, pose()), (0.2, crouch), (0.4, air(0.28)), (0.55, air(0.3)), (0.75, crouch), (1.0, pose())])
    keyed_clip(poser, "Header", [(0.0, pose()), (0.2, crouch),
                                 (0.4, air(0.3, {"Spine": (8, 0, 0), "Chest": (8, 0, 0), "Head": (14, 0, 0)})),
                                 (0.52, air(0.32, {"Spine": (-14, 0, 0), "Chest": (-12, 0, 0), "Head": (-22, 0, 0)})),
                                 (0.78, crouch), (1.05, pose())])
    for nm, sgn in (("TurnLeft", 1), ("TurnRight", -1)):
        keyed_clip(poser, nm, [
            (0.0, pose()),
            (0.15, pose(fk={"Spine": (-4, 0, 10 * sgn), "Chest": (0, 0, 12 * sgn), "Head": (0, 0, 20 * sgn)}, hips=(0, 0, -0.04, -3, -3 * sgn, 12 * sgn),
                        feet={("L" if sgn > 0 else "R"): ((-0.2 if sgn > 0 else 0.2), 0.05, ANKLE + 0.03, 0, 40 * sgn)})),
            (0.32, pose(fk={"Spine": (-4, 0, 6 * sgn), "Head": (0, 0, 10 * sgn)}, hips=(0, 0, -0.05, -3, 0, 6 * sgn),
                        feet={("L" if sgn > 0 else "R"): ((-0.16 if sgn > 0 else 0.16), 0.04, ANKLE, 0, 30 * sgn),
                              ("R" if sgn > 0 else "L"): ((0.06 if sgn > 0 else -0.06), 0.02, ANKLE + 0.06, 0, 15 * sgn)})),
            (0.6, pose())])
    keyed_clip(poser, "Accelerate", [
        (0.0, pose()),
        (0.12, pose(fk={"Spine": (-20, 0, 0), "Chest": (-10, 0, 0), "Head": (20, 0, 0), "UpperArm_L": (50, -10, 0), "UpperArm_R": (-45, 10, 0), "LowerArm_L": (80, 0, 0), "LowerArm_R": (80, 0, 0)},
                    hips=(0, 0.04, -0.1, -12, 0, 0), feet={"L": (-0.11, 0.18, ANKLE, 0, 6), "R": (0.11, -0.3, ANKLE + 0.05, -25, -6)})),
        (0.32, pose(fk={"Spine": (-24, 0, 0), "Chest": (-10, 0, 0), "Head": (22, 0, 0), "UpperArm_L": (-45, -10, 0), "UpperArm_R": (55, 10, 0), "LowerArm_L": (80, 0, 0), "LowerArm_R": (80, 0, 0)},
                    hips=(0, 0.06, -0.08, -14, 0, 0), feet={"L": (-0.11, -0.3, ANKLE + 0.05, -25, 6), "R": (0.11, 0.25, ANKLE + 0.15, 10, -6)})),
        (0.52, pose(fk={"Spine": (-18, 0, 0), "Chest": (-8, 0, 0), "Head": (18, 0, 0), "UpperArm_L": (50, -10, 0), "UpperArm_R": (-45, 10, 0), "LowerArm_L": (80, 0, 0), "LowerArm_R": (80, 0, 0)},
                    hips=(0, 0.05, -0.06, -10, 0, 0), feet={"L": (-0.11, 0.25, ANKLE + 0.15, 10, 6), "R": (0.11, -0.3, ANKLE + 0.05, -25, -6)})),
        (0.7, pose(fk={"Spine": (-16, 0, 0), "Head": (16, 0, 0), "LowerArm_L": (80, 0, 0), "LowerArm_R": (80, 0, 0)}, hips=(0, 0, -0.05, -8, 0, 0)))])
    keyed_clip(poser, "Decelerate", [
        (0.0, pose(fk={"Spine": (-14, 0, 0), "Head": (14, 0, 0), "LowerArm_L": (70, 0, 0), "LowerArm_R": (70, 0, 0)}, hips=(0, 0, -0.05, -8, 0, 0))),
        (0.2, pose(fk={"Spine": (10, 0, 0), "Chest": (4, 0, 0), "Head": (-6, 0, 0), "UpperArm_L": (30, 15, 0), "UpperArm_R": (30, -15, 0), "LowerArm_L": (40, 0, 0), "LowerArm_R": (40, 0, 0)},
                   hips=(0, -0.06, -0.12, 6, 0, 0), feet={"L": (-0.13, 0.32, ANKLE, 18, 8), "R": (0.12, -0.12, ANKLE, 0, -6)})),
        (0.42, pose(fk={"Spine": (4, 0, 0), "UpperArm_L": (20, 10, 0), "UpperArm_R": (20, -10, 0)}, hips=(0, 0.02, -0.09, 2, 0, 0),
                    feet={"L": (-0.13, 0.28, ANKLE, 0, 8), "R": (0.12, 0.05, ANKLE + 0.04, 0, -6)})),
        (0.7, pose())])
    if keeper:
        gk_arms = {"UpperArm_L": (42, 2, 0), "UpperArm_R": (42, -2, 0), "LowerArm_L": (38, 0, 0), "LowerArm_R": (38, 0, 0),
                   "Hand_L": (0, 0, 0), "Hand_R": (0, 0, 0)}
        idle_clip(poser, "Ready", crouch=0.11, wide=0.09, arms=gk_arms, period=1.4)
        ready = pose(fk={**gk_arms, "Spine": (-12, 0, 0), "Head": (14, 0, 0)}, hips=(0, 0, -0.11, -10, 0, 0),
                     feet={"L": (-0.2, 0.0, ANKLE, 0, 8), "R": (0.2, 0.0, ANKLE, 0, -8)})
        for nm, sgn in (("DiveLeft", 1), ("DiveRight", -1)):          # upward bones: + roll tilts the top toward +X, so a dive to -X uses -roll
            reach = {"UpperArm_L": (165, -10 * sgn, 0), "UpperArm_R": (165, -10 * sgn, 0), "LowerArm_L": (5, 0, 0), "LowerArm_R": (5, 0, 0)}
            near, far = ("L", "R") if sgn > 0 else ("R", "L")
            keyed_clip(poser, nm, [
                (0.0, ready),
                (0.18, pose(fk={**gk_arms, "Spine": (-10, -8 * sgn, 0)}, hips=(-0.08 * sgn, 0, -0.2, -8, -10 * sgn, 0),
                            feet={near: (-0.3 * sgn, 0.0, ANKLE, 0, 20 * sgn), far: (0.2 * sgn, 0.0, ANKLE, 0, -8 * sgn)})),
                (0.42, pose(fk={**reach, "Spine": (0, -10 * sgn, 0), "Head": (0, -8 * sgn, 0), "UpperLeg_L": (10, 0, 0), "UpperLeg_R": (10, 0, 0)},
                            hips=(-0.75 * sgn, 0, 0.05, 0, -70 * sgn, 0), ik=0.0)),
                (0.75, pose(fk={**reach, "Spine": (0, -8 * sgn, 0), "UpperLeg_L": (12, 0, 0), "UpperLeg_R": (12, 0, 0), "LowerLeg_L": (-20, 0, 0), "LowerLeg_R": (-20, 0, 0)},
                            hips=(-1.15 * sgn, 0, -0.55, 0, -88 * sgn, 0), ik=0.0)),
                (1.15, pose(fk={"UpperArm_L": (80, -20 * sgn, 0), "UpperArm_R": (80, -20 * sgn, 0), "LowerArm_L": (60, 0, 0), "LowerArm_R": (60, 0, 0),
                                "Spine": (-15, 0, 0), "UpperLeg_L": (40, 0, 0), "UpperLeg_R": (40, 0, 0), "LowerLeg_L": (-60, 0, 0), "LowerLeg_R": (-60, 0, 0)},
                            hips=(-1.2 * sgn, 0, -0.72, 0, -90 * sgn, 0), ik=0.0)),
                (1.6, pose(fk={"UpperArm_L": (80, -20 * sgn, 0), "UpperArm_R": (80, -20 * sgn, 0), "LowerArm_L": (70, 0, 0), "LowerArm_R": (70, 0, 0),
                               "Spine": (-20, 0, 0), "UpperLeg_L": (45, 0, 0), "UpperLeg_R": (45, 0, 0), "LowerLeg_L": (-70, 0, 0), "LowerLeg_R": (-70, 0, 0)},
                           hips=(-1.2 * sgn, 0, -0.74, 0, -90 * sgn, 0), ik=0.0))])
        catch_hi = {"UpperArm_L": (165, -8, 0), "UpperArm_R": (165, 8, 0), "LowerArm_L": (15, 0, 0), "LowerArm_R": (15, 0, 0)}
        chest = {"UpperArm_L": (35, -10, 0), "UpperArm_R": (35, 10, 0), "LowerArm_L": (110, 0, 0), "LowerArm_R": (110, 0, 0)}
        keyed_clip(poser, "CatchHigh", [(0.0, ready), (0.2, crouch),
                                        (0.45, pose(fk={**catch_hi, "Head": (-12, 0, 0)}, hips=(0, 0, 0.25, 2, 0, 0),
                                                    feet={"L": (-0.11, 0, ANKLE + 0.28, -25, 6), "R": (0.11, 0, ANKLE + 0.28, -25, -6)})),
                                        (0.75, pose(fk={**chest, "Spine": (-10, 0, 0)}, hips=(0, 0, -0.12, -8, 0, 0))),
                                        (1.3, pose(fk=chest))])
        keyed_clip(poser, "CatchLow", [(0.0, ready),
                                       (0.35, pose(fk={"UpperArm_L": (55, -5, 0), "UpperArm_R": (55, 5, 0), "LowerArm_L": (15, 0, 0), "LowerArm_R": (15, 0, 0),
                                                       "Spine": (-35, 0, 0), "Chest": (-10, 0, 0), "Head": (25, 0, 0)},
                                                   hips=(0, -0.05, -0.36, -20, 0, 0), feet={"L": (-0.16, 0.12, ANKLE, 0, 8), "R": (0.16, -0.18, ANKLE + 0.04, -30, -8)})),
                                       (0.75, pose(fk={**chest, "Spine": (-20, 0, 0), "Head": (15, 0, 0)}, hips=(0, -0.03, -0.25, -12, 0, 0),
                                                   feet={"L": (-0.16, 0.12, ANKLE, 0, 8), "R": (0.16, -0.18, ANKLE + 0.04, -30, -8)})),
                                       (1.3, pose(fk=chest))])
        keyed_clip(poser, "Throw", [(0.0, pose(fk=chest)),
                                    (0.3, pose(fk={"UpperArm_R": (-140, -15, 0), "LowerArm_R": (60, 0, 0), "UpperArm_L": (70, -5, 0), "Spine": (6, 0, -18), "Chest": (4, 0, -12)},
                                               hips=(0, -0.04, -0.04, 2, 0, -12), feet={"L": (-0.12, 0.22, ANKLE, 0, 10)})),
                                    (0.55, pose(fk={"UpperArm_R": (160, 10, 0), "LowerArm_R": (10, 0, 0), "UpperArm_L": (-20, -20, 0), "Spine": (-14, 0, 14), "Chest": (-8, 0, 10)},
                                                hips=(0, 0.06, -0.05, -6, 0, 12), feet={"L": (-0.12, 0.3, ANKLE, 0, 10)})),
                                    (0.8, pose(fk={"UpperArm_R": (60, 10, 0), "LowerArm_R": (20, 0, 0), "Spine": (-12, 0, 8)}, hips=(0, 0.08, -0.05, -6, 0, 8),
                                               feet={"L": (-0.12, 0.3, ANKLE, 0, 10), "R": (0.12, 0.05, ANKLE + 0.05, -20, -6)})),
                                    (1.1, pose())])
    return speeds


# ------------------------------------------------------------------------------------------------ build
def build(variant, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    keeper = variant == "goalkeeper"
    prefix = "G_" if keeper else "P_"
    rig = "Goalkeeper_Rig" if keeper else "Player_Rig"
    arm = build_armature(rig)
    mats = materials(prefix, keeper)

    body = body_skin()
    assign(body, mats, lambda p: kit_region(p.center, keeper))
    missing = auto_weights(body, arm)
    if missing:
        print("bone heat missed %d vertices -> distance weights for them" % len(missing))
        deform = [b.name for b in arm.data.bones if b.use_deform and b.name != "Root"]
        tmp = {v: None for v in missing}
        for vi in tmp:
            p = body.data.vertices[vi].co
            w = sorted(((1.0 / max(seg_dist(p, arm.data.bones[b].head_local, arm.data.bones[b].tail_local), 0.004) ** 4, b) for b in deform), reverse=True)[:3]
            s = sum(x for x, _ in w)
            for x, b in w:
                (body.vertex_groups.get(b) or body.vertex_groups.new(name=b)).add([vi], x / s, "REPLACE")
    body.parent = None
    parts, dark, brows = head_parts()
    for o in parts:
        assign(o, mats, lambda p: "Skin")
        rigid(o, "Head")
    for o in dark:
        assign(o, mats, lambda p: "Dark")
        rigid(o, "Head")
    for o in brows:
        assign(o, mats, lambda p: "Hair")
        rigid(o, "Head")
    hands = []
    for side in ("L", "R"):
        for o in hand_parts(side):
            assign(o, mats, lambda p: "Glove" if keeper else "Skin")
            bones = ["Hand_" + side, "LowerArm_" + side] + [b.name for b in arm.data.bones if b.name.endswith("_" + side)
                                                            and b.name[:-2].rstrip("0123456789") in ("Index", "Middle", "Ring", "Pinky", "Thumb")]
            distance_weights(o, bones, arm, power=6.0, keep=2)
            hands.append(o)
    num = number_patch(body)
    assign(num, mats, lambda p: "Number")
    distance_weights(num, ["Spine", "Chest"], arm, power=3.0, keep=2)
    # neck/head seam: blend the top of the neck into the head
    hg = body.vertex_groups.get("Head") or body.vertex_groups.new(name="Head")
    for v in body.data.vertices:
        if v.co.z > 1.56:
            hg.add([v.index], min(1.0, (v.co.z - 1.56) / 0.04), "ADD")
    for o in parts + dark + brows + hands + [num]:
        o.parent = None
    whole = join([body] + parts + dark + brows + hands + [num], prefix + "Body")
    limit_and_normalize(whole)
    uv_keep = whole.data.uv_layers.get("UVMap")
    uv_unwrap(whole)            # smart UV for everything; the number patch keeps its 0..1 UVs below
    num_idx = [i for i, m in enumerate(whole.data.materials) if m.name.endswith("Number")][0]
    # restore exact number UVs (smart project rescales islands)
    xs = [whole.data.vertices[i].co for p in whole.data.polygons if p.material_index == num_idx for i in p.vertices]
    x0, x1 = min(v.x for v in xs), max(v.x for v in xs)
    z0, z1 = min(v.z for v in xs), max(v.z for v in xs)
    uvl = whole.data.uv_layers.active
    for p in whole.data.polygons:
        if p.material_index == num_idx:
            for li in p.loop_indices:
                v = whole.data.vertices[whole.data.loops[li].vertex_index].co
                uvl.data[li].uv = ((v.x - x0) / (x1 - x0), (v.z - z0) / (z1 - z0))
    hair = hair_meshes(prefix, mats)
    for o in [whole] + hair:
        if o is not whole:
            rigid(o, "Head")
            uv_unwrap(o)
        for m in [m for m in o.modifiers if m.type == "ARMATURE"]:
            o.modifiers.remove(m)                  # parent_set(ARMATURE_AUTO) added one to the body: deform once only
        o.parent = arm
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    setup_leg_ik(arm)
    poser = Poser(arm)
    speeds = build_clips(poser, keeper)
    arm.animation_data.action = bpy.data.actions["Idle"]
    bpy.context.scene.frame_set(0)
    report(arm, [whole] + hair)

    os.makedirs(os.path.join(out_dir, "src"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "src", variant + "_v2.blend"))
    export(arm, [whole] + hair, os.path.join(out_dir, variant + "_v2.glb"))
    return speeds, sorted(a.name for a in bpy.data.actions)


def report(arm, meshes):
    deform = [b for b in arm.data.bones if b.use_deform]
    print("REPORT bones total=%d deform=%d" % (len(arm.data.bones), len(deform)))
    for o in meshes:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        unweighted = sum(1 for v in o.data.vertices if not v.groups)
        maxinf = max((len(v.groups) for v in o.data.vertices), default=0)
        print("REPORT mesh %-14s verts=%5d tris=%5d unweighted=%d max_influences=%d mats=%s" % (
            o.name, len(o.data.vertices), tris, unweighted, maxinf, [m.name for m in o.data.materials]))
    for a in bpy.data.actions:
        print("REPORT action %-12s frames=%s loop=%s" % (a.name, tuple(int(x) for x in a.frame_range), a.get("loop")))


def export(arm, meshes, path):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    want = dict(filepath=path, export_format="GLB", use_selection=True, export_animation_mode="ACTIONS",
                export_def_bones=True, export_force_sampling=True, export_frame_step=1, export_apply=True, export_yup=True,
                export_skins=True, export_morph=False, export_lights=False, export_cameras=False, export_texcoords=True,
                export_normals=True, export_materials="EXPORT", export_anim_slide_to_zero=True, export_optimize_animation_size=False,
                export_all_influences=False, export_extras=False, export_reset_pose_bones=True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    bpy.ops.export_scene.gltf(**{k: v for k, v in want.items() if k in props})
    print("EXPORTED", path, os.path.getsize(path))


if __name__ == "__main__":
    out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
    os.makedirs(out, exist_ok=True)
    meta = {"generator": "tools/blender/build_player_v2.py", "fps": FPS, "variants": {}}
    for variant in ("player", "goalkeeper"):
        speeds, clips = build(variant, out)
        meta["variants"][variant] = {"clips": clips, "clip_speeds": speeds}
    with open(os.path.join(out, "clips.json"), "w") as fh:
        json.dump(meta, fh, indent=1, sort_keys=True)
    print("DONE")
