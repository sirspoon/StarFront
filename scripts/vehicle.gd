class_name Vehicle
extends Soldier
## A tracked vehicle: a troop carrier or a tank. It shares the soldier's place in
## the battle (team, squad, spotting, targeting) but drives, aims and takes damage
## differently. Its armour depends on which side is hit, and only weapons with
## enough penetration can hurt it.

var vdata: Dictionary
var vkind := ""
var role := ""
var armour: Array = [5, 4, 3]
var length := 50.0
var width := 30.0
var turn_rate := 1.5
var capacity := 0
var passengers: Array[Soldier] = []
var slots: Array = []   # one per weapon: {weapon, turret, mount, cooldown, burst_left, burst_timer, target, angle, flash}
var turret_angle := 0.0
var recoil := 0.0
var hull_kick := 0.0        # the whole vehicle rocking back when the main gun fires
var cur_speed := 0.0        # it gathers speed and slows down rather than starting and stopping dead
var reversing := false
var shaken := 0.0
var track_phase := 0.0
var last_track := Vector2.INF  # where the last track mark was laid
var crushed := {}             # soldiers already run over (so it counts once each time)
var smoke_timer := 0.0
var engine_sound: AudioStreamPlayer2D
var was_moving := false
var rev_cooldown := 0.0
## Battle damage, drawn on the hull: [local point, went through?, seed], newest last.
var hits: Array = []
var plate_off := 0.0     # which side has lost an armour skirt plate (-1 / 1), 0 = none
var track_off := 0.0     # which side's track is broken and trailing
var last_hit_t := -99.0
## Carriers' grenade launchers: three salvos of each, six grenades a salvo.
var launcher := false
var launch_kind := "he"
var launch_ammo := {"he": 3, "smoke": 3}
var launch_cool := 0.0
var launch_order = null  # the player's: {point, kind, age}: turn to face it if need be, then fire
var _launch_think := 0.0


func setup_vehicle(m: Node, sq: Squad, t: int, kind_id: String) -> void:
	main = m
	map = m.map
	squad = sq
	team = t
	vkind = kind_id
	kind = kind_id
	faction = sq.faction
	colors = GameData.FACTIONS[faction]
	vdata = GameData.VEHICLES[kind_id]
	role = vdata.role
	hp = vdata.hp
	max_hp = hp
	armour = vdata.armour
	speed = vdata.speed
	turn_rate = vdata.turn
	length = vdata.length
	width = vdata.width
	capacity = vdata.capacity
	radius = width * 0.55
	is_vehicle = true
	strength = int(vdata.get("strength", 4))  # (a light buggy counts for less than a tank)
	morale = 100.0
	max_morale = 100.0
	nerve = 0.0
	for wd in vdata.weapons:
		var w: Dictionary = GameData.WEAPONS[wd.weapon]
		slots.append({"weapon": w, "turret": wd.get("turret", false), "mount": wd.get("mount", Vector2.ZERO),
				"cooldown": randf_range(0.5, 2.0), "burst_left": 0, "burst_timer": 0.0, "target": null,
				"angle": 0.0, "flash": 0.0,
				"modes": [w, GameData.WEAPONS[wd.alt]] if wd.has("alt") else []})
	weapon = slots[0].weapon
	launcher = vdata.get("launcher", false)
	engine_sound = m.sfx.make_engine()
	if engine_sound != null:
		add_child(engine_sound)
		engine_sound.pitch_scale = 0.75 if role == "tank" else (1.25 if role == "buggy" else 0.9)
		engine_sound.autoplay = true  # starts when the vehicle is placed on the map


## The main gun's settings (beam / pulse, AP / HE): which one is loaded, and switching.
func gun_mode() -> String:
	for sl in slots:
		if not sl.modes.is_empty():
			return sl.weapon.get("mode", "")
	if launcher:
		return "HE" if launch_kind == "he" else "Smoke"  # the launchers' loaded round
	return ""


func switch_gun() -> String:
	for sl in slots:
		if not sl.modes.is_empty():
			_set_mode(sl, sl.modes[1] if sl.weapon == sl.modes[0] else sl.modes[0])
			return sl.weapon.get("mode", "")
	if launcher:
		launch_kind = "smoke" if launch_kind == "he" else "he"
		return gun_mode()
	return ""


## Fire a salvo from the grenade launchers: six grenades, three from each side, over the
## ground ahead (centred on at, if given). Returns why not, or "" if it fired.
func fire_launcher(at = null) -> String:
	if not launcher or not is_alive():
		return "no launchers"
	if int(launch_ammo[launch_kind]) <= 0:
		return "no %s salvos left" % ("HE" if launch_kind == "he" else "smoke")
	if launch_cool > 0.0:
		return "reloading"
	launch_ammo[launch_kind] = int(launch_ammo[launch_kind]) - 1
	launch_cool = 3.0
	main.grenades.launch(self, launch_kind, at)
	if "--log-guns" in OS.get_cmdline_user_args():
		print("LAUNCH %s %s %s at %.0f s (%s left)" % [faction, vdata.name, launch_kind, main.time, launch_ammo])
	return ""


## The player's grenade order for a carrier: the launchers only fire forward, so it turns to
## face the spot (once it has stopped, if it's driving) and fires when it lines up.
func _carry_out_launch(dt: float) -> void:
	launch_order.age += dt
	if launch_order.age > 15.0:
		launch_order = null
		return
	var p: Vector2 = launch_order.point
	var diff := wrapf((p - position).angle() - facing, -PI, PI)
	if absf(diff) < 0.45:
		if launch_cool <= 0.0:
			launch_kind = launch_order.kind
			fire_launcher(p)
			launch_order = null
	elif path_i >= path.size():
		facing += clampf(diff, -turn_rate * dt, turn_rate * dt)  # pivot on the spot
		track_phase += turn_rate * dt * 12.0


## The computer's carriers: HE at a knot of enemy infantry close ahead, smoke when hit.
func _auto_launch(dt: float) -> void:
	_launch_think -= dt
	if _launch_think > 0.0 or launch_cool > 0.0:
		return
	_launch_think = 1.0
	if int(launch_ammo.smoke) > 0 and main.time - last_hit_t < 2.0:
		launch_kind = "smoke"
		fire_launcher()
		return
	if int(launch_ammo.he) <= 0:
		return
	var n := 0
	for e in main.soldiers:
		if e.team == team or e.is_vehicle or not e.is_alive() or not e.seen_by[team]:
			continue
		var d := position.distance_to(e.position)
		if d > 60.0 and d < 160.0 and absf(wrapf((e.position - position).angle() - facing, -PI, PI)) < 0.8:
			n += 1
	if n >= 3:
		launch_kind = "he"
		fire_launcher()


func _set_mode(sl: Dictionary, w: Dictionary) -> void:
	if sl.weapon == w:
		return
	sl.weapon = w
	sl.beam_t = 0.0  # cut the beam
	main.beam_stop(sl)
	sl.burst_left = 0
	sl.cooldown = maxf(sl.cooldown, 1.5)  # the crew change over
	weapon = slots[0].weapon
	if "--log-guns" in OS.get_cmdline_user_args():
		print("GUN %s %s -> %s at %.0f s" % [faction, vdata.name, w.get("mode", ""), main.time])


var _mode_think := 0.0
var _armour_seen := -100.0


