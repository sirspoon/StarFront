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
	strength = 4
	morale = 100.0
	max_morale = 100.0
	nerve = 0.0
	for wd in vdata.weapons:
		var w: Dictionary = GameData.WEAPONS[wd.weapon]
		slots.append({"weapon": w, "turret": wd.get("turret", false), "mount": wd.get("mount", Vector2.ZERO),
				"cooldown": randf_range(0.5, 2.0), "burst_left": 0, "burst_timer": 0.0, "target": null,
				"angle": 0.0, "flash": 0.0})
	weapon = slots[0].weapon
	engine_sound = m.sfx.make_engine()
	if engine_sound != null:
		add_child(engine_sound)
		engine_sound.pitch_scale = 0.75 if role == "tank" else 0.9
		engine_sound.autoplay = true  # starts when the vehicle is placed on the map


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
	if randf() >= pen_chance(w.get("pen", 0), arm):
		return false
	hp -= int(w.get("vdmg", w.dmg))
	shaken = maxf(shaken, 2.5)
	if hp <= 0:
		_destroy(from)
	return true


func _destroy(from: Soldier) -> void:
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
		var base := 0.85 if role == "tank" else 1.0
		engine_sound.pitch_scale = move_toward(engine_sound.pitch_scale, base * (1.15 if moving else 0.8), dt * 0.4)
		engine_sound.volume_db = move_toward(engine_sound.volume_db, -8.0 if moving else -16.0, dt * 10.0)
		rev_cooldown -= dt
		if moving and not was_moving and rev_cooldown <= 0.0:
			main.sfx.play("engine_rev", position, 0.0 if role == "tank" else -3.0, 0.05)  # groaning into motion
			rev_cooldown = 4.0
		was_moving = moving
	recoil = maxf(0.0, recoil - dt * 3.0)
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
		if visible and hp < max_hp * 0.5:
			main.effects.puff(position + Vector2(randf_range(-8, 8), randf_range(-8, 8)), Color(0.12, 0.11, 0.1), 9.0)
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
	for fx in [-0.4, 0.0, 0.4]:
		for fy in [-0.35, 0.35]:
			var c := map.cell_of(position + Vector2(length * fx, width * fy).rotated(facing))
			var t := map.get_t(c)
			if (t == BattleMap.T.BUSH or t == BattleMap.T.HEDGE or t == BattleMap.T.WIRE) and not under.has(c):
				under.append(c)
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
		return position + Vector2.from_angle(turret_angle) * (width * 0.35 + 26.0)
	var m: Vector2 = sl.mount
	return position + m.rotated(facing) + Vector2.from_angle(sl.angle) * 10.0


func _aim_and_fire(dt: float, now: float) -> void:
	var turret_goal := facing
	for sl in slots:
		sl.flash = maxf(0.0, sl.flash - dt)
		sl.cooldown -= dt
		var t = sl.target
		if t != null and (not is_instance_valid(t) or not t.is_alive()):
			sl.target = null
			t = null
		if sl.turret and t != null:
			turret_goal = (t.position - position).angle()
		if sl.get("beam_t", 0.0) > 0.0:
			# the lance is firing: hold the beam on the target (or the wall) as the turret tracks it
			sl.beam_t -= dt
			if sl.get("beam_point") != null and t == null:
				turret_goal = (sl.beam_point - position).angle()
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
					if sl.turret:
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
	turret_angle += clampf(tdiff, -1.3 * dt, 1.3 * dt)


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
	if sl.turret:
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
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if squad.selected or hp < max_hp:
		var bw := L * 0.8
		draw_rect(Rect2(-bw * 0.5, -L * 0.5 - 10, bw, 4), Color(0.1, 0.05, 0.04))
		draw_rect(Rect2(-bw * 0.5, -L * 0.5 - 10, bw * maxf(hp, 0) / max_hp, 4), Color(0.85, 0.7, 0.35))
	if passengers.size() > 0 and (team == main.player_team or main.autotest):
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


## Scorch marks and gouges as the hull is hurt.
func _draw_damage(L: float, Wd: float) -> void:
	if hp >= max_hp:
		return
	var n := int(float(max_hp - hp) / max_hp * 8.0) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	for k in n:
		var p := Vector2(rng.randf_range(-L * 0.4, L * 0.4), rng.randf_range(-Wd * 0.35, Wd * 0.35))
		draw_circle(p, rng.randf_range(2.5, 5.0), Color(0.03, 0.03, 0.02, 0.45))
		draw_circle(p, rng.randf_range(0.8, 1.6), Color(0.0, 0.0, 0.0, 0.8))
		if rng.randf() < 0.5:
			draw_line(p, p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3, 6), Color(0.55, 0.55, 0.5), 0.6)  # bright gouge


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
