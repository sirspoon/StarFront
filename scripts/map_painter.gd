class_name MapPainter
extends Node2D
## Paints one rectangular tile of the battlefield in detail. MapView renders each
## tile once into a texture at twice the map's resolution and paints it again when
## walls in it are damaged. Everything here is placeholder art drawn in code, but
## it is fully deterministic: the same cell always looks the same, so a repaint
## only changes what was actually destroyed.

const C := BattleMap.CELL
const T := BattleMap.T
const WALL_H := 6.0  # how far wall tops are raised above their base, in map pixels

var map: BattleMap
var cells: Rect2i
var ground_big: Texture2D
var ground_fine: Texture2D
var ground_grit: Texture2D
var rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------- helpers

func _seed(a: int, b: int, c: int) -> void:
	rng.seed = hash(Vector4i(a, b, c, map.map_seed))


func _h(a: int, b: int, c: int) -> float:
	return float(hash(Vector4i(a, b, c, map.map_seed)) % 100000) / 100000.0


func _stone(p: Vector2, size: float, col: Color, sides: int = 6) -> void:
	if size < 1.1:
		draw_circle(p + Vector2(0.4, 0.5), size, Color(0, 0, 0, 0.3))
		draw_circle(p, size, col)
		return
	var pts := PackedVector2Array()
	var a0 := rng.randf() * TAU
	for k in sides:
		pts.append(p + Vector2.from_angle(a0 + k * TAU / sides) * size * rng.randf_range(0.65, 1.0))
	draw_colored_polygon(PackedVector2Array(Array(pts).map(func(v): return v + Vector2(0.6, 0.7))), Color(0, 0, 0, 0.35))
	draw_colored_polygon(pts, col)
	draw_line(pts[sides - 1], pts[0], col.lightened(0.3), 0.6)
	draw_line(pts[0], pts[1], col.lightened(0.22), 0.6)