## The computer's tanks pick the setting for what they can see: the anti-armour one when an
## enemy vehicle is in range, otherwise the one for men.
func _auto_mode(sl: Dictionary, dt: float) -> void:
	_mode_think -= dt
	if _mode_think > 0.0 or sl.get("beam_t", 0.0) > 0.0 or sl.burst_left > 0:
		return
	_mode_think = 2.0
	var at: Dictionary = sl.modes[0] if int(sl.modes[0].pen) >= int(sl.modes[1].pen) else sl.modes[1]
	var men: Dictionary = sl.modes[1] if at == sl.modes[0] else sl.modes[0]
	var armour := false
	for e in main.soldiers:
		if e.is_vehicle and e.team != team and e.is_alive() and e.seen_by[team] \
				and position.distance_to(e.position) <= float(at.range):
			armour = true
			break
	if armour:
		_armour_seen = main.time
	# keep the anti-armour setting a while after the enemy vehicle drops out of sight
	_set_mode(sl, at if armour or main.time - _armour_seen < 15.0 else men)


func can_breach() -> bool:
	for sl in slots:
		if sl.weapon.get("blast", 0.0) > 0.0 or sl.weapon.get("beam", 0.0) > 0.0:
			return true
	return false


func main_range() -> float:
	return slots[0].weapon.range


func free_space() -> int:
	return capacity - passengers.size()


func is_firing() -> bool:
	for sl in slots:
		if sl.burst_left > 0 or sl.flash > 0.0:
			return true
	return false


func go_to(p: Vector2, run: bool) -> void:
	if not is_alive():
		return
	path = map.find_vehicle_path(position, p)
	path_i = 0
	running = run


func add_suppression(_v: float, _now: float) -> void:
	pass  # crews behind armour shrug off small-arms fire


## Which armour value faces a shooter standing at from_pos.
func armour_facing(from_pos: Vector2) -> int:
	var a := absf(wrapf((from_pos - position).angle() - facing, -PI, PI))
	if a < PI * 0.25:
		return armour[0]
	if a > PI * 0.75:
		return armour[2]
	return armour[1]


static func pen_chance(pen: int, arm: int) -> float:
	if pen < arm - 2:
		return 0.0
	return clampf(0.5 + (pen - arm) * 0.18, 0.05, 0.95)


func hurt_by(w: Dictionary) -> bool:
	return pen_chance(w.get("pen", 0), armour[2]) > 0.0


## Called when a shot hits the hull. Returns true if it got through the armour.
func receive_hit(w: Dictionary, from_pos: Vector2, from: Soldier) -> bool:
	var arm := armour_facing(from_pos)
	if int(w.get("pen", 0)) >= 5:
		last_hit_t = main.time  # (something that could hurt it: the crew think about smoke)
	if randf() >= pen_chance(w.get("pen", 0), arm):
		if int(w.get("pen", 0)) >= 4:
			_mark_hit(from_pos, false)  # a gouge where it glanced off
		return false
	var before := float(hp) / max_hp
	hp -= int(w.get("vdmg", w.dmg))
	shaken = maxf(shaken, 2.5)
	_mark_hit(from_pos, true)
	var now_f := float(maxi(hp, 0)) / max_hp
	var side := signf((from_pos - position).rotated(-facing).y)
	if side == 0.0:
		side = 1.0
	# bits come off as it's hurt: a skirt plate, then a track
	if before >= 0.7 and now_f < 0.7 and plate_off == 0.0:
		plate_off = side
		_shed(side)
	if before >= 0.45 and now_f < 0.45 and track_off == 0.0:
		track_off = side
		speed *= 0.8  # limping on a damaged track
		_shed(side)
	if hp <= 0:
		_destroy(from)
	return true


## Where on the hull a hit from from_pos lands (hull space), for drawing the damage.
func _mark_hit(from_pos: Vector2, through: bool) -> void:
	var d := (from_pos - position).rotated(-facing).normalized()
	var t := minf(length * 0.5 / maxf(absf(d.x), 0.01), width * 0.5 / maxf(absf(d.y), 0.01)) * 0.8
	var p := d * t + Vector2(randf_range(-5, 5), randf_range(-4, 4))
	p.x = clampf(p.x, -length * 0.44, length * 0.44)
	p.y = clampf(p.y, -width * 0.42, width * 0.42)
	hits.append([p, through, randi()])
	if hits.size() > 16:
		hits.pop_front()


## Metal torn off the hull flying away.
func _shed(side: float) -> void:
	if visible:
		main.effects.debris(position + Vector2(0, side * width * 0.5).rotated(facing), 8)
		main.sfx.play("clang", position, 2.0, 0.1)


func _destroy(from: Soldier) -> void:
	for sl in slots:
		main.beam_stop(sl)  # (a lance cut off mid-beam)
	state = State.DEAD
	z_index = -1
	moving = false
	if engine_sound != null:
		engine_sound.stop()
	main.on_vehicle_destroyed(self, from)
	# passengers scramble out; some don't make it
	var out := passengers.duplicate()
	passengers.clear()
	for s in out:
		s.state = State.READY
		s.visible = true
		s.carrier = null
		s.position = _exit_point() + Vector2(randf_range(-14, 14), randf_range(-14, 14))
		s.suppression = 90.0
		s.morale -= 35.0 * s.nerve
		if randf() < 0.35:
			s.take_hit(99, from)
	map.add_wreck(position)
	queue_redraw()


func take_aboard(s: Soldier) -> void:
	if free_space() <= 0 or not is_alive():
		s.board_vehicle = null
		return
	passengers.append(s)
	s.state = State.EMBARKED
	s.carrier = self
	s.board_vehicle = null
	s.visible = false
	s.halt()


func _exit_point() -> Vector2:
	var p := position - Vector2.from_angle(facing) * (length * 0.5 + 14.0)
	return map.center_of(map.nearest_walkable(map.cell_of(p)))


func unload() -> void:
	if passengers.is_empty() or not is_alive():
		return
	var sq: Squad = passengers[0].squad
	var exit := _exit_point()
	for s in passengers:
		s.state = State.READY
		s.visible = true
		s.carrier = null
		s.position = exit + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		s.facing = facing + PI
	passengers.clear()
	sq.order_move(map, exit - Vector2.from_angle(facing) * 40.0, false)
	if team == main.player_team:
		main.log_message("%s has left %s." % [sq.name, squad.name])


# ---------------------------------------------------------------- simulation

func tick(dt: float, now: float) -> void:
	if not is_alive():
		return
	shaken = maxf(0.0, shaken - dt)
	if engine_sound != null:
		# revs up and gets louder when moving; the tank is deeper than the carrier
		var base := 0.85 if role == "tank" else (1.35 if role == "buggy" else 1.0)
		engine_sound.pitch_scale = move_toward(engine_sound.pitch_scale, base * (1.15 if moving else 0.8), dt * 0.4)
		engine_sound.volume_db = move_toward(engine_sound.volume_db, -8.0 if moving else -16.0, dt * 10.0)
		rev_cooldown -= dt
		if moving and not was_moving and rev_cooldown <= 0.0:
			main.sfx.play("engine_rev", position, 0.0 if role == "tank" else -3.0, 0.05)  # groaning into motion
			rev_cooldown = 4.0
		was_moving = moving
	recoil = maxf(0.0, recoil - dt * 3.0)
	launch_cool = maxf(0.0, launch_cool - dt)
	if launch_order != null:
		_carry_out_launch(dt)
	if hits.is_empty() and now > 1.0 and "--demo-vdamage" in OS.get_cmdline_user_args():
		# test aid: knock every vehicle about to about a third of its hull, from all sides
		var w := {"pen": 9, "vdmg": 1, "dmg": 1}
		while hp > max_hp * 0.34:
			receive_hit(w, position + Vector2.from_angle(randf() * TAU) * 100.0, null)
		for k in 5:
			_mark_hit(position + Vector2.from_angle(randf() * TAU) * 100.0, false)
	if launcher and main.ai_controls(team):
		_auto_launch(dt)
	hull_kick = maxf(0.0, hull_kick - dt * 4.0)
	_drive(dt)
	if last_track == Vector2.INF:
		last_track = position
	elif position.distance_to(last_track) > 10.0:
		main.decals.add_track(last_track, position, width * 0.72, width * 0.2)  # ruts in the dirt
		last_track = position
	_aim_and_fire(dt, now)
	smoke_timer -= dt
	if smoke_timer <= 0.0:
		smoke_timer = 0.35
		if visible and hp < max_hp * 0.65:
			# smoke from the hurt hull: grey at first, thick and black when it's badly hurt
			var bad := hp < max_hp * 0.35
			var back := -Vector2.from_angle(facing) * length * 0.25
			main.effects.puff(position + back + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
					Color(0.1, 0.09, 0.08) if bad else Color(0.3, 0.29, 0.27), 11.0 if bad else 7.0)
		if visible and moving:
			main.effects.puff(position - Vector2.from_angle(facing) * length * 0.5, Color(0.45, 0.4, 0.33), 7.0)
	if visible:
		queue_redraw()


