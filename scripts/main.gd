extends Node2D
## Builds the battle, runs the simulation and turns the player's input into orders.
##
## Test without a screen:  godot --headless --fixed-fps 20 -- --autotest [--seed=N]
## (both sides are computer-controlled and the result is printed).

const SIGHT := 560.0          # how far soldiers can spot an enemy in the open
const SIGHT_HIDDEN := 260.0   # ...one in cover who hasn't fired lately
const HOLD_TO_WIN := 180.0    # seconds of holding the chapel unchallenged to win early
const OverlayScript := preload("res://scripts/overlay.gd")

var map: BattleMap
var effects: Effects
var units_layer: Node2D
var overlay: Node2D
var camera: Camera2D
var hud: HUD
var soldiers: Array[Soldier] = []
var squads: Array[Squad] = []
var ais: Array[AICommander] = []
var fire_lights: Array = []  # [PointLight2D, base energy, phase]

var player_team := 0
var factions := ["legion", "sworn"]
var start_counts := [0, 0]
var time := 0.0
var battle_length := 600.0
var spot_timer := 0.0
var objective_owner := -1
var hold_streak := 0.0
var started := false
var over := false
var paused := false
var autotest := false
var dragging := false
var drag_start := Vector2.ZERO
var panning := false
var shot_path := ""  # --shot=file.png saves a screenshot (needs a display)
var shot_time := 60.0
var shot_zoom := 1.2
var shots := [0, 0]
var hits := [0, 0]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = "--autotest" in args
	var seed_value := randi()
	for a in args:
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-time="):
			shot_time = float(a.trim_prefix("--shot-time="))
		elif a.begins_with("--shot-zoom="):
			shot_zoom = float(a.trim_prefix("--shot-zoom="))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world(seed_value)
	hud = HUD.new()
	add_child(hud)
	hud.setup(self)
	if autotest:
		print("StarFront autotest, seed %d" % seed_value)
		start_battle("legion")
	else:
		hud.show_menu()


func _build_world(seed_value: int) -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.84, 0.8, 0.78)
	add_child(cm)
	map = BattleMap.new()
	add_child(map)
	map.generate(seed_value)
	units_layer = Node2D.new()
	add_child(units_layer)
	effects = Effects.new()
	effects.z_index = 6
	add_child(effects)
	overlay = OverlayScript.new()
	overlay.main = self
	overlay.z_index = 10
	add_child(overlay)
	_add_fires()
	camera = Camera2D.new()
	camera.zoom = Vector2(1.2, 1.2)
	camera.position = Vector2(30 * BattleMap.CELL, map.world_size().y * 0.5)
	add_child(camera)
	_add_ash()


# ---------------------------------------------------------------- atmosphere

func _soft_dot(size: int) -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.width = size
	gt.height = size
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = g
	return gt


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_color(1, colors[colors.size() - 1])
	for i in range(1, colors.size() - 1):
		g.add_point(float(i) / (colors.size() - 1), colors[i])
	return g


