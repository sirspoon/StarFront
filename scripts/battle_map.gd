class_name BattleMap
extends Node2D
## The battlefield: a grid of terrain cells used for movement, line of sight and
## cover, including walls that can be shot down. Drawing is done by MapView/MapPainter.

signal cells_changed(cells: Array)  # terrain changed (a wall was damaged or fell)
signal roof_changed(building: int)  # part of a building's roof was damaged or fell in

const CELL := 16
const W := 160
const H := 100

enum T { OPEN, RUBBLE, CRATER, FLOOR, WALL, WRECK, LOW, WINDOW, BUSH, HEDGE, WIRE, TRENCH }

## BUSH hides a man who keeps still (and spoils aim a little); HEDGE blocks sight and is slow
## to push through; WIRE (barbed wire) gives no cover and is very slow to cross. Vehicles
## flatten all three.
const COVER := [0.0, 0.35, 0.45, 0.15, 0.0, 0.0, 0.3, 0.0, 0.3, 0.3, 0.0, 0.55]
const SPEED := [1.0, 0.7, 0.75, 1.0, 1.0, 1.0, 0.35, 1.0, 0.7, 0.3, 0.22, 0.85]
const TERRAIN_NAMES := ["Open ground", "Rubble", "Crater", "Ruin floor", "Wall", "Wreck", "Low cover", "Window",
		"Bushes", "Hedge", "Barbed wire", "Trench"]
const WINDOW_COVER := 0.5  # a man firing from just inside a window
const SLIT_COVER := 0.78   # ...or a bunker's firing slit
const BUNKER_WALL_HP := 320.0

## Low cover: chest-high things troops crouch behind and fire over. It doesn't block
## sight, infantry can clamber over it slowly, vehicles go round. It soaks up more
## punishment than a full wall before it is destroyed.
enum LowKind { NONE, SANDBAGS, STONE, BARRICADE, CRATES }
const LOW_COVER := [0.0, 0.7, 0.65, 0.5, 0.55]       # cover it gives from fire on its far side
const LOW_HP := [0.0, 260.0, 220.0, 180.0, 150.0]
const LOW_NAMES := ["", "Sandbags", "Low wall", "Barricade", "Crates"]

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
var fallen := PackedByteArray()        # 1 where a wall has collapsed into rubble, 2 where low cover was destroyed
var roof_hp := PackedFloat32Array()  # roof over each cell (100 intact, 0 none or fallen in)
var building_of := PackedInt32Array()  # which building each cell belongs to (-1: none)
var collapsed := PackedByteArray()     # cells whose roof fell in before the battle
var low_kind := PackedByteArray()      # LowKind of each LOW cell (kept after it is destroyed, for its remains)
var puddles: Array = []   # [center: Vector2, radius: float, squash: float]
var roads: Array = []     # Rect2 in world pixels
var plaza := Rect2i()     # the paved square round the chapel
var parks: Array[Rect2i] = []
## What each building was before the war (parallel to buildings): "chapel", "home", "shop",
## "tavern", "office" or "industry"; its sign (shops and taverns); and the side facing the
## nearest street (0 top, 1 bottom, 2 left, 3 right).
var building_kind: Array[String] = []
## "town" (homes, shops, parks...) or "foundry" (mostly warehouses, works and machinery yards).
var map_type := "town"
var trenches := false  # dig trench lines across the battlefield (an option)
## Big solid objects drawn by the painter, their cells WRECK (blocking): {kind, rect, seed}.
## Kinds: "tank" (storage tank), "furnace", "wagon" (rail wagon), "statue".
var props: Array = []
## Railway sidings, drawn on the ground: [start cell, length in cells, horizontal].
var rails: Array = []
var bunker_mask := PackedByteArray()  # 1 on every cell of a bunker
var building_name: Array[String] = []
var building_front: Array[int] = []
const SHOP_NAMES := ["CANDLE & CENSER", "RELIC MENDER", "BREAD OF VELL", "PAWN & SCRIP", "APOTHECARY",
		"TAILOR OF ASH ROW", "LAMP OIL", "VOTIVE GOODS", "SALVAGE", "RATION HALL", "IRONMONGER", "BOOKBINDER"]
const TAVERN_NAMES := ["THE DROWNED SAINT", "THE LAST CANDLE", "THE IRON PEW", "THE ASHEN LAMB"]
const WAREHOUSE_NAMES := ["DEPOT 4", "BONDED STORES", "GRAIN STORE", "WAREHOUSE 12", "RAILWAY GOODS"]
const WORKS_NAMES := ["VELL IRONWORKS", "TALLOW & LYE", "RECLAMATION WORKS", "PUMP STATION 3", "GAS WORKS"]
var crushed := PackedByteArray()  # the T a cell was before a vehicle or blast flattened it (bush, hedge, wire)

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


## Blocks sight and shots.
func blocks(t: int) -> bool:
	return t == T.WALL or t == T.WRECK


## Blocks movement: walls and wrecks, and windows (you can see and shoot through
## them, not walk through them).
func solid(t: int) -> bool:
	return t == T.WALL or t == T.WRECK or t == T.WINDOW


## Part of a building's wall (a window is a wall with an opening in it).
func is_wall(t: int) -> bool:
	return t == T.WALL or t == T.WINDOW


func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not solid(get_t(c))


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
		elif t == T.WINDOW:
			cov += 0.18
		elif t == T.LOW:
			cov += 0.25
	return cov


func low_cover_at(c: Vector2i) -> float:
	return LOW_COVER[low_kind[c.y * W + c.x]] if get_t(c) == T.LOW else 0.0


## How good cell c is for a soldier facing dir: low cover between him and the
## threat is best (he can shoot over it); walls and rubble help less. Falls back
## to all-round cover when there is no direction.
func cell_cover_dir(c: Vector2i, dir: Vector2) -> float:
	if dir == Vector2.ZERO:
		return cell_cover(c)
	var t := get_t(c)
	var cov: float = COVER[t]
	var best := 0.0
	var a := dir.angle()
	for off in [0.0, -0.75, 0.75]:
		var n := cell_of(center_of(c) + Vector2.from_angle(a + off) * CELL)
		var nt := get_t(n)
		var v := 0.0
		if nt == T.LOW:
			v = low_cover_at(n) + 0.25
		elif nt == T.RUBBLE:
			v = 0.4
		elif nt == T.WINDOW:
			v = (SLIT_COVER if is_bunker(n) else WINDOW_COVER) + 0.1  # a firing position: safe, and he can shoot out
		elif nt == T.WALL or nt == T.WRECK:
			v = 0.3  # safe, but he can't shoot through it
		best = maxf(best, v * (1.0 if off == 0.0 else 0.8))
	return cov + best


