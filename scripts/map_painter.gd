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
	var _t0 := Time.get_ticks_usec()
	_draw_all()
	if "--perf" in OS.get_cmdline_user_args() and cells.size.x < 10:
		print("PERF painted %s patch in %.1f ms (%s)" % [cells, (Time.get_ticks_usec() - _t0) / 1000.0, get_class()])


func _draw_all() -> void:
	var area := _cell_area()
	_draw_ground()
	_draw_roads()
	if map.plaza.intersects(area.grow(2)):
		_draw_plaza()
	_draw_parks()
	_draw_rails(area)
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
	if not map.building_of.is_empty():
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var c := Vector2i(x, y)
				if map.get_t(c) == T.FLOOR and not _is_fallen(c):
					var bi := map.building_of[y * BattleMap.W + x]
					if bi > 0 and bi < map.building_kind.size():
						_draw_furnishing(c, bi, map.building_kind[bi])
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			var t := map.get_t(c)
			if t == T.RUBBLE:
				_draw_rubble(c)
			elif t == T.FLOOR and _is_fallen(c):
				_seed(c.x, c.y, 31)
				_draw_foundation(c)  # a breach worn into a walkable gap
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.get_t(Vector2i(x, y)) == T.TRENCH:
				_draw_trench(Vector2i(x, y))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.get_t(Vector2i(x, y)) == T.LOW:
				_draw_low(Vector2i(x, y))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			match map.get_t(c):
				T.BUSH:
					_draw_bush(c)
				T.HEDGE:
					_draw_hedge(c)
				T.WIRE:
					_draw_wire(c)
				T.OPEN:
					var was := map.crushed[y * BattleMap.W + x]
					if was != 0:
						_draw_crushed(c, was)
	# shadows, then wrecks, then the walls themselves from back to front
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.is_wall(map.get_t(Vector2i(x, y))):
				var h := WALL_H * (0.5 if map.wall_stage(Vector2i(x, y)) == 2 else 1.0)
				draw_rect(Rect2(Vector2(x, y) * C + Vector2(3, 2), Vector2(C + h * 0.6, C)), Color(0, 0, 0, 0.28))
	for wk in map.wrecks:
		var rr: Rect2i = wk[0]
		if rr.intersects(area):
			_draw_wreck(rr, wk[1])
	for pr in map.props:
		var prr: Rect2i = pr.rect
		if prr.grow(3).intersects(area):
			_draw_prop(pr)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.is_wall(map.get_t(Vector2i(x, y))):
				_draw_wall(Vector2i(x, y))
				if map.get_t(Vector2i(x, y)) == T.WINDOW:
					_draw_window(Vector2i(x, y))
	_draw_exteriors(area)


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


func _in_road(p: Vector2, except := -1) -> bool:
	for i in map.roads.size():
		if i != except and (map.roads[i] as Rect2).has_point(p):
			return true
	return false


## The streets: pavements of worn flagstones along each side, the carriageway, kerbs
## (broken off where another street crosses), lane markings, cracks and potholes.
func _draw_roads() -> void:
	var view := Rect2(Vector2(cells.position * C), Vector2(cells.size * C)).grow(20)
	# pavements first, so the streets lie over them at junctions
	for i in map.roads.size():
		var r: Rect2 = map.roads[i]
		var horiz := r.size.x > r.size.y
		for side in 2:
			var strip := Rect2(r.position.x, r.position.y - C if side == 0 else r.end.y, r.size.x, C) if horiz \
					else Rect2(r.position.x - C if side == 0 else r.end.x, r.position.y, C, r.size.y)
			if not strip.intersects(view):
				continue
			var length := strip.size.x if horiz else strip.size.y
			var s := 0.0
			while s < length:
				var slab := Rect2(strip.position + Vector2(s, 0), Vector2(C, C)) if horiz else Rect2(strip.position + Vector2(0, s), Vector2(C, C))
				s += C
				if not slab.intersects(view) or _in_road(slab.get_center()):
					continue
				var cc := map.cell_of(slab.get_center())
				var t := map.get_t(cc)
				if t != T.OPEN and t != T.RUBBLE and t != T.CRATER:
					continue
				var shade := 0.33 + (_h(cc.x, cc.y, 71) - 0.5) * 0.05
				draw_rect(slab, Color(shade, shade * 0.97, shade * 0.93, 0.85))
				draw_rect(slab, Color(0.12, 0.11, 0.1, 0.5), false, 0.6)
				if _h(cc.x, cc.y, 72) < 0.25:  # a cracked or missing flag
					draw_line(slab.position + Vector2(2, _h(cc.x, cc.y, 73) * C), slab.position + Vector2(C - 2, _h(cc.x, cc.y, 74) * C), Color(0.08, 0.08, 0.08, 0.6), 0.6)
	for i in map.roads.size():
		var r: Rect2 = map.roads[i]
		if r.intersects(view):
			draw_rect(r, Color(0.16, 0.16, 0.17, 0.85))
	for i in map.roads.size():
		var r: Rect2 = map.roads[i]
		if not r.intersects(view):
			continue
		var horiz := r.size.x > r.size.y
		var length := r.size.x if horiz else r.size.y
		var mid := r.get_center()
		# kerbs, in pieces so they stop at the junctions
		var s := 0.0
		while s < length:
			for edge in 2:
				var p := Vector2(r.position.x + s, r.position.y if edge == 0 else r.end.y - 2) if horiz \
						else Vector2(r.position.x if edge == 0 else r.end.x - 2, r.position.y + s)
				if view.has_point(p) and not _in_road(p + (Vector2(4, 1) if horiz else Vector2(1, 4)), i) \
						and not _in_road(p + (Vector2(4, -3) if horiz else Vector2(-3, 4)) if edge == 0 else p + (Vector2(4, 5) if horiz else Vector2(5, 4)), i):
					draw_rect(Rect2(p, Vector2(8, 2) if horiz else Vector2(2, 8)), Color(0.42, 0.4, 0.37, 0.85))
			s += 8.0
		s = 0.0
		while s < length:
			# worn lane markings, cracks and potholes every few metres
			var p := Vector2(r.position.x + s, mid.y) if horiz else Vector2(mid.x, r.position.y + s)
			if _near(p, 40) and not _in_road(p, i) and not _in_road(p + (Vector2(26, 0) if horiz else Vector2(0, 26)), i):
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


## The chapel square: big worn flagstones, cracked and stained.
func _draw_plaza() -> void:
	var pr := map.plaza
	for x in range(pr.position.x, pr.end.x, 2):
		for y in range(pr.position.y, pr.end.y, 2):
			var c := Vector2i(x, y)
			if not _cell_area().grow(1).has_point(c):
				continue
			var rr := Rect2(Vector2(c) * C, Vector2(C, C) * 2.0)
			var shade := 0.38 + (_h(x, y, 81) - 0.5) * 0.07
			draw_rect(rr, Color(shade, shade * 0.97, shade * 0.92, 0.9))
			_tex_patch(ground_grit, rr, x, y, 0.35)
			draw_rect(rr, Color(0.1, 0.1, 0.09, 0.55), false, 0.8)
			if _h(x, y, 82) < 0.3:
				_crack(rr.position + Vector2(_h(x, y, 83), 0) * rr.size.x, rr.position + Vector2(_h(x, y, 84), 1) * rr.size.x, rr, 0.7, Color(shade, shade, shade))


## Parks: dead, trampled grass and gravel paths from the gates.
func _draw_parks() -> void:
	var area := _cell_area()
	for pk in map.parks:
		var r: Rect2i = pk
		if not r.intersects(area.grow(2)):
			continue
		for x in range(maxi(r.position.x, area.position.x), mini(r.end.x, area.end.x)):
			for y in range(maxi(r.position.y, area.position.y), mini(r.end.y, area.end.y)):
				var c := Vector2i(x, y)
				var o := Vector2(c) * C
				var g := 0.5 + (_h(x / 2, y / 2, 91) - 0.5) * 0.4
				draw_rect(Rect2(o, Vector2(C, C)), Color(0.24 * g + 0.12, 0.27 * g + 0.13, 0.13 * g + 0.08, 0.7))
				_seed(x, y, 92)
				for k in 6:  # tufts of dry grass
					var p := o + Vector2(rng.randf() * C, rng.randf() * C)
					var col := Color(0.38, 0.38, 0.2).darkened(rng.randf() * 0.4)
					for b in 3:
						draw_line(p, p + Vector2.from_angle(-PI * 0.5 + rng.randf_range(-1.0, 1.0)) * rng.randf_range(2.0, 4.0), col, 0.6)
		var cx := r.get_center()
		for horiz in [true, false]:  # gravel paths across
			var path := Rect2(Vector2(r.position.x, cx.y - 1) * C, Vector2(r.size.x, 2) * C) if horiz \
					else Rect2(Vector2(cx.x - 1, r.position.y) * C, Vector2(2, r.size.y) * C)
			if path.intersects(Rect2(Vector2(area.position * C), Vector2(area.size * C))):
				draw_rect(path, Color(0.42, 0.38, 0.3, 0.75))
				_tex_patch(ground_grit, path, int(path.position.x), int(path.position.y), 0.6)


