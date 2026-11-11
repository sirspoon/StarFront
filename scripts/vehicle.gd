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
var shaken := 0.0
var track_phase := 0.0
var smoke_timer := 0.0


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


func can_breach() -> bool:
	for sl in slots:
		if sl.weapon.get("blast", 0.0) > 0.0:
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
	recoil = maxf(0.0, recoil - dt * 3.0)
	_drive(dt)
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
		moving = false
		return
	var target := path[path_i]
	var to := target - position
	var dist := to.length()
	if dist < 4.0:
		path_i += 1
		return
	var diff := wrapf(to.angle() - facing, -PI, PI)
	var turn := turn_rate * dt
	facing += clampf(diff, -turn, turn)
	moving = true
	if absf(diff) < 0.6:
		var spd := speed * (1.35 if running else 1.0) * sqrt(map.speed_mult(position))
		var step := minf(spd * dt, dist)
		position += Vector2.from_angle(facing) * step
		track_phase += step
	else:
		track_phase += turn * 12.0


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
		if sl.burst_left > 0:
			sl.burst_timer -= dt
			if sl.burst_timer <= 0.0:
				if t != null:
					_fire(sl, t, now)
				sl.burst_left -= 1
				sl.burst_timer = sl.weapon.gap
			continue
		var bp = breach_point() if sl.weapon.get("blast", 0.0) > 0.0 else null
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
				main.resolve_point_shot(self, bp, sl.weapon, _mount_pos(sl))
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
	if sl.turret:
		recoil = 1.0
	last_fire_time = now
	main.resolve_shot(self, t, sl.weapon, _mount_pos(sl))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var L := length
	var Wd := width
	draw_set_transform(Vector2(6, 7), facing, Vector2.ONE)
	draw_rect(Rect2(-L * 0.5, -Wd * 0.5, L, Wd), Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
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


func _draw_tracks(L: float, Wd: float) -> void:
	var tw := 8.0
	for side in [-1.0, 1.0]:
		var y: float = side * (Wd * 0.5 - tw * 0.5) - tw * 0.5
		draw_rect(Rect2(-L * 0.5, y, L, tw), Color(0.1, 0.09, 0.08))
		var off := fmod(track_phase, 5.0)
		var x := -L * 0.5 + off
		while x < L * 0.5:
			draw_line(Vector2(x, y), Vector2(x, y + tw), Color(0.22, 0.2, 0.18), 1.5)
			x += 5.0


func _hull_poly(L: float, Wd: float, inset: float, nose: float) -> PackedVector2Array:
	var h := Wd * 0.5 - inset
	return PackedVector2Array([Vector2(-L * 0.5 + 2, -h), Vector2(L * 0.5 - nose, -h), Vector2(L * 0.5, -h + nose * 0.6),
			Vector2(L * 0.5, h - nose * 0.6), Vector2(L * 0.5 - nose, h), Vector2(-L * 0.5 + 2, h)])


func _draw_legion_hull(L: float, Wd: float) -> void:
	var coat: Color = colors.coat
	var trim: Color = colors.trim
	var hull := _hull_poly(L, Wd, 5.0, 8.0)
	draw_colored_polygon(hull, coat.darkened(0.05))
	draw_polyline(hull + PackedVector2Array([hull[0]]), coat.darkened(0.5), 1.5)
	# engine deck with grille, exhausts glowing at the back
	draw_rect(Rect2(-L * 0.5 + 4, -Wd * 0.3, L * 0.22, Wd * 0.6), coat.darkened(0.3))
	for i in 5:
		var x := -L * 0.5 + 6 + i * L * 0.04
		draw_line(Vector2(x, -Wd * 0.26), Vector2(x, Wd * 0.26), coat.darkened(0.55), 1.0)
	for y in [-Wd * 0.32, Wd * 0.32]:
		draw_circle(Vector2(-L * 0.5 + 3, y), 2.2, Color(1.0, 0.45, 0.15, 0.9))
	# headlamps and panel lines
	for y in [-Wd * 0.25, Wd * 0.25]:
		draw_circle(Vector2(L * 0.5 - 3, y), 1.8, Color(1.0, 0.95, 0.7))
	draw_line(Vector2(L * 0.15, -Wd * 0.5 + 6), Vector2(L * 0.15, Wd * 0.5 - 6), coat.darkened(0.35), 1.0)
	if role == "carrier":
		# troop hatches and the rear ramp
		draw_rect(Rect2(-L * 0.15, -Wd * 0.28, L * 0.28, Wd * 0.22), coat.lightened(0.08))
		draw_rect(Rect2(-L * 0.15, Wd * 0.06, L * 0.28, Wd * 0.22), coat.lightened(0.08))
		draw_rect(Rect2(-L * 0.5 + 1, -Wd * 0.35, 4, Wd * 0.7), coat.darkened(0.4))
		_draw_sunburst(Vector2(L * 0.3, 0), 5.0, trim)
	else:
		_draw_sunburst(Vector2(L * 0.36, Wd * 0.22), 4.0, trim)


func _draw_sworn_hull(L: float, Wd: float) -> void:
	var coat: Color = colors.coat
	var trim: Color = colors.trim
	var hull := _hull_poly(L, Wd, 4.0, 12.0)
	draw_colored_polygon(hull, coat)
	draw_polyline(hull + PackedVector2Array([hull[0]]), trim, 1.8)
	# a bone-coloured armoured prow
	var prow := PackedVector2Array([Vector2(L * 0.5 - 10, -Wd * 0.2), Vector2(L * 0.5 + 3, 0), Vector2(L * 0.5 - 10, Wd * 0.2)])
	draw_colored_polygon(prow, trim.darkened(0.15))
	# glowing vents at the back
	for i in 3:
		draw_rect(Rect2(-L * 0.5 + 4, -Wd * 0.25 + i * Wd * 0.2, 6, 3), Color(1.0, 0.5, 0.15))
	# oath scroll on the deck
	draw_rect(Rect2(-L * 0.18, Wd * 0.12, L * 0.22, 5), Color(0.88, 0.82, 0.66))
	for i in 3:
		draw_line(Vector2(-L * 0.16 + i * 4, Wd * 0.12 + 1.5), Vector2(-L * 0.16 + i * 4 + 2, Wd * 0.12 + 1.5), Color(0.3, 0.2, 0.15), 1.0)
	_draw_chain_emblem(Vector2(L * 0.22, -Wd * 0.18), 4.0, trim)
	if role == "carrier":
		draw_rect(Rect2(-L * 0.2, -Wd * 0.26, L * 0.3, Wd * 0.3), coat.lightened(0.07))
		draw_rect(Rect2(-L * 0.2, -Wd * 0.26, L * 0.3, Wd * 0.3), trim.darkened(0.3), false, 1.0)


func _draw_sunburst(c: Vector2, r: float, col: Color) -> void:
	for i in 7:
		draw_line(c, c + Vector2.from_angle(i * TAU / 7.0) * r * 1.6, col, 1.0)
	draw_circle(c, r * 0.6, col)


func _draw_chain_emblem(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r * 1.4, 0, TAU, 16, col, 1.2)
	draw_arc(c + Vector2(-r * 0.4, 0), r * 0.45, 0, TAU, 10, col, 1.0)
	draw_arc(c + Vector2(r * 0.5, 0), r * 0.45, 0.6, TAU - 0.6, 10, col, 1.0)


func _draw_mount(sl: Dictionary) -> void:
	var m: Vector2 = sl.mount
	var a: float = sl.angle - facing  # we're drawing in hull space
	draw_circle(m, 4.5, Color(0.15, 0.14, 0.13))
	var heavy: bool = sl.weapon.pen >= 4
	draw_line(m, m + Vector2.from_angle(a) * 13.0, Color(0.08, 0.08, 0.08), 3.5 if heavy else 2.5)
	if sl.flash > 0.0:
		draw_circle(m + Vector2.from_angle(a) * 15.0, 4.0, Color(1.0, 0.9, 0.5, 0.9))


func _draw_turret(Wd: float) -> void:
	var a := turret_angle - facing
	var r := Wd * 0.34
	var back := Vector2.from_angle(a) * (-recoil * 6.0)
	var dir := Vector2.from_angle(a)
	var nrm := dir.orthogonal()
	var coat: Color = colors.coat
	var trim: Color = colors.trim
	var sworn := faction == "sworn"
	# barrel
	var b0 := dir * r * 0.5 + back
	var b1 := dir * (r + 28.0) + back
	draw_line(b0, b1, Color(0.1, 0.09, 0.09), 6.0 if sworn else 5.0)
	if sworn:
		for i in 3:
			var p := b0.lerp(b1, 0.35 + i * 0.2)
			draw_line(p - nrm * 3.5, p + nrm * 3.5, Color(0.55, 0.85, 1.0), 2.0)  # glowing coils
	else:
		draw_line(b1 - dir * 5.0 - nrm * 4.0, b1 - dir * 5.0 + nrm * 4.0, Color(0.1, 0.09, 0.09), 4.0)  # muzzle brake
	# turret body
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(Vector2.from_angle(a + PI / 8.0 + i * TAU / 8.0) * r)
	draw_colored_polygon(pts, coat.lightened(0.06))
	draw_polyline(pts + PackedVector2Array([pts[0]]), trim if sworn else coat.darkened(0.5), 1.5)
	if sworn:
		draw_line(dir * r * 0.55 - nrm * 4.0, dir * r * 0.55 + nrm * 4.0, Color(1.0, 0.25, 0.1), 2.0)  # sensor lenses
	else:
		draw_circle(-dir * r * 0.3 + nrm * r * 0.3, 3.5, coat.darkened(0.3))  # commander's hatch
	for sl in slots:
		if sl.turret and sl.flash > 0.0:
			var tip := dir * (r + 32.0)
			draw_circle(tip, 9.0, Color(1.0, 0.85, 0.5, 0.9) if not sworn else Color(0.75, 0.9, 1.0, 0.9))


func _draw_wreck(L: float, Wd: float) -> void:
	draw_circle(Vector2.ZERO, L * 0.75, Color(0.03, 0.03, 0.02, 0.35))
	var hull := _hull_poly(L, Wd, 3.0, 8.0)
	draw_colored_polygon(hull, Color(0.13, 0.12, 0.11))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.05, 0.05, 0.05), 2.0)
	_draw_tracks(L, Wd)
	if role == "tank":
		var a := turret_angle - facing + 0.7
		draw_circle(Vector2(-6, 4), Wd * 0.3, Color(0.17, 0.16, 0.14))
		draw_line(Vector2(-6, 4), Vector2(-6, 4) + Vector2.from_angle(a) * 30.0, Color(0.08, 0.08, 0.08), 4.0)
	draw_circle(Vector2(4, -3), 6.0, Color(0.02, 0.02, 0.02))