## How good a cell is to fire from towards dir: a window or bunker slit best, then low
## cover and rubble; a plain wall in front is safe but no use to a gunner.
func firing_score(c: Vector2i, dir: Vector2) -> float:
	if dir == Vector2.ZERO:
		return cell_cover(c)
	var a := dir.angle()
	var best := 0.0
	for off in [0.0, -0.6, 0.6]:
		var n := cell_of(center_of(c) + Vector2.from_angle(a + off) * CELL)
		var nt := get_t(n)
		var v := 0.0
		if nt == T.WINDOW:
			v = 1.3 if is_bunker(n) else 1.1
		elif nt == T.LOW:
			v = low_cover_at(n) + 0.2
		elif nt == T.RUBBLE:
			v = 0.45
		best = maxf(best, v * (1.0 if off == 0.0 else 0.75))
	return best + COVER[get_t(c)] * 0.5


## The low-cover cell shielding a target from a shooter, or (-1, -1).
func cover_cell(target_pos: Vector2, shooter_pos: Vector2) -> Vector2i:
	var dir := (shooter_pos - target_pos).normalized()
	for d in [7.0, 13.0, 20.0]:
		var c := cell_of(target_pos + dir * d)
		if get_t(c) == T.LOW:
			return c
	return Vector2i(-1, -1)


## Cover a target gets against a shooter at shooter_pos (0 = none, 1 = total).
func cover_vs(target_pos: Vector2, shooter_pos: Vector2) -> float:
	var cov: float = COVER[get_t(cell_of(target_pos))]
	var dir := (shooter_pos - target_pos).normalized()
	var ft := get_t(cell_of(target_pos + dir * CELL))
	if ft == T.RUBBLE or ft == T.CRATER:
		cov = maxf(cov, 0.4)
	elif ft == T.WALL or ft == T.WRECK:
		cov = maxf(cov, 0.55)
	elif ft == T.WINDOW:
		cov = maxf(cov, SLIT_COVER if is_bunker(cell_of(target_pos + dir * CELL)) else WINDOW_COVER)
	var lc := cover_cell(target_pos, shooter_pos)
	if lc.x >= 0:
		cov = maxf(cov, low_cover_at(lc))
	return cov


## True if nothing solid lies between a and b.
var smoke_screens: Array = []  # [centre, radius] of smoke screens, which block sight (set by Grenades)