func _bush_col(c: Vector2i, k: int) -> Color:
	return Color(0.17, 0.23, 0.13).lightened((_h(c.x * 3 + k, c.y, 101) - 0.5) * 0.15)


## A bush: a clump of leafy masses, dark and dusty, lit from the top left.
func _draw_bush(c: Vector2i) -> void:
	var o := Vector2(c) * C + Vector2(8, 8)
	_seed(c.x, c.y, 100)
	var n := rng.randi_range(3, 5)
	var blobs: Array = []
	for k in n:
		blobs.append([o + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), rng.randf_range(4.0, 7.0)])
	for b in blobs:
		_poly(_blob(b[0] + Vector2(2.5, 3), b[1], 0.9, 0.4, c.x * 7 + c.y), Color(0, 0, 0, 0.35))
	for i in blobs.size():
		var b: Array = blobs[i]
		var col := _bush_col(c, i)
		_poly(_blob(b[0], b[1], 0.95, 0.45, c.x * 11 + c.y * 3 + i), col)
		for k in 7:  # leaves catching the light
			var p: Vector2 = b[0] + Vector2(rng.randf_range(-1, 0.6), rng.randf_range(-1, 0.6)) * b[1] * 0.8
			draw_circle(p, rng.randf_range(0.8, 1.6), col.lightened(rng.randf_range(0.1, 0.3)))
		if rng.randf() < 0.4:
			draw_circle(b[0] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), 1.0, Color(0.42, 0.3, 0.16))  # dead leaves


func _hedge_linked(c: Vector2i) -> bool:
	return map.get_t(c) == T.HEDGE


## A clipped hedge: a dense block of foliage joined to its neighbours, gone ragged with
## neglect, darker on its shaded sides.
func _draw_hedge(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var r := Rect2(o + Vector2(1.5, 1.5), Vector2(C - 3, C - 3))
	if _hedge_linked(c + Vector2i(-1, 0)): r = r.grow_individual(1.5, 0, 0, 0)
	if _hedge_linked(c + Vector2i(1, 0)): r = r.grow_individual(0, 0, 1.5, 0)
	if _hedge_linked(c + Vector2i(0, -1)): r = r.grow_individual(0, 1.5, 0, 0)
	if _hedge_linked(c + Vector2i(0, 1)): r = r.grow_individual(0, 0, 0, 1.5)
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.35))
	var col := Color(0.14, 0.2, 0.11).lightened((_h(c.x, c.y, 102) - 0.5) * 0.08)
	draw_rect(r, col)
	_seed(c.x, c.y, 103)
	for k in 26:  # the leaf texture, lighter towards the lit top-left
		var p := r.position + Vector2(rng.randf(), rng.randf()) * r.size
		var lit := 1.0 - ((p.x - r.position.x) / r.size.x + (p.y - r.position.y) / r.size.y) * 0.5
		draw_circle(p, rng.randf_range(0.8, 1.8), col.lightened(lit * 0.25 - 0.05).darkened(rng.randf() * 0.15))
	for k in 6:  # straggly bits poking out
		var p := r.position + Vector2(rng.randf(), rng.randf()) * r.size
		draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * 3.0, col.lightened(0.1), 0.7)


func _wire_linked(c: Vector2i) -> bool:
	return map.get_t(c) == T.WIRE


## Barbed wire: coils strung between iron pickets, along whichever way the run goes.
func _draw_wire(c: Vector2i) -> void:
	var mid := Vector2(c) * C + Vector2(8, 8)
	var along := Vector2(1, 0)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		if _wire_linked(c + d) or _wire_linked(c - d):
			along = Vector2(d).normalized()
			break
	var half := 8.0 * (1.41 if absf(along.x) > 0.1 and absf(along.y) > 0.1 else 1.0)
	var a := mid - along * half
	var b := mid + along * half
	var metal := Color(0.52, 0.5, 0.47)
	# pickets
	for p in [mid - along * half * 0.5, mid + along * half * 0.5]:
		draw_line(p + Vector2(1, 1.5), p + Vector2(1, -3.5), Color(0, 0, 0, 0.4), 1.6)
		draw_line(p, p + Vector2(0, -4.5), Color(0.25, 0.2, 0.15), 1.3)
	# coils: overlapping loops along the run
	var n := 5
	for k in n:
		var q := a.lerp(b, (k + 0.5) / n)
		draw_set_transform(q, along.angle(), Vector2(1.0, 0.75))
		draw_arc(Vector2(0, 1.2), 3.6, 0, TAU, 12, Color(0, 0, 0, 0.35), 0.7)
		draw_arc(Vector2.ZERO, 3.6, 0, TAU, 12, metal.darkened(_h(c.x + k, c.y, 104) * 0.3), 0.6)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_line(a, b, metal.darkened(0.2), 0.5)  # the line strand
	_seed(c.x, c.y, 105)
	for k in 6:  # barbs
		var p := a.lerp(b, rng.randf()) + along.orthogonal() * rng.randf_range(-3, 3)
		draw_line(p - Vector2(0.8, 0.8), p + Vector2(0.8, 0.8), metal, 0.4)
		draw_line(p - Vector2(0.8, -0.8), p + Vector2(0.8, -0.8), metal, 0.4)


## What's left after a vehicle drove over a bush, hedge or wire, or a shell burst on it.
func _draw_crushed(c: Vector2i, was: int) -> void:
	var o := Vector2(c) * C
	_seed(c.x, c.y, 106)
	if was == 20:
		# burnt away: a black scar of ash and charred stumps
		_poly(_blob(o + Vector2(8, 8), 9.0, 0.9, 0.45, c.x * 5 + c.y), Color(0.05, 0.04, 0.03, 0.7))
		for k in 5:
			var p := o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14))
			draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2, 4), Color(0.12, 0.09, 0.07), 1.0)
			draw_circle(p, 0.8, Color(0.45, 0.42, 0.38, 0.6))  # ash
		return
	if was == T.WIRE:
		for k in 4:
			var p := o + Vector2(rng.randf_range(2, 14), rng.randf_range(4, 12))
			draw_arc(p, rng.randf_range(2, 4), rng.randf() * TAU, rng.randf() * TAU + 3.0, 8, Color(0.42, 0.4, 0.37, 0.8), 0.5)
		draw_line(o + Vector2(2, 9), o + Vector2(10, 12), Color(0.25, 0.2, 0.15), 1.2)  # a flattened picket
		return
	for k in (10 if was == T.HEDGE else 6):  # crushed branches and torn leaves
		var p := o + Vector2(rng.randf_range(1, 15), rng.randf_range(1, 15))
		draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2, 5), Color(0.3, 0.22, 0.13, 0.8), 0.8)
		draw_circle(p + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)), rng.randf_range(1, 2), Color(0.18, 0.22, 0.13, 0.7))


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
			if map.get_t(c) != T.FLOOR and not map.is_wall(map.get_t(c)):
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


