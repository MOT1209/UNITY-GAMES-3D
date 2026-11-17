"""Generates the stadium "shells" of KING FOOTBALL: stands, roofs, facades, floodlights and screens.

    python3 tools/stadium_gen/build_stadiums.py        (from the project folder)

Every shell is an original, parametric design written to assets/models/stadium/shells/<id>.glb.
StadiumArena loads the base stadium.glb (pitch, goals, ad boards, dugouts, tunnel, plaza, ground and the
gameplay helpers COL_/TRIGGER_/SPAWN_), removes the base stands / roof / facade / screens / trees and adds the
shell instead, so gameplay is identical in every stadium.

Conventions (same as stadium.glb): metres, +Y up, pitch centre at the origin, length along Z (goal lines at
z = +-52.5), touchlines at x = +-34, ad boards at |x| = 37.2 / |z| = 56.2. Side stands start at |x| = 44 (the
tunnel and dugouts sit at x = -38 .. -43.5), end stands at |z| = 60.

Constraints the shapes respect:
  * the broadcast camera sits at about (30 + ball.x, 22, z), i.e. up to x = 64 at y = 22: nothing on the +x side
    may rise above y ~ 21 for x <= 64, and any roof over that side needs its underside above y = 22.5;
  * the spectators are placed by rays cast down on the collision inside x = +-78, z = +-97 (surfaces with an
    upward normal above y = 0.6), so every seating tier has a sloped COL_ surface inside that box.

Node names: Shell_* (visual) and COL_Shell_* (collision; StadiumArena turns COL_* into static bodies).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_writer import Material, MeshBuilder, write_glb  # noqa: E402

OUT_DIR = os.path.join("assets", "models", "stadium", "shells")
UP = (0.0, 1.0, 0.0)
DOWN = (0.0, -1.0, 0.0)


# ---------------------------------------------------------------------------------------------- paths

class Sample:
    """A point of a stand's inner edge with its outward (away from the pitch) horizontal normal."""

    def __init__(self, x, z, nx, nz, section=0):
        self.x, self.z, self.nx, self.nz, self.section = x, z, nx, nz, section

    def at(self, d, y):
        return (self.x + self.nx * d, y, self.z + self.nz * d)


def rounded_rect(ax, az, r, side_sections, end_sections, corner_steps):
    """Closed path around the pitch: half extents ax (x) / az (z), corner radius r. Counter-clockwise from above."""
    out = []
    sec = 0
    corners = [(ax - r, az - r, 0.0), (-(ax - r), az - r, 90.0), (-(ax - r), -(az - r), 180.0), (ax - r, -(az - r), 270.0)]
    for ci, (cx, cz, a0) in enumerate(corners):
        for s in range(corner_steps):
            a = math.radians(a0 + 90.0 * s / corner_steps)
            nx, nz = math.cos(a), math.sin(a)
            out.append(Sample(cx + nx * r, cz + nz * r, nx, nz, sec))
        sec += 1
        # straight edge to the next corner
        a = math.radians(a0 + 90.0)
        nx, nz = round(math.cos(a), 9), round(math.sin(a), 9)
        nxt = corners[(ci + 1) % 4]
        sx, sz = cx + nx * r, cz + nz * r
        ex, ez = nxt[0] + nx * r, nxt[1] + nz * r
        n_div = end_sections if abs(nz) > 0.5 else side_sections
        for k in range(n_div):
            t = k / n_div
            out.append(Sample(sx + (ex - sx) * t, sz + (ez - sz) * t, nx, nz, sec))
            sec += 1
    return out


def line(x0, z0, x1, z1, nx, nz, sections):
    return [Sample(x0 + (x1 - x0) * k / sections, z0 + (z1 - z0) * k / sections, nx, nz, k) for k in range(sections + 1)]


def segments(path, closed):
    n = len(path)
    return [(path[i], path[(i + 1) % n]) for i in range(n if closed else n - 1)]


def avg_normal(a, b):
    return ((a.nx + b.nx) * 0.5, 0.0, (a.nz + b.nz) * 0.5)


# ---------------------------------------------------------------------------------------------- parts

