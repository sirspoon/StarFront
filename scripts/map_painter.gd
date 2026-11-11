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
		var r := sl.grow(-0.5)
		draw_rect(r, col)
		draw_line(r.position, r.position + Vector2(r.size.x, 0), col.lightened(0.15), 0.5)
		draw_line(r.position + Vector2(0, r.size.y), r.end, col.darkened(0.3), 0.5)
		if _h(q.x, q.y, 13) < 0.18:
			var a := r.position + Vector2(_h(q.x, q.y, 14) * r.size.x, 0)
			draw_polyline(PackedVector2Array([a, a + Vector2(1.5, 2.5), a + Vector2(0.5, 4.5), a + Vector2(2, r.size.y)]),
					Color(0.08, 0.07, 0.06, 0.7), 0.5)
	draw_rect(Rect2(o, Vector2(C, C)), Color(0.06, 0.05, 0.04, 0.25), false, 0.4)


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


## What's left where a wall collapsed: its footing, still in line with the
## standing wall either side, with broken base stones and its rubble spilled
## out on both sides.
func _draw_foundation(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var wb := _wall_base(c)
	var linked := func(d: Vector2i) -> bool:
		var t := map.get_t(c + d)
		return t == T.WALL or _is_fallen(c + d)
	var horiz: bool = linked.call(Vector2i(-1, 0)) or linked.call(Vector2i(1, 0))
	var vert: bool = linked.call(Vector2i(0, -1)) or linked.call(Vector2i(0, 1))
	var across := Vector2(0, 1) if horiz and not vert else (Vector2(1, 0) if vert and not horiz else Vector2.ZERO)
	# footing: dark bed with a slightly raised lip
	draw_rect(Rect2(o + Vector2(1.5, 2.0), Vector2(C, C)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(o, Vector2(C, C)), Color(0.12, 0.11, 0.1))
	# the outline of the old wall: its lowest stones still mark the edges
	var edge_col := wb.darkened(0.25)
	if across == Vector2(0, 1) or across == Vector2.ZERO:
		draw_rect(Rect2(o + Vector2(0, 0.3), Vector2(C, 1.6)), edge_col)
		draw_rect(Rect2(o + Vector2(0, C - 1.9), Vector2(C, 1.6)), edge_col.darkened(0.3))
	if across == Vector2(1, 0) or across == Vector2.ZERO:
		draw_rect(Rect2(o + Vector2(0.3, 0), Vector2(1.6, C)), edge_col)
		draw_rect(Rect2(o + Vector2(C - 1.9, 0), Vector2(1.6, C)), edge_col.darkened(0.3))
	# the bottom course of stones, in the same bond as the standing wall, many broken off
	for k in 4:
		var y := o.y + k * 4.0
		var row := c.y * 4 + k
		var off := 4.0 if row % 2 == 1 else 0.0
		var x := o.x - off
		while x < o.x + C:
			var bx0 := maxf(x, o.x)
			var bx1 := minf(x + 8.0, o.x + C)
			var bi := int(floor((x + off) / 8.0))
			var v := _h(bi, row, 71)
			if bx1 - bx0 > 0.8 and v > 0.35:
				var col := wb.darkened(0.05 + _h(bi, row, 72) * 0.2)
				var br := Rect2(bx0 + 0.5, y + 0.4, bx1 - bx0 - 1.0, 3.2)
				# stones snap off unevenly
				var pts := PackedVector2Array([br.position, br.position + Vector2(br.size.x, 0),
						br.end - Vector2(0, _h(bi, row, 73) * 1.5), br.position + Vector2(br.size.x * 0.4, br.size.y),
						br.position + Vector2(0, br.size.y - _h(bi, row, 74) * 1.5)])
				draw_colored_polygon(pts, col)
				draw_line(pts[0], pts[1], col.lightened(0.25), 0.5)
				draw_line(pts[2], pts[3], col.darkened(0.4), 0.5)
			x += 8.0
	# a few stones still standing proud of the rest
	_seed(c.x, c.y, 75)
	for k in rng.randi_range(0, 2):
		var p := o + Vector2(rng.randf_range(2, 11), rng.randf_range(2, 11))
		draw_rect(Rect2(p + Vector2(1, 1.5), Vector2(5, 3.5)), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(p, Vector2(5, 3.5)), wb.darkened(0.05))
		draw_line(p, p + Vector2(5, 0), wb.lightened(0.3), 0.6)
	# masonry thrown out to both sides of the old wall line
	for k in 10:
		var along := rng.randf_range(0, C)
		var side := rng.randf_range(-1.0, 1.0)
		var p: Vector2
		if across == Vector2(0, 1):
			p = o + Vector2(along, 8.0 + side * 15.0)
		elif across == Vector2(1, 0):
			p = o + Vector2(8.0 + side * 15.0, along)
		else:
			p = o + Vector2(8, 8) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4, 15)
		draw_set_transform(p, rng.randf_range(-0.8, 0.8), Vector2.ONE)
		var bc := wb.lightened(rng.randf_range(-0.2, 0.08))
		var bw := rng.randf_range(3.5, 7.0)
		draw_rect(Rect2(-bw * 0.5 + 0.6, -1.4, bw, 3.2), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(-bw * 0.5, -2.0, bw, 3.2), bc)
		draw_line(Vector2(-bw * 0.5, -2.0), Vector2(bw * 0.5, -2.0), bc.lightened(0.25), 0.6)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _wall_base(c: Vector2i) -> Color:
	if map.chapel.grow(1).has_point(c):
		return Color(0.6, 0.57, 0.53)
	# each building has its own stone
	for i in map.buildings.size():
		if map.buildings[i].grow(1).has_point(c):
			var v := _h(i, 0, 41)
			return Color(0.5, 0.47, 0.42).lerp(Color(0.46, 0.4, 0.35), v)
	return Color(0.5, 0.47, 0.43)


func _is_fallen(c: Vector2i) -> bool:
	return map.in_bounds(c) and map.get_t(c) != T.WALL and map.fallen[c.y * BattleMap.W + c.x] == 1


## Where each of the wall's four courses of coping stones starts and ends. Next
## to a collapsed section the courses break off at different lengths, so the
## end of the wall looks torn rather than cut.
func _course_extents(c: Vector2i) -> Array:
	var o := Vector2(c) * C
	var fl := _is_fallen(c + Vector2i(-1, 0))
	var fr := _is_fallen(c + Vector2i(1, 0))
	var fu := _is_fallen(c + Vector2i(0, -1))
	var fd := _is_fallen(c + Vector2i(0, 1))
	var out: Array = []
	for k in 4:
		var x0 := o.x
		var x1 := o.x + C
		if fl:
			x0 += 1.0 + floorf(_h(c.x, c.y * 4 + k, 61) * 6.0) * 2.0
		if fr:
			x1 -= 1.0 + floorf(_h(c.x, c.y * 4 + k, 62) * 6.0) * 2.0
		# courses nearest a collapse above or below are mostly gone
		var gone_chance := 0.0
		if fu:
			gone_chance = maxf(gone_chance, [0.6, 0.3, 0.0, 0.0][k])
		if fd:
			gone_chance = maxf(gone_chance, [0.0, 0.0, 0.3, 0.6][k])
		if gone_chance > 0.0:
			var v := _h(c.x, c.y * 4 + k, 63)
			if v < gone_chance:
				# only a jagged stub of this course is left
				var mid := (x0 + x1) * 0.5 + (_h(c.x, k, 60) - 0.5) * 6.0
				var half := 1.0 + _h(c.y, k, 59) * 3.0
				x0 = maxf(x0, mid - half)
				x1 = minf(x1, mid + half)
			elif v < gone_chance + 0.3:
				if _h(c.x, k, 64) < 0.5:
					x0 += 3.0 + _h(c.x, k, 65) * 8.0
				else:
					x1 -= 3.0 + _h(c.x, k, 66) * 8.0
		out.append([x0, x1] if x1 - x0 >= 2.0 else [x0, x0])
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
	var broken := _is_fallen(c + Vector2i(-1, 0)) or _is_fallen(c + Vector2i(1, 0)) \
			or _is_fallen(c + Vector2i(0, -1)) or _is_fallen(c + Vector2i(0, 1))
	var top_y := o.y - h
	var ext := _course_extents(c)
	# south face, in courses of brick, under whatever is left of the bottom course
	if not below:
		var fx0: float = ext[3][0]
		var fx1: float = ext[3][1]
		if fx1 > fx0:
			var face := Rect2(fx0, o.y + C - h, fx1 - fx0, h)
			draw_rect(face, base.darkened(0.5))
			var rows := int(h / 2.0)
			for k in rows:
				var y := face.position.y + k * 2.0
				var off := 2.0 if (k % 2) == 1 else 0.0
				var x := o.x - off
				while x < o.x + C:
					var bx0 := maxf(x, fx0)
					var bx1 := minf(x + 4.0, fx1)
					if bx1 - bx0 > 0.6:
						draw_rect(Rect2(bx0 + 0.25, y + 0.25, bx1 - bx0 - 0.5, 1.5), base.darkened(0.38 + _h(int(x), int(y), 42) * 0.12))
					x += 4.0
	# the top: coping stones in a running bond, lit from the top left
	for k in 4:
		var y := top_y + k * 4.0
		var cx0: float = ext[k][0]
		var cx1: float = ext[k][1]
		if cx1 <= cx0:
			continue
		draw_rect(Rect2(cx0, y, cx1 - cx0, 4), base.darkened(0.42))  # mortar
		var row := c.y * 4 + k
		var off := 4.0 if row % 2 == 1 else 0.0
		var x := o.x - off
		while x < o.x + C:
			var bx0 := maxf(x, cx0)
			var bx1 := minf(x + 8.0, cx1)
			if bx1 - bx0 < 0.8:
				x += 8.0
				continue
			var bi := int(floor((x + off) / 8.0))
			var v := _h(bi, row, 43)
			if stage > 0 and v < (0.22 if stage == 1 else 0.5):
				# a stone knocked out: broken rubble and dust in the gap
				draw_rect(Rect2(bx0, y, bx1 - bx0, 4), Color(0.24, 0.22, 0.2))
				draw_circle(Vector2(bx0 + (bx1 - bx0) * 0.35, y + 2.2), 1.1, base.darkened(0.2))
				draw_circle(Vector2(bx0 + (bx1 - bx0) * 0.75, y + 1.6), 0.8, base.darkened(0.3))
			else:
				var col := base.lightened((v - 0.5) * 0.22)
				var gl := 0.5 if bx0 == x else 0.0
				var gr := 0.5 if bx1 == x + 8.0 else 0.0
				var br := Rect2(bx0 + gl, y + 0.4, bx1 - bx0 - gl - gr, 3.2)
				draw_rect(br, col)
				draw_line(br.position, br.position + Vector2(br.size.x, 0), col.lightened(0.25), 0.5)
				if _h(bi, row, 44) < 0.15:
					draw_circle(br.position + Vector2(br.size.x * 0.7, 2), 0.8, col.darkened(0.3))  # pitting
			x += 8.0
		# torn ends: the exposed core of the wall in shadow, and a stone hanging loose
		if cx0 > o.x + 0.5:
			draw_rect(Rect2(cx0 - 1.0, y, 1.2, 4), base.darkened(0.6))
			if _h(c.x, row, 67) < 0.5:
				draw_colored_polygon(PackedVector2Array([Vector2(cx0, y + 0.5), Vector2(cx0 - 2.5, y + 1.2), Vector2(cx0 - 1.5, y + 3.5), Vector2(cx0, y + 3.5)]), base.darkened(0.1))
		if cx1 < o.x + C - 0.5:
			draw_rect(Rect2(cx1 - 0.2, y, 1.2, 4), base.darkened(0.65))
			if _h(c.x, row, 68) < 0.5:
				draw_colored_polygon(PackedVector2Array([Vector2(cx1, y + 0.5), Vector2(cx1 + 2.2, y + 1.0), Vector2(cx1 + 1.8, y + 3.5), Vector2(cx1, y + 3.5)]), base.darkened(0.15))
	# lit and shaded edges where the wall ends cleanly
	if not above and ext[0][1] > ext[0][0]:
		draw_line(Vector2(ext[0][0], top_y), Vector2(ext[0][1], top_y), base.lightened(0.4), 1.0)
	if not left and ext[0][0] <= o.x + 0.5:
		draw_line(Vector2(o.x, top_y), Vector2(o.x, top_y + C), base.lightened(0.25), 0.8)
	if not right and ext[0][1] >= o.x + C - 0.5:
		draw_line(Vector2(o.x + C, top_y), Vector2(o.x + C, top_y + C), base.darkened(0.55), 1.0)
	if broken:
		# loose stones fallen into the gaps the torn courses left
		_seed(c.x, c.y, 69)
		for k in 4:
			var cx0: float = ext[k][0]
			var cx1: float = ext[k][1]
			var y := top_y + k * 4.0 + 2.0
			if cx0 > o.x + 2.0:
				_stone(Vector2(rng.randf_range(o.x, cx0 - 1.0), y + rng.randf_range(-1, 1)), rng.randf_range(1.0, 2.2), base.darkened(rng.randf_range(0.15, 0.4)), 5)
			if cx1 < o.x + C - 2.0:
				_stone(Vector2(rng.randf_range(cx1 + 1.0, o.x + C), y + rng.randf_range(-1, 1)), rng.randf_range(1.0, 2.2), base.darkened(rng.randf_range(0.15, 0.4)), 5)
	if stage > 0:
		var top := Rect2(o.x, top_y, C, C)
		_seed(c.x, c.y, 45)
		for n in stage + 1:
			var p := top.position + Vector2(rng.randf() * C, rng.randf() * C)
			var pts := PackedVector2Array([p])
			for k in 4:
				p += Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
				pts.append(p.clamp(top.position, top.end))
			draw_polyline(pts, Color(0.06, 0.05, 0.05, 0.85), 0.7)
		draw_rect(top, Color(0.05, 0.04, 0.03, 0.12 * stage))  # soot


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