func _blob(center: Vector2, r: float, squash: float, jag: float, seed_v: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 18
	for k in n:
		var a := k * TAU / n
		var rr := r * (1.0 + (_h(seed_v, k, 7) - 0.5) * jag)
		pts.append(center + Vector2(cos(a) * rr, sin(a) * rr * squash))
	return pts


func _cell_area() -> Rect2i:
	var r := cells.grow(2)
	return r.intersection(Rect2i(0, 0, BattleMap.W, BattleMap.H))


func _near(p: Vector2, reach: float) -> bool:
	var r := Rect2(Vector2(cells.position * C), Vector2(cells.size * C)).grow(reach)
	return r.has_point(p)


# ---------------------------------------------------------------- main

func _draw() -> void:
	var area := _cell_area()
	_draw_ground()
	_draw_roads()
	for s in map.scorches:
		if _near(s[0], s[1]):
			_draw_scorch(s[0], s[1])
	for pd in map.puddles:
		if _near(pd[0], pd[1] + 4):
			_draw_puddle(pd[0], pd[1], pd[2])
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.get_t(Vector2i(x, y)) == T.OPEN:
				_draw_ground_scatter(Vector2i(x, y))
	for i in map.craters.size():
		var cr: Array = map.craters[i]
		if _near(cr[0], cr[1] + 30):
			_draw_crater(cr[0], cr[1], i)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			var t := map.get_t(c)
			if t == T.FLOOR or (t == T.RUBBLE and _indoors(c)):
				_draw_floor(c)
	if map.chapel.intersects(area):
		_draw_chapel_floor()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			var t := map.get_t(c)
			if t == T.RUBBLE:
				_draw_rubble(c)
			elif t == T.FLOOR and _is_fallen(c):
				_seed(c.x, c.y, 31)
				_draw_foundation(c)  # a breach worn into a walkable gap
	# shadows, then wrecks, then the walls themselves from back to front
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.get_t(Vector2i(x, y)) == T.WALL:
				var h := WALL_H * (0.5 if map.wall_stage(Vector2i(x, y)) == 2 else 1.0)
				draw_rect(Rect2(Vector2(x, y) * C + Vector2(3, 2), Vector2(C + h * 0.6, C)), Color(0, 0, 0, 0.28))
	for wk in map.wrecks:
		var rr: Rect2i = wk[0]
		if rr.intersects(area):
			_draw_wreck(rr, wk[1])
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.get_t(Vector2i(x, y)) == T.WALL:
				_draw_wall(Vector2i(x, y))


func _indoors(c: Vector2i) -> bool:
	for b in map.buildings:
		if b.has_point(c):
			return true
	return false


# ---------------------------------------------------------------- ground

func _draw_ground() -> void:
	var ws := map.world_size()
	var r := Rect2(Vector2(cells.position * C), Vector2(cells.size * C)).grow(40)
	draw_rect(r, Color(0.27, 0.25, 0.22))
	draw_texture_rect(ground_big, Rect2(Vector2.ZERO, ws), false)
	# two detail layers at different scales so the repeat doesn't show
	draw_set_transform(Vector2.ZERO, 0, Vector2(0.5, 0.5))
	draw_texture_rect(ground_fine, Rect2(Vector2.ZERO, ws * 2.0), true)
	draw_set_transform(Vector2.ZERO, 0, Vector2(0.75, 0.75))
	draw_texture_rect(ground_grit, Rect2(Vector2.ZERO, ws / 0.75), true)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_ground_scatter(c: Vector2i) -> void:
	_seed(c.x, c.y, 1)
	var o := Vector2(c) * C
	for i in rng.randi_range(2, 6):
		var shade := rng.randf_range(0.28, 0.48)
		_stone(o + Vector2(rng.randf() * C, rng.randf() * C), rng.randf_range(0.5, 1.4),
				Color(shade, shade * 0.96, shade * 0.9), 5)
	var roll := rng.randf()
	if roll < 0.07:
		# a tuft of dead grass
		var p := o + Vector2(rng.randf() * C, rng.randf() * C)
		for k in 7:
			var a := -PI * 0.5 + rng.randf_range(-1.2, 1.2)
			draw_line(p, p + Vector2.from_angle(a) * rng.randf_range(2.5, 5.0),
					Color(0.42, 0.38, 0.22, 0.9).darkened(rng.randf() * 0.3), 0.6)
	elif roll < 0.12:
		# hairline cracks in the dirt
		var p := o + Vector2(rng.randf() * C, rng.randf() * C)
		var pts := PackedVector2Array([p])
		for k in 4:
			p += Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
			pts.append(p)
		draw_polyline(pts, Color(0.1, 0.09, 0.08, 0.55), 0.6)
	elif roll < 0.15:
		# a stray brick or a spent shell casing
		var p := o + Vector2(rng.randf() * C, rng.randf() * C)
		draw_set_transform(p, rng.randf() * TAU, Vector2.ONE)
		if rng.randf() < 0.6:
			draw_rect(Rect2(-2.5, -1.2, 5, 2.4), Color(0.45, 0.25, 0.18))
			draw_line(Vector2(-2.5, -1.2), Vector2(2.5, -1.2), Color(0.6, 0.38, 0.28), 0.5)
		else:
			draw_rect(Rect2(-1.5, -0.5, 3, 1), Color(0.72, 0.58, 0.28))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_roads() -> void:
	for rd in map.roads:
		var r: Rect2 = rd
		if not r.intersects(Rect2(Vector2(cells.position * C), Vector2(cells.size * C)).grow(20)):
			continue
		var horiz := r.size.x > r.size.y
		draw_rect(r, Color(0.16, 0.16, 0.17, 0.8))
		# kerbs
		if horiz:
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(0.42, 0.4, 0.37, 0.8))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), Color(0.42, 0.4, 0.37, 0.8))
		else:
			draw_rect(Rect2(r.position, Vector2(2, r.size.y)), Color(0.42, 0.4, 0.37, 0.8))
			draw_rect(Rect2(r.position + Vector2(r.size.x - 2, 0), Vector2(2, r.size.y)), Color(0.42, 0.4, 0.37, 0.8))
		var length := r.size.x if horiz else r.size.y
		var mid := r.get_center()
		var s := 0.0
		while s < length:
			# worn lane markings, cracks and potholes every few metres
			var p := Vector2(r.position.x + s, mid.y) if horiz else Vector2(mid.x, r.position.y + s)
			if _near(p, 40):
				_seed(int(s), int(r.position.x + r.position.y), 3)
				var dash := Rect2(p - Vector2(0, 1.2), Vector2(26, 2.4)) if horiz else Rect2(p - Vector2(1.2, 0), Vector2(2.4, 26))
				draw_rect(dash, Color(0.65, 0.58, 0.4, rng.randf_range(0.12, 0.35)))
				var q := Vector2(r.position.x + s + rng.randf() * 64, r.position.y + rng.randf() * r.size.y) if horiz \
						else Vector2(r.position.x + rng.randf() * r.size.x, r.position.y + s + rng.randf() * 64)
				var pts := PackedVector2Array([q])
				for k in 6:
					q += Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
					pts.append(q)
				draw_polyline(pts, Color(0.05, 0.05, 0.05, 0.7), 0.8)
				if rng.randf() < 0.3:
					var hp := pts[3]
					draw_colored_polygon(_blob(hp, rng.randf_range(3, 7), 0.7, 0.5, int(s)), Color(0.08, 0.08, 0.08, 0.85))
			s += 64.0


func _draw_scorch(p: Vector2, r: float) -> void:
	var seed_v := int(p.x * 7 + p.y)
	for k in 4:
		draw_colored_polygon(_blob(p, r * (1.0 - k * 0.22), 1.0, 0.5, seed_v + k), Color(0.04, 0.03, 0.02, 0.15))


func _draw_puddle(p: Vector2, r: float, squash: float) -> void:
	var seed_v := int(p.x + p.y * 3)
	draw_colored_polygon(_blob(p + Vector2(0, 1), r + 2, squash, 0.35, seed_v), Color(0.12, 0.11, 0.09, 0.6))
	draw_colored_polygon(_blob(p, r, squash, 0.35, seed_v), Color(0.16, 0.18, 0.2, 0.92))
	# sky reflection and a bright rim on the far side
	draw_colored_polygon(_blob(p + Vector2(-r * 0.2, -r * 0.15 * squash), r * 0.55, squash * 0.7, 0.3, seed_v + 1), Color(0.3, 0.32, 0.34, 0.5))
	draw_line(p + Vector2(-r * 0.5, -r * 0.2 * squash), p + Vector2(r * 0.1, -r * 0.4 * squash), Color(0.7, 0.72, 0.72, 0.4), 0.8)