class Tier:
    def __init__(self, d0, rows, depth, rise, y0, seat, step="M_step", front="M_concrete", front_h=1.1,
                 hanging=False, back="M_facade", back_to=None, walkway=0.3, seat_backs=True):
        self.d0, self.rows, self.depth, self.rise, self.y0 = d0, rows, depth, rise, y0
        self.seat, self.step, self.front, self.front_h = seat, step, front, front_h
        self.hanging = hanging        # upper tier: open underside (soffit) instead of a wall down to the ground
        self.back, self.back_to = back, back_to
        self.walkway, self.seat_backs = walkway, seat_backs

    @property
    def d_end(self):
        return self.d0 + self.rows * self.depth

    @property
    def y_top(self):
        return self.y0 + self.rows * self.rise

    def bottom(self, d):
        """Underside height at offset d (0 for a tier on the ground)."""
        if not self.hanging:
            return 0.0
        return self.y0 - 0.8 + (d - self.d0) / (self.rows * self.depth) * (self.rows * self.rise)


def build_tier(vis, col, path, closed, t):
    for a, b in segments(path, closed):
        n = avg_normal(a, b)
        inward = (-n[0], 0.0, -n[2])
        for k in range(t.rows):
            da = t.d0 + k * t.depth
            dw = da + t.walkway * t.depth
            db = da + t.depth
            yt = t.y0 + (k + 1) * t.rise
            yb = yt - t.rise
            vis.oquad(t.step, a.at(da, yb), b.at(da, yb), b.at(da, yt), a.at(da, yt), inward)
            vis.oquad(t.step, a.at(da, yt), b.at(da, yt), b.at(dw, yt), a.at(dw, yt), UP)
            mat = t.seat(a.section, k) if callable(t.seat) else t.seat
            vis.oquad(mat, a.at(dw, yt), b.at(dw, yt), b.at(db, yt), a.at(db, yt), UP)
            if t.seat_backs and mat != t.step:
                sb = db - 0.06
                vis.oquad(mat, a.at(sb, yt), b.at(sb, yt), b.at(sb, yt + 0.38), a.at(sb, yt + 0.38), inward)
        # front wall / balustrade
        fb = t.bottom(t.d0)
        vis.oquad(t.front, a.at(t.d0, fb), b.at(t.d0, fb), b.at(t.d0, t.y0 + t.front_h), a.at(t.d0, t.y0 + t.front_h), inward)
        # back wall
        top = t.y_top + 1.2 if t.back_to is None else t.back_to
        bot = 0.0 if not t.hanging else t.bottom(t.d_end)
        vis.oquad(t.back, a.at(t.d_end, bot), b.at(t.d_end, bot), b.at(t.d_end, top), a.at(t.d_end, top), n)
        col.oquad("M_col", a.at(t.d_end, 0.0), b.at(t.d_end, 0.0), b.at(t.d_end, top), a.at(t.d_end, top), n)
        if t.hanging:
            vis.oquad("M_under", a.at(t.d0, t.bottom(t.d0)), b.at(t.d0, t.bottom(t.d0)),
                      b.at(t.d_end, t.bottom(t.d_end)), a.at(t.d_end, t.bottom(t.d_end)), DOWN)
        # collision: one slope through the back corners of the treads (spectators stand on it)
        col.oquad("M_col", a.at(t.d0, t.y0), b.at(t.d0, t.y0), b.at(t.d_end, t.y_top), a.at(t.d_end, t.y_top), UP)
    if not closed:
        for s, sign in ((path[0], -1.0), (path[-1], 1.0)):
            nxt = path[1] if sign < 0 else path[-2]
            tx, tz = s.x - nxt.x, s.z - nxt.z
            ln = math.hypot(tx, tz) or 1.0
            want = (tx / ln, 0.0, tz / ln)
            for k in range(t.rows):
                da = t.d0 + k * t.depth
                db = da + t.depth
                yt = t.y0 + (k + 1) * t.rise
                vis.oquad(t.back, s.at(da, t.bottom(da)), s.at(db, t.bottom(db)), s.at(db, yt), s.at(da, yt), want)
            # the cap above the last row up to the back wall's top
            top = t.y_top + 1.2 if t.back_to is None else t.back_to
            vis.oquad(t.back, s.at(t.d_end - 0.3, t.y_top), s.at(t.d_end, t.y_top), s.at(t.d_end, top), s.at(t.d_end - 0.3, top), want)