func _drive(dt: float) -> void:
	if path_i >= path.size():
		cur_speed = 0.0
		moving = false
		reversing = false
		return
	var target := path[path_i]
	var to := target - position
	var dist := to.length()
	var final := path_i == path.size() - 1
	# take corners smoothly: head for the next point once close to this one
	if (not final and dist < 12.0) or (final and dist < 3.0):
		path_i += 1
		return
	var ang := to.angle()
	var top := speed * (1.35 if running else 1.0) * sqrt(map.speed_mult(position))
	# a short move to somewhere behind it: back up rather than turning all the way round
	reversing = final and dist < 90.0 and absf(wrapf(ang - facing, -PI, PI)) > 2.3 and (reversing or cur_speed < 4.0)
	var want := ang + (PI if reversing else 0.0)
	var diff := wrapf(want - facing, -PI, PI)
	var turn := turn_rate * dt
	facing += clampf(diff, -turn, turn)
	# full speed when lined up; slower through a turn; pivot on the spot if it's well off
	var factor := 0.0 if absf(diff) > 1.1 else cos(diff)
	var goal := top * factor * (0.45 if reversing else 1.0)
	if final:
		goal = minf(goal, sqrt(2.0 * top * 1.2 * dist))  # brake to stop on the spot
	var accel := top * (0.6 if goal > cur_speed else 1.4)
	cur_speed = move_toward(cur_speed, goal, accel * dt)
	moving = true
	if cur_speed < 0.5:
		track_phase += turn * 12.0  # pivoting: the tracks run in opposite directions
		return
	var step := minf(cur_speed * dt, dist)
	position += Vector2.from_angle(facing) * step * (-1.0 if reversing else 1.0)
	track_phase += step * (-1.0 if reversing else 1.0)
	_run_over(cur_speed)
	var under: Array = []  # it flattens bushes, hedges and wire it drives over
	for fx in [-0.4, 0.0, 0.4, 0.55]:
		for fy in [-0.35, 0.0, 0.35]:
			var c := map.cell_of(position + Vector2(length * fx, width * fy).rotated(facing))
			var t := map.get_t(c)
			if (t == BattleMap.T.BUSH or t == BattleMap.T.HEDGE or t == BattleMap.T.WIRE) and not under.has(c):
				under.append(c)
			elif t == BattleMap.T.LOW and map.vehicle_can_crush(c):
				# barricades, crates and sandbags: it shoves through them, slowing as it does
				map.chip_low(c, 9999.0)
				cur_speed *= 0.55
				if "--log-guns" in OS.get_cmdline_user_args():
					print("BASH %s %s through %s at %.0f s" % [faction, vdata.name, BattleMap.LOW_NAMES[map.low_kind[c.y * BattleMap.W + c.x]], main.time])
				hull_kick = maxf(hull_kick, 0.6)
				if visible:
					main.effects.debris(map.center_of(c), 7)
					main.sfx.play("collapse", map.center_of(c), -4.0, 0.15)
	if not under.is_empty():
		map.crush_cells(under)

## Men in the vehicle's path are shoved aside; going fast, it hits enemy soldiers it
## drives into (the crew steer clear of their own men).
func _run_over(spd: float) -> void:
	var now: float = main.time
	for s in main.soldiers:
		if s.is_vehicle or not s.is_alive() or s.state == State.EMBARKED:
			continue
		var rel: Vector2 = (s.position - position).rotated(-facing)
		var half_w: float = width * 0.5 + s.radius
		if rel.x < -length * 0.5 or rel.x > length * 0.5 + s.radius or absf(rel.y) > half_w:
			continue
		# shove him out to the nearer side
		var side := Vector2(0, 1 if rel.y >= 0.0 else -1).rotated(facing)
		var push: float = (half_w - absf(rel.y)) + 1.0
		var to: Vector2 = s.position + side * push
		if map.walkable(map.cell_of(to)):
			s.position = to
		else:
			s.position -= side * push  # pinned against a wall: the other way
		if s.team != team and spd > 40.0 and rel.x > length * 0.15 and now - float(crushed.get(s, -99.0)) > 1.5:
			crushed[s] = now
			s.add_suppression(35.0, now)
			if randf() < clampf((spd - 40.0) / 40.0 + 0.45, 0.0, 0.9) and randf() >= s.armor * 0.5:
				s.take_hit(2 if role == "tank" else 1, self)
				main.decals.add_smear(s.position, Vector2.from_angle(facing), 14.0, Color(s.colors.blood))


func _mount_pos(sl: Dictionary) -> Vector2:
	if sl.turret:
		if role == "buggy":
			return position + Vector2.from_angle(facing) * -2.0 + Vector2.from_angle(turret_angle) * 13.0
		return position + Vector2.from_angle(turret_angle) * (width * 0.35 + 26.0)
	var m: Vector2 = sl.mount
	return position + m.rotated(facing) + Vector2.from_angle(sl.angle) * 10.0