func _draw_crater(p: Vector2, r: float, idx: int) -> void:
	# thrown-out earth and stones around the rim
	_seed(idx, 0, 9)
	for k in 26:
		var a := rng.randf() * TAU
		var d := r + rng.randf_range(4, 22)
		var sh := rng.randf_range(0.25, 0.45)
		_stone(p + Vector2.from_angle(a) * d, rng.randf_range(0.8, 2.6), Color(sh, sh * 0.95, sh * 0.88), 5)
	draw_colored_polygon(_blob(p, r + 9, 1.0, 0.35, idx * 13), Color(0.36, 0.33, 0.28, 0.9))
	draw_colored_polygon(_blob(p, r + 4, 1.0, 0.3, idx * 13 + 1), Color(0.41, 0.38, 0.32))
	# the bowl: darker towards the bottom, lit on the far (bottom-right) wall
	draw_colored_polygon(_blob(p, r, 1.0, 0.25, idx * 13 + 2), Color(0.17, 0.15, 0.13))
	draw_colored_polygon(_blob(p + Vector2(r * 0.12, r * 0.15), r * 0.82, 1.0, 0.25, idx * 13 + 3), Color(0.24, 0.21, 0.18))
	draw_colored_polygon(_blob(p + Vector2(r * 0.05, r * 0.08), r * 0.6, 1.0, 0.3, idx * 13 + 4), Color(0.14, 0.13, 0.12))
	if _h(idx, 1, 1) < 0.4:
		draw_colored_polygon(_blob(p + Vector2(r * 0.05, r * 0.1), r * 0.35, 0.8, 0.3, idx * 13 + 5), Color(0.15, 0.17, 0.19, 0.95))
		draw_line(p + Vector2(-r * 0.15, 0), p + Vector2(r * 0.1, -r * 0.05), Color(0.55, 0.57, 0.58, 0.35), 0.7)
	for k in 8:
		var a := rng.randf() * TAU
		_stone(p + Vector2.from_angle(a) * r * rng.randf_range(0.2, 0.8), rng.randf_range(0.8, 1.8), Color(0.3, 0.28, 0.25), 5)


# ---------------------------------------------------------------- buildings

func _draw_floor(c: Vector2i) -> void:
	if map.chapel.has_point(c):
		return  # the chapel has its own floor
	var o := Vector2(c) * C
	# flagstones: each cell is one big slab or two long ones, laid in rows
	var slabs: Array = []
	if _h(c.x, c.y, 10) < 0.5:
		slabs.append(Rect2(o, Vector2(C, C)))
	elif (c.y % 2) == 0:
		slabs.append(Rect2(o, Vector2(C, C * 0.5)))
		slabs.append(Rect2(o + Vector2(0, C * 0.5), Vector2(C, C * 0.5)))
	else:
		slabs.append(Rect2(o, Vector2(C * 0.5, C)))
		slabs.append(Rect2(o + Vector2(C * 0.5, 0), Vector2(C * 0.5, C)))
	for k in slabs.size():
		var q := Vector2i(c.x * 2 + k, c.y)
		var v := _h(q.x, q.y, 11)
		var col := Color(0.31, 0.29, 0.26).lightened((v - 0.5) * 0.14)
		if _h(q.x, q.y, 12) < 0.15:
			col = col.darkened(0.3)  # soot
		var sl: Rect2 = slabs[k]
		_draw_slab(sl.grow(-0.5), col, q.x, q.y, 1.0)
	draw_rect(Rect2(o, Vector2(C, C)), Color(0.06, 0.05, 0.04, 0.25), false, 0.4)


## A random patch of one of the ground textures laid over r, so no two stones match.
func _tex_patch(tex: Texture2D, r: Rect2, a: int, b: int, alpha: float) -> void:
	var size := r.size * 2.0
	var room := Vector2(tex.get_width(), tex.get_height()) - size
	var off := Vector2(_h(a, b, 90) * room.x, _h(a, b, 91) * room.y)
	draw_texture_rect_region(tex, r, Rect2(off, size), Color(1, 1, 1, alpha))


