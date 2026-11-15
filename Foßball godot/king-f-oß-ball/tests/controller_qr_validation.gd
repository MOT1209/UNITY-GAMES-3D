## KING CONTROLLER (P5/P9): structural + data validation of KingQrEncoder output.
## A phone camera cannot be decoded inside Godot, so this suite asserts the invariants that
## every scanner relies on — each of them was the root cause of a real undecodable-QR bug:
##   1. structure: finders, separators, alternating timing, dark module, capacity
##   2. format info: BCH checksum, EC level L, both copies identical (a refactor once lost the copy)
##   3. data placement: exactly cap+ecc+remainder bits laid out along the standard zigzag
##      (format cells and alignment regions must be RESERVED, not eaten by the zigzag)
##   4. Reed-Solomon: the extracted codewords must divide by the generator with remainder 0
##      (the generator's coefficient order was once reversed -> garbage ECC)
##   5. alignment: for v2-v6 exactly ONE pattern (bottom-right); centres overlapping the
##      timing line must be skipped (spurious patterns once shifted the whole data stream)
##   6. payload round-trip: byte-mode header + the original URL can be parsed back out
## The empirical decode gate (real decoders, Python zxing-cpp) is a dev-time tool, documented
## in docs/reports/KING_FOOTBALL_GAMEPLAY_UPGRADE_REPORT.md.
extends Node

var _passed := 0
var _failed := 0

const CASES := [
	["v1", "http://x/?t=ABCD", 21],
	["v2", "http://x/?t=ABCDEFGH", 25],
	["v3", "http://192.168.1.50:8080/?t=AB12CD34", 29],
]
const CAPS := {21: [19, 7], 25: [34, 10], 29: [55, 15]}
const CENTERS := {25: [6, 18], 29: [6, 22]}


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" - " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== KING FOOTBALL - Controller QR validation ===")
	await get_tree().process_frame
	for c in CASES:
		_case(c[0], c[1], c[2])
	# input that exceeds v5 capacity (108 bytes) must fail cleanly
	var too_long := "http://192.168.100.100:8080/?t="
	for i in range(200):
		too_long += "x"
	var big := KingQrEncoder.encode(too_long)
	_check(int(big.get("size", 0)) == 0, "oversized input fails cleanly (size 0)")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _case(tag: String, url: String, size: int) -> void:
	var m := KingQrEncoder.encode(url)
	_check(int(m.get("size", 0)) == size, "%s: encoded at version %d (%dx%d)" % [tag, (size - 17) / 4, size, size])
	if int(m.get("size", 0)) != size:
		return
	var modules: Array = m["modules"]
	_finders(modules, size, tag)
	_timing(modules, size, tag)
	_check(modules[size - 8][8], "%s: dark module present at (size-8, 8)" % tag)
	var fmt_bits := _read_format_first_copy(modules, size)
	_format_valid(fmt_bits, tag)
	_second_copy_matches(fmt_bits, modules, size, tag)
	var data := fmt_bits ^ 0b101010000010010
	var mask := (data >> 10) & 0b111
	_capacity(modules, size, tag)
	var cws := _extract_codewords(modules, size, mask, tag)
	var cap: int = CAPS[size][0]
	var ecc: int = CAPS[size][1]
	_check(cws.size() == cap + ecc, "%s: zigzag yields exactly %d codeword bytes" % [tag, cap + ecc])
	if cws.size() == cap + ecc:
		_check(_rs_remainder_zero(cws, ecc), "%s: Reed-Solomon remainder is zero (data + ECC consistent)" % tag)
	_payload_roundtrip(cws, cap, url, tag)
	_alignment_shape(modules, size, tag)


# --- structure ---------------------------------------------------------------

func _finders(modules: Array, size: int, tag: String) -> void:
	for fp in [Vector2i(0, 0), Vector2i(0, size - 7), Vector2i(size - 7, 0)]:
		var ok := true
		for dr in range(7):
			for dc in range(7):
				var expect: bool = dr == 0 or dr == 6 or dc == 0 or dc == 6 \
						or (dr >= 2 and dr <= 4 and dc >= 2 and dc <= 4)
				if modules[fp.x + dr][fp.y + dc] != expect:
					ok = false
		_check(ok, "%s: finder pattern correct at %s" % [tag, fp])


