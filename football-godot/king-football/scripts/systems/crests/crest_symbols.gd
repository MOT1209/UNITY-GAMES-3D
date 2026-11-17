class_name CrestSymbols
extends RefCounted

## Generic geometric symbols for the original crests, as signed distance functions
## (negative = inside). Built only from circles, boxes, triangles and line segments, so they are
## simple pictograms (star, tower, mountain ...) and not copies of any club's artwork.
## Coordinates: x right, y down, the symbol lives inside |x|,|y| <= R.

const R := 0.62


static func sd(symbol: String, x: float, y: float) -> float:
	if absf(x) > R or absf(y) > R:
		return 1.0
	match symbol:
		"star": return _star(x, y)
		"tower": return _tower(x, y)
		"mountain": return minf(_tri(x, y, -0.5, 0.4, -0.12, -0.3, 0.26, 0.4), _tri(x, y, -0.02, 0.4, 0.3, -0.08, 0.56, 0.4))
		"crown": return _crown(x, y)
		"ball": return _ball(x, y)
		"tree": return _tree(x, y)
		"sun": return _sun(x, y)
		"arrow": return minf(_cap(x, y, 0.0, 0.46, 0.0, -0.04, 0.085), _tri(x, y, -0.3, -0.04, 0.0, -0.5, 0.3, -0.04))
		"bridge": return _bridge(x, y)
		"leaf": return maxf(maxf(_circle(x, y, -0.28, 0.0, 0.5), _circle(x, y, 0.28, 0.0, 0.5)), -_cap(x, y, 0.0, -0.26, 0.0, 0.34, 0.03))
		"gem": return _gem(x, y)
		"castle": return _castle(x, y)
	return 1.0


# --- primitives -------------------------------------------------------------------------------

static func _circle(x: float, y: float, cx: float, cy: float, r: float) -> float:
	return sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) - r


static func _box(x: float, y: float, cx: float, cy: float, hw: float, hh: float) -> float:
	var dx := absf(x - cx) - hw
	var dy := absf(y - cy) - hh
	return sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dy, 0.0) * maxf(dy, 0.0)) + minf(maxf(dx, dy), 0.0)


static func _cap(x: float, y: float, ax: float, ay: float, bx: float, by: float, w: float) -> float:
	var pax := x - ax
	var pay := y - ay
	var bax := bx - ax
	var bay := by - ay
	var h := clampf((pax * bax + pay * bay) / (bax * bax + bay * bay), 0.0, 1.0)
	var dx := pax - bax * h
	var dy := pay - bay * h
	return sqrt(dx * dx + dy * dy) - w


static func _edge(x: float, y: float, px: float, py: float, qx: float, qy: float, s: float) -> float:
	var ex := qx - px
	var ey := qy - py
	return s * ((x - px) * ey - (y - py) * ex) / sqrt(ex * ex + ey * ey)


