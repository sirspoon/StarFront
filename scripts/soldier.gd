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
var stall := 0.0      # how long he has been held up while trying to walk
var squeeze := 0.0    # squeezing past squad-mates (not pushed apart) for this long
var progress_from := Vector2.ZERO
var wait_for_squad := false  # got ahead of slower squad-mates: pausing for them
var in_cover := false      # crouched behind cover facing the threat
var behind_low := false    # waist-high cover between him and the threat
var corner_cover := false  # a wall or wreck between him and the threat (leans out to fire)
var posture := "stand"     # stand, crouch or prone (how he's drawn, and how hard he is to hit)
var lean := 0.0            # leaning out round cover to fire: -1..1 sideways
var lean_side := 1.0
var strength := 1         # how much this unit counts towards its side's strength
var board_vehicle = null  # carrier this soldier is walking to
var carrier = null        # carrier this soldier is riding in
# close combat
const CHARGE_RANGE := 130.0   # assault troops rush enemies this close
var melee: Dictionary = {}
var charger := false          # assault troops: charge into close combat
var melee_target: Soldier = null
var in_melee := false         # locked in a fight at arm's length
var melee_cd := 0.0
var swing := 0.0              # 1 just after a blow, fading (for drawing)
var charging: Soldier = null  # the enemy he's rushing at
var charge_check := 0.0
var charge_fresh := false     # the first blow after a charge lands harder
var resume_to = null          # where he was going before he charged
var grenades := {}            # grenades he carries: kind -> how many
# heavy weapons
const SETUP_TIME := 2.5       # seconds to set a heavy gun up
const ARC := 1.0              # once set up it covers this far either side (radians) without moving it
var heavy := false            # carries a heavy gun (the loader takes it over if the gunner falls)
var setup_t := 0.0            # 0..1: how far the gun is set up
var deploy_dir := 0.0         # the way it was set up facing
const MAG := 6                # bursts in a load of ammunition
const RELOAD := 3.0           # seconds for the loader to change it...
const RELOAD_ALONE := 7.5     # ...or for the gunner on his own
var ammo := MAG               # bursts left in the current load
var reload_t := 0.0           # reloading: seconds of work left (at the loader's pace)


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
	melee = GameData.MELEE[data.get("melee", "gun_butt")]
	charger = data.get("charger", false)
	grenades = data.get("grenades", {}).duplicate()
	heavy = data.get("heavy", false)
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
	wait_for_squad = false
	if state == State.PINNED:
		# an order steadies a man: "Move! Keep with us!"
		suppression = maxf(0.0, suppression - 15.0)
		morale = minf(max_morale, morale + 4.0)


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
	if heavy and setup_t > 0.0 and not moving and burst_left == 0 and flash <= 0.0:
		# a set-up gun stays laid on its arc; told to face well away, the team shifts it round
		if squad.facing != Vector2.ZERO and absf(wrapf(squad.facing.angle() - deploy_dir, -PI, PI)) > ARC:
			deploy_dir = squad.facing.angle()
			setup_t = minf(setup_t, 0.5)
		facing = lerp_angle(facing, deploy_dir, minf(1.0, dt * 3.0))
	elif not moving and burst_left == 0 and flash <= 0.0 and squad.facing != Vector2.ZERO:
		facing = lerp_angle(facing, squad.facing.angle(), minf(1.0, dt * 3.0))
	var under_fire := now - last_hit_time < 3.0
	# caught in a crossfire, nowhere feels safe: fear fades slower and nerves fray faster
	var crossfire: bool = under_fire and not data.get("steadfast", false) and not main.no_flank and squad.in_crossfire(now)
	suppression = maxf(0.0, suppression - dt * (4.0 if under_fire else 12.0) * (0.85 if crossfire else 1.0))
	if not under_fire:
		morale = minf(max_morale, morale + dt * (1.2 + 2.0 * squad.leader_bonus(self)))
	elif suppression > 50.0:
		morale -= dt * (suppression - 50.0) * 0.04 * nerve * (1.1 if crossfire else 1.0)
	_update_state(under_fire)
	match state:
		State.ROUTING:
			_follow_path(dt, true)
		State.PINNED:
			# pinned men with orders crawl after the squad, unless the fire is too heavy
			if path_i < path.size() and suppression < 85.0:
				_follow_path(dt, false)
			else:
				moving = false
		State.READY:
			_follow_path(dt, false)
	if state != State.ROUTING and is_alive():
		if not _melee(dt, now):
			_fight(dt, now)
	else:
		in_melee = false
		melee_target = null
		charging = null
	if heavy:
		_update_setup(dt)
	_update_posture(dt)
	if bleeding > 0.0:
		bleeding -= dt
		bleed_step -= dt
		if moving and bleed_step <= 0.0:
			bleed_step = 0.5
			main.decals.add_smear(position, -Vector2.from_angle(facing), 9.0, Color(colors.blood))
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
	elif in_melee or charging != null:
		posture = "stand"
	elif heavy and setup_t > 0.0:
		posture = "prone" if squad.prone else "crouch"
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