## One flagstone: worn surface texture, pitting, bevelled edges, the odd chipped
## corner, stain or crack. strength scales how weathered it looks.
func _draw_slab(r: Rect2, col: Color, a: int, b: int, strength: float) -> void:
	draw_rect(r, col)
	_tex_patch(ground_fine, r, a, b, strength)
	_tex_patch(ground_grit, r, a, b + 7, strength)
	_seed(a, b, 15)
	# grain and pitting
	for i in int(10 * strength):
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		var dark := rng.randf() < 0.6
		draw_circle(p, rng.randf_range(0.2, 0.45), col.darkened(0.35) if dark else col.lightened(0.18))
	# a stain: soot, damp or old blood
	if rng.randf() < 0.18 * strength:
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		var stain: Color = [Color(0.05, 0.04, 0.03, 0.3), Color(0.12, 0.16, 0.12, 0.25), Color(0.25, 0.06, 0.04, 0.2)][rng.randi() % 3]
		draw_colored_polygon(_blob(p, rng.randf_range(1.5, 4.0), rng.randf_range(0.6, 1.0), 0.5, a * 7 + b), stain)
	# bevelled edges: lit top and left, shadowed bottom and right, softened by wear
	draw_line(r.position, r.position + Vector2(r.size.x, 0), col.lightened(0.2), 0.6)
	draw_line(r.position, r.position + Vector2(0, r.size.y), col.lightened(0.1), 0.5)
	draw_line(r.position + Vector2(0, r.size.y), r.end, col.darkened(0.4), 0.6)
	draw_line(r.position + Vector2(r.size.x, 0), r.end, col.darkened(0.3), 0.5)
	# a chipped corner
	if rng.randf() < 0.25 * strength:
		var corner := rng.randi() % 4
		var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)][corner] as Vector2
		var dx := 1.0 if corner == 0 or corner == 3 else -1.0
		var dy := 1.0 if corner < 2 else -1.0
		var sz := rng.randf_range(1.2, 2.8)
		var chip := PackedVector2Array([p, p + Vector2(dx * sz, 0), p + Vector2(dx * sz * 0.3, dy * sz * 0.4), p + Vector2(0, dy * sz)])
		draw_colored_polygon(chip, col.darkened(0.55))
		draw_line(chip[1], chip[2], col.lightened(0.15), 0.4)
	# a crack running across it
	if rng.randf() < 0.22 * strength:
		var horiz := rng.randf() < 0.5
		var p0: Vector2
		var p1: Vector2
		if horiz:
			p0 = Vector2(r.position.x, r.position.y + rng.randf_range(0.2, 0.8) * r.size.y)
			p1 = Vector2(r.end.x, r.position.y + rng.randf_range(0.2, 0.8) * r.size.y)
		else:
			p0 = Vector2(r.position.x + rng.randf_range(0.2, 0.8) * r.size.x, r.position.y)
			p1 = Vector2(r.position.x + rng.randf_range(0.2, 0.8) * r.size.x, r.end.y)
		if rng.randf() < 0.4:
			p1 = p0.lerp(p1, rng.randf_range(0.4, 0.75))  # stops part way
		_crack(p0, p1, r, rng.randf_range(0.5, 0.9), col)


## A crack with depth: a dark gap that is widest in the middle, a lit lip on its
## far side, small chips knocked out along it and a branch or two.
func _crack(p0: Vector2, p1: Vector2, bounds: Rect2, width: float, surface: Color) -> void:
	var pts := PackedVector2Array()
	var n := 6
	var dir := (p1 - p0)
	var nrm := dir.orthogonal().normalized()
	for i in n + 1:
		var t := float(i) / n
		var jit := 0.0 if i == 0 or i == n else rng.randf_range(-1.6, 1.6)
		pts.append((p0 + dir * t + nrm * jit).clamp(bounds.position, bounds.end))
	var lip := surface.lightened(0.28)
	var gap := Color(0.04, 0.035, 0.03, 0.95)
	for i in n:
		var t := (i + 0.5) / n
		var w := width * (1.15 - absf(t - 0.5) * 1.5)
		draw_line(pts[i] + Vector2(0.45, 0.45), pts[i + 1] + Vector2(0.45, 0.45), lip, maxf(0.3, w * 0.6))
		draw_line(pts[i], pts[i + 1], gap, maxf(0.25, w))
	for i in range(1, n):
		if rng.randf() < 0.3:
			var p := pts[i]
			draw_colored_polygon(PackedVector2Array([p + Vector2(-0.8, -0.3), p + Vector2(0.6, -0.7), p + Vector2(0.3, 0.8)]), gap)
	for k in rng.randi_range(0, 2):
		var start := pts[rng.randi_range(1, n - 1)]
		var bdir := (dir.normalized() * 0.6 + nrm * (1.0 if rng.randf() < 0.5 else -1.0)).normalized()
		var mid := (start + bdir * rng.randf_range(1.5, 3.0) + nrm * rng.randf_range(-0.6, 0.6)).clamp(bounds.position, bounds.end)
		var end := (mid + bdir * rng.randf_range(1.0, 2.5)).clamp(bounds.position, bounds.end)
		draw_line(start + Vector2(0.4, 0.4), mid + Vector2(0.4, 0.4), lip, 0.3)
		draw_polyline(PackedVector2Array([start, mid, end]), gap, maxf(0.25, width * 0.45))