## Blast damage on a surface: layered soot that is heaviest at the centre, scorch
## streaks thrown outwards, and pits from shrapnel with a pale broken rim.
## Everything is clipped to the surface outline.
func _soot(outline: PackedVector2Array, centre: Vector2, amount: int, seed_v: int) -> void:
	_seed(seed_v, amount, 101)
	var focus := centre + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
	for k in 2 + amount:
		var blob := _blob(focus + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)),
				rng.randf_range(4, 9) * (0.7 + amount * 0.25), rng.randf_range(0.6, 1.0), 0.6, seed_v + k * 13)
		for piece in Geometry2D.intersect_polygons(blob, outline):
			_poly(piece, Color(0.03, 0.025, 0.02, 0.17 + 0.07 * amount))
	for k in 5 + amount * 4:
		var a := rng.randf() * TAU
		var p0 := focus + Vector2.from_angle(a) * rng.randf_range(1, 4)
		var p1 := focus + Vector2.from_angle(a + rng.randf_range(-0.2, 0.2)) * rng.randf_range(6, 14)
		var seg := Geometry2D.clip_polyline_with_polygon(PackedVector2Array([p0, p1]), outline)
		for line in seg:
			draw_polyline(line, Color(0.03, 0.02, 0.02, 0.3), rng.randf_range(0.5, 1.2))
	for k in 6 + amount * 9:
		var p := focus + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1, 11)
		if Geometry2D.is_point_in_polygon(p, outline):
			var rr := rng.randf_range(0.3, 0.8)
			draw_circle(p + Vector2(-0.3, -0.3), rr + 0.3, Color(0.75, 0.72, 0.68, 0.35))
			draw_circle(p, rr, Color(0.06, 0.05, 0.05, 0.9))


func _draw_rubble(c: Vector2i) -> void:
	_seed(c.x, c.y, 31)
	var o := Vector2(c) * C
	var from_wall := map.fallen[c.y * BattleMap.W + c.x] == 1
	draw_colored_polygon(_blob(o + Vector2(8, 8), 9.5, 1.0, 0.45, c.x * 977 + c.y), Color(0.33, 0.31, 0.27, 0.6))
	if from_wall:
		_draw_foundation(c)
	elif map.fallen[c.y * BattleMap.W + c.x] == 2:
		_draw_low_remains(c)
		return
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
		return map.is_wall(t) or _is_fallen(c + d)
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
	if map.wall_hp[c.y * BattleMap.W + c.x] <= 0.0:
		_soot(bed, o + Vector2(8, 8), 2, c.x * 5 + c.y * 11)  # it was blown down, not just old
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


# ---------------------------------------------------------------- low cover

func _low_kind(c: Vector2i) -> int:
	return map.low_kind[c.y * BattleMap.W + c.x]


func _low_linked(c: Vector2i, kind: int) -> bool:
	return map.get_t(c) == T.LOW and _low_kind(c) == kind or (kind == BattleMap.LowKind.STONE and map.is_wall(map.get_t(c)))


## Which way a line of low cover runs through c: true = left to right.
func _low_horizontal(c: Vector2i) -> bool:
	var k := _low_kind(c)
	var h := int(_low_linked(c + Vector2i(-1, 0), k)) + int(_low_linked(c + Vector2i(1, 0), k))
	var v := int(_low_linked(c + Vector2i(0, -1), k)) + int(_low_linked(c + Vector2i(0, 1), k))
	return h >= v


## The way a line of low cover runs through c: along a street-straight line, or at an
## angle where it only joins its neighbours corner to corner.
func _low_along(c: Vector2i) -> Vector2:
	var k := _low_kind(c)
	var h := int(_low_linked(c + Vector2i(-1, 0), k)) + int(_low_linked(c + Vector2i(1, 0), k))
	var v := int(_low_linked(c + Vector2i(0, -1), k)) + int(_low_linked(c + Vector2i(0, 1), k))
	if h + v > 0:
		return Vector2(1, 0) if h >= v else Vector2(0, 1)
	var d1 := int(_low_linked(c + Vector2i(1, 1), k)) + int(_low_linked(c + Vector2i(-1, -1), k))
	var d2 := int(_low_linked(c + Vector2i(1, -1), k)) + int(_low_linked(c + Vector2i(-1, 1), k))
	if d1 + d2 > 0:
		return Vector2(1, 1).normalized() if d1 >= d2 else Vector2(1, -1).normalized()
	return Vector2(1, 0)


func _draw_low(c: Vector2i) -> void:
	match _low_kind(c):
		BattleMap.LowKind.SANDBAGS:
			_draw_sandbags(c)
		BattleMap.LowKind.BARRICADE:
			_draw_barricade(c)
		BattleMap.LowKind.CRATES:
			_draw_crate_stack(c)
		_:
			_draw_low_wall(c)