func _aim_and_fire(dt: float, now: float) -> void:
	var turret_goal := facing
	for sl in slots:
		sl.flash = maxf(0.0, sl.flash - dt)
		sl.cooldown -= dt
		if not sl.modes.is_empty() and main.ai_controls(team):
			_auto_mode(sl, dt)
		var t = sl.target
		if t != null and (not is_instance_valid(t) or not t.is_alive()):
			sl.target = null
			t = null
		if sl.turret and t != null:
			turret_goal = (t.position - position).angle()
		if sl.get("beam_t", 0.0) > 0.0:
			# the lance is firing: hold the beam on the target (or the wall) as the turret tracks it
			sl.beam_t -= dt
			if sl.beam_t <= 0.0:
				main.beam_stop(sl)
			if sl.get("beam_point") != null and t == null:
				turret_goal = (sl.beam_point - position).angle()
			elif t == null:
				# the target's gone: swing the beam on to the next one, or hold it where it is
				sl.target = pick_target(sl.weapon, position)
				turret_goal = (sl.target.position - position).angle() if sl.target != null else turret_angle
			sl.flash = 0.06
			last_fire_time = now
			main.beam_tick(self, sl, dt)
			continue
		if sl.burst_left > 0:
			sl.burst_timer -= dt
			if sl.burst_timer <= 0.0:
				if t != null:
					_fire(sl, t, now)
				sl.burst_left -= 1
				sl.burst_timer = sl.weapon.gap
			continue
		var bp = breach_point() if (sl.weapon.get("blast", 0.0) > 0.0 or sl.weapon.get("beam", 0.0) > 0.0) else null
		if bp != null:
			var bwant: float = (bp - position).angle()
			if sl.turret:
				turret_goal = bwant
			if sl.cooldown > 0.0 or shaken > 0.0:
				continue
			if position.distance_to(bp) <= sl.weapon.range and map.los_clear(position, bp) \
					and (not sl.turret or absf(wrapf(bwant - turret_angle, -PI, PI)) < 0.08):
				if not sl.turret:
					sl.angle = bwant
				sl.flash = 0.08
				if sl.turret:
					recoil = 1.0
				last_fire_time = now
				if sl.weapon.get("beam", 0.0) > 0.0:
					sl.beam_t = float(sl.weapon.beam)
					sl.beam_point = bp
					sl.target = null
					main.beam_start(self, sl)
				else:
					main.resolve_point_shot(self, bp, sl.weapon, _mount_pos(sl))
					if sl.turret and role == "tank":
						main.big_gun_fx(self, _mount_pos(sl), Vector2.from_angle(turret_angle))
				sl.cooldown = sl.weapon.cooldown * randf_range(0.9, 1.15)
			continue
		if sl.cooldown > 0.0 or shaken > 0.0:
			continue
		var from := position
		t = pick_target(sl.weapon, from)
		sl.target = t
		if t == null:
			sl.cooldown = randf_range(0.3, 0.6)
			continue
		var want: float = (t.position - position).angle()
		if sl.turret:
			turret_goal = want
			if absf(wrapf(want - turret_angle, -PI, PI)) > 0.08:
				continue  # wait for the turret to come round
		else:
			sl.angle = want
		sl.burst_left = sl.weapon.burst
		sl.burst_timer = 0.0
		sl.cooldown = sl.weapon.cooldown * randf_range(0.9, 1.15)
	var tdiff := wrapf(turret_goal - turret_angle, -PI, PI)
	var tr := 3.2 if role == "buggy" else 1.3  # a buggy's pintle gun swings round fast
	turret_angle += clampf(tdiff, -tr * dt, tr * dt)


func _fire(sl: Dictionary, t: Soldier, now: float) -> void:
	if not sl.turret:
		sl.angle = (t.position - position).angle()
	sl.flash = 0.08
	last_fire_time = now
	if sl.weapon.get("beam", 0.0) > 0.0:
		sl.beam_t = float(sl.weapon.beam)
		sl.beam_point = null
		main.beam_start(self, sl)
		return
	if sl.turret and (sl.weapon.get("light", false) or role != "tank"):
		recoil = maxf(recoil, 0.3)  # a pulse, or a buggy's stubber: a kick, not a tank gun's blast
	elif sl.turret:
		recoil = 1.0
		main.big_gun_fx(self, _mount_pos(sl), Vector2.from_angle(turret_angle))
	main.resolve_shot(self, t, sl.weapon, _mount_pos(sl))


# ---------------------------------------------------------------- drawing

const DARK := Color(0.04, 0.04, 0.035)
const STEEL := Color(0.24, 0.24, 0.23)


func _draw() -> void:
	var L := length
	var Wd := width
	# rocking back when the main gun fires
	var kick := -Vector2.from_angle(facing) * hull_kick * 2.5
	draw_set_transform(Vector2(6, 7), facing, Vector2.ONE)
	draw_rect(Rect2(-L * 0.5 - 1, -Wd * 0.5 - 1, L + 2, Wd + 2), Color(0, 0, 0, 0.4))
	draw_set_transform(kick, facing, Vector2.ONE)
	if state == State.DEAD:
		_draw_wreck(L, Wd)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	if squad.selected:
		draw_rect(Rect2(-L * 0.5 - 5, -Wd * 0.5 - 5, L + 10, Wd + 10), Color(0.45, 1.0, 0.45, 0.85), false, 1.5)
	elif team == main.player_team:
		draw_rect(Rect2(-L * 0.5 - 4, -Wd * 0.5 - 4, L + 8, Wd + 8), Color(1.0, 0.97, 0.88, 0.5 if main.paused else 0.2), false, 1.6 if main.paused else 1.2)
	if role == "buggy":
		_draw_buggy(L, Wd)
		_draw_damage(L, Wd)
	else:
		_draw_tracks(L, Wd)
		if faction == "sworn":
			_draw_sworn_hull(L, Wd)
		else:
			_draw_legion_hull(L, Wd)
		_draw_damage(L, Wd)
	for sl in slots:
		if not sl.turret:
			_draw_mount(sl)
	if role == "tank":
		_draw_turret(Wd)
	elif role == "buggy":
		_draw_buggy_gun()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if squad.selected or hp < max_hp:
		var bw := L * 0.8
		draw_rect(Rect2(-bw * 0.5, -L * 0.5 - 10, bw, 4), Color(0.1, 0.05, 0.04))
		draw_rect(Rect2(-bw * 0.5, -L * 0.5 - 10, bw * maxf(hp, 0) / max_hp, 4), Color(0.85, 0.7, 0.35))
	if passengers.size() > 0 and (team == main.player_team or main.autotest or main.spectate):
		draw_string(ThemeDB.fallback_font, Vector2(-L * 0.5, L * 0.5 + 16), "%d aboard" % passengers.size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.85, 0.7))
	if shaken > 0.0:
		draw_circle(Vector2(0, -L * 0.5 - 16), 3.0, Color(1.0, 0.8, 0.2))


func _tw(Wd: float) -> float:
	return Wd * 0.24


## The tracks: rubber-padded plates running round, with the drive sprocket at the front and
## the idler at the back showing at the ends.
func _draw_tracks(L: float, Wd: float) -> void:
	var tw := _tw(Wd)
	for side in [-1.0, 1.0]:
		var yc: float = side * (Wd * 0.5 - tw * 0.5)
		var r := Rect2(-L * 0.5, yc - tw * 0.5, L, tw)
		draw_rect(r, Color(0.09, 0.085, 0.08))
		var off := fposmod(track_phase, 4.0)
		var x := -L * 0.5 + off
		while x < L * 0.5:
			draw_line(Vector2(x, r.position.y + 0.5), Vector2(x, r.end.y - 0.5), Color(0.2, 0.19, 0.17), 1.6)
			draw_line(Vector2(x + 1.2, r.position.y + 1.5), Vector2(x + 1.2, r.end.y - 1.5), Color(0.13, 0.12, 0.11), 0.6)
			x += 4.0
		draw_line(Vector2(-L * 0.5, r.position.y + tw * 0.5), Vector2(L * 0.5, r.position.y + tw * 0.5), Color(0.06, 0.06, 0.05), 0.8)  # the guide teeth
		for ex in [L * 0.5 - tw * 0.45, -L * 0.5 + tw * 0.45]:  # sprocket and idler
			draw_circle(Vector2(ex, yc), tw * 0.42, Color(0.16, 0.15, 0.14))
			draw_circle(Vector2(ex, yc), tw * 0.18, Color(0.3, 0.29, 0.27))
		draw_rect(r, DARK, false, 0.8)


func _rivets(a: Vector2, b: Vector2, step: float, col: Color) -> void:
	var n := int(a.distance_to(b) / step)
	for k in n + 1:
		draw_circle(a.lerp(b, float(k) / maxf(n, 1)), 0.6, col)