def build_roof(vis, path, closed, d_in, d_out, y_in, y_out, thick=0.6, top="M_roof", under="M_roof_under",
               fascia="M_dark", outer="M_roof"):
    for a, b in segments(path, closed):
        n = avg_normal(a, b)
        inward = (-n[0], 0.0, -n[2])
        vis.oquad(top, a.at(d_in, y_in), b.at(d_in, y_in), b.at(d_out, y_out), a.at(d_out, y_out), UP)
        vis.oquad(under, a.at(d_in, y_in - thick), b.at(d_in, y_in - thick), b.at(d_out, y_out - thick),
                  a.at(d_out, y_out - thick), DOWN)
        vis.oquad(fascia, a.at(d_in, y_in - thick), b.at(d_in, y_in - thick), b.at(d_in, y_in), a.at(d_in, y_in), inward)
        vis.oquad(outer, a.at(d_out, y_out - thick), b.at(d_out, y_out - thick), b.at(d_out, y_out), a.at(d_out, y_out), n)
    if not closed:
        for s, nxt in ((path[0], path[1]), (path[-1], path[-2])):
            tx, tz = s.x - nxt.x, s.z - nxt.z
            ln = math.hypot(tx, tz) or 1.0
            vis.oquad(outer, s.at(d_in, y_in - thick), s.at(d_out, y_out - thick), s.at(d_out, y_out), s.at(d_in, y_in),
                      (tx / ln, 0.0, tz / ln))


def build_wall_band(vis, path, closed, d, y0, y1, mat):
    """Vertical band facing the pitch at offset d (LED ribbons, facade crowns)."""
    for a, b in segments(path, closed):
        n = avg_normal(a, b)
        vis.oquad(mat, a.at(d, y0), b.at(d, y0), b.at(d, y1), a.at(d, y1), (-n[0], 0.0, -n[2]))


def build_bank(vis, col, path, d0, d1, h, mat="M_bank"):
    """Grass bank behind a goal: slope from the ground at d0 up to height h at d1, then flat for 4 m."""
    for a, b in segments(path, False):
        vis.oquad(mat, a.at(d0, 0.02), b.at(d0, 0.02), b.at(d1, h), a.at(d1, h), UP)
        vis.oquad(mat, a.at(d1, h), b.at(d1, h), b.at(d1 + 4.0, h), a.at(d1 + 4.0, h), UP)
        col.oquad("M_col", a.at(d0, 0.02), b.at(d0, 0.02), b.at(d1, h), a.at(d1, h), UP)
    for s, nxt in ((path[0], path[1]), (path[-1], path[-2])):
        tx, tz = s.x - nxt.x, s.z - nxt.z
        ln = math.hypot(tx, tz) or 1.0
        want = (tx / ln, 0.0, tz / ln)
        vis.oquad(mat, s.at(d0, 0.0), s.at(d1, 0.0), s.at(d1, h), s.at(d0, 0.02), want)
        vis.oquad(mat, s.at(d1, 0.0), s.at(d1 + 4.0, 0.0), s.at(d1 + 4.0, h), s.at(d1, h), want)


def build_columns(vis, path, d, y_top, every, size=0.35, mat="M_metal"):
    for i, s in enumerate(path):
        if i % every:
            continue
        p = s.at(d, 0.0)
        vis.box(mat, (p[0], y_top * 0.5, p[2]), (size, y_top, size))


def floodlight(vis, x, z, height, panel=(7.0, 3.5), mast=1.0):
    vis.box("M_metal", (x, height * 0.5, z), (mast, height, mast))
    ln = math.hypot(x, z) or 1.0
    ux, uz = -x / ln, -z / ln
    c, s = math.cos(math.radians(35.0)), math.sin(math.radians(35.0))
    nrm = (ux * c, -s, uz * c)
    right = (uz, 0.0, -ux)
    upv = (nrm[1] * right[2] - nrm[2] * right[1], nrm[2] * right[0] - nrm[0] * right[2], nrm[0] * right[1] - nrm[1] * right[0])
    hc = (x + ux * 0.8, height + panel[1] * 0.3, z + uz * 0.8)

    def corner(off, sr, su):
        return (hc[0] + nrm[0] * off + right[0] * sr * panel[0] * 0.5 + upv[0] * su * panel[1] * 0.5,
                hc[1] + nrm[1] * off + right[1] * sr * panel[0] * 0.5 + upv[1] * su * panel[1] * 0.5,
                hc[2] + nrm[2] * off + right[2] * sr * panel[0] * 0.5 + upv[2] * su * panel[1] * 0.5)

    vis.oquad("M_flood", corner(0.05, -1, -1), corner(0.05, 1, -1), corner(0.05, 1, 1), corner(0.05, -1, 1), nrm)
    back = (-nrm[0], -nrm[1], -nrm[2])
    vis.oquad("M_dark", corner(-0.35, -1, -1), corner(-0.35, 1, -1), corner(-0.35, 1, 1), corner(-0.35, -1, 1), back)
    for sr in (-1, 1):
        vis.oquad("M_dark", corner(-0.35, sr, -1), corner(0.05, sr, -1), corner(0.05, sr, 1), corner(-0.35, sr, 1),
                  (right[0] * sr, right[1] * sr, right[2] * sr))
    for su in (-1, 1):
        vis.oquad("M_dark", corner(-0.35, -1, su), corner(0.05, -1, su), corner(0.05, 1, su), corner(-0.35, 1, su),
                  (upv[0] * su, upv[1] * su, upv[2] * su))