## A bag's outline: a rounded, slightly squashed box lying along `along`.
func _bag_shape(p: Vector2, along: Vector2, half_len: float, half_w: float, seed_v: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var across := along.orthogonal()
	for k in 16:
		var a := k * TAU / 16.0
		var cx := cos(a)
		var cy := sin(a)
		var x := signf(cx) * pow(absf(cx), 0.55) * half_len * (1.0 + (_h(seed_v, k, 113) - 0.5) * 0.08)
		var y := signf(cy) * pow(absf(cy), 0.7) * half_w
		pts.append(p + along * x + across * y)
	return pts


## Sandbags: a wall a full cell thick, two staggered rows of fat burlap bags with
## a third layer on top, seams and tied ends, some burst open when damaged.
func _draw_sandbags(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var stage := map.wall_stage(c)
	var along := _low_along(c)
	var diag := absf(along.x) > 0.1 and absf(along.y) > 0.1
	var across := along.orthogonal()
	var mid := o + Vector2(8, 8)
	var base := Color(0.47, 0.42, 0.31)
	draw_rect(Rect2(o + Vector2(2.5, 3.5), Vector2(C, C)), Color(0, 0, 0, 0.3))
	var layers := [[-3.4, 0.0, 0.0], [3.4, 0.0, 3.0], [0.0, -2.2, 1.5]]  # across offset, lift, stagger
	var n := 0
	for li in layers.size():
		var L: Array = layers[li]
		for k in (4 if diag else 3):  # a diagonal run is longer across the cell: one more bag
			n += 1
			var t: float = k * 6.0 - (9.0 if diag else 6.0) + L[2]
			var p: Vector2 = mid + along * t + across * L[0] + Vector2(0, L[1])
			if stage > 0 and _h(c.x * 7 + k, c.y * 5 + li, 111) < 0.18 * stage:
				# burst open: a flattened sack with sand spilling out
				_poly(_blob(p + Vector2(0, 1.5), 3.6, 0.55, 0.6, c.x * 7 + k + li), base.darkened(0.35))
				_poly(_blob(p + across * 2.5 + Vector2(0, 2.5), 2.8, 0.6, 0.6, c.x * 9 + k + li), Color(0.56, 0.49, 0.36, 0.85))
				continue
			var col := base.lightened((_h(c.x * 3 + k, c.y + li, 112) - 0.5) * 0.18)
			if li == 2:
				col = col.lightened(0.06)  # the top layer catches more light
			var bag := _bag_shape(p, along, 3.4, 2.5, c.x * 31 + c.y * 7 + n)
			var sh := PackedVector2Array()
			for q in bag:
				sh.append(q + Vector2(0.8, 1.0))
			_poly(sh, Color(0, 0, 0, 0.38))
			_poly(bag, col)
			_tex_poly(bag, c.x + k, c.y + li, 0.9)
			# stitched seam along the bag, tied-off ends, a lit upper edge
			draw_line(p - along * 2.6, p + along * 2.6, col.darkened(0.25), 0.35)
			draw_line(p - along * 3.1 - across * 1.2, p - along * 3.1 + across * 1.2, col.darkened(0.35), 0.5)
			draw_line(p - along * 2.6 - across * 2.1 + Vector2(0, -0.2), p + along * 2.6 - across * 2.1, col.lightened(0.25), 0.5)
	if stage > 0:
		var outline := PackedVector2Array([o, o + Vector2(C, 0), o + Vector2(C, C), o + Vector2(0, C)])
		_soot(outline, mid, stage, c.x * 3 + c.y)


## A barricade: a rusted steel hedgehog with salvaged planks and sheet metal lashed to it.
func _draw_barricade(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var stage := map.wall_stage(c)
	var along := _low_along(c)
	var reach := 11.5 if absf(along.x) > 0.1 and absf(along.y) > 0.1 else 8.5
	var across := along.orthogonal()
	var mid := o + Vector2(8, 8)
	draw_rect(Rect2(o + Vector2(2, 3), Vector2(C, C)), Color(0, 0, 0, 0.25))
	_seed(c.x, c.y, 120)
	# planks or sheet metal along the line
	var sheet := _h(c.x, c.y, 121) < 0.5
	for k in 3:
		if stage > 0 and _h(c.x, c.y + k, 122) < 0.25 * stage:
			continue  # blown off
		var a := mid - along * reach + across * (k - 1) * 2.4
		var b := mid + along * reach + across * (k - 1) * 2.4 + across * rng.randf_range(-0.8, 0.8)
		var col := Color(0.4, 0.37, 0.33) if sheet else Color(0.36, 0.26, 0.17).lightened(rng.randf_range(-0.1, 0.1))
		draw_line(a + Vector2(0.6, 0.8), b + Vector2(0.6, 0.8), Color(0, 0, 0, 0.35), 2.4)
		draw_line(a, b, col, 2.2)
		draw_line(a - across * 0.8, b - across * 0.8, col.lightened(0.2), 0.5)
		if sheet:
			for r in 4:
				var q := a.lerp(b, (r + 0.5) / 4.0)
				draw_line(q - across * 1.0, q + across * 1.0, col.darkened(0.3), 0.4)  # corrugations
	# the steel hedgehog: three crossed beams
	var hog := mid + along * rng.randf_range(-3, 3)
	for k in 3:
		var ang := along.angle() + k * PI / 3.0 + 0.3
		var d := Vector2.from_angle(ang) * 6.0
		draw_line(hog - d + Vector2(0.8, 1), hog + d + Vector2(0.8, 1), Color(0, 0, 0, 0.4), 2.0)
		draw_line(hog - d, hog + d, Color(0.3, 0.2, 0.15), 1.8)
		draw_line(hog - d, hog + d * 0.2, Color(0.5, 0.32, 0.2), 0.6)  # rust highlight
	draw_circle(hog, 1.0, Color(0.18, 0.15, 0.13))
	if stage > 0:
		var outline := PackedVector2Array([o, o + Vector2(C, 0), o + Vector2(C, C), o + Vector2(0, C)])
		_soot(outline, mid, stage, c.x * 5 + c.y)


## A wall crumbled to waist height: the same concrete as the walls, but low,
## its top broken into an uneven line, with fallen pieces at its foot.
func _draw_low_wall(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var stage := map.wall_stage(c)
	var base := _wall_base(c).darkened(0.05)
	var lh := 2.5  # how far its top is raised
	var below_low := map.get_t(c + Vector2i(0, 1)) == T.LOW or map.is_wall(map.get_t(c + Vector2i(0, 1)))
	draw_rect(Rect2(o + Vector2(2, 2), Vector2(C, C)), Color(0, 0, 0, 0.25))
	var top := o.y - lh
	# a jagged top outline on all four sides
	var pts := PackedVector2Array()
	var corners := [Vector2(o.x, top), Vector2(o.x + C, top), Vector2(o.x + C, top + C), Vector2(o.x, top + C)]
	var inward := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var linked := false
		var nb := [c + Vector2i(0, -1), c + Vector2i(1, 0), c + Vector2i(0, 1), c + Vector2i(-1, 0)][e] as Vector2i
		linked = map.get_t(nb) == T.LOW or map.is_wall(map.get_t(nb))
		pts.append(a)
		if not linked:
			for k in range(1, 6):
				var t := k / 6.0
				pts.append(a.lerp(b, t) + inward[e] * (0.5 + _h(c.x * 5 + e, c.y + k, 130) * 2.5) * pow(sin(PI * t), 2.0))
	if not below_low:
		var face := PackedVector2Array([Vector2(o.x, top + C), Vector2(o.x + C, top + C), Vector2(o.x + C, o.y + C), Vector2(o.x, o.y + C)])
		_poly(face, base.darkened(0.45))
		_tex_poly(face, c.x, c.y + 500, 0.8)
	_poly(pts, base)
	_tex_poly(pts, c.x / 4, c.y / 4, 1.0)
	draw_line(Vector2(o.x, top), Vector2(o.x + C, top), base.lightened(0.2), 0.6)
	_seed(c.x, c.y, 131)
	for k in 10:
		var p := o + Vector2(rng.randf_range(1, 15), rng.randf_range(1, 15) - lh)
		draw_circle(p, rng.randf_range(0.2, 0.5), base.darkened(0.3) if rng.randf() < 0.6 else base.lightened(0.15))
	for k in 2:
		_rebar(o + Vector2(rng.randf_range(3, 13), rng.randf_range(3, 13) - lh), o + Vector2(rng.randf_range(3, 13), rng.randf_range(-2, 2) - lh))
	var foot := o + Vector2(rng.randf_range(2, 14), C + rng.randf_range(0, 3))
	_chunk(foot, rng.randf_range(2.4, 3.6), base.darkened(0.2), c.x, c.y + 77)
	if stage > 0:
		_soot(pts, o + Vector2(8, 8 - lh), stage, c.x * 7 + c.y)


## What's left once low cover is destroyed.
func _draw_low_remains(c: Vector2i) -> void:
	var o := Vector2(c) * C
	_seed(c.x, c.y, 140)
	match _low_kind(c):
		BattleMap.LowKind.SANDBAGS:
			for k in 5:
				var p := o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14))
				_poly(_blob(p, rng.randf_range(2.5, 4.0), 0.5, 0.6, c.x * 3 + k), Color(0.38, 0.34, 0.25))
			for k in 3:
				_poly(_blob(o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14)), rng.randf_range(3, 5), 0.7, 0.5, c.y * 5 + k), Color(0.52, 0.46, 0.34, 0.8))
		BattleMap.LowKind.CRATES:
			for k in 6:  # smashed planks and spilled goods
				var p := o + Vector2(rng.randf_range(1, 15), rng.randf_range(1, 15))
				draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2, 5), WOOD if k % 2 == 0 else DARK_WOOD, 1.4)
		BattleMap.LowKind.BARRICADE:
			for k in 4:
				var p := o + Vector2(rng.randf_range(1, 15), rng.randf_range(1, 15))
				var d := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3, 7)
				draw_line(p - d, p + d, Color(0.32, 0.22, 0.15) if k % 2 == 0 else Color(0.38, 0.35, 0.31), 1.8)
			_rebar(o + Vector2(4, 8), o + Vector2(12, 5))
		_:
			for k in 5:
				_chunk(o + Vector2(rng.randf_range(2, 14), rng.randf_range(2, 14)), rng.randf_range(2.2, 3.8), _wall_base(c).darkened(0.2), c.x * 7 + k, c.y)
	_soot(PackedVector2Array([o, o + Vector2(C, 0), o + Vector2(C, C), o + Vector2(0, C)]), o + Vector2(8, 8), 1, c.x * 11 + c.y)


func _wall_base(c: Vector2i) -> Color:
	if map.chapel.grow(1).has_point(c):
		return Color(0.52, 0.5, 0.47)  # pale, older ferrocrete
	if map.is_bunker(c):
		return Color(0.34, 0.34, 0.31)  # dark, heavy military concrete
	# each building was cast from its own batch of concrete
	for i in map.buildings.size():
		if map.buildings[i].grow(1).has_point(c):
			var v := _h(i, 0, 41)
			return Color(0.41, 0.4, 0.38).lerp(Color(0.4, 0.37, 0.33), v)
	return Color(0.4, 0.39, 0.37)


func _is_fallen(c: Vector2i) -> bool:
	return map.in_bounds(c) and not map.is_wall(map.get_t(c)) and map.fallen[c.y * BattleMap.W + c.x] == 1


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