## The Legion's vehicles: slab-sided olive steel, riveted, a sloped glacis catching the light,
## an engine deck with its grille and twin exhausts at the back, fenders over the tracks with
## stowage strapped to them, headlamps in cages, and the sunburst of the Dominion.
func _draw_legion_hull(L: float, Wd: float) -> void:
	var coat: Color = colors.coat
	var trim: Color = colors.trim
	var tw := _tw(Wd)
	var hw := Wd * 0.5 - tw * 0.55
	# fenders over the inner halves of the tracks
	for side in [-1.0, 1.0]:
		var fy: float = side * (Wd * 0.5 - tw * 0.75)
		draw_rect(Rect2(-L * 0.5 + 3, fy - tw * 0.3, L - 6, tw * 0.6), coat.darkened(0.15))
		draw_line(Vector2(-L * 0.5 + 3, fy - side * tw * 0.3), Vector2(L * 0.5 - 3, fy - side * tw * 0.3), coat.darkened(0.45), 0.6)
	var hull := PackedVector2Array([Vector2(-L * 0.5 + 1, -hw), Vector2(L * 0.32, -hw), Vector2(L * 0.5 - 1, -hw + 3),
			Vector2(L * 0.5 - 1, hw - 3), Vector2(L * 0.32, hw), Vector2(-L * 0.5 + 1, hw)])
	draw_colored_polygon(hull, coat)
	# the glacis: the sloped front plate, lit
	var glacis := PackedVector2Array([Vector2(L * 0.22, -hw + 1), Vector2(L * 0.32, -hw + 1), Vector2(L * 0.5 - 2, -hw + 4),
			Vector2(L * 0.5 - 2, hw - 4), Vector2(L * 0.32, hw - 1), Vector2(L * 0.22, hw - 1)])
	draw_colored_polygon(glacis, coat.lightened(0.14))
	draw_line(Vector2(L * 0.22, -hw + 1), Vector2(L * 0.22, hw - 1), coat.darkened(0.4), 0.8)
	draw_line(Vector2(-L * 0.5 + 1, -hw), Vector2(L * 0.32, -hw), coat.lightened(0.22), 0.8)  # lit edge
	draw_polyline(hull + PackedVector2Array([hull[0]]), DARK, 1.2)
	_rivets(Vector2(-L * 0.5 + 3, -hw + 2), Vector2(L * 0.3, -hw + 2), 5.0, coat.darkened(0.45))
	_rivets(Vector2(-L * 0.5 + 3, hw - 2), Vector2(L * 0.3, hw - 2), 5.0, coat.darkened(0.45))
	# spare track links on the glacis
	for k in 3:
		var q := Vector2(L * 0.36 + k * 3.5, -hw * 0.55)
		draw_rect(Rect2(q, Vector2(3, 6)), Color(0.13, 0.12, 0.11))
		draw_line(q + Vector2(0, 3), q + Vector2(3, 3), Color(0.3, 0.29, 0.27), 0.5)
	# headlamps in cages
	for y in [-hw + 3, hw - 3]:
		draw_circle(Vector2(L * 0.5 - 2, y), 2.0, Color(1.0, 0.95, 0.7))
		draw_arc(Vector2(L * 0.5 - 2, y), 2.8, 0, TAU, 8, DARK, 0.6)
	# the driver's hatch and vision block
	draw_circle(Vector2(L * 0.28, -hw * 0.45), 3.6, coat.darkened(0.1))
	draw_arc(Vector2(L * 0.28, -hw * 0.45), 3.6, 0, TAU, 12, DARK, 0.8)
	draw_rect(Rect2(L * 0.33, -hw * 0.6, 2, 3), Color(0.45, 0.6, 0.6))
	# engine deck at the back: grille, twin exhausts
	var deck := Rect2(-L * 0.5 + 3, -hw * 0.75, L * 0.24, hw * 1.5)
	draw_rect(deck, coat.darkened(0.25))
	var gx := deck.position.x + 2
	while gx < deck.end.x - 1:
		draw_line(Vector2(gx, deck.position.y + 1), Vector2(gx, deck.end.y - 1), coat.darkened(0.55), 0.9)
		gx += 2.5
	draw_rect(deck, DARK, false, 0.8)
	for y in [-hw * 0.85, hw * 0.85]:
		draw_rect(Rect2(-L * 0.5 - 2, y - 1.8, 6, 3.6), Color(0.18, 0.16, 0.14))
		draw_circle(Vector2(-L * 0.5 - 2, y), 1.8, Color(0.05, 0.04, 0.03))
		draw_circle(Vector2(-L * 0.5 - 2, y), 0.9, Color(1.0, 0.45, 0.15, 0.7))
	# stowage on the fenders: jerrycans and a toolbox
	for k in 2:
		var jc := Vector2(-L * 0.18 + k * 5.0, Wd * 0.5 - tw * 0.75)
		draw_rect(Rect2(jc - Vector2(2, 2.5), Vector2(4, 5)), Color(0.3, 0.32, 0.22))
		draw_line(jc - Vector2(1.5, 2), jc + Vector2(1.5, 2), Color(0.18, 0.2, 0.13), 0.5)
	draw_rect(Rect2(L * 0.05, -Wd * 0.5 + tw * 0.5, 9, 3.5), Color(0.28, 0.2, 0.13))
	if role == "carrier":
		# the troop compartment: two big roof hatches, the ramp at the back, an aerial
		for y in [-hw * 0.5, hw * 0.5]:
			var hr := Rect2(-L * 0.18, y - hw * 0.35, L * 0.34, hw * 0.7)
			draw_rect(hr, coat.lightened(0.05))
			draw_rect(hr, DARK, false, 0.8)
			draw_line(hr.get_center() - Vector2(4, 0), hr.get_center() + Vector2(4, 0), Color(0.15, 0.15, 0.14), 1.2)  # handle
		draw_line(Vector2(-L * 0.5 + 1, -hw + 2), Vector2(-L * 0.5 + 1, hw - 2), Color(0.12, 0.12, 0.1), 2.0)  # ramp hinge
		draw_line(Vector2(-L * 0.25, -hw + 2), Vector2(-L * 0.44, -hw - 8), Color(0.1, 0.1, 0.1), 0.7)  # aerial
		_draw_sunburst(Vector2(L * 0.12, 0), 4.0, trim)
	else:
		_draw_sunburst(Vector2(L * 0.38, hw * 0.45), 3.2, trim)