func los_clear(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	if not smoke_screens.is_empty() and d.length_squared() > 40.0 * 40.0:
		var l2 := d.length_squared()
		for s in smoke_screens:
			var c: Vector2 = s[0]
			var k := clampf((c - a).dot(d) / l2, 0.0, 1.0)
			if (a + d * k).distance_squared_to(c) < float(s[1]) * float(s[1]):
				return false  # the smoke is in the way
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
		var t := get_t(c)
		if blocks(t) or t == T.HEDGE:
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
			if in_bounds(n) and not is_wall(get_t(n)):
				set_t(n, T.WRECK)
				changed.append(n)
	_refresh_cells(changed)


# ---------------------------------------------------------------- destruction

## Wall strength left in cell c, from 0 to 1 (1 for anything that isn't a wall).
func wall_health(c: Vector2i) -> float:
	if not in_bounds(c) or (not is_wall(get_t(c)) and get_t(c) != T.LOW):
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
			if not in_bounds(c) or (not is_wall(get_t(c)) and get_t(c) != T.LOW):
				continue
			var d := center_of(c).distance_to(at)
			if d > reach:
				continue
			var stage := wall_stage(c)
			var i := c.y * W + c.x
			wall_hp[i] -= dmg * clampf(1.0 - d / (reach * 1.15), 0.25, 1.0)
			if wall_hp[i] <= 0.0:
				fallen[i] = 2 if get_t(c) == T.LOW else 1
				set_t(c, T.RUBBLE)
				fell.append(c)
				changed.append(c)
			elif wall_stage(c) != stage:
				changed.append(c)
	if not fell.is_empty():
		_refresh_cells(fell)
		_collapse_roof_near(fell)
	if not changed.is_empty():
		cells_changed.emit(changed)
	return fell


func wall_near(at: Vector2, reach: float) -> bool:
	var c0 := cell_of(at)
	var n := int(ceil(reach / CELL))
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			var c := c0 + Vector2i(dx, dy)
			if is_wall(get_t(c)) and in_bounds(c) and center_of(c).distance_to(at) <= reach:
				return true
	return false


## Small arms chewing at low cover (sandbags split, barricades splinter).
## Returns true if it was destroyed.
func chip_low(c: Vector2i, dmg: float) -> bool:
	if get_t(c) != T.LOW:
		return false
	var i := c.y * W + c.x
	var stage := wall_stage(c)
	wall_hp[i] -= dmg
	if wall_hp[i] <= 0.0:
		fallen[i] = 2
		set_t(c, T.RUBBLE)
		_refresh_cells([c])
		_collapse_roof_near([c])
		cells_changed.emit([c])
		return true
	if wall_stage(c) != stage:
		cells_changed.emit([c])
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
	astar.set_point_solid(c, solid(t))
	if not solid(t):
		astar.set_point_weight_scale(c, 1.0 / SPEED[t])


func _refresh_vastar(c: Vector2i) -> void:
	if not in_bounds(c):
		return
	var clear := c.x > 0 and c.y > 0 and c.x < W - 1 and c.y < H - 1
	var bash := 0.0  # how much it would rather not push through what's here (sandbags most)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			var nt := get_t(n)
			if nt == T.LOW and vehicle_can_crush(n):
				bash = maxf(bash, 3.0 if low_kind[n.y * W + n.x] == LowKind.SANDBAGS else 1.8)
			elif clear and (solid(nt) or nt == T.LOW or nt == T.TRENCH):
				clear = false  # vehicles drive round low walls and trenches
	vastar.set_point_solid(c, not clear)
	if clear:
		var t := get_t(c)
		var w := 1.0 if t == T.OPEN or t == T.FLOOR else 1.8
		vastar.set_point_weight_scale(c, maxf(w, bash))


## Barricades, crates and sandbags give way under a vehicle (low stone walls don't).
func vehicle_can_crush(c: Vector2i) -> bool:
	return get_t(c) == T.LOW and low_kind[c.y * W + c.x] != LowKind.STONE


# ---------------------------------------------------------------- generation

func generate(seed_value: int) -> void:
	map_seed = seed_value
	rng.seed = seed_value
	grid.resize(W * H)
	grid.fill(T.OPEN)
	collapsed.resize(W * H)
	collapsed.fill(0)
	low_kind.resize(W * H)
	low_kind.fill(0)
	crushed.resize(W * H)
	crushed.fill(0)
	bunker_mask.resize(W * H)
	bunker_mask.fill(0)
	_make_city()
	for i in 22:
		_make_crater()
	for i in 6:
		_make_wreck()
	for i in 26:
		_make_rubble_patch()
	for i in 14:
		_make_scrub()
	_crumble_walls()
	_make_windows()
	_fortify()
	if trenches:
		_make_trenches()
	for i in 30:
		scorches.append([Vector2(rng.randf_range(0, W * CELL), rng.randf_range(0, H * CELL)),
				rng.randf_range(20, 60)])
	_init_walls()
	_init_roofs()
	_make_decor()
	_build_astar()


# ---------------------------------------------------------------- the city

## Streets laid out the way a city's are: avenues running north-south, two cross streets,
## the chapel in a paved square in the middle, and city blocks between them, each built
## up, a park, a walled compound or a bombed-out lot. The deployment strips at either end
## stay open ground.
func _make_city() -> void:
	var vx := [rng.randi_range(27, 33), rng.randi_range(50, 56), rng.randi_range(104, 110), rng.randi_range(127, 133)]
	var vw := [4, 5, 5, 4]
	var hy := [rng.randi_range(22, 28), rng.randi_range(70, 76)]
	var hw := [5, 5]
	for i in vx.size():
		roads.append(Rect2(vx[i] * CELL, 0, vw[i] * CELL, H * CELL))
	for i in hy.size():
		roads.append(Rect2(0, hy[i] * CELL, W * CELL, hw[i] * CELL))
	_make_chapel()
	plaza = chapel.grow(5)
	# the city blocks: between the deployment strips, the avenues and the cross streets
	var xs := [[16, vx[0] - 1]]
	for i in range(vx.size() - 1):
		xs.append([vx[i] + vw[i] + 1, vx[i + 1] - 1])
	xs.append([vx[vx.size() - 1] + vw[vw.size() - 1] + 1, W - 17])
	var ys := [[1, hy[0] - 1], [hy[0] + hw[0] + 1, hy[1] - 1], [hy[1] + hw[1] + 1, H - 2]]
	var blocks: Array[Rect2i] = []
	for xr in xs:
		for yr in ys:
			var r := Rect2i(xr[0], yr[0], xr[1] - xr[0], yr[1] - yr[0])
			if r.size.x >= 6 and r.size.y >= 6:
				blocks.append(r)
	blocks.sort_custom(func(p, q): return _h(p.position.x, p.position.y) < _h(q.position.x, q.position.y))
	var kinds := ["park", "compound"] if map_type == "town" else ["industrial", "industrial", "compound"]  # at least these
	var mix := ["built", "built", "built", "park", "compound", "lot", "built", "built", "park", "compound", "lot", "industrial"] if map_type == "town" \
			else ["industrial", "industrial", "industrial", "compound", "compound", "built", "lot", "industrial"]
	for i in blocks.size():
		var b := blocks[i]
		if b.intersects(plaza):
			_make_square(b)
			continue
		var kind: String = kinds.pop_front() if not kinds.is_empty() else mix[rng.randi() % mix.size()]
		match kind:
			"industrial":
				_make_industrial(b)
			"built":
				_make_built_block(b)
			"park":
				_make_park(b)
			"compound":
				_make_compound(b)
			_:
				for k in 3:
					_make_rubble_patch_at(Vector2(b.position) + Vector2(b.size) * Vector2(rng.randf(), rng.randf()))


func _h(a: int, b: int) -> float:
	return float(hash(Vector3i(a, b, map_seed)) % 10000) / 10000.0


func is_road(c: Vector2i) -> bool:
	var p := center_of(c)
	for rd in roads:
		if (rd as Rect2).has_point(p):
			return true
	return false


## The chapel's block: the square round it, with the rest of the block built up.
func _make_square(b: Rect2i) -> void:
	# saints on plinths flanking the chapel's west and east doors (at the factorium: great iron
	# cog-wheels raised on plinths, monuments to the works)
	var cy := chapel.get_center().y
	for x in [chapel.position.x - 3, chapel.end.x + 1]:
		for dy in [-4, 3]:
			if map_type == "foundry":
				var r := Rect2i(Vector2i(x, cy + dy), Vector2i(2, 2))
				if _all_open(r):
					_place_prop("cogwheel", r)
			else:
				_make_statue(Vector2i(x, cy + dy))
	for side in 2:  # a building or two on the far edges of the block, clear of the square
		var strip := Rect2i(b.position.x, b.position.y, b.size.x, plaza.position.y - b.position.y - 2) if side == 0 \
				else Rect2i(b.position.x, plaza.end.y + 2, b.size.x, b.end.y - plaza.end.y - 2)
		if strip.size.y >= 6:
			_make_built_block(strip)


## Buildings along the block's edges facing the streets, alleys between them, yards behind.
func _make_built_block(b: Rect2i) -> void:
	var rows := 2 if b.size.y >= 17 else 1
	for row in rows:
		var depth := mini(rng.randi_range(6, 11), b.size.y - 1 if rows == 1 else b.size.y / 2 - 1)
		if depth < 5:
			continue
		var y := b.position.y if row == 0 else b.end.y - depth
		if rows == 1 and rng.randf() < 0.5:
			y = b.end.y - depth  # face the other street
		var x := b.position.x
		while x < b.end.x - 5:
			var w := mini(rng.randi_range(7, 16), b.end.x - x)
			if b.end.x - (x + w) < 6:
				w = b.end.x - x  # don't leave a sliver
			if w >= 6:
				var r := Rect2i(x, y, w, depth)
				if not _overlaps(r.grow(1)) and not r.intersects(plaza):
					_make_ruin(r)
			x += w + rng.randi_range(2, 3)  # an alley


## A park: dead grass, gravel paths, bushes and clipped hedges, a low wall round it.
func _make_park(b: Rect2i) -> void:
	var r := b.grow(-1)
	parks.append(r)
	var walled := rng.randf() < 0.65
	for c in _ring(r):
		if walled and rng.randf() > 0.12:
			_set_low(c, LowKind.STONE)
		elif not walled and rng.randf() > 0.2:
			set_t(c, T.HEDGE)
	# gates: gaps in the middle of each side
	for g in [Vector2i(r.get_center().x, r.position.y), Vector2i(r.get_center().x, r.end.y - 1),
			Vector2i(r.position.x, r.get_center().y), Vector2i(r.end.x - 1, r.get_center().y)]:
		for k in range(-1, 2):
			var gc: Vector2i = g + (Vector2i(k, 0) if g.y == r.position.y or g.y == r.end.y - 1 else Vector2i(0, k))
			set_t(gc, T.OPEN)
			low_kind[gc.y * W + gc.x] = 0
	var inner := r.grow(-2)
	# a statue (or two) by the paths' crossing
	var pc := r.get_center()
	_make_statue(pc + Vector2i(2, 2))
	if rng.randf() < 0.5:
		_make_statue(pc - Vector2i(3, 3))
	for i in int(inner.get_area() / 20):  # clumps of bushes
		var o := Vector2(inner.position) + Vector2(inner.size) * Vector2(rng.randf(), rng.randf())
		var rad := rng.randf_range(0.8, 1.8)
		for x in range(int(o.x - rad), int(o.x + rad) + 1):
			for y in range(int(o.y - rad), int(o.y + rad) + 1):
				var c := Vector2i(x, y)
				if inner.has_point(c) and get_t(c) == T.OPEN and Vector2(c).distance_to(o) <= rad and rng.randf() < 0.85:
					set_t(c, T.BUSH)
	for i in rng.randi_range(2, 4):  # hedge rows
		var horiz := rng.randf() < 0.5
		var o := Vector2i(rng.randi_range(inner.position.x, inner.end.x - 1), rng.randi_range(inner.position.y, inner.end.y - 1))
		var along := Vector2i(1, 0) if horiz else Vector2i(0, 1)
		var length := rng.randi_range(4, 9)
		var gap := rng.randi_range(1, length - 2)
		for k in length:
			var c := o + along * k
			if k != gap and inner.has_point(c) and get_t(c) == T.OPEN:
				set_t(c, T.HEDGE)


## A compound: a tall wall round the block with a gate on a street, and inside a
## building, a fortified position or both.
func _make_compound(b: Rect2i) -> void:
	var r := b.grow(-1)
	for c in _ring(r):
		set_t(c, T.WALL)
	# a gate wide enough for a vehicle on each long side, and a breach or two
	var gx := rng.randi_range(r.position.x + 2, r.end.x - 5)
	for side_y in [r.position.y, r.end.y - 1]:
		for k in 3:
			set_t(Vector2i(gx + k, side_y), T.OPEN)
	var gy := rng.randi_range(r.position.y + 2, r.end.y - 5)
	for k in 3:
		set_t(Vector2i(r.position.x if rng.randf() < 0.5 else r.end.x - 1, gy + k), T.OPEN)
	for c in _ring(r):
		if get_t(c) == T.WALL:
			var roll := rng.randf()
			if roll < 0.05:
				set_t(c, T.RUBBLE)
			elif roll < 0.12:
				_set_low(c, LowKind.STONE)
	var inner := r.grow(-2)
	if inner.size.x >= 9 and inner.size.y >= 7 and rng.randf() < 0.7:
		var w := mini(rng.randi_range(8, 14), inner.size.x - 2)
		var h := mini(rng.randi_range(6, 10), inner.size.y - 2)
		var bx := inner.position.x + rng.randi_range(0, inner.size.x - w)
		var by := inner.position.y + rng.randi_range(0, inner.size.y - h)
		_make_ruin(Rect2i(bx, by, w, h), "industry")  # behind a compound's walls: works


## A statue on a plinth (2x2 cells, solid): a saint, a soldier or a robed figure.
func _make_statue(c: Vector2i) -> void:
	var r := Rect2i(c, Vector2i(2, 2))
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			if get_t(Vector2i(x, y)) != T.OPEN:
				return
	_place_prop("statue", r)


func _place_prop(kind: String, r: Rect2i) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			set_t(Vector2i(x, y), T.WRECK)
	props.append({"kind": kind, "rect": r, "seed": rng.randi()})


func _all_open(r: Rect2i) -> bool:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			if not in_bounds(Vector2i(x, y)) or get_t(Vector2i(x, y)) != T.OPEN:
				return false
	return true


## Heavy industry: a big warehouse (aisles of stacked crates inside), and a yard of storage
## tanks, a furnace house, crate stacks and a railway siding with a wagon on it.
func _make_industrial(b: Rect2i) -> void:
	var r := b.grow(-1)
	# the warehouse along one long side of the block
	var top := rng.randf() < 0.5
	var depth := mini(rng.randi_range(9, 13), r.size.y - 6)
	var wlen := mini(rng.randi_range(14, 24), r.size.x)
	if depth >= 7 and wlen >= 10:
		var wx := r.position.x + rng.randi_range(0, r.size.x - wlen)
		var wr := Rect2i(wx, r.position.y if top else r.end.y - depth, wlen, depth)
		if not _overlaps(wr.grow(1)) and not wr.intersects(plaza):
			_make_ruin(wr, "warehouse")
			for y in range(wr.position.y + 2, wr.end.y - 2, 3):  # aisles of stacked crates
				for x in range(wr.position.x + 2, wr.end.x - 2):
					var c := Vector2i(x, y)
					if get_t(c) == T.FLOOR and rng.randf() < 0.55 and (x - wr.position.x) % 6 != 0:
						_set_low(c, LowKind.CRATES)
	# the yard
	var yard := Rect2i(r.position.x, r.end.y - (r.size.y - depth - 1) if top else r.position.y, r.size.x, r.size.y - depth - 1)
	if yard.size.y < 4:
		return
	# a railway siding running along the yard, with a wagon standing on it
	var ry := yard.position.y + yard.size.y / 2
	rails.append([Vector2i(yard.position.x, ry), yard.size.x, true])
	var wagon := Rect2i(yard.position.x + rng.randi_range(1, maxi(1, yard.size.x - 8)), ry - 1, 6, 2)
	if _all_open(wagon):
		_place_prop("wagon", wagon)
	var tanks := rng.randi_range(2, 4)
	for i in 14:  # storage tanks (several tries to find room for each)
		if tanks <= 0:
			break
		var d := rng.randi_range(3, 5)
		var tr := Rect2i(yard.position.x + rng.randi_range(0, maxi(0, yard.size.x - d)), yard.position.y + rng.randi_range(0, maxi(0, yard.size.y - d)), d, d)
		if tr.position.y <= ry + 1 and tr.end.y >= ry - 1:
			continue  # not on the rails
		if _all_open(tr.grow(1)):
			_place_prop("tank", tr)
			tanks -= 1
	var furnaces := rng.randi_range(1, 2)
	for i in 10:  # furnace houses with their stacks
		if furnaces <= 0:
			break
		var fr := Rect2i(yard.position.x + rng.randi_range(0, maxi(0, yard.size.x - 4)), yard.position.y + rng.randi_range(0, maxi(0, yard.size.y - 3)), 4, 3)
		if (fr.position.y > ry + 1 or fr.end.y < ry - 1) and _all_open(fr.grow(1)):
			_place_prop("furnace", fr)
			furnaces -= 1
	for i in rng.randi_range(3, 6):  # stacks of crates: cover in the yard
		var o := Vector2i(yard.position.x + rng.randi_range(0, yard.size.x - 3), yard.position.y + rng.randi_range(0, yard.size.y - 2))
		var cells: Array = [o, o + Vector2i(1, 0)]
		if rng.randf() < 0.5:
			cells.append(o + Vector2i(0, 1))
		for c in cells:
			if get_t(c) == T.OPEN and absi(c.y - ry) > 0:
				_set_low(c, LowKind.CRATES)


## The cells round the edge of r.
func _ring(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y))
		out.append(Vector2i(x, r.end.y - 1))
	for y in range(r.position.y + 1, r.end.y - 1):
		out.append(Vector2i(r.position.x, y))
		out.append(Vector2i(r.end.x - 1, y))
	return out


