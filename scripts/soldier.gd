class_name Soldier
extends Node2D
## One trooper. Walks its path, fires at enemies it can see, and reacts to
## incoming fire through suppression (short term) and morale (long term).

enum State { READY, PINNED, ROUTING, DEAD, FLED, EMBARKED }

var main: Node
var map: BattleMap
var squad: Squad
var team := 0
var faction := ""
var kind := ""
var data: Dictionary
var weapon: Dictionary
var colors: Dictionary

var hp := 1
var max_hp := 1
var armor := 0.0
var speed := 40.0
var radius := 7.0
var nerve := 1.0
var is_leader := false
var morale := 60.0
var max_morale := 60.0
var suppression := 0.0
var state := State.READY

var path := PackedVector2Array()
var path_i := 0
var running := false
var moving := false
var facing := 0.0
var cooldown := 0.0
var burst_left := 0
var burst_timer := 0.0
var burst_target: Soldier = null
var last_hit_time := -99.0
var last_fire_time := -99.0
var flash := 0.0
var walk := 0.0
var seen_by := [true, true]
var is_vehicle := false
var in_cover := false      # crouched behind cover facing the threat
var behind_low := false    # waist-high cover between him and the threat
var corner_cover := false  # a wall or wreck between him and the threat (leans out to fire)
var posture := "stand"     # stand, crouch or prone (how he's drawn, and how hard he is to hit)
var lean := 0.0            # leaning out round cover to fire: -1..1 sideways
var lean_side := 1.0
var strength := 1         # how much this unit counts towards its side's strength
var board_vehicle = null  # carrier this soldier is walking to
var carrier = null        # carrier this soldier is riding in


func setup(m: Node, sq: Squad, t: int, kind_id: String) -> void:
	main = m
	map = m.map
	squad = sq
	team = t
	kind = kind_id
	faction = sq.faction
	data = GameData.SOLDIERS[kind_id]
	colors = GameData.FACTIONS[faction]
	weapon = GameData.WEAPONS[data.weapon]
	hp = data.hp
	max_hp = hp
	armor = data.armor
	speed = data.speed * randf_range(0.93, 1.07)
	radius = data.radius
	nerve = data.nerve
	is_leader = data.get("leader", false)
	max_morale = data.morale
	morale = max_morale * randf_range(0.85, 1.0)
	cooldown = randf_range(0.0, 1.5)


func is_alive() -> bool:
	return state <= State.ROUTING


func is_effective() -> bool:
	return state == State.READY or state == State.PINNED


## Still in the fight: on the field and steady, or riding in a carrier.
func is_present() -> bool:
	return is_effective() or state == State.EMBARKED


func muzzle_pos() -> Vector2:
	return position + Vector2.from_angle(facing) * (radius + 9.0)


func go_to(p: Vector2, run: bool) -> void:
	if not is_alive() or state == State.ROUTING:
		return
	path = map.find_path(position, p)
	path_i = 0
	running = run


func halt() -> void:
	path = PackedVector2Array()
	path_i = 0


# ---------------------------------------------------------------- simulation

func tick(dt: float, now: float) -> void:
	if state == State.EMBARKED:
		position = carrier.position
		return
	if not is_alive():
		return
	if board_vehicle != null and state == State.READY:
		_try_board()
	flash = maxf(0.0, flash - dt)
	# when idle, watch the way the squad was told to look
	if not moving and burst_left == 0 and flash <= 0.0 and squad.facing != Vector2.ZERO:
		facing = lerp_angle(facing, squad.facing.angle(), minf(1.0, dt * 3.0))
	var under_fire := now - last_hit_time < 3.0
	suppression = maxf(0.0, suppression - dt * (4.0 if under_fire else 12.0))
	if not under_fire:
		morale = minf(max_morale, morale + dt * (1.2 + 2.0 * squad.leader_bonus(self)))
	elif suppression > 50.0:
		morale -= dt * (suppression - 50.0) * 0.04 * nerve
	_update_state(under_fire)
	match state:
		State.ROUTING:
			_follow_path(dt, true)
		State.PINNED:
			moving = false
		State.READY:
			_follow_path(dt, false)
	if state != State.ROUTING and is_alive():
		_fight(dt, now)
	_update_posture(dt)
	if visible:
		queue_redraw()