def screen(vis, z_sign, z, y, w, h, depth=1.0):
    """Video screen at |z| facing the pitch (z_sign = +1 for the +Z end)."""
    vis.box("M_dark", (0.0, y, z_sign * (z + depth * 0.5)), (w + 0.6, h + 0.6, depth))
    zf = z_sign * (z - 0.02)
    want = (0.0, 0.0, -z_sign)
    vis.oquad("M_screen", (-w / 2, y - h / 2, zf), (w / 2, y - h / 2, zf), (w / 2, y + h / 2, zf), (-w / 2, y + h / 2, zf), want)


def build_ground(mat):
    """Fills the base plaza's hole (rounded rect 77.8 x 97.3, corner radius 47.8, where the base stadium stood)
    with a flat ground just below the pitch, so no void shows between a shell and the plaza."""
    g = MeshBuilder("Shell_Ground")
    ring = rounded_rect(77.8, 97.3, 47.8, 1, 1, 16)
    c = (0.0, -0.02, 0.0)
    for a, b in segments(ring, True):
        g.tri(mat, c, a.at(0.0, -0.02), b.at(0.0, -0.02))
    # make sure every triangle faces up
    pos, nor = g.groups[mat]
    for i in range(0, len(pos), 3):
        if nor[i][1] < 0.0:
            pos[i + 1], pos[i + 2] = pos[i + 2], pos[i + 1]
            nor[i] = nor[i + 1] = nor[i + 2] = (0.0, 1.0, 0.0)
    return g


# ---------------------------------------------------------------------------------------------- materials

def palette(seat_a, seat_b, facade, roof, led, extra=None):
    mats = [
        Material("M_step", (0.52, 0.53, 0.55), 0.9),
        Material("M_concrete", (0.62, 0.62, 0.62), 0.9),
        Material("M_under", (0.34, 0.35, 0.37), 0.95),
        Material("M_facade", facade, 0.8),
        Material("M_seat_a", seat_a, 0.6),
        Material("M_seat_b", seat_b, 0.6),
        Material("M_roof", roof, 0.55, 0.2),
        Material("M_roof_under", (0.72, 0.72, 0.74), 0.8),
        Material("M_metal", (0.55, 0.57, 0.6), 0.45, 0.6),
        Material("M_dark", (0.07, 0.07, 0.08), 0.7),
        Material("M_led", led, 0.4, emissive=led, emissive_strength=2.5),
        Material("M_flood", (1.0, 0.97, 0.9), 0.3, emissive=(1.0, 0.96, 0.86), emissive_strength=4.0),
        Material("M_screen", (0.1, 0.16, 0.25), 0.3, emissive=(0.25, 0.45, 0.75), emissive_strength=1.5),
        Material("M_bank", (0.2, 0.42, 0.18), 1.0),
        Material("M_col", (0.5, 0.5, 0.5), 1.0),
        Material("M_ground", (0.34, 0.35, 0.36), 0.95),
    ]
    for m in extra or []:
        mats.append(m)
    return mats


# ---------------------------------------------------------------------------------------------- stadiums