func _draw_chapel_floor() -> void:
	var ch := map.chapel
	var r := Rect2(Vector2(ch.position * C), Vector2(ch.size * C))
	for y in range(ch.position.y * 2, ch.end.y * 2):
		for x in range(ch.position.x * 2, ch.end.x * 2):
			var c := Vector2i(x / 2, y / 2)
			if map.get_t(c) != T.FLOOR and map.get_t(c) != T.WALL:
				continue
			var light := (x / 2 + y / 2) % 2 == 0
			var col := Color(0.42, 0.4, 0.37) if light else Color(0.3, 0.29, 0.28)
			col = col.lightened((_h(x, y, 21) - 0.5) * 0.08)
			var tr := Rect2(Vector2(x, y) * (C * 0.5), Vector2(C * 0.5, C * 0.5))
			draw_rect(tr, col)
			_tex_patch(ground_fine, tr, x, y, 0.7)
			_tex_patch(ground_grit, tr, x, y + 5, 0.5)
			if x % 2 == 0 and y % 2 == 0:
				draw_rect(Rect2(tr.position, Vector2(C, C)), Color(0.1, 0.09, 0.08, 0.5), false, 0.5)
			if light and _h(x, y, 22) < 0.5:
				var a := tr.position + Vector2(0, _h(x, y, 23) * 8)
				draw_line(a, a + Vector2(8, _h(x, y, 24) * 8 - 2), col.darkened(0.2), 0.4)  # marble vein
	# a faded red runner down the nave, edged in tarnished gold
	var cy := r.get_center().y
	var run := Rect2(r.position.x + C * 1.5, cy - C * 1.2, r.size.x - C * 5, C * 2.4)
	draw_rect(run, Color(0.32, 0.07, 0.06, 0.85))
	draw_rect(run.grow(-1.5), Color(0.62, 0.48, 0.2, 0.7), false, 0.8)
	for k in 10:
		var px := run.position.x + _h(k, 5, 25) * run.size.x
		draw_colored_polygon(_blob(Vector2(px, run.position.y + _h(k, 6, 25) * run.size.y), 3.0, 1.0, 0.6, k),
				Color(0.2, 0.18, 0.16, 0.9))  # torn holes
	# a mosaic sunburst at the crossing
	var c := r.get_center() + Vector2(-C * 2, 0)
	for i in 14:
		var a := i * TAU / 14.0
		draw_line(c + Vector2.from_angle(a) * 8, c + Vector2.from_angle(a) * 30, Color(0.78, 0.62, 0.3, 0.7), 2.0)
	draw_circle(c, 9.0, Color(0.6, 0.46, 0.2))
	draw_circle(c, 5.0, Color(0.2, 0.15, 0.1))
	# shattered stained glass near the walls
	_seed(ch.position.x, ch.position.y, 26)
	for k in 70:
		var edge := rng.randi() % 4
		var p := Vector2()
		match edge:
			0:
				p = Vector2(rng.randf_range(r.position.x, r.end.x), r.position.y + C + rng.randf() * 10)
			1:
				p = Vector2(rng.randf_range(r.position.x, r.end.x), r.end.y - C - rng.randf() * 10)
			2:
				p = Vector2(r.position.x + C + rng.randf() * 10, rng.randf_range(r.position.y, r.end.y))
			_:
				p = Vector2(r.end.x - C - rng.randf() * 10, rng.randf_range(r.position.y, r.end.y))
		var glass: Color = [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.75, 0.6, 0.15), Color(0.2, 0.5, 0.3)][rng.randi() % 4]
		var pts := PackedVector2Array([p, p + Vector2(rng.randf_range(0.8, 2.2), rng.randf_range(-0.6, 0.6)),
				p + Vector2(rng.randf_range(-0.5, 1), rng.randf_range(0.8, 2))])
		draw_colored_polygon(pts, Color(glass, 0.85))


func _draw_rubble(c: Vector2i) -> void:
	_seed(c.x, c.y, 31)
	var o := Vector2(c) * C
	var from_wall := map.fallen[c.y * BattleMap.W + c.x] == 1
	draw_colored_polygon(_blob(o + Vector2(8, 8), 9.5, 1.0, 0.45, c.x * 977 + c.y), Color(0.33, 0.31, 0.27, 0.6))
	if from_wall:
		_draw_foundation(c)
	for k in (rng.randi_range(3, 5) if from_wall else rng.randi_range(7, 12)):
		var p := o + Vector2(rng.randf_range(0, C), rng.randf_range(0, C))
		var sh := rng.randf_range(0.3, 0.55)
		_stone(p, rng.randf_range(1.0, 3.8), Color(sh, sh * 0.95, sh * 0.88), rng.randi_range(5, 7))
	if rng.randf() < 0.3:
		var p := o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14))
		draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5, 9), Color(0.3, 0.18, 0.12), 0.8)  # rebar
	if rng.randf() < 0.25:
		var p := o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14))
		draw_set_transform(p, rng.randf() * TAU, Vector2.ONE)
		draw_rect(Rect2(-2.5, -1.2, 5, 2.4), Color(0.45, 0.25, 0.18))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## What's left where a wall collapsed: a broken concrete footing still in line