## Is there something to rest a heavy gun on here: the team lying Down, a window, low
## cover or rubble just in front, or the lip of a crater or rubble heap he's in?
func can_brace() -> bool:
	if squad.prone:
		return true
	var own := map.get_t(map.cell_of(position))
	if own == BattleMap.T.CRATER or own == BattleMap.T.RUBBLE:
		return true
	for off in [0.0, -0.8, 0.8]:
		var t := map.get_t(map.cell_of(position + Vector2.from_angle(facing + off) * BattleMap.CELL))
		if t == BattleMap.T.LOW or t == BattleMap.T.WINDOW or t == BattleMap.T.RUBBLE or t == BattleMap.T.WRECK \
				or t == BattleMap.T.WALL:
			return true
	return false


## His loader, if he's beside the gun and free to work it.
func loader_at_hand() -> Soldier:
	for m in squad.members:
		if m != self and m.data.get("loader", false) and not m.heavy and m.state == State.READY and not m.in_melee \
				and m.position.distance_to(position) < 40.0:
			return m
	return null


func is_reloading() -> bool:
	return heavy and reload_t > 0.0


func is_set_up() -> bool:
	return heavy and setup_t >= 1.0


## Heavy guns: set up over a couple of seconds when he's stopped somewhere he can brace
## it (slower without his loader); packed up the moment he moves.
func _update_setup(dt: float) -> void:
	if moving or state == State.ROUTING or in_melee:
		setup_t = 0.0
		return
	if not can_brace():
		setup_t = maxf(0.0, setup_t - dt)
		return
	if setup_t <= 0.0:
		deploy_dir = facing
	var helped := loader_at_hand() != null
	setup_t = minf(1.0, setup_t + dt / (SETUP_TIME * (1.0 if helped else 1.6)))


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
	if in_melee and not fleeing and not (running and squad.running):
		moving = false  # locked in a fight: he can't just walk off
		return
	var target := path[path_i]
	var to := target - position
	if wait_for_squad and not fleeing:
		moving = false
		return
	var spd := speed * map.speed_mult(position)
	if state == State.PINNED:
		spd *= 0.25  # crawling under fire
	elif squad.prone and not fleeing:
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
	# held up (by men standing in the way)? after a moment, squeeze past them
	squeeze = maxf(0.0, squeeze - dt)
	if position.distance_to(progress_from) < step * 0.35:
		stall += dt
		if stall > 0.8:
			squeeze = 1.2
			stall = 0.0
	else:
		stall = maxf(0.0, stall - dt * 2.0)
	progress_from = position


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
	if heavy and moving:
		return  # can't fire a heavy gun on the move
	if heavy and reload_t > 0.0:
		# the loader changes the ammunition; on his own the gunner takes far longer
		var l := loader_at_hand()
		reload_t -= dt * (1.0 if l != null else RELOAD / RELOAD_ALONE)
		if l != null:
			l.facing = (position - l.position).angle()
			if l.swing <= 0.0 and randf() < dt * 1.5:
				l.swing = 1.0  # heaving the new belt / power cell into place
		if reload_t <= 0.0:
			ammo = MAG
		return
	var t := pick_target(weapon, position)
	if t == null:
		cooldown = randf_range(0.3, 0.6)
		return
	if is_set_up() and absf(wrapf((t.position - position).angle() - deploy_dir, -PI, PI)) > ARC:
		setup_t = 0.5  # outside its arc: shift the gun round first
		deploy_dir = (t.position - position).angle()
		facing = deploy_dir
		cooldown = 0.4
		return
	burst_target = t
	burst_left = weapon.burst
	burst_timer = 0.0
	var cd: float = weapon.cooldown * randf_range(0.85, 1.2)
	if state == State.PINNED:
		cd *= 2.5
	cooldown = cd
	if heavy:
		ammo -= 1
		if ammo <= 0:
			reload_t = RELOAD  # that load's spent: change the ammunition