func _try_board() -> void:
	var v = board_vehicle
	if not is_instance_valid(v) or not v.is_alive() or v.free_space() <= 0:
		board_vehicle = null
		return
	if position.distance_to(v.position) < v.radius + radius + 8.0:
		v.take_aboard(self)
	elif path_i >= path.size() or path[path.size() - 1].distance_to(v.position) > 30.0:
		path = map.find_path(position, v.position)
		path_i = 0
		running = true


## How he holds himself: flat when pinned or in the Down stance (but kneeling behind
## waist-high cover, so he can see over it), kneeling when in cover, otherwise upright.
## When firing from behind a wall or wreck he leans out round it.
func _update_posture(dt: float) -> void:
	if state == State.PINNED:
		posture = "prone"
	elif squad.prone and not (running and moving):
		posture = "crouch" if behind_low else "prone"
	elif (in_cover or behind_low) and not moving:
		posture = "crouch"
	else:
		posture = "stand"
	var firing := burst_left > 0 or flash > 0.0
	var want := 0.0
	if firing and corner_cover and not moving:
		if lean == 0.0:
			# lean towards whichever side is open
			var side := Vector2.from_angle(facing).orthogonal()
			var right_open := not map.blocks(map.get_t(map.cell_of(position + side * BattleMap.CELL)))
			lean_side = 1.0 if right_open else -1.0
		want = lean_side
	lean = move_toward(lean, want, dt * 6.0)


func _update_state(under_fire: bool) -> void:
	if state == State.ROUTING:
		if morale > 45.0 and not under_fire:
			state = State.READY
			halt()
		return
	if morale < 12.0:
		_start_rout()
		return
	if state == State.PINNED:
		if suppression < 30.0 and morale > 30.0:
			state = State.READY
	elif suppression > 70.0 or morale < 22.0:
		state = State.PINNED


func _start_rout() -> void:
	state = State.ROUTING
	burst_left = 0
	running = true
	var edge_x := 4.0 if team == 0 else BattleMap.W * BattleMap.CELL - 4.0
	path = map.find_path(position, Vector2(edge_x, position.y))
	path_i = 0


func _follow_path(dt: float, fleeing: bool) -> void:
	if path_i >= path.size():
		moving = false
		if fleeing:
			state = State.FLED
			visible = false
			main.on_fled(self)
		return
	var target := path[path_i]
	var to := target - position
	var spd := speed * map.speed_mult(position)
	if squad.prone and not fleeing:
		spd *= 0.35  # crawling
	elif running:
		spd *= 1.7
	if suppression > 40.0:
		spd *= 0.6
	var step := spd * dt
	var dist := to.length()
	if dist <= step:
		position = target
		path_i += 1
	else:
		position += to / dist * step
	if dist > 0.5 and burst_left == 0:
		facing = lerp_angle(facing, to.angle(), minf(1.0, dt * 8.0))
	moving = true
	walk += dt * spd * 0.25


