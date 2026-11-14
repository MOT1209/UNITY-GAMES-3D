class_name KingQrEncoder
extends RefCounted

## Compact byte-mode QR code generator (pure GDScript, no dependencies).
## Supports EC level L, versions 1-5 (single RS block each) -> up to 108 bytes.
## Output is a 2D boolean matrix (true = dark module) plus its size.
##
## Returns a Dictionary: { "size": int, "modules": Array[Array[bool]] }.
## On failure (input too long) returns { "size": 0, "modules": [] }.

const VERSIONS: Array[Dictionary] = [
	# capacity = data codewords for EC level L (single block)
	{"v": 1, "size": 21, "cap": 19},
	{"v": 2, "size": 25, "cap": 34},
	{"v": 3, "size": 29, "cap": 55},
	{"v": 4, "size": 33, "cap": 80},
	{"v": 5, "size": 37, "cap": 108},
]

# GF(256) tables (polynomial 0x11D)
static var _exp: Array[int] = []
static var _log: Array[int] = []

static func _init_gf() -> void:
	if _exp.size() > 0:
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in range(255):
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]

static func gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	_init_gf()
	return _exp[_log[a] + _log[b]]

static func gf_poly_mul(a: Array[int], b: Array[int]) -> Array[int]:
	var res: Array[int] = []
	res.resize(a.size() + b.size() - 1)
	for i in range(res.size()):
		res[i] = 0
	for i in range(a.size()):
		if a[i] == 0:
			continue
		for j in range(b.size()):
			res[i + j] ^= gf_mul(a[i], b[j])
	return res

# Build generator polynomial of given degree.
static func _generator(deg: int) -> Array[int]:
	var g: Array[int] = [1]
	for i in range(deg):
		# factor (x + alpha^i) -> coeffs [alpha^i, 1]
		var factor: Array[int] = [_exp[i], 1]
		g = gf_poly_mul(g, factor)
	return g


## Encode `text` (ASCII/Latin-1) into a QR matrix.
static func encode(text: String) -> Dictionary:
	_init_gf()
	var data_bytes := text.to_utf8_buffer()
	# choose version
	var chosen: Dictionary = {}
	for v in VERSIONS:
		var needed_bits := 4 + 8 + data_bytes.size() * 8 + 4
		var needed_bytes := (needed_bits + 7) / 8
		if needed_bytes <= v["cap"]:
			chosen = v
			break
	if chosen.is_empty():
		return {"size": 0, "modules": []}

	var size: int = chosen["size"]
	var cap: int = chosen["cap"]
	var ecc_count := _ecc_for_version(chosen["v"])

	# Build data codewords (length = cap)
	var bits: Array[int] = []
	# mode indicator: byte = 0100
	_append_bits(bits, 0b0100, 4)
	# length (8 bits for v1-9)
	_append_bits(bits, data_bytes.size(), 8)
	for b in data_bytes:
		_append_bits(bits, b, 8)
	# terminator (up to 4 zeros)
	var term: int = min(4, cap * 8 - bits.size())
	for _i in range(term):
		bits.append(0)
	# pad to byte boundary
	while bits.size() % 8 != 0:
		bits.append(0)
	# convert to bytes
	var codewords: Array[int] = []
	var idx := 0
	while idx + 8 <= bits.size():
		var byte := 0
		for k in range(8):
			byte = (byte << 1) | bits[idx + k]
		codewords.append(byte)
		idx += 8
	# pad codewords to capacity with 0xEC, 0x11
	var pad_toggle := true
	while codewords.size() < cap:
		codewords.append(0xEC if pad_toggle else 0x11)
		pad_toggle = not pad_toggle

	# RS error correction
	var gen := _generator(ecc_count)
	# divide codewords (zero-padded) by gen
	var msg: Array[int] = codewords.duplicate()
	msg.resize(cap + ecc_count)
	for i in range(cap):
		msg[i] = codewords[i]
	for i in range(cap):
		var coef := msg[i]
		if coef != 0:
			for j in range(1, gen.size()):
				msg[i + j] ^= gf_mul(coef, gen[j])
	var ecc: Array[int] = []
	for i in range(ecc_count):
		ecc.append(msg[cap + i])

	var full: Array[int] = codewords + ecc

	# Build matrix
	var modules: Array = []
	for r in range(size):
		var row: Array[bool] = []
		row.resize(size)
		for c in range(size):
			row[c] = false
		modules.append(row)
	var is_func: Array = []
	for r in range(size):
		var row: Array[bool] = []
		row.resize(size)
		for c in range(size):
			row[c] = false
		is_func.append(row)

	# Finder patterns
	var finder_positions := [Vector2i(0, 0), Vector2i(0, size - 7), Vector2i(size - 7, 0)]
	for fp in finder_positions:
		_place_finder(modules, is_func, fp.x, fp.y)
	for fp in finder_positions:
		_place_separator(modules, is_func, fp.x, fp.y, size)
	# Timing
	for i in range(8, size - 8):
		var dark := (i % 2 == 0)
		if not is_func[6][i]:
			modules[6][i] = dark
			is_func[6][i] = true
		if not is_func[i][6]:
			modules[i][6] = dark
			is_func[i][6] = true
	# Alignment (v>=2)
	if chosen["v"] >= 2:
		var centers := _alignment_centers(chosen["v"], size)
		for r in centers:
			for c in centers:
				if is_func[r - 2][c - 2]:
					continue
				_place_alignment(modules, is_func, r, c)
	# Format info placeholder (filled after mask chosen)

	# Place data
	var data_bits: Array[int] = []
	for byte in full:
		for k in range(7, -1, -1):
			data_bits.append((byte >> k) & 1)
	_place_data(modules, is_func, size, data_bits)

	# Choose mask + apply format info
	var best_mask := 0
	var best_penalty := 1 << 30
	for mask in range(8):
		var pen := _penalty_if_mask(modules, is_func, size, mask)
		if pen < best_penalty:
			best_penalty = pen
			best_mask = mask
	_apply_mask(modules, is_func, size, best_mask)
	_place_format(modules, is_func, size, best_mask)

	return {"size": size, "modules": modules}