# ---------------------------------------------------------------- close combat

## Pinned, or lying flat in the Down stance: easy meat for a man with a blade.
func grounded() -> bool:
	return state == State.PINNED or squad.prone


func _reach(e: Soldier) -> float:
	return radius + e.radius + 6.0


## A foot soldier of the other side at arm's length, nearest first.
func _foe_in_reach() -> Soldier:
	var best: Soldier = null
	var bd := INF
	for e in main.soldiers:
		if e.team == team or e.is_vehicle or not e.is_alive() or e.state == State.EMBARKED:
			continue
		var d := position.distance_to(e.position) - _reach(e)
		if d <= 0.0 and d < bd:
			bd = d
			best = e
	return best


## An enemy close enough for assault troops to rush, with a short way to him.
func _charge_target() -> Soldier:
	if squad.prone or state != State.READY or board_vehicle != null:
		return null  # in the Down stance they hold back
	var best: Soldier = null
	var bd := CHARGE_RANGE
	for e in main.soldiers:
		if e.team == team or e.is_vehicle or not e.is_alive() or e.state == State.EMBARKED \
				or e.state == State.ROUTING or not e.seen_by[team]:
			continue
		var d := position.distance_to(e.position) - (35.0 if e.grounded() else 0.0)  # men on the ground draw them in
		if d < bd and map.los_clear(position, e.position):
			bd = d
			best = e
	return best


## Close combat. Returns true while he's fighting or rushing in (and so not shooting).
func _melee(dt: float, now: float) -> bool:
	if is_vehicle:
		return false
	melee_cd -= dt
	swing = maxf(0.0, swing - dt * 4.0)
	var foe := _foe_in_reach()
	if foe == null and charger:
		charge_check -= dt
		if charging != null and (not is_instance_valid(charging) or not charging.is_alive() \
				or charging.state == State.ROUTING or position.distance_to(charging.position) > CHARGE_RANGE * 1.4):
			charging = null
		if charge_check <= 0.0:
			charge_check = 0.35
			var t := charging if charging != null else _charge_target()
			if t != null:
				var p := map.find_path(position, t.position)
				var plen := 0.0
				var prev := position
				for q in p:
					plen += prev.distance_to(q)
					prev = q
				if p.size() > 0 and plen < position.distance_to(t.position) * 1.6 + 24.0:
					if charging == null:
						charge_fresh = true
						if path_i < path.size():
							resume_to = path[path.size() - 1]
					charging = t
					path = p
					path_i = 0
					running = true
				elif charging == t:
					charging = null
		if charging != null:
			in_melee = false
			burst_left = 0
			return true
	if foe == null:
		in_melee = false
		melee_target = null
		if charging == null and resume_to != null:
			go_to(resume_to, squad.running)  # the fight's over: back to what he was doing
			resume_to = null
		elif charging == null and running and path_i >= path.size():
			running = squad.running
		return false
	if not in_melee and charging != null:
		# crashing into the enemy line: a shock to them
		foe.add_suppression(25.0 if foe.grounded() else 15.0, now)
		halt()
	in_melee = true
	charging = null
	melee_target = foe
	burst_left = 0
	facing = lerp_angle(facing, (foe.position - position).angle(), minf(1.0, dt * 12.0))
	if melee_cd <= 0.0:
		_strike(foe, now)
	return true