func _add_fires() -> void:
	var dot := _soft_dot(64)
	var light_tex := _soft_dot(256)
	for p in map.fire_points:
		var light := PointLight2D.new()
		light.texture = light_tex
		light.color = Color(1.0, 0.55, 0.25)
		light.energy = 1.1
		light.texture_scale = 1.6
		light.position = p
		add_child(light)
		fire_lights.append([light, 1.1, randf() * TAU])

		var fire := CPUParticles2D.new()
		fire.texture = dot
		fire.position = p
		fire.amount = 40
		fire.lifetime = 0.7
		fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		fire.emission_sphere_radius = 10.0
		fire.direction = Vector2(0, -1)
		fire.spread = 30.0
		fire.gravity = Vector2(0, -60)
		fire.initial_velocity_min = 10.0
		fire.initial_velocity_max = 30.0
		fire.scale_amount_min = 0.15
		fire.scale_amount_max = 0.35
		fire.color_ramp = _ramp([Color(1, 0.95, 0.6, 0.9), Color(1, 0.5, 0.15, 0.8), Color(0.5, 0.1, 0.05, 0)])
		fire.z_index = 4
		add_child(fire)

		var smoke := CPUParticles2D.new()
		smoke.texture = dot
		smoke.position = p
		smoke.amount = 36
		smoke.lifetime = 5.0
		smoke.preprocess = 5.0
		smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 8.0
		smoke.direction = Vector2(0.4, -1)
		smoke.spread = 20.0
		smoke.gravity = Vector2(10, -8)
		smoke.initial_velocity_min = 12.0
		smoke.initial_velocity_max = 22.0
		smoke.scale_amount_min = 0.5
		smoke.scale_amount_max = 0.9
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.3))
		curve.add_point(Vector2(1, 1.6))
		smoke.scale_amount_curve = curve
		smoke.color_ramp = _ramp([Color(0.15, 0.13, 0.12, 0.0), Color(0.15, 0.13, 0.12, 0.55), Color(0.3, 0.29, 0.28, 0)])
		smoke.z_index = 5
		add_child(smoke)


func _add_ash() -> void:
	var ash := CPUParticles2D.new()
	ash.texture = _soft_dot(16)
	ash.amount = 160
	ash.lifetime = 9.0
	ash.preprocess = 9.0
	ash.local_coords = false
	ash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ash.emission_rect_extents = Vector2(1100, 700)
	ash.direction = Vector2(1, 0.6)
	ash.spread = 25.0
	ash.gravity = Vector2(4, 6)
	ash.initial_velocity_min = 6.0
	ash.initial_velocity_max = 18.0
	ash.scale_amount_min = 0.15
	ash.scale_amount_max = 0.35
	ash.color = Color(0.85, 0.82, 0.78, 0.55)
	ash.z_index = 7
	camera.add_child(ash)


# ---------------------------------------------------------------- setup

func start_battle(player_faction: String) -> void:
	factions = [player_faction, "sworn" if player_faction == "legion" else "legion"]
	for t in 2:
		_spawn_team(t)
	ais.append(AICommander.new(self, 1))
	if autotest:
		ais.append(AICommander.new(self, 0))
	hud.build_squad_cards()
	started = true
	var f: Dictionary = GameData.FACTIONS[factions[1]]
	log_message("Scouts report %s advancing from the east. Take the chapel!" % f.name)


func _spawn_team(team: int) -> void:
	var f: Dictionary = GameData.FACTIONS[factions[team]]
	var defs: Array = f.squads
	var counts := {}
	for i in defs.size():
		var def: Dictionary = defs[i]
		var sq := Squad.new()
		sq.team = team
		sq.faction = factions[team]
		counts[def.name] = counts.get(def.name, 0) + 1
		sq.name = "%s %s" % [def.name, GameData.NUMERALS[counts[def.name] - 1]]
		var cy := int((i + 1.0) * BattleMap.H / (defs.size() + 1.0))
		var cx := 6 if team == 0 else BattleMap.W - 7
		var slots := sq.pick_slots(map, map.center_of(Vector2i(cx, cy)), def.members.size())
		for j in def.members.size():
			var s := Soldier.new()
			s.setup(self, sq, team, def.members[j])
			s.position = slots[j]
			s.facing = 0.0 if team == 0 else PI
			units_layer.add_child(s)
			soldiers.append(s)
			sq.members.append(s)
		sq.start_size = sq.members.size()
		start_counts[team] += sq.start_size
		squads.append(sq)


# ---------------------------------------------------------------- main loop

func _process(dt: float) -> void:
	_camera_keys(dt)
	for fl in fire_lights:
		fl[2] += dt * 9.0
		fl[0].energy = fl[1] + sin(fl[2]) * 0.12 + randf() * 0.12
	if not started or over or paused:
		return
	time += dt
	for s in soldiers:
		s.tick(dt, time)
	_separate(dt)
	spot_timer -= dt
	if spot_timer <= 0.0:
		spot_timer = 0.25
		_update_spotting()
	for ai in ais:
		ai.tick(dt)
	_update_objective(dt)
	_check_end()
	if shot_path != "" and time >= shot_time:
		_take_shot()