static func _ecc_for_version(v: int) -> int:
	match v:
		1: return 7
		2: return 10
		3: return 15
		4: return 20
		5: return 26
	return 7


static func _alignment_centers(v: int, size: int) -> Array[int]:
	var last := size - 7
	match v:
		2: return [6, 18]
		3: return [6, 22]
		4: return [6, 26]
		5: return [6, 30]
	return [6, last]


static func _append_bits(bits: Array[int], value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _place_finder(modules: Array, is_func: Array, r: int, c: int) -> void:
	for dr in range(7):
		for dc in range(7):
			var dark: bool
			if dr == 0 or dr == 6 or dc == 0 or dc == 6:
				dark = true
			elif dr >= 2 and dr <= 4 and dc >= 2 and dc <= 4:
				dark = true
			else:
				dark = false
			modules[r + dr][c + dc] = dark
			is_func[r + dr][c + dc] = true


static func _place_separator(modules: Array, is_func: Array, r: int, c: int, size: int) -> void:
	# light border around finder
	for dr in range(-1, 8):
		for dc in range(-1, 8):
			var rr := r + dr
			var cc := c + dc
			if rr < 0 or cc < 0 or rr >= size or cc >= size:
				continue
			if dr == -1 or dr == 7 or dc == -1 or dc == 7:
				if not is_func[rr][cc]:
					modules[rr][cc] = false
					is_func[rr][cc] = true


static func _place_alignment(modules: Array, is_func: Array, r: int, c: int) -> void:
	for dr in range(-2, 3):
		for dc in range(-2, 3):
			var dark: bool
			if abs(dr) == 2 or abs(dc) == 2:
				dark = true
			elif dr == 0 and dc == 0:
				dark = true
			else:
				dark = false
			modules[r + dr][c + dc] = dark
			is_func[r + dr][c + dc] = true


static func _place_data(modules: Array, is_func: Array, size: int, bits: Array[int]) -> void:
	var bit_idx := 0
	var col := size - 1
	var going_up := true
	while col >= 1:
		if col == 6:
			col -= 1
		var rows: Array
		if going_up:
			rows = range(size - 1, -1, -1)
		else:
			rows = range(0, size, 1)
		for r in rows:
			for cc in [col, col - 1]:
				if is_func[r][cc]:
					continue
				var bit := 0
				if bit_idx < bits.size():
					bit = bits[bit_idx]
					bit_idx += 1
				modules[r][cc] = (bit == 1)
		col -= 2
		going_up = not going_up


static func _apply_mask(modules: Array, is_func: Array, size: int, mask: int) -> void:
	for r in range(size):
		for c in range(size):
			if is_func[r][c]:
				continue
			var invert := false
			match mask:
				0: invert = ((r + c) % 2 == 0)
				1: invert = (r % 2 == 0)
				2: invert = (c % 3 == 0)
				3: invert = ((r + c) % 3 == 0)
				4: invert = ((r / 2 + c / 3) % 2 == 0) if false else (((r >> 1) + (c / 3)) % 2 == 0)
				5: invert = (((r * c) % 2) + ((r * c) % 3) == 0)
				6: invert = ((((r * c) % 2) + ((r * c) % 3)) % 2 == 0)
				7: invert = ((((r + c) % 2) + ((r * c) % 3)) % 2 == 0)
			if invert:
				modules[r][c] = not modules[r][c]


static func _penalty_if_mask(modules: Array, is_func: Array, size: int, mask: int) -> int:
	# Simulate mask on a copy and score.
	var m: Array = []
	for r in range(size):
		var row: Array[bool] = []
		for c in range(size):
			if is_func[r][c]:
				row.append(modules[r][c])
			else:
				var inv := false
				match mask:
					0: inv = ((r + c) % 2 == 0)
					1: inv = (r % 2 == 0)
					2: inv = (c % 3 == 0)
					3: inv = ((r + c) % 3 == 0)
					4: inv = (((r >> 1) + (c / 3)) % 2 == 0)
					5: inv = (((r * c) % 2) + ((r * c) % 3) == 0)
					6: inv = ((((r * c) % 2) + ((r * c) % 3)) % 2 == 0)
					7: inv = ((((r + c) % 2) + ((r * c) % 3)) % 2 == 0)
				row.append(modules[r][c] != inv)
		m.append(row)
	return _score(m, size)


static func _score(m: Array, size: int) -> int:
	var pen := 0
	# runs in rows
	for r in range(size):
		var run := 1
		for c in range(1, size):
			if m[r][c] == m[r][c - 1]:
				run += 1
			else:
				if run >= 5:
					pen += 3 + (run - 5)
				run = 1
		if run >= 5:
			pen += 3 + (run - 5)
	# runs in cols
	for c in range(size):
		var run := 1
		for r in range(1, size):
			if m[r][c] == m[r - 1][c]:
				run += 1
			else:
				if run >= 5:
					pen += 3 + (run - 5)
				run = 1
		if run >= 5:
			pen += 3 + (run - 5)
	# 2x2 blocks
	for r in range(size - 1):
		for c in range(size - 1):
			var v: bool = m[r][c]
			if m[r][c + 1] == v and m[r + 1][c] == v and m[r + 1][c + 1] == v:
				pen += 3
	# finder-like 1:1:3:1:1
	# simplified: skip
	# balance
	var dark := 0
	for r in range(size):
		for c in range(size):
			if m[r][c]:
				dark += 1
	var total := size * size
	var pct := (dark * 100) / total
	var dev: int = int(abs(pct - 50) / 5)
	pen += dev * 10
	return pen
static func _place_format(modules: Array, is_func: Array, size: int, mask: int) -> void:
	var ec_level := 1
	var format := (ec_level << 3) | mask
	var bch := format << 10
	for i in range(4, -1, -1):
		if (bch >> (i + 10)) & 1:
			bch ^= 0b10100110111 << i
	var code := (format << 10) | bch
	code ^= 0b101010000010010
	var bits_arr: Array[int] = []
	for i in range(14, -1, -1):
		bits_arr.append((code >> i) & 1)

	var pos1: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3),
		Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 7), Vector2i(8, 8),
		Vector2i(7, 8), Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8),
		Vector2i(2, 8), Vector2i(1, 8), Vector2i(0, 8)]
	for i in range(15):
		var pp := pos1[i]
		modules[pp.x][pp.y] = (bits_arr[i] == 1)
		is_func[pp.x][pp.y] = true

	var pos2: Array[Vector2i] = []
	for i in range(7):
		pos2.append(Vector2i(size - 1 - i, 8))
	for i in range(8):
		pos2.append(Vector2i(8, size - 8 + i))
	for i in range(15):
		var pp := pos2[i]
		modules[pp.x][pp.y] = (bits_arr[i] == 1)
		is_func[pp.x][pp.y] = true