func _strike(foe: Soldier, now: float) -> void:
	var m := melee
	var p: float = m.hit
	var sees_it := absf(wrapf((position - foe.position).angle() - foe.facing, -PI, PI)) < 1.6
	if foe.grounded():
		# pinned or lying flat: he can't fend anything off, and assault troops butcher him
		p *= 1.8 if charger else 1.3
		if m.blade:
			m = m.duplicate()
			m.dmg = int(m.dmg) + 1  # a blade finishes a man on the ground
	elif foe.state == State.READY and sees_it:
		p *= 1.0 - float(foe.melee.parry)  # he sees it coming and fends it off
	elif not sees_it:
		p *= 1.25  # struck from behind
	if charge_fresh:
		p *= 1.3
		charge_fresh = false
	if grounded():
		p *= 0.5  # fighting back from the ground
	p = minf(p, 0.95)
	swing = 1.0
	melee_cd = float(m.cooldown) * randf_range(0.85, 1.15) * (1.8 if grounded() else 1.0)
	last_fire_time = now
	foe.add_suppression(6.0, now)
	main.resolve_blow(self, foe, m, randf() < p)


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
		if e.in_melee and is_instance_valid(e.melee_target) and e.melee_target.team == team:
			continue  # he's grappling with one of ours: no clear shot
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
		bleeding = 6.0  # a wounded man leaves a trail for a while


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
	# a blow twists his body into it: a slash with a blade, a jab with a gun butt
	var fa := facing + sin(swing * PI) * (0.45 if melee.get("blade", false) else 0.8)
	draw_set_transform(off, fa, Vector2.ONE)
	if prone:
		# legs stretched out behind him, shuffling when he crawls
		var c := sin(walk * 1.5) * r * 0.25 if moving else 0.0
		for sgn in [-1.0, 1.0]:
			var k: float = c * sgn
			draw_line(Vector2(-r * 0.6, sgn * r * 0.3), Vector2(-r * 1.9 + k, sgn * r * 0.42), Color(0, 0, 0, 0.35), r * 0.62)
			draw_line(Vector2(-r * 0.6, sgn * r * 0.3), Vector2(-r * 1.85 + k, sgn * r * 0.4), leg, r * 0.5)
			draw_circle(Vector2(-r * 1.95 + k, sgn * r * 0.4), r * 0.26, Color(0.12, 0.11, 0.1))  # boots
		draw_set_transform(off, fa, Vector2(1.1, 0.82))
	elif crouch:
		# kneeling: one knee forward, the other foot tucked behind
		draw_circle(Vector2(r * 0.55, -r * 0.55), r * 0.36, leg)  # knee forward
		draw_line(Vector2(-r * 0.2, r * 0.45), Vector2(-r * 0.95, r * 0.5), leg.darkened(0.15), r * 0.42)
		draw_circle(Vector2(-r * 1.05, r * 0.5), r * 0.24, Color(0.12, 0.11, 0.1))  # foot tucked behind
		draw_set_transform(off, fa, Vector2(0.86, 0.9))
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
	if data.get("loader", false):
		draw_rect(Rect2(-r - 3.0, -4.0, 6.0, 8.0), Color(0.28, 0.26, 0.16))  # power cells for the heavy gun
		draw_line(Vector2(-r - 3.0, 0), Vector2(-r + 3.0, 0), Color(1.0, 0.55, 0.25, 0.8), 1.0)
	elif heavy:
		draw_rect(Rect2(-r - 2.0, -3.5, 5.0, 7.0), Color(0.22, 0.22, 0.17))  # the gun's power pack
	elif not kind.begins_with("raider"):
		draw_rect(Rect2(-r - 1.0, -3.0, 4.0, 6.0), arm.darkened(0.2))  # pack and bedroll (raiders travel light)
	draw_circle(Vector2.ZERO, r, coat.darkened(0.25) if kind.begins_with("raider") else coat)
	draw_arc(Vector2.ZERO, r, 0, TAU, 16, coat.darkened(0.45), 1.0)
	var big_gun := heavy
	var stubber := kind == "gunner"
	var raider := kind.begins_with("raider")
	if big_gun:
		_draw_heavy_gun(Color(0.18, 0.19, 0.15), Color(1.0, 0.5, 0.25), 4.2, r + 13.0)
	elif raider:
		draw_line(Vector2(-r * 0.2, -r * 0.75), Vector2(r * 0.5, r * 0.75), Color(0.22, 0.16, 0.1), 1.6)  # bandolier
		draw_line(Vector2(0, 3), Vector2(r + 4.0, 3), Color(0.1, 0.09, 0.08), 2.6)  # ripper gun, short and stubby
		draw_rect(Rect2(r * 0.4, 3.5, 2.5, 3.5), Color(0.15, 0.13, 0.1))  # drum
		_draw_blade(Vector2(r * 0.35, -r * 0.7), r * (1.5 if kind == "raider_sgt" else 0.9), 1.4 if kind == "raider_sgt" else 1.1,
				Color(0.62, 0.62, 0.6), Color(0.3, 0.22, 0.14), kind == "raider_sgt")
	elif kind == "lancer":
		draw_line(Vector2(-r - 2.0, -3), Vector2(r + 6.0, -3), Color(0.2, 0.22, 0.16), 4.5)  # launcher tube
		draw_circle(Vector2(r + 7.0, -3), 2.6, Color(0.45, 0.35, 0.2))  # warhead
	else:
		draw_line(Vector2(0, 3), Vector2(r + (10.0 if stubber else 9.0), 3), Color(0.1, 0.09, 0.08), 3.5 if stubber else 2.0)
	if stubber:
		draw_rect(Rect2(1, 4, 4, 4), Color(0.3, 0.27, 0.15))  # ammo box
	draw_circle(Vector2(r * 0.6, 3.5), 1.8, coat.darkened(0.2))
	draw_circle(Vector2(0.5, 0), r * 0.58, arm)
	draw_arc(Vector2(0.5, 0), r * 0.58, -1.3, 1.0, 8, arm.lightened(0.35), 1.0)
	draw_circle(Vector2(r * 0.55, 0), 1.5, Color(0.12, 0.12, 0.12))  # rebreather
	if kind.begins_with("raider"):
		draw_line(Vector2(r * 0.15, -r * 0.5), Vector2(r * 0.15, r * 0.5), Color(0.55, 0.5, 0.42), 1.2)  # goggles strap
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
	var bastion: bool = data.get("bastion", false)
	if kind == "pyre_warden":
		for s in [-1.0, 1.0]:  # twin fuel tanks on his back
			draw_circle(Vector2(-r - 1.0, s * r * 0.35), r * 0.38, Color(0.35, 0.3, 0.22))
			draw_arc(Vector2(-r - 1.0, s * r * 0.35), r * 0.38, 0, TAU, 12, Color(0.12, 0.1, 0.08), 1.0)
		draw_line(Vector2(-r - 1.0, 0), Vector2(r * 0.3, r * 0.5), Color(0.15, 0.13, 0.1), 1.6)  # fuel hose
	else:
		draw_rect(Rect2(-r - 3.0, -r * 0.6, 6.0, r * 1.2), arm.darkened(0.3))  # power pack
	if data.get("loader", false):
		draw_rect(Rect2(-r - 6.0, -r * 0.5, 4.0, r), Color(0.3, 0.27, 0.2))  # ammunition crate
		draw_line(Vector2(-r - 2.0, -r * 0.3), Vector2(1, r * 0.5), Color(0.6, 0.5, 0.25), 1.2)  # belt
	draw_circle(Vector2(-r - 1.0, -2.5), 1.3, Color(1.0, 0.55, 0.2))
	draw_circle(Vector2(-r - 1.0, 2.5), 1.3, Color(1.0, 0.55, 0.2))
	draw_circle(Vector2.ZERO, r * 0.85, coat)
	var bladed := kind == "oathblade" or kind == "blade_champion"
	if heavy:
		_draw_heavy_gun(Color(0.13, 0.12, 0.12), trim.darkened(0.2), 6.0, r + 15.0, true)
	elif kind == "pyre_warden":
		draw_rect(Rect2(1, 1.0, r + 6.0, 5.0), Color(0.16, 0.14, 0.12))  # the projector
		draw_rect(Rect2(r + 5.0, 0.5, 3.5, 6.0), trim.darkened(0.3))  # nozzle
		draw_circle(Vector2(r + 9.5, 3.5), 1.6 + sin(walk * 3.0 + float(pool_seed % 7)) * 0.3, Color(0.5, 0.75, 1.0, 0.9))  # pilot flame
	elif kind == "bastion":
		for k in 3:  # the hail cannon's spinning barrels
			draw_rect(Rect2(3, 0.0 + k * 2.4, r + 10.0, 1.8), Color(0.15, 0.14, 0.14))
		draw_rect(Rect2(1, -0.6, r * 0.7, 8.0), Color(0.2, 0.18, 0.17))  # housing
		draw_rect(Rect2(r + 9.0, -0.3, 2.5, 7.5), trim.darkened(0.2))
	elif bladed:
		draw_rect(Rect2(1, 2.5, r * 0.8, 3.0), Color(0.13, 0.12, 0.12))  # pistol
		draw_rect(Rect2(r * 0.8, 2.0, 2.0, 4.0), trim.darkened(0.2))
		var great := kind == "blade_champion"
		_draw_blade(Vector2(r * 0.25, -r * 0.75), r * (2.1 if great else 1.7), 2.6 if great else 2.0,
				Color(0.78, 0.8, 0.84), trim, true, Color(0.55, 0.8, 1.0, 0.8))
	else:
		var gun_w := 5.0 if kind == "cannoneer" else 3.5
		draw_rect(Rect2(1, 1.5, r + 8.0, gun_w), Color(0.13, 0.12, 0.12))
		draw_rect(Rect2(r + 6.0, 1.0, 3.0, gun_w + 1.0), trim.darkened(0.2))
	if kind == "breacher":
		draw_circle(Vector2(r + 9.0, 3.2), 2.2, Color(0.6, 0.85, 1.0))  # fusion glow
	for s in [-1.0, 1.0]:
		var p := Vector2(-1, s * r * 0.72)
		var pad := r * (0.55 if bastion else 0.45)  # massive plate pauldrons on the heavy armour
		draw_circle(p, pad, coat.lightened(0.08))
		draw_arc(p, pad, 0, TAU, 14, trim, 1.6 if bastion else 1.3)
		if bastion:
			draw_arc(p, pad * 0.6, 0, TAU, 12, coat.darkened(0.25), 1.0)
	if bastion:
		draw_rect(Rect2(-r * 0.4, -r * 0.25, r * 0.5, r * 0.5), trim.darkened(0.15))  # chest seal
	draw_circle(Vector2(1, 0), r * 0.42, arm)
	draw_line(Vector2(r * 0.32, -2.2), Vector2(r * 0.32, 2.2), Color(1.0, 0.25, 0.1), 1.8)  # eye lenses