func _take_shot() -> void:
	var path := shot_path
	shot_path = ""
	var c := Vector2.ZERO
	var n := 0
	for s in soldiers:
		if s.is_alive():
			c += s.position
			n += 1
	camera.position = c / maxi(n, 1)
	camera.zoom = Vector2(shot_zoom, shot_zoom)
	paused = true
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


func _separate(dt: float) -> void:
	var k := minf(1.0, dt * 8.0)
	for i in soldiers.size():
		var a := soldiers[i]
		if not a.is_alive():
			continue
		for j in range(i + 1, soldiers.size()):
			var b := soldiers[j]
			if not b.is_alive():
				continue
			var d := b.position - a.position
			var min_d := a.radius + b.radius + 2.0
			var l2 := d.length_squared()
			if l2 >= min_d * min_d or l2 < 0.0001:
				continue
			var l := sqrt(l2)
			var push := d / l * (min_d - l) * 0.5 * k
			if map.walkable(map.cell_of(a.position - push)):
				a.position -= push
			if map.walkable(map.cell_of(b.position + push)):
				b.position += push


func _update_spotting() -> void:
	for s in soldiers:
		if not s.is_alive():
			continue
		var hidden := map.cell_cover(map.cell_of(s.position)) > 0.2 and time - s.last_fire_time > 4.0 and not s.moving
		var sight := SIGHT_HIDDEN if hidden else SIGHT
		for team in 2:
			if team == s.team:
				s.seen_by[team] = true
				continue
			var seen := false
			for o in soldiers:
				if o.team != team or not o.is_alive() or o.state == Soldier.State.ROUTING:
					continue
				var d2 := o.position.distance_squared_to(s.position)
				if d2 > sight * sight:
					continue
				if d2 < 2500.0 or map.los_clear(o.position, s.position):
					seen = true
					break
			s.seen_by[team] = seen
		s.visible = autotest or s.seen_by[player_team]


func nearest_seen_enemy(team: int, from: Vector2) -> Soldier:
	var best: Soldier = null
	var bd := INF
	for s in soldiers:
		if s.team == team or not s.is_alive() or not s.seen_by[team]:
			continue
		var d := from.distance_squared_to(s.position)
		if d < bd:
			bd = d
			best = s
	return best


func resolve_shot(shooter: Soldier, target: Soldier) -> void:
	shots[shooter.team] += 1
	var w := shooter.weapon
	var d := shooter.position.distance_to(target.position)
	var p: float = w.acc * lerpf(1.0, 0.45, clampf(d / w.range, 0.0, 1.0))
	p *= 1.0 - map.cover_vs(target.position, shooter.position)
	if shooter.moving:
		p *= 0.5
	if shooter.state == Soldier.State.PINNED:
		p *= 0.5
	p *= 1.0 - shooter.suppression / 200.0
	if target.state == Soldier.State.PINNED:
		p *= 0.75
	var hit := randf() < p
	if hit:
		hits[shooter.team] += 1
	var end := target.position
	if not hit:
		end += Vector2.from_angle(randf() * TAU) * randf_range(8.0, 24.0)
	var show := shooter.visible or target.visible
	if show:
		effects.tracer(shooter.muzzle_pos(), end, w.tracer, w.width)
	var supp: float = w.supp * (1.0 if hit else 0.6)
	target.add_suppression(supp, time)
	for o in soldiers:
		if o != target and o.team == target.team and o.is_alive() \
				and o.position.distance_squared_to(target.position) < 40.0 * 40.0:
			o.add_suppression(supp * 0.4, time)
	if hit:
		if randf() < target.armor * (1.0 - w.ap):
			if show:
				effects.spark(target.position)
			target.morale -= 1.0
		else:
			if show:
				effects.puff(target.position, Color(target.colors.blood), 5.0)
			target.take_hit(w.dmg, shooter)
	elif show:
		effects.puff(end, Color(0.55, 0.5, 0.42), 4.0)


