class_name BattleMap
extends Node2D
## The battlefield: a grid of terrain cells used for movement, line of sight
## and cover, and the (procedural, placeholder) drawing of the ruined city.

const CELL := 16
const W := 160
const H := 100

enum T { OPEN, RUBBLE, CRATER, FLOOR, WALL, WRECK }

const COVER := [0.0, 0.35, 0.45, 0.15, 0.0, 0.0]
const SPEED := [1.0, 0.7, 0.75, 1.0, 1.0, 1.0]
const TERRAIN_NAMES := ["Open ground", "Rubble", "Crater", "Ruin floor", "Wall", "Wreck"]

var grid := PackedByteArray()
var astar := AStarGrid2D.new()
var vastar := AStarGrid2D.new()  # for vehicles: keeps a cell of clearance from walls
var rng := RandomNumberGenerator.new()
var map_seed := 0
var objective_rect := Rect2()
var chapel := Rect2i()
var fire_points: Array[Vector2] = []
var buildings: Array[Rect2i] = []
var craters: Array = []   # [center: Vector2, radius: float]
var wrecks: Array = []    # [rect: Rect2i, horizontal: bool]
var scorches: Array = []  # [center: Vector2, radius: float]
var noise_big: NoiseTexture2D
var noise_fine: NoiseTexture2D


func world_size() -> Vector2:
	return Vector2(W * CELL, H * CELL)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func get_t(c: Vector2i) -> int:
	if not in_bounds(c):
		return T.WALL
	return grid[c.y * W + c.x]