## with the standing wall either side, slab chunks and twisted rebar thrown out
## to both sides.
func _draw_foundation(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var wb := _wall_base(c)
	var linked := func(d: Vector2i) -> bool:
		var t := map.get_t(c + d)
		return t == T.WALL or _is_fallen(c + d)
	var horiz: bool = linked.call(Vector2i(-1, 0)) or linked.call(Vector2i(1, 0))
	var vert: bool = linked.call(Vector2i(0, -1)) or linked.call(Vector2i(0, 1))
	var across := Vector2(0, 1) if horiz and not vert else (Vector2(1, 0) if vert and not horiz else Vector2.ZERO)
	# the footing: a dark bed with the wall's outline still showing along its edges
	draw_rect(Rect2(o + Vector2(1.5, 2.0), Vector2(C, C)), Color(0, 0, 0, 0.3))
	var bed := PackedVector2Array([o, o + Vector2(C, 0), o + Vector2(C, C), o + Vector2(0, C)])
	_poly(bed, wb.darkened(0.45))
	_tex_poly(bed, c.x / 4, c.y / 4, 1.0)
	var edge := wb.darkened(0.2)
	if across == Vector2(0, 1) or across == Vector2.ZERO:
		draw_rect(Rect2(o + Vector2(0, 0.3), Vector2(C, 1.8)), edge)
		draw_rect(Rect2(o + Vector2(0, C - 2.1), Vector2(C, 1.8)), edge.darkened(0.3))
	if across == Vector2(1, 0) or across == Vector2.ZERO:
		draw_rect(Rect2(o + Vector2(0.3, 0), Vector2(1.8, C)), edge)
		draw_rect(Rect2(o + Vector2(C - 2.1, 0), Vector2(1.8, C)), edge.darkened(0.3))
	# stubs of the broken wall: low, jagged slabs of concrete
	_seed(c.x, c.y, 75)
	for k in rng.randi_range(1, 3):
		var p := o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14))
		_chunk(p, rng.randf_range(2.5, 4.5), wb.darkened(rng.randf_range(0.05, 0.25)), c.x * 13 + k, c.y)
	# rebar left standing out of the footing
	for k in rng.randi_range(1, 3):
		var p := o + Vector2(rng.randf_range(3, 13), rng.randf_range(3, 13))
		_rebar(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3, 6))
	# slab chunks thrown out to both sides of the old wall line
	for k in 9:
		var along := rng.randf_range(0, C)
		var side := rng.randf_range(-1.0, 1.0)
		var p: Vector2
		if across == Vector2(0, 1):
			p = o + Vector2(along, 8.0 + side * 15.0)
		elif across == Vector2(1, 0):
			p = o + Vector2(8.0 + side * 15.0, along)
		else:
			p = o + Vector2(8, 8) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4, 15)
		_chunk(p, rng.randf_range(1.5, 4.0), wb.darkened(rng.randf_range(0.0, 0.3)), c.x * 31 + k, c.y * 7)
		if rng.randf() < 0.2:
			_rebar(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3, 7))


## A broken piece of concrete: an angular slab with a lit top edge and a shadow.
func _chunk(p: Vector2, size: float, col: Color, a: int, b: int) -> void:
	if size < 2.2:
		_stone(p, size, col, 4)
		return
	var pts := PackedVector2Array()
	var n := 4 + int(_h(a, b, 81) * 3.0)
	var a0 := _h(a, b, 82) * TAU
	for k in n:
		var ang := a0 + k * TAU / n + (_h(a, b, 83 + k) - 0.5) * 0.8
		pts.append(p + Vector2.from_angle(ang) * size * (0.55 + _h(a, b, 90 + k) * 0.45))
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(0.9, 1.1))
	_poly(sh, Color(0, 0, 0, 0.35))
	_poly(pts, col)
	_tex_poly(pts, a, b, 0.8)
	draw_line(pts[n - 1], pts[0], col.lightened(0.28), 0.6)
	draw_line(pts[0], pts[1], col.lightened(0.18), 0.5)
	draw_line(pts[n / 2], pts[n / 2 + 1 if n / 2 + 1 < n else 0], col.darkened(0.35), 0.5)


## draw_colored_polygon, but skipping shapes too thin or twisted to fill.
static var skipped := 0
func _poly(pts: PackedVector2Array, col: Color, uvs := PackedVector2Array(), tex: Texture2D = null) -> void:
	if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
		skipped += 1
		return
	draw_colored_polygon(pts, col, uvs, tex)


func _rebar(a: Vector2, b: Vector2) -> void:
	var mid := a.lerp(b, 0.6) + (b - a).orthogonal().normalized() * 0.8
	draw_polyline(PackedVector2Array([a + Vector2(0.4, 0.5), mid + Vector2(0.4, 0.5), b + Vector2(0.4, 0.5)]), Color(0, 0, 0, 0.4), 0.7)
	draw_polyline(PackedVector2Array([a, mid, b]), Color(0.42, 0.22, 0.12), 0.6)


## Lay the ground's grit texture over a polygon, aligned to the world so
## neighbouring pieces of the same wall join up.
func _tex_poly(pts: PackedVector2Array, a: int, b: int, alpha: float) -> void:
	var uvs := PackedVector2Array()
	var off := Vector2(_h(a, b, 95), _h(a, b, 96))
	for q in pts:
		uvs.append(q / 256.0 + off)
	_poly(pts, Color(1, 1, 1, alpha), uvs, ground_grit)
	var uvs2 := PackedVector2Array()
	for q in pts:
		uvs2.append(q / 300.0 + off * 0.7)
	_poly(pts, Color(1, 1, 1, alpha * 0.8), uvs2, ground_fine)


func _wall_base(c: Vector2i) -> Color:
	if map.chapel.grow(1).has_point(c):
		return Color(0.52, 0.5, 0.47)  # pale, older ferrocrete
	# each building was cast from its own batch of concrete
	for i in map.buildings.size():
		if map.buildings[i].grow(1).has_point(c):
			var v := _h(i, 0, 41)
			return Color(0.41, 0.4, 0.38).lerp(Color(0.4, 0.37, 0.33), v)
	return Color(0.4, 0.39, 0.37)


func _is_fallen(c: Vector2i) -> bool:
	return map.in_bounds(c) and map.get_t(c) != T.WALL and map.fallen[c.y * BattleMap.W + c.x] == 1