## The Sworn's vehicles: crimson armour in angular gothic plates, armoured skirts over the
## tracks studded and edged in gold, a bone-white prow, ribs of gold filigree, glowing vents,
## an oath scroll on the deck and the sunburst sigil.
func _draw_sworn_hull(L: float, Wd: float) -> void:
	var coat: Color = colors.coat
	var arm: Color = colors.armour
	var trim: Color = colors.trim
	var tw := _tw(Wd)
	# armoured skirts over the tracks
	for side in [-1.0, 1.0]:
		var sy: float = side * (Wd * 0.5 - tw * 0.5)
		var sk := Rect2(-L * 0.42, sy - tw * 0.5, L * 0.84, tw)
		draw_rect(sk, arm)
		draw_line(Vector2(sk.position.x, sy - side * tw * 0.5), Vector2(sk.end.x, sy - side * tw * 0.5), arm.lightened(0.2), 0.7)
		draw_rect(sk, trim.darkened(0.25), false, 1.0)
		_rivets(Vector2(sk.position.x + 3, sy), Vector2(sk.end.x - 3, sy), 6.0, trim)
	var hw := Wd * 0.5 - tw * 0.8
	var hull := PackedVector2Array([Vector2(-L * 0.5 + 3, -hw), Vector2(L * 0.25, -hw), Vector2(L * 0.42, -hw * 0.55),
			Vector2(L * 0.42, hw * 0.55), Vector2(L * 0.25, hw), Vector2(-L * 0.5 + 3, hw), Vector2(-L * 0.5, hw - 3), Vector2(-L * 0.5, -hw + 3)])
	draw_colored_polygon(hull, coat)
	# angled armour plates, lit on the near side
	draw_colored_polygon(PackedVector2Array([Vector2(-L * 0.3, -hw), Vector2(L * 0.25, -hw), Vector2(L * 0.18, -hw * 0.45), Vector2(-L * 0.3, -hw * 0.45)]), coat.lightened(0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(-L * 0.3, hw), Vector2(L * 0.25, hw), Vector2(L * 0.18, hw * 0.45), Vector2(-L * 0.3, hw * 0.45)]), coat.darkened(0.15))
	draw_polyline(hull + PackedVector2Array([hull[0]]), trim, 1.6)
	# ribs of gold filigree
	for k in 3:
		var x := -L * 0.22 + k * L * 0.15
		draw_line(Vector2(x, -hw + 1), Vector2(x + 4, -hw * 0.45), trim.darkened(0.15), 1.0)
		draw_line(Vector2(x, hw - 1), Vector2(x + 4, hw * 0.45), trim.darkened(0.15), 1.0)
	# the bone prow
	var prow := PackedVector2Array([Vector2(L * 0.36, -hw * 0.7), Vector2(L * 0.5 + 4, 0), Vector2(L * 0.36, hw * 0.7)])
	draw_colored_polygon(prow, Color(0.82, 0.78, 0.66))
	draw_colored_polygon(PackedVector2Array([Vector2(L * 0.36, -hw * 0.7), Vector2(L * 0.5 + 4, 0), Vector2(L * 0.4, 0)]), Color(0.9, 0.87, 0.78))
	draw_polyline(prow + PackedVector2Array([prow[0]]), trim.darkened(0.3), 0.8)
	# glowing vents at the back
	for k in 3:
		var vr := Rect2(-L * 0.5 + 3, -hw * 0.6 + k * hw * 0.45, 7, 3)
		draw_rect(vr, Color(0.1, 0.03, 0.02))
		draw_rect(vr.grow(-0.6), Color(1.0, 0.45, 0.12, 0.9))
	# the oath scroll and the sigil
	var sc := Rect2(-L * 0.2, hw * 0.1, L * 0.22, 5)
	draw_rect(sc, Color(0.88, 0.82, 0.66))
	draw_circle(Vector2(sc.position.x, sc.get_center().y), 2.6, Color(0.82, 0.76, 0.6))
	draw_circle(Vector2(sc.end.x, sc.get_center().y), 2.6, Color(0.82, 0.76, 0.6))
	for k in 4:
		draw_line(Vector2(sc.position.x + 2 + k * 3, sc.get_center().y), Vector2(sc.position.x + 3.5 + k * 3, sc.get_center().y), Color(0.3, 0.2, 0.15), 0.8)
	_draw_sunburst(Vector2(L * 0.22, -hw * 0.25), 3.6, trim)
	if role == "carrier":
		var hr := Rect2(-L * 0.24, -hw * 0.4, L * 0.32, hw * 0.75)
		draw_rect(hr, coat.lightened(0.06))
		draw_rect(hr, trim.darkened(0.2), false, 1.0)
		draw_line(Vector2(hr.get_center().x, hr.position.y), Vector2(hr.get_center().x, hr.end.y), trim.darkened(0.35), 0.8)  # the doors' seam
		for y in [-hw + 1.5, hw - 1.5]:  # vision slits
			draw_line(Vector2(-L * 0.1, y), Vector2(L * 0.05, y), Color(1.0, 0.3, 0.12), 1.0)


## Battle damage: scorched holes where rounds went through, bright gouges where they
## glanced off, a skirt plate torn away (and one left hanging), a broken track trailing its
## links, and fire on the engine deck when it's close to brewing up.
func _draw_damage(L: float, Wd: float) -> void:
	var tw := _tw(Wd)
	var t: float = main.time
	if plate_off != 0.0 and role != "buggy":
		var y: float = plate_off * (Wd * 0.5 - tw * 0.5)
		var bare := Rect2(-L * 0.12, y - tw * 0.55, L * 0.3, tw * 1.1)
		draw_rect(bare, Color(0.11, 0.1, 0.09))  # the bare hull side under it
		for k in 4:
			draw_circle(Vector2(bare.position.x + 2 + k * bare.size.x / 4.0, y), 0.7, Color(0.35, 0.33, 0.3))  # empty bolt holes
		# the next plate along, hanging off one bolt
		var hp0 := Vector2(-L * 0.22, y + plate_off * tw * 0.5)
		var hang := PackedVector2Array([hp0, hp0 + Vector2(-L * 0.12, plate_off * 2.5), hp0 + Vector2(-L * 0.13, plate_off * (tw * 0.9 + 3)),
				hp0 + Vector2(-1, plate_off * tw * 0.8)])
		draw_colored_polygon(hang, colors.coat.darkened(0.35))
		draw_polyline(hang + PackedVector2Array([hp0]), DARK, 0.8)
	if track_off != 0.0 and role == "buggy":
		# a wheel blown off: the bare hub on its axle
		var wy: float = track_off * Wd * 0.5
		draw_rect(Rect2(-L * 0.42, wy - 3.0, 9.0, 6.0), Color(0.15, 0.14, 0.13))
		draw_circle(Vector2(-L * 0.42 + 4.5, wy), 1.8, Color(0.4, 0.38, 0.35))
	elif track_off != 0.0:
		var yc: float = track_off * (Wd * 0.5 - tw * 0.5)
		# the broken run: a gap, then links trailing out behind
		draw_rect(Rect2(-L * 0.5, yc - tw * 0.5, L * 0.28, tw), Color(0.16, 0.14, 0.12))
		var a := Vector2(-L * 0.5, yc)
		for k in 6:
			var p := a + Vector2(-3.6 * k, track_off * (k * k) * 0.35 + sin(k * 1.3) * 0.8)
			draw_rect(Rect2(p - Vector2(1.6, tw * 0.45), Vector2(3.0, tw * 0.9)), Color(0.12, 0.11, 0.1))
			draw_line(p - Vector2(0, tw * 0.4), p + Vector2(0, tw * 0.4), Color(0.25, 0.23, 0.2), 0.8)
		draw_circle(Vector2(-L * 0.5 + tw * 0.45, yc), tw * 0.42, Color(0.2, 0.19, 0.17))  # the bare idler wheel
	for h in hits:
		var p: Vector2 = h[0]
		var rng := RandomNumberGenerator.new()
		rng.seed = h[2]
		if h[1]:
			draw_circle(p, rng.randf_range(4.0, 6.0), Color(0.02, 0.02, 0.015, 0.5))  # scorch
			draw_circle(p, rng.randf_range(2.0, 3.0), Color(0.06, 0.05, 0.04, 0.8))
			for k in 6:  # the metal splashed back round the hole
				var ang := k * TAU / 6.0 + rng.randf() * 0.5
				draw_line(p + Vector2.from_angle(ang) * 1.4, p + Vector2.from_angle(ang) * rng.randf_range(2.5, 4.0), Color(0.42, 0.3, 0.2), 0.7)
			draw_circle(p, 1.2, Color(0, 0, 0))
		else:
			var ang := rng.randf() * TAU
			draw_line(p, p + Vector2.from_angle(ang) * rng.randf_range(3.0, 6.0), Color(0.62, 0.6, 0.55), 0.9)
			draw_circle(p, 1.6, Color(0.05, 0.05, 0.04, 0.45))
	if hp < max_hp * 0.35:
		# flames licking up from the engine deck
		for k in 3:
			var p := Vector2(-L * 0.32 + k * 4.0, sin(k * 2.1) * Wd * 0.15)
			var f := 0.6 + 0.4 * sin(t * 13.0 + k * 1.7)
			draw_circle(p, 3.2 * f + 1.0, Color(1.0, 0.45, 0.1, 0.75))
			draw_circle(p, 1.6 * f + 0.5, Color(1.0, 0.85, 0.4, 0.9))