func set_t(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		grid[c.y * W + c.x] = t


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func center_of(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + Vector2(CELL, CELL) * 0.5


func blocks(t: int) -> bool:
	return t == T.WALL or t == T.WRECK


func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not blocks(get_t(c))


func speed_mult(p: Vector2) -> float:
	return SPEED[get_t(cell_of(p))]


func terrain_name(p: Vector2) -> String:
	return TERRAIN_NAMES[get_t(cell_of(p))]


## How good a cell is to stand in: its own cover plus solid things next to it.
func cell_cover(c: Vector2i) -> float:
	var cov: float = COVER[get_t(c)]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := get_t(c + d)
		if t == T.WALL or t == T.WRECK or t == T.RUBBLE:
			cov += 0.12
	return cov


## Cover a target gets against a shooter at shooter_pos (0 = none, 1 = total).
func cover_vs(target_pos: Vector2, shooter_pos: Vector2) -> float:
	var cov: float = COVER[get_t(cell_of(target_pos))]
	var dir := (shooter_pos - target_pos).normalized()
	var ft := get_t(cell_of(target_pos + dir * CELL))
	if ft == T.RUBBLE or ft == T.CRATER:
		cov = maxf(cov, 0.4)
	elif ft == T.WALL or ft == T.WRECK:
		cov = maxf(cov, 0.55)
	return cov


## True if nothing solid lies between a and b.
func los_clear(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(d.length() / 6.0)
	if steps < 2:
		return true
	var ca := cell_of(a)
	var cb := cell_of(b)
	var last := Vector2i(-1, -1)
	for i in range(1, steps):
		var c := cell_of(a + d * (float(i) / steps))
		if c == last or c == ca or c == cb:
			continue
		last = c
		if blocks(get_t(c)):
			return false
	return true


func nearest_walkable(c: Vector2i) -> Vector2i:
	if walkable(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if walkable(n):
					return n
	return c


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_walkable(cell_of(from))
	var b := nearest_walkable(cell_of(to))
	var p := astar.get_point_path(a, b)
	if p.size() > 1:
		p.remove_at(0)
	if p.size() > 0 and walkable(cell_of(to)):
		p[p.size() - 1] = to
	return p


func vehicle_can_be_at(c: Vector2i) -> bool:
	return in_bounds(c) and not vastar.is_point_solid(c)


func nearest_vehicle_cell(c: Vector2i) -> Vector2i:
	if vehicle_can_be_at(c):
		return c
	for r in range(1, 10):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				if vehicle_can_be_at(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return c


func find_vehicle_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_vehicle_cell(cell_of(from))
	var b := nearest_vehicle_cell(cell_of(to))
	var p := vastar.get_point_path(a, b)
	if p.size() > 1:
		p.remove_at(0)
	return p


## A destroyed vehicle becomes a wreck that blocks movement and sight like the others.
func add_wreck(pos: Vector2) -> void:
	var c := cell_of(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if in_bounds(n) and get_t(n) != T.WALL:
				set_t(n, T.WRECK)
				astar.set_point_solid(n, true)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if in_bounds(c + Vector2i(dx, dy)):
				vastar.set_point_solid(c + Vector2i(dx, dy), true)


# ---------------------------------------------------------------- generation

func generate(seed_value: int) -> void:
	map_seed = seed_value
	rng.seed = seed_value
	grid.resize(W * H)
	grid.fill(T.OPEN)
	_make_chapel()
	var tries := 0
	while buildings.size() < 22 and tries < 600:
		tries += 1
		var r := Rect2i(rng.randi_range(16, W - 34), rng.randi_range(2, H - 14),
				rng.randi_range(8, 16), rng.randi_range(6, 11))
		if r.end.x > W - 16 or r.end.y > H - 2:
			continue
		if _overlaps(r.grow(3)):
			continue
		_make_ruin(r)
	for i in 30:
		_make_crater()
	for i in 7:
		_make_wreck()
	for i in 40:
		_make_rubble_patch()
	for i in 30:
		scorches.append([Vector2(rng.randf_range(0, W * CELL), rng.randf_range(0, H * CELL)),
				rng.randf_range(20, 60)])
	_build_astar()
	_make_textures()
	queue_redraw()


func _overlaps(r: Rect2i) -> bool:
	for b in buildings:
		if b.intersects(r):
			return true
	return false


func _side_cells(r: Rect2i, side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match side:
		0:
			for x in range(r.position.x + 1, r.end.x - 1):
				out.append(Vector2i(x, r.position.y))
		1:
			for x in range(r.position.x + 1, r.end.x - 1):
				out.append(Vector2i(x, r.end.y - 1))
		2:
			for y in range(r.position.y + 1, r.end.y - 1):
				out.append(Vector2i(r.position.x, y))
		3:
			for y in range(r.position.y + 1, r.end.y - 1):
				out.append(Vector2i(r.end.x - 1, y))
	return out


func _fill_room(r: Rect2i) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			set_t(Vector2i(x, y), T.WALL if edge else T.FLOOR)


func _make_chapel() -> void:
	chapel = Rect2i(W / 2 - 12, H / 2 - 7, 24, 14)
	buildings.append(chapel)
	_fill_room(chapel)
	for side in 4:
		var cells := _side_cells(chapel, side)
		var mid := cells.size() / 2
		for k in range(mid - 1, mid + 2):
			set_t(cells[k], T.FLOOR)
	# two rows of pillars down the nave and an altar block at the east end
	for x in range(chapel.position.x + 4, chapel.end.x - 5, 4):
		set_t(Vector2i(x, chapel.position.y + 4), T.WALL)
		set_t(Vector2i(x, chapel.end.y - 5), T.WALL)
	for y in range(chapel.position.y + 6, chapel.end.y - 6):
		set_t(Vector2i(chapel.end.x - 3, y), T.WALL)
	for side in 4:
		for c in _side_cells(chapel, side):
			if get_t(c) == T.WALL and rng.randf() < 0.08:
				set_t(c, T.RUBBLE)
	_add_buttresses(chapel)
	objective_rect = Rect2(Vector2(chapel.position + Vector2i(1, 1)) * CELL,
			Vector2(chapel.size - Vector2i(2, 2)) * CELL)


func _make_ruin(r: Rect2i) -> void:
	buildings.append(r)
	_fill_room(r)
	for side in 4:
		var cells := _side_cells(r, side)
		if cells.size() < 3:
			continue
		for g in rng.randi_range(1, 2):
			var start := rng.randi_range(0, cells.size() - 3)
			for k in rng.randi_range(2, 3):
				set_t(cells[mini(start + k, cells.size() - 1)], T.RUBBLE if rng.randf() < 0.5 else T.FLOOR)
	for side in 4:
		for c in _side_cells(r, side):
			if get_t(c) == T.WALL and rng.randf() < 0.12:
				set_t(c, T.RUBBLE)
	# part of the building has collapsed
	if rng.randf() < 0.55:
		var qw := r.size.x / 2
		var qh := r.size.y / 2
		var qx := r.position.x if rng.randf() < 0.5 else r.position.x + r.size.x - qw
		var qy := r.position.y if rng.randf() < 0.5 else r.position.y + r.size.y - qh
		for x in range(qx, qx + qw):
			for y in range(qy, qy + qh):
				var roll := rng.randf()
				set_t(Vector2i(x, y), T.RUBBLE if roll < 0.7 else T.OPEN)
	for x in range(r.position.x + 1, r.end.x - 1):
		for y in range(r.position.y + 1, r.end.y - 1):
			if get_t(Vector2i(x, y)) == T.FLOOR and rng.randf() < 0.1:
				set_t(Vector2i(x, y), T.RUBBLE)
	_add_buttresses(r)


func _add_buttresses(r: Rect2i) -> void:
	for x in range(r.position.x + 2, r.end.x - 2, 4):
		for pair in [[Vector2i(x, r.position.y), Vector2i(x, r.position.y - 1)],
				[Vector2i(x, r.end.y - 1), Vector2i(x, r.end.y)]]:
			if get_t(pair[0]) == T.WALL and get_t(pair[1]) == T.OPEN:
				set_t(pair[1], T.WALL)


func _make_crater() -> void:
	var c := Vector2(rng.randf_range(16, W - 16), rng.randf_range(3, H - 3))
	if get_t(Vector2i(c)) != T.OPEN:
		return
	var rad := rng.randf_range(1.5, 3.5)
	craters.append([c * CELL, rad * CELL])
	for x in range(int(c.x - rad - 2), int(c.x + rad + 2)):
		for y in range(int(c.y - rad - 2), int(c.y + rad + 2)):
			var cell := Vector2i(x, y)
			if get_t(cell) != T.OPEN:
				continue
			var d := (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(c)
			if d <= rad:
				set_t(cell, T.CRATER)
			elif d <= rad + 1.0 and rng.randf() < 0.6:
				set_t(cell, T.RUBBLE)


func _make_wreck() -> void:
	var horiz := rng.randf() < 0.5
	var size := Vector2i(6, 3) if horiz else Vector2i(3, 6)
	var r := Rect2i(Vector2i(rng.randi_range(16, W - 22), rng.randi_range(3, H - 9)), size)
	var area := r.grow(2)
	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var t := get_t(Vector2i(x, y))
			if t == T.WALL or t == T.FLOOR or t == T.WRECK:
				return
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			set_t(Vector2i(x, y), T.WRECK)
	wrecks.append([r, horiz])
	var centre := Vector2(r.position * CELL) + Vector2(r.size * CELL) * 0.5
	scorches.append([centre, 70.0])
	if rng.randf() < 0.7:
		fire_points.append(centre + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)))


func _make_rubble_patch() -> void:
	var c := Vector2(rng.randf_range(10, W - 10), rng.randf_range(2, H - 2))
	var rad := rng.randf_range(1.0, 2.5)
	for x in range(int(c.x - rad), int(c.x + rad) + 1):
		for y in range(int(c.y - rad), int(c.y + rad) + 1):
			var cell := Vector2i(x, y)
			if get_t(cell) == T.OPEN and Vector2(cell).distance_to(c) <= rad and rng.randf() < 0.7:
				set_t(cell, T.RUBBLE)


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL, CELL) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			var t := get_t(c)
			if blocks(t):
				astar.set_point_solid(c, true)
			else:
				astar.set_point_weight_scale(c, 1.0 / SPEED[t])
	vastar.region = astar.region
	vastar.cell_size = astar.cell_size
	vastar.offset = astar.offset
	vastar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	vastar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	vastar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	vastar.update()
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			var clear := x > 0 and y > 0 and x < W - 1 and y < H - 1
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if clear and blocks(get_t(c + Vector2i(dx, dy))):
						clear = false
			if not clear:
				vastar.set_point_solid(c, true)
			else:
				var t := get_t(c)
				vastar.set_point_weight_scale(c, 1.0 if t == T.OPEN or t == T.FLOOR else 1.8)


# ---------------------------------------------------------------- drawing

func _make_textures() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	noise_big = NoiseTexture2D.new()
	noise_big.width = 640
	noise_big.height = 400
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.01
	n.fractal_octaves = 5
	noise_big.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.2, 0.19, 0.17))
	g.set_color(1, Color(0.43, 0.4, 0.34))
	g.add_point(0.55, Color(0.32, 0.29, 0.24))
	noise_big.color_ramp = g
	noise_big.changed.connect(queue_redraw)

	noise_fine = NoiseTexture2D.new()
	noise_fine.width = 256
	noise_fine.height = 256
	noise_fine.seamless = true
	var nf := FastNoiseLite.new()
	nf.seed = rng.randi()
	nf.frequency = 0.09
	noise_fine.noise = nf
	var gf := Gradient.new()
	gf.set_color(0, Color(0, 0, 0, 0.28))
	gf.set_color(1, Color(1, 0.95, 0.85, 0.07))
	noise_fine.color_ramp = gf
	noise_fine.changed.connect(queue_redraw)


func _cell_rng(c: Vector2i) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(c.x, c.y, map_seed))
	return r


func _draw() -> void:
	var ws := world_size()
	draw_rect(Rect2(Vector2.ZERO, ws), Color(0.27, 0.25, 0.22))
	if noise_big:
		draw_texture_rect(noise_big, Rect2(Vector2.ZERO, ws), false)
		draw_texture_rect(noise_fine, Rect2(Vector2.ZERO, ws), true)
	_draw_roads()
	for s in scorches:
		for k in 4:
			draw_circle(s[0], s[1] * (1.0 - k * 0.22), Color(0.04, 0.03, 0.02, 0.16))
	for cr in craters:
		var p: Vector2 = cr[0]
		var r: float = cr[1]
		draw_circle(p, r + 7, Color(0.38, 0.35, 0.3, 0.9))
		draw_circle(p, r, Color(0.13, 0.11, 0.1))
		draw_circle(p + Vector2(r * 0.15, r * 0.2), r * 0.72, Color(0.19, 0.17, 0.14))
		draw_circle(p + Vector2(r * 0.25, r * 0.3), r * 0.35, Color(0.12, 0.13, 0.13, 0.8))
	# floors and rubble
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var t := get_t(c)
			if t == T.FLOOR:
				_draw_floor(c)
			elif t == T.RUBBLE:
				_draw_rubble(c)
	# wall shadows, then wrecks, then walls on top
	for y in H:
		for x in W:
			if get_t(Vector2i(x, y)) == T.WALL:
				draw_rect(Rect2(Vector2(x, y) * CELL + Vector2(5, 6), Vector2(CELL, CELL)), Color(0, 0, 0, 0.33))
	for wk in wrecks:
		_draw_wreck(wk[0], wk[1])
	for y in H:
		for x in W:
			if get_t(Vector2i(x, y)) == T.WALL:
				_draw_wall(Vector2i(x, y))
	_draw_chapel_details()


func _draw_roads() -> void:
	var road := Color(0.17, 0.17, 0.18, 0.75)
	var mark := Color(0.62, 0.55, 0.38, 0.3)
	var y := H * 0.8 * CELL
	draw_rect(Rect2(0, y, W * CELL, 5 * CELL), road)
	var x := W * 0.3 * CELL
	draw_rect(Rect2(x, 0, 5 * CELL, H * CELL), road)
	for i in range(0, W * CELL, 64):
		draw_rect(Rect2(i, y + 2.5 * CELL - 1, 30, 3), mark)
	for i in range(0, H * CELL, 64):
		draw_rect(Rect2(x + 2.5 * CELL - 1, i, 3, 30), mark)
	var r := RandomNumberGenerator.new()
	r.seed = map_seed
	for i in 60:
		var p := Vector2(r.randf_range(0, W * CELL), y + r.randf_range(0, 5 * CELL))
		if i % 2 == 0:
			p = Vector2(x + r.randf_range(0, 5 * CELL), r.randf_range(0, H * CELL))
		var pts := PackedVector2Array([p])
		for k in 4:
			p += Vector2(r.randf_range(-14, 14), r.randf_range(-14, 14))
			pts.append(p)
		draw_polyline(pts, Color(0.06, 0.06, 0.06, 0.6), 1.0)


func _draw_floor(c: Vector2i) -> void:
	var r := _cell_rng(c)
	var pos := Vector2(c) * CELL
	var col: Color
	if chapel.has_point(c):
		col = Color(0.4, 0.38, 0.35) if (c.x + c.y) % 2 == 0 else Color(0.31, 0.3, 0.29)
	else:
		col = Color(0.36, 0.33, 0.29).lightened(r.randf_range(-0.12, 0.08))
	draw_rect(Rect2(pos, Vector2(CELL, CELL)), col)
	draw_rect(Rect2(pos, Vector2(CELL, CELL)), Color(0, 0, 0, 0.25), false, 1.0)
	if r.randf() < 0.25:
		draw_line(pos + Vector2(r.randf() * CELL, 0), pos + Vector2(r.randf() * CELL, CELL), Color(0, 0, 0, 0.3), 1.0)


func _draw_rubble(c: Vector2i) -> void:
	var r := _cell_rng(c)
	var pos := Vector2(c) * CELL
	draw_circle(pos + Vector2(8, 8), 10, Color(0.31, 0.29, 0.26, 0.55))
	for i in r.randi_range(3, 6):
		var p := pos + Vector2(r.randf_range(1, 15), r.randf_range(1, 15))
		var s := r.randf_range(2.0, 5.5)
		var shade := r.randf_range(0.3, 0.55)
		var stone := Color(shade, shade * 0.95, shade * 0.88)
		var pts := PackedVector2Array()
		var a0 := r.randf() * TAU
		for k in 5:
			var a := a0 + k * TAU / 5.0
			pts.append(p + Vector2.from_angle(a) * s * r.randf_range(0.6, 1.0))
		draw_colored_polygon(pts, stone)
		draw_line(pts[0], pts[1], stone.lightened(0.25), 1.0)


func _draw_wall(c: Vector2i) -> void:
	var r := _cell_rng(c)
	var pos := Vector2(c) * CELL
	var base := Color(0.5, 0.47, 0.43).lightened(r.randf_range(-0.08, 0.06))
	if chapel.has_point(c) or chapel.grow(1).has_point(c):
		base = Color(0.56, 0.53, 0.5).lightened(r.randf_range(-0.06, 0.04))
	draw_rect(Rect2(pos, Vector2(CELL, CELL)), base)
	# masonry lines
	draw_line(pos + Vector2(0, 8), pos + Vector2(CELL, 8), base.darkened(0.25), 1.0)
	var off := 4.0 if c.y % 2 == 0 else 11.0
	draw_line(pos + Vector2(off, 0), pos + Vector2(off, 8), base.darkened(0.25), 1.0)
	draw_line(pos + Vector2(fmod(off + 7.0, 16.0), 8), pos + Vector2(fmod(off + 7.0, 16.0), 16), base.darkened(0.25), 1.0)
	# lit top edge and a darker south face so walls read as raised
	if get_t(c + Vector2i(0, -1)) != T.WALL:
		draw_rect(Rect2(pos, Vector2(CELL, 2)), base.lightened(0.3))
	if get_t(c + Vector2i(0, 1)) != T.WALL:
		draw_rect(Rect2(pos + Vector2(0, CELL - 4), Vector2(CELL, 4)), base.darkened(0.45))
	if get_t(c + Vector2i(1, 0)) != T.WALL:
		draw_rect(Rect2(pos + Vector2(CELL - 2, 0), Vector2(2, CELL)), base.darkened(0.3))


func _draw_wreck(rect: Rect2i, horiz: bool) -> void:
	var rr := Rect2(Vector2(rect.position * CELL), Vector2(rect.size * CELL))
	var hull := rr.grow(-2)
	draw_rect(Rect2(hull.position + Vector2(6, 7), hull.size), Color(0, 0, 0, 0.4))
	var tracks := Color(0.12, 0.11, 0.1)
	if horiz:
		draw_rect(Rect2(hull.position, Vector2(hull.size.x, 8)), tracks)
		draw_rect(Rect2(hull.position + Vector2(0, hull.size.y - 8), Vector2(hull.size.x, 8)), tracks)
		for i in range(0, int(hull.size.x), 6):
			draw_line(hull.position + Vector2(i, 0), hull.position + Vector2(i, 8), Color(0.2, 0.19, 0.17), 1.0)
	else:
		draw_rect(Rect2(hull.position, Vector2(8, hull.size.y)), tracks)
		draw_rect(Rect2(hull.position + Vector2(hull.size.x - 8, 0), Vector2(8, hull.size.y)), tracks)
	var body := hull.grow(-6)
	draw_rect(body, Color(0.24, 0.22, 0.19))
	draw_rect(body, Color(0.08, 0.07, 0.06), false, 2.0)
	var mid := body.get_center()
	draw_circle(mid, 11, Color(0.2, 0.18, 0.16))
	draw_arc(mid, 11, 0, TAU, 20, Color(0.06, 0.05, 0.05), 2.0)
	var barrel_dir := Vector2(1, 0.25) if horiz else Vector2(0.3, 1)
	draw_line(mid, mid + barrel_dir.normalized() * 34, Color(0.1, 0.09, 0.08), 4.0)
	draw_circle(mid + Vector2(-3, -2), 4, Color(0.05, 0.04, 0.04))


func _draw_chapel_details() -> void:
	var r := Rect2(Vector2(chapel.position * CELL), Vector2(chapel.size * CELL))
	# a faded mosaic sunburst at the centre of the nave
	var c := r.get_center()
	for i in 12:
		var a := i * TAU / 12.0
		draw_line(c, c + Vector2.from_angle(a) * 46, Color(0.75, 0.6, 0.3, 0.35), 3.0)
	draw_circle(c, 18, Color(0.55, 0.42, 0.2, 0.6))
	draw_circle(c, 10, Color(0.2, 0.16, 0.12, 0.8))