func _timing(modules: Array, size: int, tag: String) -> void:
	var ok := true
	for i in range(8, size - 8):
		if modules[6][i] != (i % 2 == 0) or modules[i][6] != (i % 2 == 0):
			ok = false
	_check(ok, "%s: timing pattern alternates along row and column 6" % tag)


# --- format info -------------------------------------------------------------

func _format_cells(size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3),
		Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 7), Vector2i(8, 8),
		Vector2i(7, 8), Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8),
		Vector2i(2, 8), Vector2i(1, 8), Vector2i(0, 8)]
	for i in range(7):
		cells.append(Vector2i(size - 1 - i, 8))
	for i in range(8):
		cells.append(Vector2i(8, size - 8 + i))
	return cells


func _read_format_first_copy(modules: Array, size: int) -> int:
	var cells := _format_cells(size)
	var v := 0
	for i in range(15):
		v = (v << 1) | (1 if modules[cells[i].x][cells[i].y] else 0)
	return v


func _format_valid(fmt_bits: int, tag: String) -> void:
	var data := fmt_bits ^ 0b101010000010010
	var level := (data >> 13) & 0b11
	var mask := (data >> 10) & 0b111
	_check(level == 0b01, "%s: format declares EC level L" % tag)
	_check(mask <= 7, "%s: format declares a valid mask (%d)" % [tag, mask])
	# BCH(15,5) checksum: the 5 data bits must produce the 10 transmitted BCH bits
	var five := data >> 10
	var bch_rx := data & 0x3FF
	var shifted := five << 10
	for i in range(4, -1, -1):
		if (shifted >> (i + 10)) & 1:
			shifted ^= 0b10100110111 << i
	_check((shifted & 0x3FF) == bch_rx, "%s: format BCH checksum is self-consistent" % tag)


func _second_copy_matches(fmt_bits: int, modules: Array, size: int, tag: String) -> void:
	var cells := _format_cells(size)
	var v := 0
	for i in range(15):
		v = (v << 1) | (1 if modules[cells[15 + i].x][cells[15 + i].y] else 0)
	_check(v == fmt_bits, "%s: second format copy is identical to the first" % tag)


# --- data placement + Reed-Solomon -------------------------------------------

func _data_cell_count(modules: Array, size: int) -> int:
	# functional mask rebuilt independently
	var func_cells := _functional(size, CENTERS.get(size, []))
	var n := 0
	for r in range(size):
		for c in range(size):
			if not func_cells[r][c]:
				n += 1
	return n


func _capacity(modules: Array, size: int, tag: String) -> void:
	var cap: int = CAPS[size][0]
	var ecc: int = CAPS[size][1]
	# remainder bits: v1 = 0, v2-v6 = 7
	var rem := 0 if size == 21 else 7
	_check(_data_cell_count(modules, size) == (cap + ecc) * 8 + rem,
			"%s: exactly %d data cells (%d+%d bytes + %d remainder bits)" % [tag, (cap + ecc) * 8 + rem, cap, ecc, rem])


func _functional(size: int, centers: Array) -> Array:
	var f: Array = []
	for r in range(size):
		var row: Array[bool] = []
		row.resize(size)
		for c in range(size):
			row[c] = false
		f.append(row)
	# three finder corners only — there is NO finder at the bottom-right
	for corner in [[0, 0], [0, size - 7], [size - 7, 0]]:
		for dr in range(-1, 8):
			for dc in range(-1, 8):
				var rr: int = corner[0] + dr
				var cc: int = corner[1] + dc
				if rr >= 0 and cc >= 0 and rr < size and cc < size:
					f[rr][cc] = true
	for i in range(8, size - 8):
		f[6][i] = true
		f[i][6] = true
	f[size - 8][8] = true
	for pp in _format_cells(size):
		f[pp.x][pp.y] = true
	for r in centers:
		for c in centers:
			var blocked := false
			for dr in range(-2, 3):
				for dc in range(-2, 3):
					if f[r + dr][c + dc]:
						blocked = true
			if not blocked:
				for dr in range(-2, 3):
					for dc in range(-2, 3):
						f[r + dr][c + dc] = true
	return f