func _fight(dt: float, now: float) -> void:
	cooldown -= dt
	if burst_left > 0:
		burst_timer -= dt
		if burst_timer <= 0.0:
			if is_instance_valid(burst_target) and burst_target.is_alive():
				facing = (burst_target.position - position).angle()
				flash = 0.06
				last_fire_time = now
				main.resolve_shot(self, burst_target, weapon, muzzle_pos())
			burst_left -= 1
			burst_timer = weapon.gap
		return
	if cooldown > 0.0:
		return
	var bp = breach_point() if can_breach() else null
	if bp != null:
		if position.distance_to(bp) <= weapon.range and map.los_clear(position, bp):
			facing = (bp - position).angle()
			flash = 0.08
			last_fire_time = now
			main.resolve_point_shot(self, bp, weapon, muzzle_pos())
			cooldown = weapon.cooldown * randf_range(0.9, 1.15) * (2.5 if state == State.PINNED else 1.0)
			return
	var t := pick_target(weapon, position)
	if t == null:
		cooldown = randf_range(0.3, 0.6)
		return
	burst_target = t
	burst_left = weapon.burst
	burst_timer = 0.0
	var cd: float = weapon.cooldown * randf_range(0.85, 1.2)
	if state == State.PINNED:
		cd *= 2.5
	cooldown = cd


func can_breach() -> bool:
	return weapon.get("blast", 0.0) > 0.0


## The wall this soldier's squad was told to shell, if it's still standing.
func breach_point():
	if squad.fire_point == null:
		return null
	var fp: Vector2 = squad.fire_point
	if map.get_t(map.cell_of(fp)) != BattleMap.T.WALL:
		squad.fire_point = null  # it's down
		return null
	return fp


## Whether weapon w could ever damage this unit (infantry: always; vehicles override).
func hurt_by(_w: Dictionary) -> bool:
	return true


func _can_hit(e: Soldier, w: Dictionary, from: Vector2) -> bool:
	return e.is_alive() and e.seen_by[team] and e.hurt_by(w) \
			and from.distance_to(e.position) <= w.range and map.los_clear(from, e.position)