# ---------------------------------------------------------------- defences

## Defences built round what's worth holding: the chapel, and two or three other key
## buildings. Each gets fighting positions facing out towards its approaches (their way
## in at the back, towards what they defend), barbed wire in front of them, and barricades
## across the streets leading in.
func _fortify() -> void:
	_fortify_site(chapel, [0.0, PI, PI * 0.25, -PI * 0.25, PI * 0.75, -PI * 0.75, PI * 0.5, -PI * 0.5])
	_make_bunker(chapel, 0)  # bunkers on the chapel's east and west approaches
	_make_bunker(chapel, 2)
	var picks: Array = []
	for i in range(1, buildings.size()):
		var k := building_kind[i]
		if k == "warehouse" or k == "tavern" or k == "office" or (k == "industry" and rng.randf() < 0.5):
			picks.append(i)
	picks.sort_custom(func(a, b): return _h(a, 7) < _h(b, 7))
	for i in picks.slice(0, 3):
		var r: Rect2i = buildings[i]
		var east := r.get_center().x > W / 2  # positions face the way the enemy would come
		_fortify_site(r, [0.0 if east else PI, (0.4 if east else PI - 0.4), (-0.4 if east else PI + 0.4)])
		_make_bunker(r, 0 if east else 2)


func _fortify_site(site: Rect2i, angles: Array) -> void:
	var c := Vector2(site.get_center())
	var hw := site.size.x * 0.5
	var hh := site.size.y * 0.5
	for a in angles:
		var dir := Vector2.from_angle(a)
		var edge := minf(hw / maxf(absf(dir.x), 0.01), hh / maxf(absf(dir.y), 0.01))  # out to the site's edge
		for attempt in 16:
			var o := c + dir * (edge + rng.randf_range(4.0, 8.0)) + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			var shape: String = ["ring", "arc", "line"][rng.randi() % 3]
			if _fighting_position(o, a, shape):
				break
	_street_barricades(site)