## Points along one edge of a wall's top, from a towards b (b not included).
## Next to a collapse the edge is torn into a jagged line bitten into the slab.
func _edge(c: Vector2i, a: Vector2, b: Vector2, inward: Vector2, torn: bool, salt: int) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	if not torn:
		return out
	var n := 7
	for k in range(1, n):
		var t := float(k) / n
		var depth := (0.8 + _h(c.x * 3 + salt, c.y * 3 + k, 51) * 6.0) * pow(sin(PI * t), 2.0)  # shallow at corners so edges never cross
		out.append(a.lerp(b, t) + inward * depth)
	return out


func _draw_wall(c: Vector2i) -> void:
	var stage := map.wall_stage(c)
	var h := WALL_H * (0.5 if stage == 2 else 1.0)
	var o := Vector2(c) * C
	var base := _wall_base(c)
	var below := map.get_t(c + Vector2i(0, 1)) == T.WALL
	var above := map.get_t(c + Vector2i(0, -1)) == T.WALL
	var left := map.get_t(c + Vector2i(-1, 0)) == T.WALL
	var right := map.get_t(c + Vector2i(1, 0)) == T.WALL
	var fu := _is_fallen(c + Vector2i(0, -1))
	var fr := _is_fallen(c + Vector2i(1, 0))
	var fd := _is_fallen(c + Vector2i(0, 1))
	var fl := _is_fallen(c + Vector2i(-1, 0))
	var top_y := o.y - h
	var tl := Vector2(o.x, top_y)
	var tr := Vector2(o.x + C, top_y)
	var br := Vector2(o.x + C, top_y + C)
	var bl := Vector2(o.x, top_y + C)
	# the outline of the slab's top, torn where the wall next to it fell
	var e_top := _edge(c, tl, tr, Vector2(0, 1), fu, 0)
	var e_right := _edge(c, tr, br, Vector2(-1, 0), fr, 1)
	var e_bottom := _edge(c, br, bl, Vector2(0, -1), fd, 2)
	var e_left := _edge(c, bl, tl, Vector2(1, 0), fl, 3)
	var poly := PackedVector2Array()
	poly.append_array(e_top)
	poly.append_array(e_right)
	poly.append_array(e_bottom)
	poly.append_array(e_left)
	# the front face, hanging below the bottom edge of the top
	if not below:
		var chain := PackedVector2Array(e_bottom)
		chain.append(bl)
		var face := PackedVector2Array()
		for q in chain:
			face.append(q)
		for i in range(chain.size() - 1, -1, -1):
			face.append(chain[i] + Vector2(0, h))
		var fcol := base.darkened(0.42)
		_poly(face, fcol)
		_tex_poly(face, c.x, c.y + 1000, 0.9)
		# rain streaks and formwork tie holes
		_seed(c.x, c.y, 47)
		for k in 3:
			var x := o.x + rng.randf_range(1, C - 1)
			draw_line(Vector2(x, top_y + C), Vector2(x, top_y + C + h * rng.randf_range(0.5, 1.0)), Color(0.05, 0.05, 0.05, 0.25), rng.randf_range(0.6, 1.4))
		if c.x % 2 == 0 and not fl and not fr:
			draw_circle(Vector2(o.x + 4, top_y + C + h * 0.5), 0.5, Color(0.08, 0.08, 0.08))
			draw_circle(Vector2(o.x + 12, top_y + C + h * 0.5), 0.5, Color(0.08, 0.08, 0.08))
	# the top of the slab
	_poly(poly, base)
	_tex_poly(poly, c.x / 4, c.y / 4, 1.0)
	_tex_poly(poly, c.x / 4 + 9, c.y / 4 + 9, 0.7)
	_seed(c.x, c.y, 46)
	# mottling: damp patches and paler, sun-bleached ones
	for k in 3:
		var p := o + Vector2(rng.randf_range(0, C), rng.randf_range(0, C) - h)
		var dark := rng.randf() < 0.6
		var blob := _blob(p, rng.randf_range(3, 7), rng.randf_range(0.6, 1.0), 0.5, c.x * 17 + c.y * 3 + k)
		var clip := Geometry2D.intersect_polygons(blob, poly)
		for piece in clip:
			_poly(piece, Color(0.05, 0.05, 0.04, 0.16) if dark else Color(1, 1, 0.95, 0.06))
	for k in 14:
		var p := o + Vector2(rng.randf_range(1, C - 1), rng.randf_range(1, C - 1) - h)
		if Geometry2D.is_point_in_polygon(p, poly):
			draw_circle(p, rng.randf_range(0.2, 0.5), base.darkened(0.3) if rng.randf() < 0.6 else base.lightened(0.15))  # aggregate
	if rng.randf() < 0.35:
		var p := o + Vector2(rng.randf_range(3, 13), rng.randf_range(3, 13) - h)
		draw_colored_polygon(_blob(p, rng.randf_range(2, 5), 0.8, 0.5, c.x * 5 + c.y), Color(0.08, 0.08, 0.06, 0.18))  # weathering
	# panel joints where the formwork met
	var runs_x := left or right or fl or fr
	var runs_y := above or below or fu or fd
	if runs_x and not runs_y and c.x % 3 == 0 and not fl:
		draw_line(tl + Vector2(0, 1), bl - Vector2(0, 1), base.darkened(0.35), 0.6)
		draw_line(tl + Vector2(0.6, 1), bl + Vector2(0.6, -1), base.lightened(0.12), 0.4)
	elif runs_y and not runs_x and c.y % 3 == 0 and not fu:
		draw_line(tl + Vector2(1, 0), tr - Vector2(1, 0), base.darkened(0.35), 0.6)
		draw_line(tl + Vector2(1, 0.6), tr + Vector2(-1, 0.6), base.lightened(0.12), 0.4)
	# edges: lit where the wall ends cleanly, dark and broken where it was torn off
	if not above and not fu:
		draw_line(tl, tr, base.lightened(0.25), 0.7)
	if not left and not fl:
		draw_line(tl, bl, base.lightened(0.2), 0.7)
	if not right and not fr:
		draw_line(tr, br, base.darkened(0.5), 0.9)
	for torn in [[fu, e_top], [fr, e_right], [fd, e_bottom], [fl, e_left]]:
		if not torn[0]:
			continue
		var e: PackedVector2Array = torn[1]
		for i in range(1, e.size() - 1):
			draw_line(e[i], e[i + 1], base.darkened(0.55), 0.8)
		# reinforcing bars sticking out of the break
		_seed(c.x, c.y, 48 + e.size())
		for k in 2:
			var q := e[rng.randi_range(1, e.size() - 1)]
			var out := (q - (o + Vector2(8, 8 - h))).normalized()
			_rebar(q - out * 1.5, q + out * rng.randf_range(2.5, 5.5) + out.orthogonal() * rng.randf_range(-1.5, 1.5))
	# damage: chunks blown out showing the rebar inside, and cracks
	if stage > 0:
		_seed(c.x, c.y, 45)
		for n in stage * 2:
			var p := o + Vector2(rng.randf_range(3, 13), rng.randf_range(3, 13) - h)
			var hole := _blob(p, rng.randf_range(1.5, 3.2) * stage, 0.8, 0.6, c.x * 11 + c.y + n)
			_poly(hole, base.darkened(0.6))
			draw_line(p + Vector2(-2.5, -0.8), p + Vector2(2.5, 0.8), Color(0.42, 0.22, 0.12), 0.5)
		var top := Rect2(o.x, top_y, C, C)
		for n in stage + 1:
			var p := top.position + Vector2(rng.randf() * C, rng.randf() * C)
			var q := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6, 12)
			_crack(p, q, top, rng.randf_range(0.7, 1.1), base)
		_poly(poly, Color(0.05, 0.04, 0.03, 0.12 * stage))  # soot