## Best enemy for weapon w fired from `from`: the squad's ordered target if possible,
## otherwise the closest, with anti-tank weapons preferring vehicles.
func pick_target(w: Dictionary, from: Vector2) -> Soldier:
	var focus: Soldier = squad.focus
	if focus != null and is_instance_valid(focus) and _can_hit(focus, w, from):
		return focus
	var anti_tank: bool = w.get("pen", 0) >= 6
	var cands: Array = []
	for e in main.soldiers:
		if e.team == team or not e.is_alive() or not e.seen_by[team] or not e.hurt_by(w):
			continue
		var d := from.distance_to(e.position)
		if d > w.range:
			continue
		var score := d + (250.0 if e.state == State.ROUTING else 0.0)
		if squad.facing != Vector2.ZERO and absf(wrapf((e.position - from).angle() - squad.facing.angle(), -PI, PI)) > 1.3:
			score += 140.0  # prefer targets in the arc the squad is watching
		if e.is_vehicle:
			score += -400.0 if anti_tank else 150.0
		cands.append([score, e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands:
		if map.los_clear(from, c[1].position):
			return c[1]
	return null


func add_suppression(v: float, now: float) -> void:
	suppression = minf(100.0, suppression + v * nerve)
	morale -= v * 0.05 * nerve
	last_hit_time = now


func take_hit(dmg: int, from: Soldier) -> void:
	hp -= dmg
	if hp <= 0:
		state = State.DEAD
		z_index = -1
		burst_left = 0
		moving = false
		main.on_death(self, from)
		queue_redraw()
	else:
		morale -= 10.0 * nerve


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if state == State.DEAD:
		_draw_corpse()
		return
	if squad.selected:
		var picked := squad.sub.has(self)
		draw_arc(Vector2.ZERO, radius + 5.0, 0, TAU, 28, Color(1.0, 0.85, 0.3, 0.95) if picked else Color(0.45, 1.0, 0.45, 0.85), 2.0 if picked else 1.5)
	var prone := posture == "prone"
	var crouch := posture == "crouch"
	var r := radius
	var off := Vector2.from_angle(facing).orthogonal() * lean * r * 0.9  # leaning out round cover
	var leg: Color = Color(colors.coat).darkened(0.18)
	# shadow: long and low when lying flat, small when kneeling
	if prone:
		draw_set_transform(off + Vector2(2, 3) - Vector2.from_angle(facing) * r * 0.6, facing, Vector2(1.9, 0.8))
	else:
		draw_set_transform(off + Vector2(3, 4), 0, Vector2(0.85, 0.7) if crouch else Vector2(1, 0.8))
	draw_circle(Vector2.ZERO, r + 1.0, Color(0, 0, 0, 0.35))
	draw_set_transform(off, facing, Vector2.ONE)
	if prone:
		# legs stretched out behind him, shuffling when he crawls
		var c := sin(walk * 1.5) * r * 0.25 if moving else 0.0
		for sgn in [-1.0, 1.0]:
			var k: float = c * sgn
			draw_line(Vector2(-r * 0.6, sgn * r * 0.3), Vector2(-r * 1.9 + k, sgn * r * 0.42), Color(0, 0, 0, 0.35), r * 0.62)
			draw_line(Vector2(-r * 0.6, sgn * r * 0.3), Vector2(-r * 1.85 + k, sgn * r * 0.4), leg, r * 0.5)
			draw_circle(Vector2(-r * 1.95 + k, sgn * r * 0.4), r * 0.26, Color(0.12, 0.11, 0.1))  # boots
		draw_set_transform(off, facing, Vector2(1.1, 0.82))
	elif crouch:
		# kneeling: one knee forward, the other foot tucked behind
		draw_circle(Vector2(r * 0.55, -r * 0.55), r * 0.36, leg)  # knee forward
		draw_line(Vector2(-r * 0.2, r * 0.45), Vector2(-r * 0.95, r * 0.5), leg.darkened(0.15), r * 0.42)
		draw_circle(Vector2(-r * 1.05, r * 0.5), r * 0.24, Color(0.12, 0.11, 0.1))  # foot tucked behind
		draw_set_transform(off, facing, Vector2(0.86, 0.9))
	elif moving:
		var sw := sin(walk) * r * 0.45
		draw_circle(Vector2(sw, -r * 0.38), r * 0.32, leg)
		draw_circle(Vector2(-sw, r * 0.38), r * 0.32, leg)
	if faction == "sworn":
		_draw_sworn()
	else:
		_draw_conscript()
	if flash > 0.0:
		var m := Vector2(radius + 10.0, 3.0)
		var pts := PackedVector2Array()
		for i in 8:
			var rr := 6.0 if i % 2 == 0 else 2.5
			pts.append(m + Vector2.from_angle(i * TAU / 8.0) * rr)
		draw_colored_polygon(pts, Color(1.0, 0.9, 0.5, 0.95))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if squad.prone and squad.selected:
		draw_line(Vector2(-4, r + 7.0), Vector2(4, r + 7.0), Color(0.6, 0.8, 1.0, 0.8), 1.5)  # Down stance marker
	if max_hp > 1 and (squad.selected or hp < max_hp):
		for i in max_hp:
			var c := Color(0.9, 0.85, 0.6) if i < hp else Color(0.2, 0.2, 0.2)
			draw_rect(Rect2(Vector2(-max_hp * 2.5 + i * 5.0, radius + 4.0), Vector2(4, 2)), c)
	if state == State.PINNED:
		draw_circle(Vector2(0, -radius - 6.0), 2.5, Color(1.0, 0.8, 0.2))
	elif state == State.ROUTING:
		draw_circle(Vector2(0, -radius - 6.0), 2.5, Color(1, 1, 1))


func _draw_conscript() -> void:
	var coat: Color = colors.coat
	var arm: Color = colors.armour
	var trim: Color = colors.trim
	var r := radius
	draw_rect(Rect2(-r - 1.0, -3.0, 4.0, 6.0), arm.darkened(0.2))  # pack and bedroll
	draw_circle(Vector2.ZERO, r, coat)
	draw_arc(Vector2.ZERO, r, 0, TAU, 16, coat.darkened(0.45), 1.0)
	var heavy := kind == "gunner"
	if kind == "lancer":
		draw_line(Vector2(-r - 2.0, -3), Vector2(r + 6.0, -3), Color(0.2, 0.22, 0.16), 4.5)  # launcher tube
		draw_circle(Vector2(r + 7.0, -3), 2.6, Color(0.45, 0.35, 0.2))  # warhead
	else:
		draw_line(Vector2(0, 3), Vector2(r + (10.0 if heavy else 9.0), 3), Color(0.1, 0.09, 0.08), 3.5 if heavy else 2.0)
	if heavy:
		draw_rect(Rect2(1, 4, 4, 4), Color(0.3, 0.27, 0.15))  # ammo box
	draw_circle(Vector2(r * 0.6, 3.5), 1.8, coat.darkened(0.2))
	draw_circle(Vector2(0.5, 0), r * 0.58, arm)
	draw_arc(Vector2(0.5, 0), r * 0.58, -1.3, 1.0, 8, arm.lightened(0.35), 1.0)
	draw_circle(Vector2(r * 0.55, 0), 1.5, Color(0.12, 0.12, 0.12))  # rebreather
	if is_leader:
		draw_line(Vector2(-2.5, 0), Vector2(2.5, 0), trim, 2.0)  # crest


func _draw_sworn() -> void:
	var coat: Color = colors.coat
	var arm: Color = colors.armour
	var trim: Color = colors.trim
	var r := radius
	if is_leader:
		var cape := PackedVector2Array([Vector2(-2, -r * 0.8), Vector2(-r * 1.7, -r * 0.6),
				Vector2(-r * 1.9, 0), Vector2(-r * 1.7, r * 0.6), Vector2(-2, r * 0.8)])
		draw_colored_polygon(cape, trim.darkened(0.35))
	draw_rect(Rect2(-r - 3.0, -r * 0.6, 6.0, r * 1.2), arm.darkened(0.3))  # power pack
	draw_circle(Vector2(-r - 1.0, -2.5), 1.3, Color(1.0, 0.55, 0.2))
	draw_circle(Vector2(-r - 1.0, 2.5), 1.3, Color(1.0, 0.55, 0.2))
	draw_circle(Vector2.ZERO, r * 0.85, coat)
	var gun_w := 5.0 if kind == "cannoneer" else 3.5
	draw_rect(Rect2(1, 1.5, r + 8.0, gun_w), Color(0.13, 0.12, 0.12))
	draw_rect(Rect2(r + 6.0, 1.0, 3.0, gun_w + 1.0), trim.darkened(0.2))
	if kind == "breacher":
		draw_circle(Vector2(r + 9.0, 3.2), 2.2, Color(0.6, 0.85, 1.0))  # fusion glow
	for s in [-1.0, 1.0]:
		var p := Vector2(-1, s * r * 0.72)
		draw_circle(p, r * 0.45, coat.lightened(0.08))
		draw_arc(p, r * 0.45, 0, TAU, 14, trim, 1.3)
	draw_circle(Vector2(1, 0), r * 0.42, arm)
	draw_line(Vector2(r * 0.32, -2.2), Vector2(r * 0.32, 2.2), Color(1.0, 0.25, 0.1), 1.8)  # eye lenses


func _draw_corpse() -> void:
	var blood: Color = colors.blood
	draw_set_transform(Vector2(2, 1), facing, Vector2(1.4, 1.0))
	draw_circle(Vector2.ZERO, radius * 1.1, Color(blood, 0.75))
	draw_set_transform(Vector2.ZERO, facing + 2.2, Vector2(1.3, 0.75))
	var coat: Color = colors.coat
	draw_circle(Vector2.ZERO, radius * 0.85, coat.darkened(0.45))
	draw_circle(Vector2(radius * 0.9, 1), radius * 0.4, Color(colors.armour).darkened(0.4))