## The shape of a wall cell as drawn: the outline of its raised top (torn where
## the wall next to it fell), its four edges, and the front face hanging below it
## (empty when another wall stands in front). Shared by the colour and height passes.
func _wall_geom(c: Vector2i) -> Dictionary:
	var stage := map.wall_stage(c)
	var h := WALL_H * (0.5 if stage == 2 else 1.0)
	var o := Vector2(c) * C
	var top_y := o.y - h
	var tl := Vector2(o.x, top_y)
	var tr := Vector2(o.x + C, top_y)
	var br := Vector2(o.x + C, top_y + C)
	var bl := Vector2(o.x, top_y + C)
	var e_top := _edge(c, tl, tr, Vector2(0, 1), _is_fallen(c + Vector2i(0, -1)), 0)
	var e_right := _edge(c, tr, br, Vector2(-1, 0), _is_fallen(c + Vector2i(1, 0)), 1)
	var e_bottom := _edge(c, br, bl, Vector2(0, -1), _is_fallen(c + Vector2i(0, 1)), 2)
	var e_left := _edge(c, bl, tl, Vector2(1, 0), _is_fallen(c + Vector2i(-1, 0)), 3)
	var poly := PackedVector2Array()
	for e in [e_top, e_right, e_bottom, e_left]:
		poly.append_array(e)
	var face := PackedVector2Array()
	var chain := PackedVector2Array()
	if not map.is_wall(map.get_t(c + Vector2i(0, 1))):
		chain = PackedVector2Array(e_bottom)
		chain.append(bl)
		for q in chain:
			face.append(q)
		for i in range(chain.size() - 1, -1, -1):
			face.append(chain[i] + Vector2(0, h))
	return {"poly": poly, "face": face, "chain": chain, "h": h, "edges": [e_top, e_right, e_bottom, e_left]}


func _draw_wall(c: Vector2i) -> void:
	var stage := map.wall_stage(c)
	var h := WALL_H * (0.5 if stage == 2 else 1.0)
	var o := Vector2(c) * C
	var base := _wall_base(c)
	var below := map.is_wall(map.get_t(c + Vector2i(0, 1)))
	var above := map.is_wall(map.get_t(c + Vector2i(0, -1)))
	var left := map.is_wall(map.get_t(c + Vector2i(-1, 0)))
	var right := map.is_wall(map.get_t(c + Vector2i(1, 0)))
	var fu := _is_fallen(c + Vector2i(0, -1))
	var fr := _is_fallen(c + Vector2i(1, 0))
	var fd := _is_fallen(c + Vector2i(0, 1))
	var fl := _is_fallen(c + Vector2i(-1, 0))
	var top_y := o.y - h
	var bl := Vector2(o.x, top_y + C)
	var tl := Vector2(o.x, top_y)
	var tr := Vector2(o.x + C, top_y)
	var br := Vector2(o.x + C, top_y + C)
	var geom := _wall_geom(c)
	var poly: PackedVector2Array = geom.poly
	var e_top: PackedVector2Array = geom.edges[0]
	var e_right: PackedVector2Array = geom.edges[1]
	var e_bottom: PackedVector2Array = geom.edges[2]
	var e_left: PackedVector2Array = geom.edges[3]
	# the front face, hanging below the bottom edge of the top
	if not below:
		var face: PackedVector2Array = geom.face
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
	# damage: soot, shrapnel pitting, chunks blown out showing the rebar inside, and cracks
	if stage > 0:
		_soot(poly, o + Vector2(8, 8 - h), stage, c.x * 7 + c.y)
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


## A window opening in a wall: a gap through the wall's top, with a stone sill and
## jambs, shards of glass and lead on the floor beneath.
func _draw_window(c: Vector2i) -> void:
	var g := _wall_geom(c)
	var h: float = g.h
	var o := Vector2(c) * C - Vector2(0, h)
	var base := _wall_base(c)
	var horiz := map.is_wall(map.get_t(c + Vector2i(-1, 0))) or map.is_wall(map.get_t(c + Vector2i(1, 0)))
	# the opening runs across the wall's thickness (a bunker's firing slit: long and narrow, joined up)
	var gap := Rect2(o + Vector2(3, 5), Vector2(10, 6)) if horiz else Rect2(o + Vector2(5, 3), Vector2(6, 10))
	if map.is_bunker(c):
		gap = Rect2(o + Vector2(0, 6), Vector2(C, 3.5)) if horiz else Rect2(o + Vector2(6, 0), Vector2(3.5, C))
		draw_rect(gap.grow(1.2), base.darkened(0.5))
		draw_rect(gap, Color(0.04, 0.04, 0.05))
		return
	var dark := Color(0.07, 0.07, 0.08)
	draw_rect(gap.grow(0.8), base.darkened(0.55))   # shadowed reveal
	draw_rect(gap, dark)
	var sill := Rect2(gap.position + Vector2(0, gap.size.y - 1.4), Vector2(gap.size.x, 1.4)) if horiz \
			else Rect2(gap.position + Vector2(gap.size.x - 1.4, 0), Vector2(1.4, gap.size.y))
	draw_rect(sill, base.lightened(0.15))
	_seed(c.x, c.y, 160)
	if map.chapel.grow(1).has_point(c):
		# what's left of the stained glass: a few coloured shards in the lead
		for k in 4:
			var p := gap.position + Vector2(rng.randf() * gap.size.x, rng.randf() * gap.size.y)
			var col: Color = [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.75, 0.6, 0.15)][rng.randi() % 3]
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(1.6, 0.4), p + Vector2(0.5, 1.5)]), Color(col, 0.8))
	else:
		for k in 2:  # a broken bar or two
			var x := gap.position.x + gap.size.x * (0.33 + 0.33 * k) if horiz else gap.position.x
			if horiz:
				draw_line(Vector2(x, gap.position.y), Vector2(x, gap.end.y - rng.randf() * 3), Color(0.3, 0.2, 0.15), 0.6)


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


# ---------------------------------------------------------------- a lived-in town

const WOOD := Color(0.36, 0.25, 0.15)
const DARK_WOOD := Color(0.24, 0.16, 0.1)
const IRON := Color(0.3, 0.3, 0.31)


## Which way the nearest wall lies from c (for furniture standing against it), or ZERO.
func _wall_dir(c: Vector2i) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		if map.is_wall(map.get_t(c + d)):
			return d
	return Vector2i.ZERO


func _box(center: Vector2, size: Vector2, col: Color, rot := 0.0) -> void:
	draw_set_transform(center, rot, Vector2.ONE)
	draw_rect(Rect2(-size * 0.5 + Vector2(1, 1.2), size), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-size * 0.5, size), col)
	draw_rect(Rect2(-size * 0.5, size), col.darkened(0.45), false, 0.5)
	draw_line(-size * 0.5 + Vector2(0.4, 0.4), Vector2(size.x * 0.5 - 0.4, -size.y * 0.5 + 0.4), col.lightened(0.25), 0.5)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _barrel(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p + Vector2(0.8, 1.0), r, Color(0, 0, 0, 0.35))
	draw_circle(p, r, col)
	draw_arc(p, r * 0.75, 0, TAU, 12, col.darkened(0.4), 0.6)
	draw_arc(p, r, 0, TAU, 12, col.darkened(0.55), 0.6)
	draw_circle(p - Vector2(r * 0.3, r * 0.3), r * 0.25, col.lightened(0.25))


func _crate(p: Vector2, s: float, rot: float) -> void:
	_box(p, Vector2(s, s), WOOD.lightened(0.05), rot)
	draw_set_transform(p, rot, Vector2.ONE)
	draw_line(Vector2(-s, -s) * 0.5, Vector2(s, s) * 0.5, DARK_WOOD, 0.6)
	draw_line(Vector2(-s, s) * 0.5, Vector2(s, -s) * 0.5, DARK_WOOD, 0.6)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _table(m: Vector2, round_top: bool) -> void:
	for k in 4:  # chairs round it, a couple knocked over
		var a := k * PI * 0.5 + _h(int(m.x), int(m.y), 320 + k) * 0.4
		var cp := m + Vector2.from_angle(a) * 6.0
		_box(cp, Vector2(3.0, 3.0), WOOD.darkened(0.1), a + (0.9 if _h(int(m.x), k, 321) < 0.3 else 0.0))
	if round_top:
		draw_circle(m + Vector2(0.8, 1.0), 4.2, Color(0, 0, 0, 0.35))
		draw_circle(m, 4.2, WOOD)
		draw_arc(m, 4.2, 0, TAU, 14, DARK_WOOD, 0.6)
	else:
		_box(m, Vector2(8, 6), WOOD, 0.0)
	if _h(int(m.x), int(m.y), 322) < 0.5:
		draw_circle(m + Vector2(1.5, -1), 0.9, Color(0.75, 0.72, 0.65))  # a cup or a plate