## The Sworn's Outrider: a low wedge of a hull on four big knobbly wheels, an open cab with
## the driver behind a slit visor, a roll cage over the back, oath-scroll pennant, and the
## gunner standing at the pintle stubber (drawn by _draw_buggy_gun).
func _draw_buggy(L: float, Wd: float) -> void:
	var coat: Color = colors.coat
	var trim: Color = colors.trim
	var spin := fposmod(track_phase * 0.6, 4.0)
	for sx in [-1.0, 1.0]:  # wheels, sticking out past the body, treads turning
		for sy in [-1.0, 1.0]:
			if track_off == sy and sx < 0.0:
				continue  # that one's gone
			var wc := Vector2(sx * L * 0.3, sy * (Wd * 0.5 - 1.0))
			var wr := Rect2(wc - Vector2(5.5, 3.2), Vector2(11, 6.4))
			draw_rect(wr, Color(0.09, 0.085, 0.08))
			var x := wr.position.x + spin * 0.5
			while x < wr.end.x:
				draw_line(Vector2(x, wr.position.y + 0.6), Vector2(x, wr.end.y - 0.6), Color(0.2, 0.19, 0.17), 1.0)
				x += 2.0
			draw_circle(wc, 1.4, Color(0.42, 0.4, 0.36))  # hub
	# the body: a low wedge, nose forward
	var body := PackedVector2Array([Vector2(L * 0.5, -Wd * 0.22), Vector2(L * 0.5, Wd * 0.22), Vector2(L * 0.18, Wd * 0.36),
			Vector2(-L * 0.45, Wd * 0.36), Vector2(-L * 0.5, Wd * 0.25), Vector2(-L * 0.5, -Wd * 0.25), Vector2(-L * 0.45, -Wd * 0.36),
			Vector2(L * 0.18, -Wd * 0.36)])
	draw_colored_polygon(body, coat.darkened(0.1))
	var lit := PackedVector2Array([Vector2(L * 0.5, -Wd * 0.22), Vector2(L * 0.18, -Wd * 0.36), Vector2(-L * 0.45, -Wd * 0.36), Vector2(-L * 0.3, -Wd * 0.18), Vector2(L * 0.3, -Wd * 0.12)])
	draw_colored_polygon(lit, coat.lightened(0.12))  # the side catching the light
	var edge := body.duplicate()
	edge.append(body[0])
	draw_polyline(edge, DARK, 1.0)
	# bull bar and headlamps on the nose
	draw_line(Vector2(L * 0.52, -Wd * 0.25), Vector2(L * 0.52, Wd * 0.25), STEEL.lightened(0.15), 1.6)
	for sy in [-1.0, 1.0]:
		draw_circle(Vector2(L * 0.46, sy * Wd * 0.17), 1.5, Color(0.95, 0.85, 0.55))
	# the open cab: the driver's seat and slit visor
	draw_rect(Rect2(L * 0.02, -Wd * 0.2, L * 0.2, Wd * 0.4), Color(0.12, 0.08, 0.07))
	draw_circle(Vector2(L * 0.09, 0), Wd * 0.13, coat.darkened(0.3))  # the driver's helm
	draw_line(Vector2(L * 0.14, -Wd * 0.05), Vector2(L * 0.14, Wd * 0.05), Color(1.0, 0.3, 0.12), 1.0)
	# the roll cage over the back
	var cage := Rect2(-L * 0.42, -Wd * 0.3, L * 0.38, Wd * 0.6)
	draw_rect(cage, STEEL.darkened(0.2), false, 1.4)
	draw_line(cage.position, cage.end, STEEL.darkened(0.3), 1.0)
	draw_line(Vector2(cage.position.x, cage.end.y), Vector2(cage.end.x, cage.position.y), STEEL.darkened(0.3), 1.0)
	# gilt trim and an oath-scroll pennant streaming from the cage
	draw_line(Vector2(-L * 0.45, Wd * 0.36), Vector2(L * 0.18, Wd * 0.36), trim.darkened(0.2), 1.0)
	var pole := Vector2(-L * 0.42, -Wd * 0.3)
	var flutter := sin(main.time * 9.0 + get_instance_id()) * 1.5
	draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(-9, -2 + flutter), pole + Vector2(-7, 2 + flutter)]), Color(0.86, 0.8, 0.62))


## The Outrider's gunner at his pintle-mounted stubber, swinging round with the gun.
func _draw_buggy_gun() -> void:
	var a := turret_angle - facing
	var mount := Vector2(-length * 0.08, 0)
	draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
	var dir := Vector2.from_angle(a)
	draw_circle(mount, 5.0, Color(0.1, 0.09, 0.08))  # the ring
	draw_circle(mount - dir * 2.0, 3.6, colors.coat.darkened(0.25))  # the gunner's shoulders
	draw_circle(mount - dir * 2.0, 2.2, colors.armour)  # his helm
	var muzzle := mount + dir * 13.0
	draw_line(mount + dir * 2.0, muzzle, Color(0, 0, 0, 0.4), 3.6)
	draw_line(mount + dir * 2.0, muzzle, STEEL.lightened(0.1), 2.4)
	draw_rect(Rect2(mount + dir * 3.0 - Vector2(2, 2), Vector2(4, 4)), Color(0.3, 0.25, 0.15))  # the ammo box
	draw_line(mount + dir.orthogonal() * 3.0 + dir * 3.0, mount - dir.orthogonal() * 3.0 + dir * 3.0, STEEL.darkened(0.2), 1.6)  # gun shield
	if slots[0].flash > 0.0:
		draw_circle(muzzle + dir * 2.0, 3.0, Color(0.7, 0.9, 1.0, 0.9))


func _draw_sunburst(c: Vector2, r: float, col: Color) -> void:
	for i in 8:
		draw_line(c, c + Vector2.from_angle(i * TAU / 8.0) * r * (1.6 if i % 2 == 0 else 1.2), col, 0.9)
	draw_circle(c, r * 0.6, col)
	draw_circle(c, r * 0.3, col.darkened(0.5))


## A hull-mounted gun: a ball mount with the gun's shroud (three barrels for a rotor cannon).
func _draw_mount(sl: Dictionary) -> void:
	var m: Vector2 = sl.mount
	var a: float = sl.angle - facing  # we're drawing in hull space
	var dir := Vector2.from_angle(a)
	var nrm := dir.orthogonal()
	var rotor: bool = sl.weapon.get("burst", 1) >= 5 and sl.weapon.get("pen", 0) >= 4
	draw_circle(m, 5.0, DARK)
	draw_circle(m, 4.2, Color(0.2, 0.19, 0.18))
	if rotor:
		for k in 3:
			var o: Vector2 = nrm * (k - 1) * 1.6
			draw_line(m + o, m + o + dir * 15.0, Color(0.1, 0.1, 0.1), 1.4)
		draw_line(m + dir * 13.0 - nrm * 2.6, m + dir * 13.0 + nrm * 2.6, Color(0.3, 0.3, 0.3), 1.2)
	else:
		draw_line(m, m + dir * 14.0, DARK, 3.2)
		draw_line(m + dir * 3.0, m + dir * 9.0, Color(0.25, 0.25, 0.24), 3.6)  # cooling jacket
	draw_circle(m - dir * 1.0, 1.4, Color(0.4, 0.4, 0.38))
	if sl.flash > 0.0:
		draw_circle(m + dir * 17.0, 4.5, Color(1.0, 0.9, 0.5, 0.9))