## A heavy gun: a long, thick barrel; standing on a tripod once it's set up (legs splay
## out as it goes up). Laser: a glowing lens. Bullets: a drum and belt.
func _draw_heavy_gun(body: Color, tip: Color, w: float, length: float, belt := false) -> void:
	if setup_t > 0.0:
		# tripod legs splaying out: two forward, one back
		var pivot := Vector2(length * 0.6, 2.0)
		var reach := 8.0 * (0.4 + setup_t * 0.6)
		for a in [-0.75 - setup_t * 0.35, 0.75 + setup_t * 0.35, PI]:
			var foot: Vector2 = pivot + Vector2.from_angle(a) * reach
			draw_line(pivot, foot, Color(0.05, 0.05, 0.05), 2.4)
			draw_line(pivot, foot, Color(0.42, 0.4, 0.36), 1.2)
			draw_circle(foot, 1.3, Color(0.05, 0.05, 0.05))
	draw_rect(Rect2(-0.6, 2.0 - w * 0.5 - 0.6, length + 1.2, w + 1.2), Color(0.03, 0.03, 0.03))  # outline: reads in firelight
	draw_rect(Rect2(0, 2.0 - w * 0.5, length, w), body)
	draw_line(Vector2(1, 2.0 - w * 0.3), Vector2(length - 1, 2.0 - w * 0.3), body.lightened(0.35), 0.8)  # metal catching the light
	draw_rect(Rect2(length * 0.2, 2.0 - w * 0.5 - 1.0, length * 0.3, w + 2.0), body.lightened(0.12))  # receiver
	if belt:
		draw_circle(Vector2(length * 0.35, 2.0 + w), w * 0.6, Color(0.3, 0.27, 0.2))  # ammo drum
		draw_rect(Rect2(length - 3.0, 2.0 - w * 0.5 - 0.5, 3.0, w + 1.0), tip)
	else:
		draw_circle(Vector2(length, 2.0), w * 0.45, tip)  # the lens
		draw_circle(Vector2(length, 2.0), w * 0.8, Color(tip, 0.25))