## A sandbagged fighting position at o, its front facing angle `a`: a ring with its way in
## at the back, an arc open at the back, or a straight wall across the line of approach;
## with barbed wire strung in front.
func _fighting_position(o: Vector2, a: float, shape: String) -> bool:
	var cells: Array = []
	var rad := rng.randf_range(2.6, 3.4)
	var n := 40
	if shape == "line":
		var across := Vector2.from_angle(a).orthogonal()
		for k in range(-3, 4):
			var cc := Vector2i(roundi(o.x + across.x * k), roundi(o.y + across.y * k))
			if not cells.has(cc):
				cells.append(cc)
		rad = 0.0
	else:
		for i in n:
			var ang := i * TAU / n
			var off := absf(wrapf(ang - a, -PI, PI))
			if shape == "ring" and off > PI - 0.5:
				continue  # the way in, at the back
			if shape == "arc" and off > 1.7:
				continue  # open at the back
			var cc := Vector2i(roundi(o.x + cos(ang) * rad), roundi(o.y + sin(ang) * rad))
			if not cells.has(cc):
				cells.append(cc)
	for cc in cells:  # built on open ground or rubble, clear of the streets' far side and the start areas
		if not in_bounds(cc) or cc.x < 16 or cc.x > W - 17 or not (get_t(cc) == T.OPEN or get_t(cc) == T.RUBBLE):
			return false
	for cc in cells:
		_set_low(cc, LowKind.SANDBAGS)
	for i in n:  # wire in front
		var ang := i * TAU / n
		if absf(wrapf(ang - a, -PI, PI)) > 0.8:
			continue
		var wc := Vector2i(roundi(o.x + cos(ang) * (rad + 3.5)), roundi(o.y + sin(ang) * (rad + 3.5)))
		if in_bounds(wc) and get_t(wc) == T.OPEN and wc.x > 16 and wc.x < W - 17:
			set_t(wc, T.WIRE)
	return true


## A small concrete bunker out on one approach to a site (side 0 east, 1 south, 2 west,
## 3 north): thick walls, a long firing slit in the front facing the approach, and a doorway
## at the back facing the site.
func _make_bunker(site: Rect2i, side: int) -> void:
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var out: Vector2i = dirs[side]
	var size := Vector2i(4, 5) if out.x != 0 else Vector2i(5, 4)
	for attempt in 14:
		var dist := rng.randi_range(5, 10)
		var c := site.get_center()
		var base := Vector2i(site.end.x + dist if out.x > 0 else (site.position.x - dist - size.x if out.x < 0 else c.x - size.x / 2),
				site.end.y + dist if out.y > 0 else (site.position.y - dist - size.y if out.y < 0 else c.y - size.y / 2))
		base += Vector2i(0, rng.randi_range(-6, 6)) if out.x != 0 else Vector2i(rng.randi_range(-6, 6), 0)
		var r := Rect2i(base, size)
		var ok := r.position.x >= 17 and r.end.x <= W - 17 and r.position.y >= 1 and r.end.y <= H - 1 and not _overlaps(r.grow(1))
		if ok:
			for x in range(r.position.x - 1, r.end.x + 1):
				for y in range(r.position.y - 1, r.end.y + 1):
					var t := get_t(Vector2i(x, y))
					if is_road(Vector2i(x, y)) or not (t == T.OPEN or t == T.RUBBLE or t == T.BUSH):
						ok = false
		if not ok:
			continue
		buildings.append(r)
		_note_building("bunker")
		building_front[building_front.size() - 1] = [3, 1, 2, 0][side]  # its front is the slit side
		_fill_room(r)
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				bunker_mask[y * W + x] = 1
		# the firing slit along the front, and the doorway at the back
		var front := _side_cells(r, [3, 1, 2, 0][side])
		var back := _side_cells(r, [2, 0, 3, 1][side])
		for k in front.size():
			set_t(front[k], T.WINDOW)
		var door: Vector2i = back[back.size() / 2]
		set_t(door, T.FLOOR)
		# a short sandbag blast wall a step outside the doorway, open at both ends
		var outward: Vector2i = -out
		var across := Vector2i(out.y, out.x)
		for k in range(-1, 2):
			var bc: Vector2i = door + outward * 2 + across * k
			if in_bounds(bc) and (get_t(bc) == T.OPEN or get_t(bc) == T.RUBBLE):
				_set_low(bc, LowKind.SANDBAGS)
		return