## The turret. The Legion's: a slab-sided box with a heavy mantlet, the lumen lance (a long
## projector with focusing rings and an emitter that glows when it fires), the commander's
## cupola, smoke dischargers and a whip aerial. The Sworn's: a faceted gothic dome with a gold
## rim, the fusion cannon with heat-sink fins and glowing coils, and red sensor lenses.
func _draw_turret(Wd: float) -> void:
	var a := turret_angle - facing
	var r := Wd * 0.36
	var dir := Vector2.from_angle(a)
	var nrm := dir.orthogonal()
	var back := dir * (-recoil * 7.0)
	var coat: Color = colors.coat
	var trim: Color = colors.trim
	var sworn := faction == "sworn"
	var firing := false
	for sl in slots:
		if sl.turret and (sl.flash > 0.0 or sl.get("beam_t", 0.0) > 0.0):
			firing = true
	var b0 := dir * r * 0.4 + back
	var b1 := dir * (r + 32.0) + back
	draw_line(b0 + Vector2(2, 3), b1 + Vector2(2, 3), Color(0, 0, 0, 0.35), 6.0)  # the barrel's shadow
	if sworn:
		draw_line(b0, b1, DARK, 7.5)
		draw_line(b0, b1, Color(0.2, 0.18, 0.18), 6.0)
		for k in 5:  # heat-sink fins
			var p := b0.lerp(b1, 0.25 + k * 0.12)
			draw_line(p - nrm * 5.0, p + nrm * 5.0, Color(0.12, 0.11, 0.11), 1.6)
		for k in 3:  # glowing coils
			var p := b0.lerp(b1, 0.3 + k * 0.24)
			draw_line(p - nrm * 3.5, p + nrm * 3.5, Color(0.55, 0.85, 1.0, 1.0 if firing else 0.7), 1.6)
		draw_circle(b1, 4.0, Color(0.12, 0.11, 0.11))
		draw_circle(b1, 2.4, Color(0.6, 0.85, 1.0, 1.0 if firing else 0.6))
	else:
		draw_line(b0, b1, DARK, 6.5)
		draw_line(b0, b1, Color(0.28, 0.29, 0.25), 5.0)
		draw_line(b0 + nrm * 1.2, b1 + nrm * 1.2, Color(0.4, 0.41, 0.36), 0.8)
		for k in 3:  # focusing rings
			var p := b0.lerp(b1, 0.35 + k * 0.2)
			draw_line(p - nrm * 4.0, p + nrm * 4.0, DARK, 2.6)
			draw_line(p - nrm * 3.4, p + nrm * 3.4, Color(1.0, 0.55, 0.25, 1.0 if firing else 0.45), 1.0)
		# the emitter: a flared cone with a lens
		draw_colored_polygon(PackedVector2Array([b1 - dir * 4.0 - nrm * 3.0, b1 + dir * 2.0 - nrm * 5.0, b1 + dir * 2.0 + nrm * 5.0, b1 - dir * 4.0 + nrm * 3.0]), Color(0.22, 0.23, 0.2))
		draw_circle(b1 + dir * 2.0, 3.0, Color(1.0, 0.6, 0.3, 1.0 if firing else 0.5))
	# the turret body
	var pts := PackedVector2Array()
	if sworn:
		for i in 8:
			pts.append(back + Vector2.from_angle(a + PI / 8.0 + i * TAU / 8.0) * r)
	else:
		for v in [Vector2(1.05, -0.62), Vector2(1.05, 0.62), Vector2(0.55, 0.95), Vector2(-0.9, 0.9), Vector2(-1.05, 0.55),
				Vector2(-1.05, -0.55), Vector2(-0.9, -0.9), Vector2(0.55, -0.95)]:
			pts.append(back + (dir * v.x + nrm * v.y) * r)
	draw_colored_polygon(pts, coat.lightened(0.04))
	# lit and shaded halves for a rounded, solid look
	var lit := PackedVector2Array([back])
	for i in pts.size() / 2 + 1:
		lit.append(pts[i])
	var ld := Vector2(-0.6, -0.8).rotated(-facing)
	if ld.dot(nrm) > 0.0:
		draw_colored_polygon(lit, Color(1, 1, 1, 0.07))
	else:
		draw_colored_polygon(lit, Color(0, 0, 0, 0.12))
	draw_polyline(pts + PackedVector2Array([pts[0]]), trim if sworn else DARK, 1.6 if sworn else 1.2)
	if sworn:
		for i in 8:  # facet lines meeting at the crown
			draw_line(back, pts[i], coat.darkened(0.25), 0.5)
		draw_circle(back, r * 0.25, trim.darkened(0.15))
		for s in [-1.0, 1.0]:  # sensor lenses
			draw_circle(back + dir * r * 0.6 + nrm * s * r * 0.3, 1.8, Color(1.0, 0.25, 0.1))
	else:
		draw_rect(Rect2(back + dir * r * 0.8 - nrm * r * 0.5 - Vector2(1, 1), Vector2(2, 2)), DARK)
		# the mantlet round the gun
		draw_line(back + dir * r * 0.9 - nrm * r * 0.42, back + dir * r * 0.9 + nrm * r * 0.42, coat.darkened(0.3), 3.0)
		# commander's cupola with periscopes
		var cup := back - dir * r * 0.25 + nrm * r * 0.35
		draw_circle(cup, 4.5, coat.darkened(0.1))
		draw_arc(cup, 4.5, 0, TAU, 12, DARK, 0.8)
		for k in 4:
			draw_rect(Rect2(cup + Vector2.from_angle(k * TAU / 4.0 + a) * 4.0 - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(0.4, 0.55, 0.55))
		for s in [-1.0, 1.0]:  # smoke dischargers
			for k in 3:
				draw_circle(back + dir * r * (0.35 - k * 0.22) + nrm * s * r * 0.98, 1.2, DARK)
		var aer := back - dir * r * 0.8 - nrm * r * 0.4  # a whip aerial
		draw_line(aer, aer - dir * 14.0 - nrm * 4.0, Color(0.08, 0.08, 0.08), 0.6)


func _draw_wreck(L: float, Wd: float) -> void:
	draw_circle(Vector2.ZERO, L * 0.75, Color(0.03, 0.03, 0.02, 0.35))
	_draw_tracks(L, Wd)
	var hull := _hull_poly(L, Wd, _tw(Wd) * 0.55, 8.0)
	draw_colored_polygon(hull, Color(0.13, 0.12, 0.11))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.05, 0.05, 0.05), 2.0)
	for k in 6:  # burnt out: blistered, buckled plates
		draw_circle(Vector2(L * (k / 6.0 - 0.45), sin(k * 2.3) * Wd * 0.2), 3.0, Color(0.06, 0.05, 0.04))
	if role == "tank":
		var a := turret_angle - facing + 0.7
		draw_circle(Vector2(-6, 4), Wd * 0.3, Color(0.17, 0.16, 0.14))
		draw_line(Vector2(-6, 4), Vector2(-6, 4) + Vector2.from_angle(a) * 30.0, Color(0.08, 0.08, 0.08), 4.0)
	draw_circle(Vector2(4, -3), 6.0, Color(0.02, 0.02, 0.02))


func _hull_poly(L: float, Wd: float, inset: float, nose: float) -> PackedVector2Array:
	var h := Wd * 0.5 - inset
	return PackedVector2Array([Vector2(-L * 0.5 + 2, -h), Vector2(L * 0.5 - nose, -h), Vector2(L * 0.5, -h + nose * 0.6),
			Vector2(L * 0.5, h - nose * 0.6), Vector2(L * 0.5 - nose, h), Vector2(-L * 0.5 + 2, h)])