## A blade in his off hand: held point-forward ready, swept across in a blow, and
## carried down by his side when there's no close fight.
func _draw_blade(hand: Vector2, length: float, width: float, steel: Color, hilt: Color, guard: bool, glow := Color(0, 0, 0, 0)) -> void:
	var ready := in_melee or charging != null
	if not ready and glow.a <= 0.0 and swing <= 0.0:
		# a knife or sabre stays in its sheath at his hip until he needs it
		draw_line(Vector2(-radius * 0.5, radius * 0.7), Vector2(-radius * 0.5 + length * 0.7, radius * 0.95), hilt.darkened(0.3), width + 1.0)
		return
	var a := -0.25 if ready else -0.75  # point forward, or held low and ready
	if swing > 0.0:
		a = lerpf(-1.4, 0.9, 1.0 - swing)  # the slash sweeps across in front of him
	var dir := Vector2.from_angle(a)
	var tip := hand + dir * length
	draw_line(hand - dir * 2.5, hand, hilt, width + 0.6)  # grip
	if guard:
		draw_line(hand + dir.orthogonal() * 2.2, hand - dir.orthogonal() * 2.2, hilt.lightened(0.2), 1.2)
	if glow.a > 0.0:
		draw_line(hand, tip, glow, width + 1.6)  # the edict blade's crackling field
	draw_line(hand, tip, steel, width)
	draw_line(hand + dir.orthogonal() * width * 0.25, tip, steel.lightened(0.4), maxf(0.5, width * 0.3))  # the edge catching the light
	if swing > 0.5:  # the blur of the blow
		draw_arc(hand, length * 0.85, a - 0.9, a, 8, Color(1, 1, 1, (swing - 0.5) * 0.5), 1.0)