## One cell of a building's insides: furniture against the walls and in the rooms, by what
## the building was. Purely scenery.
func _draw_furnishing(c: Vector2i, bi: int, kind: String) -> void:
	var roll := _h(c.x, c.y, 300 + bi)
	var pick := _h(c.x, c.y, 301)
	var o := Vector2(c) * C
	var m := o + Vector2(8, 8)
	var wd := _wall_dir(c)
	var along := Vector2(absf(wd.y), absf(wd.x))  # runs along the wall
	var back := m + Vector2(wd) * 4.5  # pushed up against it
	match kind:
		"home":
			if roll > 0.4:
				return
			if wd != Vector2i.ZERO:
				if pick < 0.4:  # a bed: frame, blanket, pillow at the wall end
					var rot := Vector2(wd).angle() + PI * 0.5
					_box(m + Vector2(wd) * 2.0, Vector2(8, 13), WOOD.darkened(0.15), rot)
					_box(m + Vector2(wd) * 2.0 - Vector2(wd) * 1.0, Vector2(7, 9), Color(0.38, 0.3, 0.25).lerp(Color(0.3, 0.32, 0.4), pick * 2.0), rot)
					_box(m + Vector2(wd) * 6.5, Vector2(6, 3), Color(0.7, 0.68, 0.6), rot)
				elif pick < 0.7:  # a dresser
					_box(back, Vector2(12, 5) if along.x > 0 else Vector2(5, 12), WOOD, 0.0)
				else:  # an iron stove and its soot
					draw_circle(back, 6, Color(0.05, 0.04, 0.03, 0.3))
					_box(back, Vector2(7, 7), IRON.darkened(0.3), 0.0)
					draw_circle(back, 1.6, Color(0.6, 0.25, 0.1, 0.8))
			elif pick < 0.5:
				_table(m, false)
			else:  # a worn rug
				_box(m, Vector2(13, 9), Color(0.4, 0.15, 0.12).lerp(Color(0.25, 0.25, 0.32), _h(c.x, c.y, 302)), _h(c.x, c.y, 303) * 0.3)
				draw_rect(Rect2(m - Vector2(4.5, 2.5), Vector2(9, 5)), Color(0.75, 0.6, 0.35, 0.4), false, 0.6)
		"shop":
			if roll > 0.5:
				return
			if wd != Vector2i.ZERO:
				# shelves of goods against the walls
				var sz := Vector2(15, 5) if along.x > 0 else Vector2(5, 15)
				_box(back, sz, DARK_WOOD, 0.0)
				for k in 6:
					var q := back + along * (k - 2.5) * 2.4 + Vector2(_h(c.x + k, c.y, 304) - 0.5, _h(c.x, c.y + k, 305) - 0.5)
					draw_rect(Rect2(q - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color.from_hsv(_h(c.x + k, c.y, 306), 0.35, 0.6))
			elif pick < 0.5:
				_box(m, Vector2(14, 5), WOOD, 0.0)  # the counter
				draw_rect(Rect2(m + Vector2(3, -1.5), Vector2(3, 2)), Color(0.45, 0.45, 0.4))  # a cash box
			else:
				_crate(m + Vector2(-2, 1), 6.0, pick)
				_crate(m + Vector2(3, -3), 5.0, pick * 2.0)
		"tavern":
			if roll > 0.45:
				return
			if wd != Vector2i.ZERO and pick < 0.6:
				var sz := Vector2(15, 5) if along.x > 0 else Vector2(5, 15)
				_box(back, sz, DARK_WOOD.lightened(0.1), 0.0)  # the bar
				for k in 4:
					var q := back + along * (k - 1.5) * 3.2
					draw_circle(q, 0.9, Color(0.3, 0.45, 0.25, 0.9) if k % 2 == 0 else Color(0.5, 0.3, 0.15, 0.9))  # bottles
			elif wd != Vector2i.ZERO:
				_barrel(back, 3.6, WOOD)
			else:
				_table(m, true)
		"office":
			if roll > 0.4:
				return
			if wd != Vector2i.ZERO and pick < 0.5:
				_box(back, Vector2(12, 5) if along.x > 0 else Vector2(5, 12), IRON.lightened(0.15), 0.0)  # filing cabinets
				for k in 3:
					draw_line(back + along * (k - 1) * 3.6 - Vector2(wd) * 1.5, back + along * (k - 1) * 3.6 + Vector2(wd) * 1.5, IRON.darkened(0.3), 0.5)
			else:
				_box(m, Vector2(10, 6), WOOD.darkened(0.05), 0.0)  # a desk
				draw_rect(Rect2(m - Vector2(3, 2), Vector2(4, 3)), Color(0.8, 0.78, 0.7))  # papers
				_box(m + Vector2(0, 5), Vector2(3.5, 3.5), WOOD.darkened(0.2), 0.0)
				for k in 3:  # papers strewn about
					draw_rect(Rect2(m + Vector2(_h(c.x, k, 307) * 14 - 7, _h(k, c.y, 308) * 14 - 7), Vector2(3, 2)), Color(0.78, 0.75, 0.68, 0.8))
		"bunker":
			if roll < 0.35:
				_crate(m + Vector2(-2, 1), 6.0, pick)  # ammunition boxes
				draw_rect(Rect2(m + Vector2(-4, -1), Vector2(4, 1)), Color(0.65, 0.55, 0.25))
			elif roll < 0.55:
				_box(m, Vector2(12, 4), WOOD.darkened(0.1), 0.0)  # a bench
			elif roll < 0.65:
				_box(m, Vector2(5, 4), Color(0.25, 0.27, 0.22), 0.0)  # a field telephone
				draw_line(m + Vector2(2.5, 0), m + Vector2(8, 5), Color(0.1, 0.1, 0.1), 0.6)
		"warehouse":
			if roll < 0.2:
				_box(m, Vector2(12, 12), WOOD.darkened(0.1), _h(c.x, c.y, 309) * 0.2)  # a pallet
				for k in 3:
					draw_line(m + Vector2(-6, -4 + k * 4), m + Vector2(6, -4 + k * 4), DARK_WOOD, 0.6)
			elif roll < 0.3:
				draw_circle(m, 5.0, Color(0.03, 0.03, 0.03, 0.3))  # oil
		"industry":
			if roll > 0.55:
				if roll < 0.7:
					draw_circle(m + Vector2(pick * 6 - 3, roll * 6 - 3), 4.0 + pick * 3.0, Color(0.03, 0.03, 0.03, 0.35))  # oil stain
				return
			if wd != Vector2i.ZERO and pick < 0.45:
				# a machine against the wall: housing, flywheel, dials
				_box(back - Vector2(wd) * 1.0, Vector2(13, 9) if along.x > 0 else Vector2(9, 13), IRON, 0.0)
				draw_circle(back - Vector2(wd) * 1.0 + along * 3.0, 2.6, IRON.darkened(0.35))
				draw_arc(back - Vector2(wd) * 1.0 + along * 3.0, 2.6, 0, TAU, 10, IRON.lightened(0.3), 0.5)
				draw_circle(back - Vector2(wd) * 1.0 - along * 3.0, 1.0, Color(0.85, 0.75, 0.4))
			elif wd != Vector2i.ZERO:
				# pipes running along the wall
				for k in 2:
					var a := back - along * 8.0 + Vector2(wd) * (k * 2.5 - 1.0)
					draw_line(a, a + along * 16.0, Color(0.05, 0.05, 0.05), 2.4)
					draw_line(a, a + along * 16.0, Color(0.45, 0.32, 0.22) if k == 0 else IRON.lightened(0.1), 1.6)
			elif pick < 0.5:
				_barrel(m + Vector2(-2.5, -1), 3.4, Color(0.35, 0.22, 0.14))
				_barrel(m + Vector2(3, 2.5), 3.4, Color(0.25, 0.3, 0.22))
			else:
				_crate(m, 9.0, pick)


## Outside the buildings: striped awnings over shop and tavern fronts, washing strung up
## behind homes, barrels and crates in the yards of the works.
func _draw_exteriors(area: Rect2i) -> void:
	for bi in range(1, map.buildings.size()):
		if bi >= map.building_kind.size():
			break
		var r: Rect2i = map.buildings[bi]
		if not r.grow(4).intersects(area):
			continue
		var kind: String = map.building_kind[bi]
		var front: int = map.building_front[bi]
		var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		var out: Vector2i = dirs[front]
		var along := Vector2i(1, 0) if front < 2 else Vector2i(0, 1)
		var start := Vector2i(r.position.x, r.position.y - 1) if front == 0 else (Vector2i(r.position.x, r.end.y) if front == 1 \
				else (Vector2i(r.position.x - 1, r.position.y) if front == 2 else Vector2i(r.end.x, r.position.y)))
		var length := r.size.x if front < 2 else r.size.y
		if kind == "shop" or kind == "tavern":
			# an awning over the shop front, faded stripes, torn here and there
			var stripe_a := Color(0.5, 0.16, 0.12) if _h(bi, 0, 330) < 0.5 else Color(0.2, 0.3, 0.22)
			for k in range(2, length - 2):
				var c: Vector2i = start + along * k
				if not area.has_point(c) or map.get_t(c) != T.OPEN or _h(c.x, c.y, 331) < 0.12:
					continue
				var rr := Rect2(Vector2(c) * C, Vector2(C, C))
				draw_rect(Rect2(rr.position + Vector2(2, 3), rr.size), Color(0, 0, 0, 0.3))
				for s in 4:
					var sr := Rect2(rr.position + Vector2(along) * s * 4.0, Vector2(4, C) if along.x > 0 else Vector2(C, 4))
					draw_rect(sr, stripe_a if s % 2 == 0 else Color(0.72, 0.68, 0.58))
				var edge := Vector2(c) * C + (Vector2(0, C) if front == 0 else (Vector2.ZERO if front == 1 else (Vector2(C, 0) if front == 2 else Vector2.ZERO)))
				if front == 0 or front == 3:
					edge = Vector2(c) * C + (Vector2(0, 0) if front == 0 else Vector2(C, 0))
				draw_line(edge, edge + Vector2(along) * C, Color(0.15, 0.1, 0.08), 0.8)
		elif kind == "home":
			# a washing line in the yard behind
			var back_side: int = [1, 0, 3, 2][front]
			var bout: Vector2i = dirs[back_side]
			var bstart := Vector2i(r.position.x, r.position.y - 2) if back_side == 0 else (Vector2i(r.position.x, r.end.y + 1) if back_side == 1 \
					else (Vector2i(r.position.x - 2, r.position.y) if back_side == 2 else Vector2i(r.end.x + 1, r.position.y)))
			var k0 := 1 + int(_h(bi, 1, 332) * 3)
			var n := 4
			var a: Vector2i = bstart + along * k0
			var b: Vector2i = a + along * n
			var ok := true
			for k in n + 1:
				var t := map.get_t(a + along * k)
				if t != T.OPEN and t != T.RUBBLE:
					ok = false
			if not ok or not Rect2i(a.min(b), (b - a).abs() + Vector2i.ONE).intersects(area):
				continue
			var pa := map.center_of(a)
			var pb := map.center_of(b)
			for p in [pa, pb]:
				draw_circle(p + Vector2(1, 1), 1.4, Color(0, 0, 0, 0.35))
				draw_circle(p, 1.3, DARK_WOOD)
			draw_line(pa, pb, Color(0.6, 0.58, 0.52), 0.5)
			for k in 7:
				var q := pa.lerp(pb, (k + 0.6) / 7.6)
				var col := Color.from_hsv(_h(bi, k, 333), 0.25, 0.55)
				var sz := Vector2(3.0, 4.0) if along.x > 0 else Vector2(4.0, 3.0)
				draw_rect(Rect2(q - sz * 0.5 + Vector2(1, 1.2), sz), Color(0, 0, 0, 0.25))
				draw_rect(Rect2(q - sz * 0.5, sz), col)
		elif kind == "industry" or kind == "warehouse":
			# barrels and crates stacked in the yard round the works
			for k in range(-1, length + 1):
				for d in [1, 2]:
					for side in [front, [1, 0, 3, 2][front]]:
						var so: Vector2i = dirs[side]
						var base := Vector2i(r.position.x, r.position.y) if side == 0 else (Vector2i(r.position.x, r.end.y - 1) if side == 1 \
								else (Vector2i(r.position.x, r.position.y) if side == 2 else Vector2i(r.end.x - 1, r.position.y)))
						var c: Vector2i = base + along * k + so * d
						if not area.has_point(c) or map.get_t(c) != T.OPEN or map.is_road(c) or _h(c.x, c.y, 334) > 0.16:
							continue
						var m := map.center_of(c)
						if _h(c.x, c.y, 335) < 0.5:
							_barrel(m + Vector2(-2, 0), 3.2, Color(0.35, 0.22, 0.14) if _h(c.x, c.y, 336) < 0.5 else Color(0.25, 0.3, 0.22))
							_barrel(m + Vector2(3, 2), 3.2, Color(0.3, 0.3, 0.3))
						else:
							_crate(m, 9.0, _h(c.x, c.y, 337))


# ---------------------------------------------------------------- heavy industry and statues

## Railway sidings: sleepers and two rails, on whatever ground they cross.
func _draw_rails(area: Rect2i) -> void:
	for rl in map.rails:
		var start: Vector2i = rl[0]
		var n: int = rl[1]
		var y := (start.y + 0.5) * C
		var x0 := float(start.x * C)
		var x1 := float((start.x + n) * C)
		if not Rect2(x0, y - 16, x1 - x0, 32).intersects(Rect2(Vector2(area.position * C), Vector2(area.size * C)).grow(16)):
			continue
		draw_rect(Rect2(x0, y - 9, x1 - x0, 18), Color(0.25, 0.23, 0.2, 0.6))  # ballast
		var x := x0 + 2.0
		while x < x1:  # sleepers
			draw_rect(Rect2(x, y - 8, 3.2, 16), Color(0.22, 0.16, 0.11))
			x += 6.0
		for dy in [-5.0, 5.0]:
			draw_line(Vector2(x0, y + dy + 0.8), Vector2(x1, y + dy + 0.8), Color(0, 0, 0, 0.4), 1.6)
			draw_line(Vector2(x0, y + dy), Vector2(x1, y + dy), Color(0.42, 0.38, 0.34), 1.4)
			draw_line(Vector2(x0, y + dy - 0.4), Vector2(x1, y + dy - 0.4), Color(0.62, 0.6, 0.56), 0.4)


func _draw_crate_stack(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var stage := map.wall_stage(c)
	draw_rect(Rect2(o + Vector2(2.5, 3.5), Vector2(C, C)), Color(0, 0, 0, 0.32))
	_seed(c.x, c.y, 150)
	for k in 2:
		if stage > 0 and rng.randf() < 0.3 * stage:
			continue
		var p := o + Vector2(4 + k * 8, 5 + rng.randf_range(0, 6))
		if rng.randf() < 0.35:
			_barrel(p, 3.6, Color(0.35, 0.22, 0.14) if rng.randf() < 0.5 else Color(0.25, 0.3, 0.22))
		else:
			_crate(p, 7.5, rng.randf_range(-0.2, 0.2))
	if rng.randf() < 0.5:
		_crate(o + Vector2(8, 8), 6.5, rng.randf_range(-0.3, 0.3))  # one stacked on top


func _draw_prop(pr: Dictionary) -> void:
	var r: Rect2i = pr.rect
	var rr := Rect2(Vector2(r.position * C), Vector2(r.size * C))
	var m := rr.get_center()
	var sd: int = pr.seed
	match pr.kind:
		"tank":
			# a storage tank: a riveted drum with a domed top, an access ladder and a pipe
			var rad := rr.size.x * 0.5 - 1.0
			draw_circle(m + Vector2(6, 8), rad, Color(0, 0, 0, 0.4))
			draw_circle(m, rad, Color(0.38, 0.36, 0.33))
			draw_circle(m - Vector2(rad, rad) * 0.15, rad * 0.8, Color(0.44, 0.42, 0.38))
			draw_circle(m - Vector2(rad, rad) * 0.3, rad * 0.4, Color(0.52, 0.5, 0.46))
			draw_arc(m, rad, 0, TAU, 32, Color(0.12, 0.11, 0.1), 1.2)
			for k in 16:  # rivets round the rim
				draw_circle(m + Vector2.from_angle(k * TAU / 16.0) * (rad - 2.0), 0.6, Color(0.2, 0.19, 0.18))
			if (sd % 3) == 0:
				_poly(_blob(m + Vector2(rad * 0.3, rad * 0.2), rad * 0.35, 0.7, 0.5, sd), Color(0.45, 0.22, 0.1, 0.45))  # rust
			draw_circle(m, 2.0, Color(0.25, 0.24, 0.22))  # the hatch
			var ld := m + Vector2(rad, 0)
			for k in 4:  # ladder rungs
				draw_line(ld + Vector2(-2, -4 + k * 2.6), ld + Vector2(2, -4 + k * 2.6), Color(0.2, 0.2, 0.2), 0.6)
		"furnace":
			# a furnace house: brick walls, a tall stack, a glowing firebox door
			draw_rect(Rect2(rr.position + Vector2(5, 6), rr.size), Color(0, 0, 0, 0.4))
			draw_rect(rr, Color(0.36, 0.2, 0.15))
			for y in range(int(rr.position.y) + 3, int(rr.end.y), 4):  # brick courses
				draw_line(Vector2(rr.position.x, y), Vector2(rr.end.x, y), Color(0.25, 0.13, 0.1), 0.6)
			draw_rect(rr, Color(0.12, 0.07, 0.05), false, 1.2)
			draw_rect(Rect2(rr.position.x + 4, rr.end.y - 6, 9, 5), Color(0.9, 0.45, 0.15))
			draw_rect(Rect2(rr.position.x + 4, rr.end.y - 6, 9, 5), Color(0.15, 0.08, 0.05), false, 0.8)
			var st := Vector2(rr.end.x - 9, rr.position.y + 9)
			draw_circle(st + Vector2(10, 14), 7, Color(0, 0, 0, 0.35))  # the stack's long shadow
			draw_circle(st, 7, Color(0.3, 0.17, 0.12))
			draw_circle(st, 4.5, Color(0.05, 0.03, 0.03))
			draw_arc(st, 7, 0, TAU, 16, Color(0.12, 0.07, 0.05), 1.0)
		"wagon":
			# a goods wagon on the rails: a planked box on its frame, doors, a tarpaulin
			draw_rect(Rect2(rr.position + Vector2(5, 6), rr.size), Color(0, 0, 0, 0.4))
			var body := rr.grow_individual(-1, 2, -1, 2)
			draw_rect(body, Color(0.3, 0.22, 0.17))
			var x := body.position.x + 3
			while x < body.end.x:
				draw_line(Vector2(x, body.position.y), Vector2(x, body.end.y), Color(0.2, 0.14, 0.1), 0.6)
				x += 4.0
			draw_rect(body, Color(0.1, 0.07, 0.05), false, 1.0)
			draw_rect(Rect2(body.get_center() - Vector2(8, body.size.y * 0.5), Vector2(16, body.size.y)), Color(0.28, 0.3, 0.24, 0.85))  # tarpaulin
			draw_line(body.position + Vector2(0, 2), Vector2(body.end.x, body.position.y + 2), Color(0.45, 0.35, 0.25), 0.6)
		"statue":
			# a saint on a stepped plinth: robe, head bowed, a sword or a candle held before him
			draw_rect(Rect2(rr.position + Vector2(6, 8), rr.size), Color(0, 0, 0, 0.4))
			draw_rect(rr, Color(0.42, 0.41, 0.39))
			draw_rect(rr.grow(-4), Color(0.48, 0.47, 0.45))
			draw_rect(rr, Color(0.18, 0.17, 0.16), false, 1.0)
			draw_rect(rr.grow(-4), Color(0.25, 0.24, 0.23), false, 0.6)
			var stone := Color(0.55, 0.55, 0.52) if (sd % 2) == 0 else Color(0.36, 0.42, 0.36)  # pale stone or old bronze
			draw_set_transform(m, 0, Vector2(1.45, 1.45))  # the figure, drawn about its centre
			m = Vector2.ZERO
			draw_circle(m + Vector2(8, 11), 7, Color(0, 0, 0, 0.3))
			var robe := PackedVector2Array([m + Vector2(-6, 5), m + Vector2(-4, -5), m + Vector2(4, -5), m + Vector2(6, 5), m + Vector2(0, 7)])
			draw_colored_polygon(robe, stone.darkened(0.1))
			draw_line(m + Vector2(-2, -4), m + Vector2(-3, 5), stone.darkened(0.3), 0.6)  # folds
			draw_line(m + Vector2(2, -4), m + Vector2(3, 5), stone.darkened(0.3), 0.6)
			draw_circle(m + Vector2(0, -4), 3.0, stone)  # head
			draw_circle(m + Vector2(-0.8, -5), 1.2, stone.lightened(0.2))
			if (sd % 3) == 0:
				draw_line(m + Vector2(0, -1), m + Vector2(0, 9), Color(0.6, 0.6, 0.58), 1.4)  # a sword, point down
				draw_line(m + Vector2(-2.5, 0), m + Vector2(2.5, 0), Color(0.6, 0.6, 0.58), 1.0)
			else:
				draw_circle(m + Vector2(0, 1), 1.6, Color(0.9, 0.75, 0.4, 0.9))  # a candle flame cupped in his hands
			if (sd % 5) == 0:
				draw_circle(m + Vector2(2, -6), 1.2, Color(0.05, 0.05, 0.05))  # shrapnel damage
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## A trench: a dug channel with a muddy floor and duckboards, its walls shored with planks;
## the walls on the lit side catch the light, the others fall into shadow, and the spoil is
## heaped along the lip.
func _draw_trench(c: Vector2i) -> void:
	var o := Vector2(c) * C
	var tr := func(d: Vector2i) -> bool: return map.get_t(c + d) == T.TRENCH
	var up: bool = tr.call(Vector2i(0, -1))
	var dn: bool = tr.call(Vector2i(0, 1))
	var lf: bool = tr.call(Vector2i(-1, 0))
	var rt: bool = tr.call(Vector2i(1, 0))
	# spoil heaped along the lip outside
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if not tr.call(d):
			var lip := o + Vector2(8, 8) + Vector2(d) * 10.0
			_poly(_blob(lip, 5.0, 0.6, 0.5, c.x * 7 + c.y + d.x * 3 + d.y), Color(0.3, 0.25, 0.19, 0.7))
	draw_rect(Rect2(o, Vector2(C, C)), Color(0.13, 0.11, 0.09))  # the floor, deep in shadow
	# the walls: shadowed on the top and left (the light comes from the top left), lit on the others
	if not up:
		draw_rect(Rect2(o, Vector2(C, 4)), Color(0.07, 0.06, 0.05))
	if not lf:
		draw_rect(Rect2(o, Vector2(4, C)), Color(0.08, 0.07, 0.06))
	if not dn:
		draw_rect(Rect2(o + Vector2(0, C - 3), Vector2(C, 3)), Color(0.34, 0.28, 0.21))
	if not rt:
		draw_rect(Rect2(o + Vector2(C - 3, 0), Vector2(3, C)), Color(0.3, 0.25, 0.19))
	# revetment: planks shoring the walls
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if tr.call(d):
			continue
		var a := o + (Vector2(0, 2) if d.y < 0 else (Vector2(0, C - 2) if d.y > 0 else (Vector2(2, 0) if d.x < 0 else Vector2(C - 2, 0))))
		var along := Vector2(1, 0) if d.y != 0 else Vector2(0, 1)
		for k in 3:
			var q := a + along * (k * 5.5 + 2.0)
			draw_line(q - along * 2.2, q + along * 2.2, Color(0.3, 0.21, 0.13), 1.1)
	# duckboards along the floor
	var vertical := up or dn
	var mid := o + Vector2(8, 8)
	for k in 4:
		var t := (k + 0.5) * 4.0 - 8.0
		if vertical:
			draw_line(mid + Vector2(-3.5, t), mid + Vector2(3.5, t), Color(0.32, 0.23, 0.15), 1.6)
		else:
			draw_line(mid + Vector2(t, -3.5), mid + Vector2(t, 3.5), Color(0.32, 0.23, 0.15), 1.6)
	if _h(c.x, c.y, 160) < 0.25:
		_poly(_blob(mid + Vector2(_h(c.x, c.y, 161) * 6 - 3, _h(c.x, c.y, 162) * 6 - 3), 3.0, 0.6, 0.4, c.x + c.y), Color(0.12, 0.13, 0.12, 0.8))  # a puddle