func on_death(s: Soldier, killer: Soldier) -> void:
	for o in soldiers:
		if not o.is_alive() or o.team != s.team:
			continue
		var loss := 0.0
		if o.squad == s.squad:
			loss = 9.0 + (10.0 if s.is_leader else 0.0)
		elif o.position.distance_to(s.position) < 150.0:
			loss = 3.0
		o.morale -= loss * o.nerve
	if killer != null:
		for o in killer.squad.members:
			if o.is_alive():
				o.morale = minf(o.max_morale, o.morale + 3.0)
	if s.is_leader and (s.team == player_team or s.visible):
		log_message("%s has lost its leader!" % s.squad.name)


func on_fled(s: Soldier) -> void:
	if s.team == player_team:
		log_message("A man from %s has fled the field." % s.squad.name)


func _update_objective(dt: float) -> void:
	var count := [0, 0]
	for s in soldiers:
		if s.is_effective() and map.objective_rect.has_point(s.position):
			count[s.team] += 1
	var holder := objective_owner
	if count[0] > 0 and count[1] == 0:
		holder = 0
	elif count[1] > 0 and count[0] == 0:
		holder = 1
	if holder != objective_owner:
		objective_owner = holder
		hold_streak = 0.0
		var f: Dictionary = GameData.FACTIONS[factions[holder]]
		log_message("[color=#ffd070]%s have taken the Ashen Chapel![/color]" % f.name)
	if objective_owner >= 0:
		if count[1 - objective_owner] == 0:
			hold_streak += dt
		else:
			hold_streak = 0.0


func _check_end() -> void:
	var eff := [0, 0]
	for s in soldiers:
		if s.is_effective():
			eff[s.team] += 1
	var broken := [false, false]
	for t in 2:
		broken[t] = eff[t] <= int(start_counts[t] * 0.2)
	var names := [GameData.FACTIONS[factions[0]].name, GameData.FACTIONS[factions[1]].name]
	if broken[0] and broken[1]:
		_end(-1, "Both forces are shattered. Nobody holds the chapel.")
	elif broken[0] or broken[1]:
		var w := 1 if broken[0] else 0
		_end(w, "%s have broken. %s hold the field." % [names[1 - w], names[w]])
	elif objective_owner >= 0 and hold_streak >= HOLD_TO_WIN:
		_end(objective_owner, "%s have held the Ashen Chapel unchallenged." % names[objective_owner])
	elif time >= battle_length:
		if objective_owner >= 0:
			_end(objective_owner, "Time is up. %s hold the Ashen Chapel." % names[objective_owner])
		else:
			_end(-1, "Time is up. The chapel is still contested.")


func _end(winner: int, reason: String) -> void:
	over = true
	var left := [0, 0]
	var dead := [0, 0]
	var fled := [0, 0]
	for s in soldiers:
		if s.is_alive():
			left[s.team] += 1
		elif s.state == Soldier.State.DEAD:
			dead[s.team] += 1
		else:
			fled[s.team] += 1
	if autotest:
		print("RESULT winner=%s time=%d shots=%s hits=%s left=%s/%s dead=%s/%s fled=%s/%s %s" % [
				factions[winner] if winner >= 0 else "draw", int(time), shots, hits,
				left[0], left[1], dead[0], dead[1], fled[0], fled[1], reason])
		get_tree().quit()
		return
	var head := "DRAW"
	if winner >= 0:
		head = "VICTORY" if winner == player_team else "DEFEAT"
	hud.show_end("%s\n%s\nSurvivors: yours %d of %d, enemy %d of %d" % [head, reason,
			left[player_team], start_counts[player_team], left[1 - player_team], start_counts[1 - player_team]])