func _draw_wreck(rect: Rect2i, horiz: bool) -> void:
	var rr := Rect2(Vector2(rect.position * C), Vector2(rect.size * C))
	var hull := rr.grow(-2)
	draw_rect(Rect2(hull.position + Vector2(5, 6), hull.size), Color(0, 0, 0, 0.4))
	var tracks := Color(0.11, 0.1, 0.09)
	var tw := 8.0
	if horiz:
		for y in [hull.position.y, hull.end.y - tw]:
			draw_rect(Rect2(hull.position.x, y, hull.size.x, tw), tracks)
			for i in range(0, int(hull.size.x), 4):
				draw_line(Vector2(hull.position.x + i, y), Vector2(hull.position.x + i, y + tw), Color(0.2, 0.19, 0.17), 0.8)
	else:
		for x in [hull.position.x, hull.end.x - tw]:
			draw_rect(Rect2(x, hull.position.y, tw, hull.size.y), tracks)
			for i in range(0, int(hull.size.y), 4):
				draw_line(Vector2(x, hull.position.y + i), Vector2(x + tw, hull.position.y + i), Color(0.2, 0.19, 0.17), 0.8)
	var body := hull.grow(-6)
	draw_rect(body, Color(0.23, 0.21, 0.18))
	# rust streaks and scorching
	_seed(rect.position.x, rect.position.y, 51)
	for k in 12:
		var p := body.position + Vector2(rng.randf() * body.size.x, rng.randf() * body.size.y)
		draw_circle(p, rng.randf_range(1, 3.5), Color(0.38, 0.18, 0.08, 0.5) if k % 2 == 0 else Color(0.05, 0.04, 0.04, 0.6))
	draw_rect(body, Color(0.07, 0.06, 0.05), false, 1.5)
	for i in 4:
		var y := body.position.y + body.size.y * (0.2 + i * 0.2)
		if horiz:
			draw_line(Vector2(body.position.x + 3, y), Vector2(body.end.x - 3, y), Color(0.15, 0.14, 0.12), 0.6)
	var mid := body.get_center()
	draw_circle(mid + Vector2(1, 2), 12, Color(0, 0, 0, 0.35))
	draw_circle(mid, 11, Color(0.2, 0.18, 0.16))
	draw_arc(mid, 11, 0, TAU, 28, Color(0.06, 0.05, 0.05), 1.5)
	var barrel_dir := Vector2(1, 0.25) if horiz else Vector2(0.3, 1)
	draw_line(mid, mid + barrel_dir.normalized() * 34, Color(0.1, 0.09, 0.08), 4.0)
	draw_circle(mid + Vector2(-3, -2), 4, Color(0.04, 0.04, 0.04))
	draw_circle(mid + Vector2(-3, -2), 2, Color(0.25, 0.1, 0.04))