## Barricades across the streets leading to a site, a little way out from it, each with a
## gap to squeeze through.
func _street_barricades(site: Rect2i) -> void:
	for rd in roads:
		var r: Rect2 = rd
		var rc := Rect2i(Vector2i(r.position / CELL), Vector2i(r.size / CELL))
		var horiz := r.size.x > r.size.y
		var spots: Array = []
		if horiz and rc.position.y < site.end.y + 14 and rc.end.y > site.position.y - 14:
			spots = [site.position.x - rng.randi_range(6, 10), site.end.x + rng.randi_range(5, 9)]
		elif not horiz and rc.position.x < site.end.x + 14 and rc.end.x > site.position.x - 14:
			spots = [site.position.y - rng.randi_range(6, 10), site.end.y + rng.randi_range(5, 9)]
		for s in spots:
			var cells: Array = []
			if horiz:
				for y in range(rc.position.y, rc.end.y):
					cells.append(Vector2i(s, y))
			else:
				for x in range(rc.position.x, rc.end.x):
					cells.append(Vector2i(x, s))
			cells.remove_at(rng.randi_range(0, cells.size() - 1))
			if _open_run(cells):
				for cc in cells:
					_set_low(cc, LowKind.BARRICADE)


## Trench lines (an option): a zig-zag fire trench across the battlefield in front of each
## side's start, communication trenches running back from it, and a trench round the
## chapel square. Dug only through open ground; the streets cross them, and there are
## causeways, so vehicles can get through.
func _make_trenches() -> void:
	for side in 2:
		var x0 := 26 if side == 0 else W - 27
		var pts: Array = []
		var y := 2
		var zig := 0
		while y < H - 2:
			pts.append(Vector2i(x0 + (2 if zig % 2 == 0 else -1), y))
			y += rng.randi_range(4, 6)
			zig += 1
		for k in range(pts.size() - 1):
			_dig(pts[k], pts[k + 1], k % 4 == 3)  # every fourth stretch left as a causeway
		for k in 3:  # communication trenches back towards the start
			var p: Vector2i = pts[(k + 1) * pts.size() / 4]
			_dig(p, Vector2i(p.x + (-8 if side == 0 else 8), p.y + rng.randi_range(-3, 3)), false)
	var ring := plaza.grow(3)
	for c in _ring(ring):
		var mid := ring.get_center()
		if absi(c.x - mid.x) <= 1 or absi(c.y - mid.y) <= 1:
			continue  # ways through
		_dig_cell(c)


func _dig(a: Vector2i, b: Vector2i, skip: bool) -> void:
	if skip:
		return
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in n + 1:
		var c := Vector2i(roundi(lerpf(a.x, b.x, float(k) / maxi(n, 1))), roundi(lerpf(a.y, b.y, float(k) / maxi(n, 1))))
		_dig_cell(c)
		if k < n:
			# keep it joined edge to edge, not corner to corner
			var nx := Vector2i(roundi(lerpf(a.x, b.x, float(k + 1) / n)), roundi(lerpf(a.y, b.y, float(k + 1) / n)))
			if nx.x != c.x and nx.y != c.y:
				_dig_cell(Vector2i(nx.x, c.y))


func _dig_cell(c: Vector2i) -> void:
	if not in_bounds(c) or is_road(c):
		return
	var t := get_t(c)
	if t == T.OPEN or t == T.RUBBLE or t == T.CRATER or t == T.BUSH:
		set_t(c, T.TRENCH)


## A fortified position: a ring of sandbags (its sides running straight and at angles),
## an opening at the back, and barbed wire strung in front of it.
func _make_base(near_chapel: bool) -> void:
	for attempt in 40:
		var o := Vector2(rng.randi_range(20, W - 21), rng.randi_range(5, H - 6))
		if near_chapel:
			o = Vector2(plaza.get_center()) + Vector2(rng.randf_range(-1, 1) * (plaza.size.x * 0.5 + 6), rng.randf_range(-1, 1) * (plaza.size.y * 0.5 + 6))
		var rad := rng.randf_range(2.6, 3.6)
		var facing := 0.0 if o.x < W * 0.5 else PI  # its front faces the far side of the map
		facing += rng.randf_range(-0.6, 0.6)
		var cells: Array = []
		var n := 40
		for i in n:
			var a := i * TAU / n
			if absf(wrapf(a - facing - PI, -PI, PI)) < 0.5:
				continue  # the way in, at the back
			var c := Vector2i(roundi(o.x + cos(a) * rad), roundi(o.y + sin(a) * rad))
			if not cells.has(c):
				cells.append(c)
		var wire: Array = []
		for i in n:
			var a := i * TAU / n
			if absf(wrapf(a - facing, -PI, PI)) > 0.9:
				continue
			var c := Vector2i(roundi(o.x + cos(a) * (rad + 3.0)), roundi(o.y + sin(a) * (rad + 3.0)))
			if not wire.has(c):
				wire.append(c)
		if not _open_run(cells) or chapel.grow(2).intersects(Rect2i(Vector2i(o) - Vector2i(5, 5), Vector2i(10, 10))):
			continue
		for c in cells:
			_set_low(c, LowKind.SANDBAGS)
		for c in wire:
			if in_bounds(c) and get_t(c) == T.OPEN:
				set_t(c, T.WIRE)
		return


## A run of barbed wire: across a street, in front of a position or out in the open,
## straight or at an angle.
func _make_wire() -> void:
	for attempt in 30:
		var o := Vector2i(rng.randi_range(18, W - 19), rng.randi_range(3, H - 4))
		var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
		var along: Vector2i = dirs[rng.randi() % 4]
		var cells: Array = []
		for k in rng.randi_range(4, 8):
			cells.append(o + along * k)
		if not _open_run(cells):
			continue
		for c in cells:
			set_t(c, T.WIRE)
		return


## Flatten a bush, hedge or wire cell (a vehicle drove over it or a shell burst on it).
func crush(c: Vector2i) -> bool:
	var t := get_t(c)
	if t != T.BUSH and t != T.HEDGE and t != T.WIRE:
		return false
	crushed[c.y * W + c.x] = t
	set_t(c, T.OPEN)
	_refresh_cells([c])
	return true


## A clump of wild scrub grown up on waste ground (not on the streets).
func _make_scrub() -> void:
	for attempt in 20:
		var o := Vector2(rng.randf_range(18, W - 18), rng.randf_range(2, H - 2))
		if is_road(Vector2i(o)) or get_t(Vector2i(o)) != T.OPEN:
			continue
		var rad := rng.randf_range(0.8, 1.6)
		for x in range(int(o.x - rad), int(o.x + rad) + 1):
			for y in range(int(o.y - rad), int(o.y + rad) + 1):
				var c := Vector2i(x, y)
				if get_t(c) == T.OPEN and not is_road(c) and Vector2(c).distance_to(o) <= rad and rng.randf() < 0.75:
					set_t(c, T.BUSH)
		return


## Can fire take hold here (a flamer's jet)? Bushes, hedges, wooden barricades, crates,
## and the furnishings of rooms.
func is_bunker(c: Vector2i) -> bool:
	return in_bounds(c) and bunker_mask[c.y * W + c.x] == 1


func flammable(c: Vector2i) -> bool:
	var t := get_t(c)
	if t == T.BUSH or t == T.HEDGE:
		return true
	if t == T.LOW:
		var k := low_kind[c.y * W + c.x]
		return k == LowKind.BARRICADE or k == LowKind.CRATES
	return t == T.FLOOR and building_of.size() > 0 and building_of[c.y * W + c.x] > 0


