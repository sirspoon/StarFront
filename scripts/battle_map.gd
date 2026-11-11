class_name BattleMap
extends Node2D
## The battlefield: a grid of terrain cells used for movement, line of sight and
## cover, including walls that can be shot down. Drawing is done by MapView/MapPainter.

signal cells_changed(cells: Array)  # terrain changed (a wall was damaged or fell)

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
var wall_hp := PackedFloat32Array()   # strength of each wall cell (100 = intact)
var wall_max := PackedFloat32Array()
var fallen := PackedByteArray()        # 1 where a wall has collapsed into rubble
var puddles: Array = []   # [center: Vector2, radius: float, squash: float]
var roads: Array = []     # Rect2 in world pixels

const WALL_HP := 100.0
const CHAPEL_WALL_HP := 160.0


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
	var changed: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if in_bounds(n) and get_t(n) != T.WALL:
				set_t(n, T.WRECK)
				changed.append(n)
	_refresh_cells(changed)


# ---------------------------------------------------------------- destruction

## Wall strength left in cell c, from 0 to 1 (1 for anything that isn't a wall).
func wall_health(c: Vector2i) -> float:
	if not in_bounds(c) or get_t(c) != T.WALL:
		return 1.0
	var i := c.y * W + c.x
	return wall_hp[i] / wall_max[i]


## Damage stage used for drawing: 0 intact, 1 cracked, 2 badly broken.
func wall_stage(c: Vector2i) -> int:
	var h := wall_health(c)
	return 0 if h > 0.66 else (1 if h > 0.33 else 2)


## An explosion: wall cells within reach lose strength, more near the centre.
## Walls only feel the heart of a blast, so radius here is about half the blast's.
## Walls that run out collapse into passable rubble.
func damage_walls(at: Vector2, radius: float, dmg: float) -> Array:
	var changed: Array = []
	var fell: Array = []
	var reach := radius * 0.5 + CELL * 0.6
	var c0 := cell_of(at)
	var n := int(ceil(reach / CELL)) + 1
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			var c := c0 + Vector2i(dx, dy)
			if not in_bounds(c) or get_t(c) != T.WALL:
				continue
			var d := center_of(c).distance_to(at)
			if d > reach:
				continue
			var stage := wall_stage(c)
			var i := c.y * W + c.x
			wall_hp[i] -= dmg * clampf(1.0 - d / (reach * 1.15), 0.25, 1.0)
			if wall_hp[i] <= 0.0:
				set_t(c, T.RUBBLE)
				fallen[i] = 1
				fell.append(c)
				changed.append(c)
			elif wall_stage(c) != stage:
				changed.append(c)
	if not fell.is_empty():
		_refresh_cells(fell)
	if not changed.is_empty():
		cells_changed.emit(changed)
	return fell


func wall_near(at: Vector2, reach: float) -> bool:
	var c0 := cell_of(at)
	var n := int(ceil(reach / CELL))
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			var c := c0 + Vector2i(dx, dy)
			if get_t(c) == T.WALL and in_bounds(c) and center_of(c).distance_to(at) <= reach:
				return true
	return false


## First point on the line a->b that runs into a wall or wreck, or b if none.
func first_obstacle(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var steps := int(d.length() / 4.0)
	var ca := cell_of(a)
	for i in range(1, steps + 1):
		var p := a + d * (float(i) / steps)
		var c := cell_of(p)
		if c != ca and blocks(get_t(c)):
			return p
	return b


## Bring path-finding up to date after cells changed type.
func _refresh_cells(cells: Array) -> void:
	for c in cells:
		_refresh_astar(c)
	for c in cells:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_refresh_vastar(c + Vector2i(dx, dy))


func _refresh_astar(c: Vector2i) -> void:
	var t := get_t(c)
	astar.set_point_solid(c, blocks(t))
	if not blocks(t):
		astar.set_point_weight_scale(c, 1.0 / SPEED[t])


func _refresh_vastar(c: Vector2i) -> void:
	if not in_bounds(c):
		return
	var clear := c.x > 0 and c.y > 0 and c.x < W - 1 and c.y < H - 1
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if clear and blocks(get_t(c + Vector2i(dx, dy))):
				clear = false
	vastar.set_point_solid(c, not clear)
	if clear:
		var t := get_t(c)
		vastar.set_point_weight_scale(c, 1.0 if t == T.OPEN or t == T.FLOOR else 1.8)


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
	_init_walls()
	_make_decor()
	_build_astar()


func _init_walls() -> void:
	wall_hp.resize(W * H)
	wall_max.resize(W * H)
	fallen.resize(W * H)
	fallen.fill(0)
	for y in H:
		for x in W:
			var hp := CHAPEL_WALL_HP if chapel.grow(1).has_point(Vector2i(x, y)) else WALL_HP
			wall_hp[y * W + x] = hp
			wall_max[y * W + x] = hp
	# gaps in the ruins' outer walls are collapsed wall too (the chapel's doorways aren't)
	for b in buildings:
		var is_chapel := b == chapel
		for side in 4:
			for c in _side_cells(b, side) + [b.position, Vector2i(b.end.x - 1, b.position.y),
					Vector2i(b.position.x, b.end.y - 1), b.end - Vector2i.ONE]:
				var t := get_t(c)
				if t == T.WALL or (is_chapel and t == T.FLOOR):
					continue
				if t == T.OPEN:
					set_t(c, T.RUBBLE)
				fallen[c.y * W + c.x] = 1


func _make_decor() -> void:
	roads = [Rect2(0, H * 0.8 * CELL, W * CELL, 5 * CELL), Rect2(W * 0.3 * CELL, 0, 5 * CELL, H * CELL)]
	for i in 26:
		var c := Vector2(rng.randf_range(0, W * CELL), rng.randf_range(0, H * CELL))
		if get_t(cell_of(c)) == T.OPEN:
			puddles.append([c, rng.randf_range(10, 30), rng.randf_range(0.45, 0.8)])


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
	for a in [astar, vastar]:
		a.region = Rect2i(0, 0, W, H)
		a.cell_size = Vector2(CELL, CELL)
		a.offset = Vector2(CELL, CELL) * 0.5
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.update()
	for x in W:
		for y in H:
			_refresh_astar(Vector2i(x, y))
			_refresh_vastar(Vector2i(x, y))