func log_message(text: String) -> void:
	if autotest:
		return
	var t := int(time)
	hud.add_message("[color=#8a8070]%d:%02d[/color]  %s" % [t / 60, t % 60, text])


# ---------------------------------------------------------------- input

func select_squad(sq: Squad, add: bool) -> void:
	if not add:
		for o in squads:
			o.selected = false
	sq.selected = not sq.selected if add else true


func _player_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for sq in squads:
		if sq.team == player_team:
			out.append(sq)
	return out


func _soldier_at(p: Vector2, team: int) -> Soldier:
	var best: Soldier = null
	var bd := INF
	for s in soldiers:
		if s.team != team or not s.is_alive() or not s.visible:
			continue
		var d := s.position.distance_to(p)
		if d < s.radius + 8.0 and d < bd:
			bd = d
			best = s
	return best


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		var wp := get_global_mouse_position()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / 1.12)
			MOUSE_BUTTON_MIDDLE:
				panning = mb.pressed
			MOUSE_BUTTON_LEFT:
				if not started or over:
					return
				if mb.pressed:
					dragging = true
					drag_start = wp
				elif dragging:
					dragging = false
					_select(drag_start, wp, mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and started and not over:
					_order(wp, mb.shift_pressed)
	elif e is InputEventMouseMotion and panning:
		camera.position -= (e as InputEventMouseMotion).relative / camera.zoom
		_clamp_camera()
	elif e is InputEventKey and e.is_pressed() and not e.is_echo():
		var k := (e as InputEventKey).keycode
		if k == KEY_SPACE and started and not over:
			paused = not paused
		elif k == KEY_F1:
			hud.toggle_help()
		elif k == KEY_H:
			for sq in _player_squads():
				if sq.selected:
					sq.halt()
		elif k >= KEY_1 and k <= KEY_9:
			var mine := _player_squads()
			var i := k - KEY_1
			if i < mine.size():
				select_squad(mine[i], (e as InputEventKey).shift_pressed)
				camera.position = mine[i].center()
				_clamp_camera()


func _select(a: Vector2, b: Vector2, add: bool) -> void:
	if not add:
		for sq in squads:
			sq.selected = false
	if a.distance_to(b) < 8.0:
		var s := _soldier_at(b, player_team)
		if s != null:
			s.squad.selected = not s.squad.selected if add else true
		return
	var box := Rect2(a, b - a).abs()
	for sq in _player_squads():
		if sq.alive().any(func(m): return box.has_point(m.position)):
			sq.selected = true


func _order(wp: Vector2, run: bool) -> void:
	var sel: Array = _player_squads().filter(func(sq): return sq.selected and not sq.alive().is_empty())
	if sel.is_empty():
		return
	var enemy := _soldier_at(wp, 1 - player_team)
	if enemy != null:
		for sq in sel:
			sq.focus = enemy
		effects.marker(enemy.position, Color(1.0, 0.3, 0.2))
		return
	var group_c := Vector2.ZERO
	for sq in sel:
		group_c += sq.center()
	group_c /= sel.size()
	for sq in sel:
		var off: Vector2 = (sq.center() - group_c).limit_length(120.0) if sel.size() > 1 else Vector2.ZERO
		sq.focus = null
		sq.order_move(map, wp + off, run)
	effects.marker(wp, Color(1.0, 0.8, 0.3) if run else Color(0.5, 1.0, 0.5))


func _zoom(f: float) -> void:
	var z := clampf(camera.zoom.x * f, 0.5, 2.5)
	camera.zoom = Vector2(z, z)
	_clamp_camera()


func _camera_keys(dt: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		camera.position += v.normalized() * 700.0 * dt / camera.zoom.x
		_clamp_camera()


func _clamp_camera() -> void:
	var ws := map.world_size()
	camera.position = camera.position.clamp(Vector2.ZERO, ws)