def crescent_bowl():
    """Open two-tier bowl, continuous around the pitch, teal / white sections and a light crown ring."""
    vis, roof, col = MeshBuilder("Shell_Stands"), MeshBuilder("Shell_Roof"), MeshBuilder("COL_Shell_Stands")
    path = rounded_rect(44.0, 60.0, 16.0, 8, 6, 6)

    def seat(section, row):
        return "M_seat_a" if section % 2 == 0 else "M_seat_b"

    lower = Tier(0.0, 22, 0.85, 0.42, 0.9, seat, back_to=11.6)
    upper = Tier(17.0, 20, 0.85, 0.42, 12.4, seat, front="M_led", front_h=0.7, hanging=True, back_to=24.0)
    build_tier(vis, col, path, True, lower)
    build_tier(vis, col, path, True, upper)
    build_roof(roof, path, True, 27.0, 36.5, 24.6, 24.0, 0.5, fascia="M_flood")
    screen(roof, 1, 92.0, 28.5, 18.0, 7.0)
    screen(roof, -1, 92.0, 28.5, 18.0, 7.0)
    mats = palette((0.03, 0.42, 0.47), (0.86, 0.88, 0.89), (0.9, 0.91, 0.92), (0.95, 0.95, 0.96), (0.1, 0.85, 0.8))
    return [vis, roof, col, build_ground("M_ground")], mats


def old_fortress():
    """Four separate two-tier stands with roofs and open corners, red brick, floodlight pylons in the corners."""
    vis, roof, col = MeshBuilder("Shell_Stands"), MeshBuilder("Shell_Roof"), MeshBuilder("COL_Shell_Stands")
    west = line(-44.0, 50.0, -44.0, -50.0, -1.0, 0.0, 10)
    east = line(44.0, -50.0, 44.0, 50.0, 1.0, 0.0, 10)
    north = line(-32.0, -60.0, 32.0, -60.0, 0.0, -1.0, 8)
    south = line(32.0, 60.0, -32.0, 60.0, 0.0, 1.0, 8)

    def side_seat(section, row):
        return "M_seat_b" if row in (0, 1) else "M_seat_a"

    def end_seat(section, row):
        return "M_seat_a" if row % 6 in (0,) else "M_seat_b"

    for path, roof_in, roof_out in ((west, 21.5, 19.5), (east, 25.8, 24.4)):
        build_tier(vis, col, path, False, Tier(0.0, 16, 0.85, 0.4, 0.8, side_seat, back_to=8.4))
        build_tier(vis, col, path, False, Tier(10.0, 18, 0.85, 0.4, 9.0, side_seat, hanging=True, back_to=roof_out))
        build_roof(roof, path, False, 3.0, 26.6, roof_in, roof_out, 0.6, top="M_roof", fascia="M_facade")
    build_columns(roof, west, 3.2, 21.0, 2, 0.4)
    for path in (north, south):
        build_tier(vis, col, path, False, Tier(0.0, 24, 0.8, 0.45, 0.8, end_seat, back_to=15.8))
        build_roof(roof, path, False, 4.0, 19.5, 16.8, 15.8, 0.5, top="M_roof", fascia="M_facade")
        build_columns(roof, path, 4.2, 16.4, 2, 0.35)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            floodlight(roof, sx * 60.0, sz * 78.0, 34.0)
    screen(roof, -1, 72.0, 19.6, 10.0, 4.0)
    mats = palette((0.46, 0.06, 0.1), (0.07, 0.1, 0.26), (0.45, 0.21, 0.15), (0.25, 0.27, 0.3), (0.95, 0.3, 0.2))
    return [vis, roof, col, build_ground("M_ground")], mats