static func _tri(x: float, y: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	var s := signf((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
	return maxf(maxf(_edge(x, y, ax, ay, bx, by, s), _edge(x, y, bx, by, cx, cy, s)), _edge(x, y, cx, cy, ax, ay, s))


# --- symbols ----------------------------------------------------------------------------------

static func _star(x: float, y: float) -> float:
	var d := _circle(x, y, 0.0, 0.0, 0.22)
	d = minf(d, _tri(x, y, -0.1234, -0.1699, 0.0, -0.52, 0.1234, -0.1699))
	d = minf(d, _tri(x, y, 0.1234, -0.1699, 0.4946, -0.1607, 0.1997, 0.0649))
	d = minf(d, _tri(x, y, 0.1997, 0.0649, 0.3057, 0.4207, 0.0, 0.21))
	d = minf(d, _tri(x, y, 0.0, 0.21, -0.3057, 0.4207, -0.1997, 0.0649))
	d = minf(d, _tri(x, y, -0.1997, 0.0649, -0.4946, -0.1607, -0.1234, -0.1699))
	return d


static func _tower(x: float, y: float) -> float:
	var d := _box(x, y, 0.0, 0.12, 0.26, 0.4)
	for cx in [-0.2, 0.0, 0.2]:
		d = minf(d, _box(x, y, cx, -0.34, 0.07, 0.1))
	return maxf(d, -_box(x, y, 0.0, 0.34, 0.08, 0.16))


static func _crown(x: float, y: float) -> float:
	var d := _box(x, y, 0.0, 0.27, 0.42, 0.1)
	d = minf(d, _tri(x, y, -0.42, 0.18, -0.36, -0.32, -0.12, 0.18))
	d = minf(d, _tri(x, y, -0.18, 0.18, 0.0, -0.42, 0.18, 0.18))
	d = minf(d, _tri(x, y, 0.12, 0.18, 0.36, -0.32, 0.42, 0.18))
	return d


static func _ball(x: float, y: float) -> float:
	var d := absf(_circle(x, y, 0.0, 0.0, 0.42)) - 0.05
	d = minf(d, _circle(x, y, 0.0, 0.0, 0.16))
	for i in 5:
		var a := -PI * 0.5 + TAU * float(i) / 5.0
		d = minf(d, _cap(x, y, 0.16 * cos(a), 0.16 * sin(a), 0.4 * cos(a), 0.4 * sin(a), 0.03))
	return d


static func _tree(x: float, y: float) -> float:
	var d := minf(_circle(x, y, 0.0, -0.14, 0.3), minf(_circle(x, y, -0.2, 0.0, 0.2), _circle(x, y, 0.2, 0.0, 0.2)))
	return minf(d, _cap(x, y, 0.0, 0.1, 0.0, 0.44, 0.07))


static func _sun(x: float, y: float) -> float:
	var d := _circle(x, y, 0.0, 0.0, 0.2)
	for i in 8:
		var a := TAU * float(i) / 8.0
		d = minf(d, _cap(x, y, 0.3 * cos(a), 0.3 * sin(a), 0.48 * cos(a), 0.48 * sin(a), 0.045))
	return d


static func _bridge(x: float, y: float) -> float:
	var d := _box(x, y, 0.0, -0.12, 0.5, 0.06)
	d = minf(d, maxf(absf(_circle(x, y, 0.0, 0.42, 0.38)) - 0.065, y - 0.42))
	d = minf(d, _cap(x, y, -0.42, -0.1, -0.42, 0.44, 0.06))
	return minf(d, _cap(x, y, 0.42, -0.1, 0.42, 0.44, 0.06))


static func _gem(x: float, y: float) -> float:
	# One convex polygon (no union seams), facet line carved out.
	var d := _edge(x, y, -0.22, -0.38, 0.22, -0.38, 1.0)
	d = maxf(d, _edge(x, y, 0.22, -0.38, 0.45, -0.1, 1.0))
	d = maxf(d, _edge(x, y, 0.45, -0.1, 0.0, 0.46, 1.0))
	d = maxf(d, _edge(x, y, 0.0, 0.46, -0.45, -0.1, 1.0))
	d = maxf(d, _edge(x, y, -0.45, -0.1, -0.22, -0.38, 1.0))
	return maxf(d, -_cap(x, y, -0.45, -0.1, 0.45, -0.1, 0.018))


static func _castle(x: float, y: float) -> float:
	var d := _box(x, y, 0.0, 0.15, 0.4, 0.28)
	d = minf(d, _box(x, y, -0.34, -0.1, 0.1, 0.3))
	d = minf(d, _box(x, y, 0.34, -0.1, 0.1, 0.3))
	for cx in [-0.14, 0.0, 0.14]:
		d = minf(d, _box(x, y, cx, -0.19, 0.05, 0.07))
	return maxf(d, -minf(_box(x, y, 0.0, 0.33, 0.1, 0.14), _circle(x, y, 0.0, 0.2, 0.1)))