func _extract_codewords(modules: Array, size: int, mask: int, tag: String) -> Array[int]:
	var f := _functional(size, CENTERS.get(size, []))
	var bytes: Array[int] = []
	var col := size - 1
	var up := true
	var bits := 0
	var cur := 0
	while col >= 1:
		if col == 6:
			col -= 1
		var rows: Array = range(size - 1, -1, -1) if up else range(0, size, 1)
		for r in rows:
			for cc in [col, col - 1]:
				if f[r][cc]:
					continue
				var v := 1 if modules[r][cc] else 0
				# unmask
				if _mask_fn(mask, r, cc):
					v ^= 1
				cur = (cur << 1) | v
				bits += 1
				if bits == 8:
					bytes.append(cur)
					bits = 0
					cur = 0
		col -= 2
		up = not up
	return bytes


func _mask_fn(mask: int, r: int, c: int) -> bool:
	match mask:
		0: return (r + c) % 2 == 0
		1: return r % 2 == 0
		2: return c % 3 == 0
		3: return (r + c) % 3 == 0
		4: return ((r >> 1) + (c / 3)) % 2 == 0
		5: return ((r * c) % 2) + ((r * c) % 3) == 0
		6: return (((r * c) % 2) + ((r * c) % 3)) % 2 == 0
		7: return (((r + c) % 2) + ((r * c) % 3)) % 2 == 0
	return false


func _rs_remainder_zero(cws: Array[int], deg: int) -> bool:
	# Build the generator low-to-high with gf_poly_mul (its index = power of x), then
	# reverse to the high-to-low order the synthetic division below consumes.
	var g: Array[int] = [1]
	for i in range(deg):
		var factor: Array[int] = [KingQrEncoder._exp[i], 1]
		var res: Array[int] = []
		res.resize(g.size() + factor.size() - 1)
		for k in range(res.size()):
			res[k] = 0
		for a in range(g.size()):
			if g[a] == 0:
				continue
			for b in range(factor.size()):
				res[a + b] ^= KingQrEncoder.gf_mul(g[a], factor[b])
		g = res
	g.reverse()
	var msg: Array[int] = cws.duplicate()
	for i in range(msg.size() - deg):
		var coef := msg[i]
		if coef != 0:
			for j in range(1, g.size()):
				msg[i + j] ^= KingQrEncoder.gf_mul(coef, g[j])
	for i in range(msg.size() - deg, msg.size()):
		if msg[i] != 0:
			return false
	return true


# --- payload round-trip ------------------------------------------------------

func _payload_roundtrip(cws: Array[int], cap: int, url: String, tag: String) -> void:
	# GDScript ints are 64-bit: cap*8 bits overflows for every version here, so parse
	# straight from a bit array instead of a big integer.
	var bits: Array[int] = []
	for i in range(cap):
		for k in range(7, -1, -1):
			bits.append((cws[i] >> k) & 1)
	var pos := 0
	var mode := 0
	for k in range(4):
		mode = (mode << 1) | bits[pos + k]
	_check(mode == 4, "%s: payload header is byte mode (0100)" % tag)
	pos += 4
	var count := 0
	for k in range(8):
		count = (count << 1) | bits[pos + k]
	_check(count == url.length(), "%s: byte count matches the URL (%d)" % [tag, count])
	pos += 8
	var text := ""
	var ok := pos + count * 8 <= bits.size()
	for i in range(count):
		if pos + 8 > bits.size():
			ok = false
			break
		var ch := 0
		for k in range(8):
			ch = (ch << 1) | bits[pos + k]
		text += char(ch)
		pos += 8
	_check(ok and text == url, "%s: URL round-trips out of the matrix" % tag)


# --- alignment ---------------------------------------------------------------

func _alignment_shape(modules: Array, size: int, tag: String) -> void:
	var centers: Array = CENTERS.get(size, [])
	if centers.is_empty():
		return
	# exactly one alignment pattern, at the bottom-right centre
	var expected := Vector2i(centers[1], centers[1])
	for c in centers:
		for r in centers:
			var is_pattern := _is_alignment(modules, r, c)
			if Vector2i(r, c) == expected:
				_check(is_pattern, "%s: alignment pattern present at (%d, %d)" % [tag, r, c])
			else:
				_check(not is_pattern, "%s: no spurious alignment pattern at (%d, %d)" % [tag, r, c])


func _is_alignment(modules: Array, r: int, c: int) -> bool:
	for dr in range(-2, 3):
		for dc in range(-2, 3):
			var expect: bool = abs(dr) == 2 or abs(dc) == 2 or (dr == 0 and dc == 0)
			if modules[r + dr][c + dc] != expect:
				return false
	return true