## A fire here has burnt out: bushes and hedges are gone (charred), crates and barricades burnt
## to nothing.
func burn_out(c: Vector2i) -> void:
	var t := get_t(c)
	if t == T.BUSH or t == T.HEDGE:
		crushed[c.y * W + c.x] = 20  # burnt
		set_t(c, T.OPEN)
		_refresh_cells([c])
		cells_changed.emit([c])
	elif t == T.LOW:
		chip_low(c, 9999.0)


## Flatten every bush, hedge and wire cell under a footprint (cells), repainting once.
func crush_cells(cells: Array) -> void:
	var done: Array = []
	for c in cells:
		if crush(c):
			done.append(c)
	if not done.is_empty():
		cells_changed.emit(done)


func _make_rubble_patch_at(c: Vector2) -> void:
	var rad := rng.randf_range(1.0, 2.5)
	for x in range(int(c.x - rad), int(c.x + rad) + 1):
		for y in range(int(c.y - rad), int(c.y + rad) + 1):
			var cell := Vector2i(x, y)
			if get_t(cell) == T.OPEN and Vector2(cell).distance_to(c) <= rad and rng.randf() < 0.7:
				set_t(cell, T.RUBBLE)


## Roofs over the buildings: whole where the building still stands, gone where it
## collapsed before the battle, with a few holes already blown through them.
func _init_roofs() -> void:
	roof_hp.resize(W * H)
	roof_hp.fill(0.0)
	building_of.resize(W * H)
	building_of.fill(-1)
	for i in buildings.size():
		var b: Rect2i = buildings[i]
		for x in range(b.position.x, b.end.x):
			for y in range(b.position.y, b.end.y):
				var c := Vector2i(x, y)
				var j := y * W + x
				building_of[j] = i
				var t := get_t(c)
				if collapsed[j] == 0 and t != T.OPEN and t != T.CRATER:
					roof_hp[j] = 100.0
		if b == chapel:
			continue
		for h in rng.randi_range(0, 2):  # shell holes from earlier fighting
			var hc := Vector2i(rng.randi_range(b.position.x + 1, b.end.x - 2), rng.randi_range(b.position.y + 1, b.end.y - 2))
			var hr := rng.randf_range(0.8, 1.8)
			for x in range(hc.x - 2, hc.x + 3):
				for y in range(hc.y - 2, hc.y + 3):
					var c := Vector2i(x, y)
					if b.has_point(c):
						var d := Vector2(c - hc).length()
						if d <= hr:
							roof_hp[y * W + x] = 0.0
						elif d <= hr + 1.2:
							roof_hp[y * W + x] = minf(roof_hp[y * W + x], 45.0)


func roof_at(c: Vector2i) -> float:
	return roof_hp[c.y * W + c.x] if in_bounds(c) else 0.0


## A blast on or near a building smashes the roof around it.
func damage_roof(at: Vector2, radius: float, dmg: float) -> void:
	var touched := {}
	var c0 := cell_of(at)
	var reach := radius * 0.6 + CELL * 0.5
	var n := int(ceil(reach / CELL)) + 1
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			var c := c0 + Vector2i(dx, dy)
			if not in_bounds(c) or roof_at(c) <= 0.0:
				continue
			var d := center_of(c).distance_to(at)
			if d > reach:
				continue
			var j := c.y * W + c.x
			roof_hp[j] = maxf(0.0, roof_hp[j] - dmg * clampf(1.0 - d / (reach * 1.2), 0.3, 1.0) * (0.2 if bunker_mask[j] == 1 else 1.0))
			touched[building_of[j]] = true
	for b in touched:
		if b >= 0:
			roof_changed.emit(b)


## Where a wall falls, the roof it held up comes down with it.
func _collapse_roof_near(cells: Array) -> void:
	var touched := {}
	for c in cells:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var n: Vector2i = c + Vector2i(dx, dy)
				if not in_bounds(n) or roof_at(n) <= 0.0:
					continue
				var j := n.y * W + n.x
				var d := Vector2(dx, dy).length()
				roof_hp[j] = 0.0 if d <= 1.5 else maxf(0.0, roof_hp[j] - 45.0)
				touched[building_of[j]] = true
	for b in touched:
		if b >= 0:
			roof_changed.emit(b)


func _init_walls() -> void:
	wall_hp.resize(W * H)
	wall_max.resize(W * H)
	fallen.resize(W * H)
	fallen.fill(0)
	for y in H:
		for x in W:
			var hp := CHAPEL_WALL_HP if chapel.grow(1).has_point(Vector2i(x, y)) else WALL_HP
			if bunker_mask[y * W + x] == 1:
				hp = BUNKER_WALL_HP  # thick reinforced concrete
			if grid[y * W + x] == T.LOW:
				hp = LOW_HP[low_kind[y * W + x]]
			elif grid[y * W + x] == T.WINDOW:
				hp *= 0.8
			wall_hp[y * W + x] = hp
			wall_max[y * W + x] = hp
	# gaps in the ruins' outer walls are collapsed wall too (the chapel's doorways aren't)
	for b in buildings:
		var is_chapel := b == chapel
		for side in 4:
			for c in _side_cells(b, side) + [b.position, Vector2i(b.end.x - 1, b.position.y),
					Vector2i(b.position.x, b.end.y - 1), b.end - Vector2i.ONE]:
				var t := get_t(c)
				if is_wall(t) or t == T.LOW or ((is_chapel or is_bunker(c)) and t == T.FLOOR):
					continue
				if t == T.OPEN:
					set_t(c, T.RUBBLE)
				fallen[c.y * W + c.x] = 1


func _make_decor() -> void:
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


## What the battle is for: the chapel in the Old Town, the Prime Factorium in the Foundry
## District (the same building in the middle of the map, built and decorated for its district).
func objective_name() -> String:
	return "the Prime Factorium" if map_type == "foundry" else "the Ashen Chapel"


func objective_word() -> String:
	return "factorium" if map_type == "foundry" else "chapel"


func _make_chapel() -> void:
	chapel = Rect2i(W / 2 - 12, H / 2 - 7, 24, 14)
	buildings.append(chapel)
	_note_building("factorium" if map_type == "foundry" else "chapel")
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


func _make_ruin(r: Rect2i, kind := "") -> void:
	buildings.append(r)
	if kind == "":
		var roll := rng.randf()
		kind = "home" if roll < 0.4 else ("shop" if roll < 0.65 else ("industry" if roll < 0.82 else ("tavern" if roll < 0.9 else "office")))
	_note_building(kind)
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
				collapsed[y * W + x] = 1
	for x in range(r.position.x + 1, r.end.x - 1):
		for y in range(r.position.y + 1, r.end.y - 1):
			if get_t(Vector2i(x, y)) == T.FLOOR and rng.randf() < 0.1:
				set_t(Vector2i(x, y), T.RUBBLE)
	_add_buttresses(r)