var pool_seed := randi()
var bleeding := 0.0
var bleed_step := 0.0


## Each body lies in its own pool: an irregular shape of varying size, darker at
## the middle, sometimes with a smear where he fell or spatter around it.
func _draw_corpse() -> void:
	var blood: Color = colors.blood
	var rng := RandomNumberGenerator.new()
	rng.seed = pool_seed
	var size := radius * rng.randf_range(0.7, 1.6)
	blood = blood.darkened(0.55)  # pooled blood is dark, almost black at the middle
	var centre := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0, radius * 0.5)
	var squash := rng.randf_range(0.55, 1.0)
	var rot := rng.randf() * TAU
	for layer in 2:
		var pts := PackedVector2Array()
		var lr := size * (1.0 if layer == 0 else rng.randf_range(0.45, 0.65))
		var n := 14
		for i in n:
			var a := i * TAU / n
			var rr := lr * rng.randf_range(0.65, 1.2)
			pts.append(centre + Vector2(cos(a) * rr, sin(a) * rr * squash).rotated(rot))
		draw_colored_polygon(pts, Color(blood.darkened(layer * 0.3), 0.6 + layer * 0.2))
	for i in rng.randi_range(0, 3):  # lobes where it ran out across the ground
		var a := rng.randf() * TAU
		draw_circle(centre + Vector2.from_angle(a) * size * rng.randf_range(0.7, 1.1), size * rng.randf_range(0.2, 0.4), Color(blood, 0.55))
	if rng.randf() < 0.4:  # a smear where he slumped
		var a := rng.randf() * TAU
		draw_line(centre, centre + Vector2.from_angle(a) * size * rng.randf_range(1.5, 2.5), Color(blood.darkened(0.2), 0.5), size * 0.4)
	for i in rng.randi_range(0, 5):  # spatter
		draw_circle(Vector2.from_angle(rng.randf() * TAU) * size * rng.randf_range(1.2, 2.2), rng.randf_range(0.5, 1.2), Color(blood, 0.6))
	draw_set_transform(Vector2.ZERO, facing + 2.2, Vector2(1.3, 0.75))
	var coat: Color = colors.coat
	draw_circle(Vector2.ZERO, radius * 0.85, coat.darkened(0.45))
	draw_circle(Vector2(radius * 0.9, 1), radius * 0.4, Color(colors.armour).darkened(0.4))