def riverside_park():
    """Small community ground: a covered wooden main stand, an open terrace and grass banks behind the goals."""
    vis, roof, col = MeshBuilder("Shell_Stands"), MeshBuilder("Shell_Roof"), MeshBuilder("COL_Shell_Stands")
    main = line(-44.0, 30.0, -44.0, -30.0, -1.0, 0.0, 6)
    terrace = line(44.0, -45.0, 44.0, 45.0, 1.0, 0.0, 6)
    north = line(-38.0, -60.0, 38.0, -60.0, 0.0, -1.0, 6)
    south = line(38.0, 60.0, -38.0, 60.0, 0.0, 1.0, 6)

    def seat(section, row):
        return "M_seat_a" if (section + row) % 4 else "M_seat_b"

    build_tier(vis, col, main, False, Tier(0.0, 10, 0.85, 0.38, 0.6, seat, back_to=7.4))
    build_roof(roof, main, False, 0.4, 10.2, 8.0, 7.2, 0.3, top="M_roof", fascia="M_facade", outer="M_facade")
    build_columns(roof, main, 0.6, 7.8, 1, 0.22, "M_facade")
    build_tier(vis, col, terrace, False, Tier(0.0, 8, 0.7, 0.3, 0.3, "M_step", front="M_concrete", front_h=1.0,
                                              back="M_concrete", seat_backs=False))
    # crush barriers on the terrace
    for s in terrace[1:-1]:
        for k in (2, 5):
            p = s.at(k * 0.7 + 0.2, 0.3 + (k + 1) * 0.3)
            roof.box("M_metal", (p[0], p[1] + 0.5, p[2]), (0.08, 1.0, 0.08))
    for a, b in segments(terrace, False):
        for k in (2, 5):
            pa, pb = a.at(k * 0.7 + 0.2, 0.3 + (k + 1) * 0.3 + 1.0), b.at(k * 0.7 + 0.2, 0.3 + (k + 1) * 0.3 + 1.0)
            roof.box("M_metal", ((pa[0] + pb[0]) / 2, pa[1], (pa[2] + pb[2]) / 2), (0.08, 0.08, abs(pb[2] - pa[2])))
    build_bank(vis, col, north, 1.0, 14.0, 4.5)
    build_bank(vis, col, south, 1.0, 14.0, 4.5)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            floodlight(roof, sx * 47.0, sz * 64.0, 22.0, (4.0, 2.0), 0.45)
    roof.box("M_dark", (0.0, 7.6, 77.8), (7.0, 3.2, 0.5))
    roof.oquad("M_screen", (-3.2, 6.2, 77.5), (3.2, 6.2, 77.5), (3.2, 9.0, 77.5), (-3.2, 9.0, 77.5), (0.0, 0.0, -1.0))
    for x in (-2.8, 2.8):
        roof.box("M_metal", (x, 3.0, 77.8), (0.25, 6.0, 0.25))
    mats = palette((0.1, 0.36, 0.2), (0.9, 0.9, 0.86), (0.13, 0.3, 0.2), (0.2, 0.22, 0.2), (0.9, 0.8, 0.3))
    return [vis, roof, col, build_ground("M_bank")], mats


def desert_dome():
    """Closed modern arena: two continuous tiers, sand facade, amber LED ribbon and a roof ring with an open centre."""
    vis, roof, col = MeshBuilder("Shell_Stands"), MeshBuilder("Shell_Roof"), MeshBuilder("COL_Shell_Stands")
    path = rounded_rect(44.0, 60.0, 22.0, 8, 6, 8)

    def seat(section, row):
        return "M_seat_b" if row >= 14 or section % 5 == 0 else "M_seat_a"

    build_tier(vis, col, path, True, Tier(0.0, 18, 0.85, 0.4, 0.9, seat, back_to=9.8))
    build_tier(vis, col, path, True, Tier(14.0, 18, 0.85, 0.45, 10.6, seat, front="M_led", front_h=0.8, hanging=True,
                                          back_to=33.0))
    build_roof(roof, path, True, 2.0, 34.0, 30.0, 33.0, 1.2, top="M_roof", under="M_roof_under", fascia="M_flood",
               outer="M_facade")
    build_wall_band(roof, path, True, 33.2, 22.0, 23.0, "M_led")
    screen(roof, 1, 86.0, 24.0, 20.0, 8.0)
    screen(roof, -1, 86.0, 24.0, 20.0, 8.0)
    mats = palette((0.62, 0.15, 0.12), (0.85, 0.7, 0.45), (0.78, 0.64, 0.44), (0.93, 0.93, 0.9), (1.0, 0.62, 0.15))
    return [vis, roof, col, build_ground("M_ground")], mats


STADIUMS = {
    "crescent_bowl": crescent_bowl,
    "old_fortress": old_fortress,
    "riverside_park": riverside_park,
    "desert_dome": desert_dome,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for sid, fn in STADIUMS.items():
        meshes, mats = fn()
        path = os.path.join(OUT_DIR, sid + ".glb")
        write_glb(path, meshes, mats)
        tris = {m.name: m.triangle_count() for m in meshes}
        print("%-16s %8d bytes  %s" % (sid, os.path.getsize(path), tris))


if __name__ == "__main__":
    main()