## Note the latest building's kind, its name (if it has a sign) and which side faces the street.
func _note_building(kind: String) -> void:
	var r: Rect2i = buildings[buildings.size() - 1]
	building_kind.append(kind)
	var nm := ""
	match kind:
		"warehouse": nm = WAREHOUSE_NAMES[rng.randi() % WAREHOUSE_NAMES.size()]
		"shop": nm = SHOP_NAMES[rng.randi() % SHOP_NAMES.size()]
		"tavern": nm = TAVERN_NAMES[rng.randi() % TAVERN_NAMES.size()]
		"industry": nm = WORKS_NAMES[rng.randi() % WORKS_NAMES.size()]
	building_name.append(nm)
	var best := 0
	var bd := INF
	var mids := [Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y),
			Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]
	for side in 4:
		var p: Vector2 = mids[side] * CELL
		for rd in roads:
			var rr: Rect2 = rd
			var d := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.y, rr.position.y, rr.end.y)).distance_to(p)
			if d < bd:
				bd = d
				best = side
	building_front.append(best)


## Which building a cell is inside (-1: none).
func building_at(c: Vector2i) -> int:
	for i in buildings.size():
		if buildings[i].has_point(c):
			return i
	return -1


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
	var at := Vector2i(rng.randi_range(16, W - 22), rng.randi_range(3, H - 9))
	if rng.randf() < 0.7 and not roads.is_empty():
		# most burnt-out vehicles lie in the streets, lined up with them
		var rd: Rect2 = roads[rng.randi() % roads.size()]
		horiz = rd.size.x > rd.size.y
		at = Vector2i(rd.position / CELL) + Vector2i(rng.randi_range(0, int(rd.size.x / CELL) - 6), rng.randi_range(0, int(rd.size.y / CELL) - 6))
		at.x = clampi(at.x, 16, W - 22)
		at.y = clampi(at.y, 3, H - 9)
	var size := Vector2i(6, 3) if horiz else Vector2i(3, 6)
	var r := Rect2i(at, size)
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


func _set_low(c: Vector2i, kind: int) -> void:
	set_t(c, T.LOW)
	low_kind[c.y * W + c.x] = kind


## Window openings along the buildings' walls: every few cells on a straight
## stretch of standing wall, never at corners or next to another opening.
func _make_windows() -> void:
	if "--no-windows" in OS.get_cmdline_user_args():
		return  # test aid
	for b in buildings:
		var is_chapel := b == chapel
		for side in 4:
			var cells := _side_cells(b, side)
			var gap := 3 if is_chapel else rng.randi_range(4, 6)
			var k := rng.randi_range(1, 2)
			while k < cells.size() - 1:
				var c: Vector2i = cells[k]
				var ok := get_t(c) == T.WALL
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if get_t(c + d) == T.WINDOW:
						ok = false
				var along := Vector2i(1, 0) if side < 2 else Vector2i(0, 1)
				if get_t(c + along) != T.WALL or get_t(c - along) != T.WALL:
					ok = false  # both neighbours along the wall must be standing wall
				if ok and (is_chapel or rng.randf() < 0.7):
					set_t(c, T.WINDOW)
				k += gap


## Some stretches of the ruins' outer walls have crumbled to waist height.
func _crumble_walls() -> void:
	for b in buildings:
		for side in 4:
			var cells := _side_cells(b, side)
			if cells.size() < 5 or rng.randf() > (0.3 if b == chapel else 0.55):
				continue
			var start := rng.randi_range(1, cells.size() - 4)
			for k in rng.randi_range(2, 4):
				var c: Vector2i = cells[mini(start + k, cells.size() - 2)]
				if get_t(c) == T.WALL:
					_set_low(c, LowKind.STONE)
			for c in cells:
				if get_t(c) == T.WALL and rng.randf() < 0.06:
					_set_low(c, LowKind.STONE)


func _open_run(cells: Array) -> bool:
	for c in cells:
		if not in_bounds(c) or get_t(c) != T.OPEN or c.x < 16 or c.x > W - 17:
			return false
	return true


## A sandbagged firing position: a straight line, an L or a horseshoe.
func _make_sandbags(near_chapel: bool) -> void:
	for attempt in 30:
		var o := Vector2i(rng.randi_range(18, W - 19), rng.randi_range(3, H - 4))
		if near_chapel:
			o = chapel.get_center() + Vector2i(rng.randi_range(-26, 26), rng.randi_range(-16, 16))
			if chapel.grow(3).has_point(o):
				continue
		var cells: Array = []
		var shape := rng.randi() % 3
		var horiz := rng.randf() < 0.5
		var length := rng.randi_range(3, 6)
		var along := Vector2i(1, 0) if horiz else Vector2i(0, 1)
		var side := Vector2i(0, 1) if horiz else Vector2i(1, 0)
		if rng.randf() < 0.4:
			# at an angle: a diagonal run, its arms going off straight
			along = Vector2i(1, 1) if rng.randf() < 0.5 else Vector2i(1, -1)
			side = Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		if rng.randf() < 0.5:
			side = -side
		for k in length:
			cells.append(o + along * k)
		if shape >= 1:
			cells.append(o + side)
			if length > 1:
				cells.append(o + side * 2)
		if shape == 2:
			cells.append(o + along * (length - 1) + side)
			cells.append(o + along * (length - 1) + side * 2)
		if not _open_run(cells):
			continue
		for c in cells:
			_set_low(c, LowKind.SANDBAGS)
		return


## Barricades of steel and planks thrown across the roads, and a few in the open.
func _make_barricades() -> void:
	for rd in roads:
		var r: Rect2 = rd
		var horiz := r.size.x > r.size.y
		for n in rng.randi_range(1, 2):
			for attempt in 20:
				var cells: Array = []
				if horiz:
					var x := rng.randi_range(18, W - 19)
					for y in range(int(r.position.y / CELL), int(r.end.y / CELL)):
						cells.append(Vector2i(x, y))
				else:
					var y := rng.randi_range(4, H - 5)
					for x in range(int(r.position.x / CELL), int(r.end.x / CELL)):
						cells.append(Vector2i(x, y))
				cells.remove_at(rng.randi_range(0, cells.size() - 1))  # a gap to squeeze through
				if not _open_run(cells):
					continue
				for c in cells:
					_set_low(c, LowKind.BARRICADE)
				break
	for i in 6:
		for attempt in 20:
			var o := Vector2i(rng.randi_range(18, W - 19), rng.randi_range(3, H - 4))
			var along: Vector2i = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)][rng.randi() % 4]
			var cells: Array = []
			for k in rng.randi_range(3, 5):
				cells.append(o + along * k)
			if not _open_run(cells):
				continue
			for c in cells:
				_set_low(c, LowKind.BARRICADE)
			break


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
