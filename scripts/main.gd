extends Node2D
## Builds the battle, runs the simulation and turns the player's input into orders.
##
## Test without a screen:  godot --headless --fixed-fps 20 -- --autotest [--seed=N]
## (both sides are computer-controlled and the result is printed).

const SIGHT := 560.0          # how far soldiers can spot an enemy in the open
const SIGHT_HIDDEN := 260.0   # ...one in cover who hasn't fired lately
const HOLD_TO_WIN := 180.0    # seconds of holding the chapel unchallenged to win early
const OverlayScript := preload("res://scripts/overlay.gd")
const DecalsScript := preload("res://scripts/decals.gd")

var map: BattleMap
var map_view: MapView
var effects: Effects
var light_fx: LightFX
var smokes: Array = []  # lingering smoke emitters [node, time left]
var decals: Node2D
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
var rdragging := false
var previous_stage := ""  # where the last visit got to (web only), shown if it didn't finish
var ran_ok := false
var touch_mode := false       # phone / tablet controls
var touches := {}             # finger index -> screen position
var t_start := Vector2.ZERO   # where the current one-finger touch began
var t_mode := ""              # "" (maybe a tap), "line", "pan", "pinch" or "done"
var pinch_prev_dist := 0.0
var pinch_prev_center := Vector2.ZERO
var run_toggle := false
var face_mode := false
var pick_mode := false
var pointer_world := Vector2.ZERO  # where the mouse or dragging finger is on the map
var rdrag_start := Vector2.ZERO
var drag_start := Vector2.ZERO
var panning := false
var shot_path := ""  # --shot=file.png saves a screenshot (needs a display)
var shot_time := 60.0
var shot_zoom := 1.2
var walls_destroyed := 0
var cover_blocks := [0, 0]   # shots at each side stopped by low cover
var cover_time := [0.0, 0.0] # soldier-seconds spent in cover, per side
var field_time := [0.0, 0.0]
var last_wall_down = null
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
	previous_stage = Settings.last_stage()
	Settings.stage("starting (%s)" % Settings.summary())
	touch_mode = "--touch" in args or DisplayServer.is_touchscreen_available() \
			or OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")
	if touch_mode:
		_fit_touch_screen()
		get_tree().root.size_changed.connect(_fit_touch_screen)
	_build_world(seed_value)
	hud = HUD.new()
	add_child(hud)
	hud.setup(self)
	if autotest:
		print("StarFront autotest, seed %d" % seed_value)
		start_battle("legion")
		if "--demo-damage" in args:
			_demo_damage()
		if "--test-orders" in args:
			_test_orders()
	else:
		hud.show_menu()


## Test aid: exercise the line and picked-soldier orders without the computer
## player interfering, and print whether the squad kept in contact.
func _test_orders() -> void:
	ais = ais.filter(func(ai): return ai.team != 0)
	var sq: Squad = _player_squads().filter(func(q): return q.vehicle() == null and q.carrier() == null and q.members.size() >= 5)[0]
	var c := sq.center()
	var a := c + Vector2(120, -60)
	var b := c + Vector2(120, 90)
	sq.order_line(map, a, b, Vector2(1, 0), false)
	await get_tree().create_timer(8.0 / Engine.time_scale).timeout
	var out := []
	for m in sq.members:
		out.append("(%d,%d)" % [m.position.x, m.position.y])
	print("line order %s -> %s: %s coherent=%s" % [a, b, " ".join(out), sq.is_coherent()])
	sq.sub = [sq.members[0], sq.members[1]]
	sq.order_move(map, c + Vector2(600, 0), false)
	await get_tree().create_timer(8.0).timeout
	var far := 0.0
	for m in sq.sub:
		var nearest := INF
		for o in sq.members:
			if not sq.sub.has(o):
				nearest = minf(nearest, o.position.distance_to(m.position))
		far = maxf(far, nearest)
	print("picked soldiers sent 600px away: furthest from the rest %d px (limit %d), coherent=%s" % [far, Squad.COH, sq.is_coherent()])


## Test aid: shell the chapel's west wall so screenshots show every damage stage.
func _demo_damage() -> void:
	var ch := map.chapel
	var x := ch.position.x * BattleMap.CELL + 8
	var w: Dictionary = GameData.WEAPONS["siege_cannon"]
	for i in 3:
		var y := (ch.position.y + 2 + i * 4) * BattleMap.CELL + 8
		for k in i * 2 + 1:  # one, three and five hits
			_blast(Vector2(x, y), w, null, true)
	# and punch a hole in the middle of an ordinary building's north wall
	var b: Rect2i = map.buildings[1]
	var bx := (b.position.x + b.size.x / 2) * BattleMap.CELL + 8
	var by := b.position.y * BattleMap.CELL + 8
	for k in 2:
		_blast(Vector2(bx, by), GameData.WEAPONS["siege_cannon"], null, true)
	print("demo damage: %d wall cells down; building hole at %d,%d" % [walls_destroyed, bx, by])


## On a phone the screen has many tiny pixels: lay the game out for a screen about
## 620 points tall so text and buttons are a usable size.
func _fit_touch_screen() -> void:
	var win := DisplayServer.window_get_size()
	var h := 620.0
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(int(h * win.x / maxf(win.y, 1.0)), int(h))


func _build_world(seed_value: int) -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.55, 0.53, 0.53)  # dim, so fires and weapons light the scene
	add_child(cm)
	# a faint, cold light from the north-west that shows the relief everywhere
	# (no shadows: from overhead they'd stretch right across the map)
	var lights_on := Settings.on("lights", true)
	var moon := DirectionalLight2D.new()
	moon.enabled = lights_on
	moon.color = Color(0.62, 0.68, 0.85)
	moon.energy = 0.5
	moon.height = 0.3
	moon.rotation = deg_to_rad(35.0)
	add_child(moon)
	map = BattleMap.new()
	add_child(map)
	map.generate(seed_value)
	map_view = MapView.new()
	map_view.z_index = -10
	add_child(map_view)
	map_view.setup(map)
	decals = DecalsScript.new()
	decals.z_index = -5
	add_child(decals)
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
	light_fx = LightFX.new()
	light_fx.z_index = 6
	add_child(light_fx)
	light_fx.enabled_fx = Settings.on("lights", true)
	light_fx.shadows_ok = Settings.on("shadows", not Settings.is_phone())
	light_fx.setup(_light_tex if _light_tex != null else _soft_dot(256))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test-light="):  # test aid: a strong light to check the normal maps
			var xy := a.trim_prefix("--test-light=").split(",")
			var tl := PointLight2D.new()
			tl.texture = _soft_dot(256)
			tl.texture_scale = 1.6
			tl.energy = 2.2
			tl.color = Color(1.0, 0.7, 0.4)
			tl.height = 30.0
			tl.position = Vector2(float(xy[0]), float(xy[1]))
			add_child(tl)
	camera = Camera2D.new()
	camera.zoom = Vector2(1.2, 1.2)
	camera.position = Vector2(30 * BattleMap.CELL, map.world_size().y * 0.5)
	add_child(camera)
	_clamp_camera()
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
	for p in map.fire_points:
		add_fire(p)


var _dot_tex: GradientTexture2D
var _light_tex: GradientTexture2D


func add_fire(p: Vector2) -> void:
	if _dot_tex == null:
		_dot_tex = _soft_dot(64)
		_light_tex = _soft_dot(256)
	var dot := _dot_tex
	var light_tex := _light_tex
	var light := PointLight2D.new()
	light.texture = light_tex
	light.color = Color(1.0, 0.55, 0.25)
	light.energy = 1.6
	light.texture_scale = 1.6
	light.position = p
	light.enabled = Settings.on("lights", true)
	light.height = 36.0  # flames stand above the ground, so they light surfaces at an angle
	light.shadow_enabled = Settings.on("shadows", not Settings.is_phone())
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_color = Color(0, 0, 0, 0.7)
	add_child(light)
	fire_lights.append([light, 1.6, randf() * TAU])

	var fire := SimpleParticles.new()
	fire.texture = dot
	fire.position = p
	fire.amount = 40
	fire.lifetime = 0.7
	fire.emission_radius = 10.0
	fire.direction = Vector2(0, -1)
	fire.spread = 30.0
	fire.gravity = Vector2(0, -60)
	fire.velocity_min = 10.0
	fire.velocity_max = 30.0
	fire.scale_min = 0.15
	fire.scale_max = 0.35
	fire.color_ramp = _ramp([Color(1, 0.95, 0.6, 0.9), Color(1, 0.5, 0.15, 0.8), Color(0.5, 0.1, 0.05, 0)])
	fire.z_index = 4
	add_child(fire)

	var smoke := SimpleParticles.new()
	smoke.texture = dot
	smoke.position = p
	smoke.amount = 36
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0
	smoke.emission_radius = 8.0
	smoke.direction = Vector2(0.4, -1)
	smoke.spread = 20.0
	smoke.gravity = Vector2(10, -8)
	smoke.velocity_min = 12.0
	smoke.velocity_max = 22.0
	smoke.scale_min = 0.5
	smoke.scale_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_curve = curve
	smoke.color_ramp = _ramp([Color(0.15, 0.13, 0.12, 0.0), Color(0.15, 0.13, 0.12, 0.55), Color(0.3, 0.29, 0.28, 0)])
	smoke.z_index = 5
	add_child(smoke)


func _add_ash() -> void:
	var ash := SimpleParticles.new()
	ash.texture = _soft_dot(16)
	ash.amount = 110
	ash.lifetime = 9.0
	ash.preprocess = 9.0
	ash.emission_rect = Vector2(1100, 700)
	ash.direction = Vector2(1, 0.6)
	ash.spread = 25.0
	ash.gravity = Vector2(4, 6)
	ash.velocity_min = 6.0
	ash.velocity_max = 18.0
	ash.scale_min = 0.15
	ash.scale_max = 0.35
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
	Settings.stage("battle started (%s)" % Settings.summary())
	# start looking at your own force
	var c := Vector2.ZERO
	var n := 0
	for s in soldiers:
		if s.team == player_team:
			c += s.position
			n += 1
	camera.position = Vector2(c.x / maxi(n, 1) + get_viewport_rect().size.x * 0.25 / camera.zoom.x, c.y / maxi(n, 1))
	_clamp_camera()
	var f: Dictionary = GameData.FACTIONS[factions[1]]
	log_message("Scouts report %s advancing from the east. Take the chapel!" % f.name)


func _spawn_team(team: int) -> void:
	var f: Dictionary = GameData.FACTIONS[factions[team]]
	var defs: Array = f.squads
	var counts := {}
	for i in defs.size():
		var def: Dictionary = defs[i]
		var cy := int((i + 1.0) * BattleMap.H / (defs.size() + 1.0))
		if def.has("vehicle"):
			_spawn_vehicle(team, def.vehicle, cy, counts)
			continue
		var sq := Squad.new()
		sq.team = team
		sq.faction = factions[team]
		counts[def.name] = counts.get(def.name, 0) + 1
		sq.name = "%s %s" % [def.name, GameData.NUMERALS[counts[def.name] - 1]]
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
		if def.has("carrier"):
			var v := _spawn_vehicle(team, def.carrier, cy, counts)
			for s in sq.members:
				v.take_aboard(s)


func _spawn_vehicle(team: int, kind_id: String, cy: int, counts: Dictionary) -> Vehicle:
	var vd: Dictionary = GameData.VEHICLES[kind_id]
	var sq := Squad.new()
	sq.team = team
	sq.faction = factions[team]
	counts[vd.name] = counts.get(vd.name, 0) + 1
	sq.name = "%s %s" % [vd.name, GameData.NUMERALS[counts[vd.name] - 1]]
	var v := Vehicle.new()
	v.setup_vehicle(self, sq, team, kind_id)
	var cx := 11 if team == 0 else BattleMap.W - 12
	v.position = map.center_of(map.nearest_vehicle_cell(Vector2i(cx, cy)))
	v.facing = 0.0 if team == 0 else PI
	v.turret_angle = v.facing
	units_layer.add_child(v)
	soldiers.append(v)
	sq.members.append(v)
	sq.start_size = 1
	start_counts[team] += v.strength
	squads.append(sq)
	return v


# ---------------------------------------------------------------- main loop

func _process(dt: float) -> void:
	_camera_keys(dt)
	if not touch_mode:
		pointer_world = get_global_mouse_position()
	for sm in smokes.duplicate():
		sm[1] -= dt
		if sm[1] <= 0.0:
			smokes.erase(sm)
			var node: SimpleParticles = sm[0]
			node.emitting = false
			get_tree().create_timer(6.5).timeout.connect(node.queue_free)
	for fl in fire_lights:
		fl[2] += dt * 9.0
		fl[0].energy = fl[1] + sin(fl[2]) * 0.12 + randf() * 0.12
	if not started or over or paused:
		return
	time += dt
	if not ran_ok and time > 15.0:
		ran_ok = true
		Settings.stage("ran fine")
	for s in soldiers:
		s.tick(dt, time)
	_separate(dt)
	spot_timer -= dt
	if spot_timer <= 0.0:
		spot_timer = 0.25
		_update_spotting()
	for sq in squads:
		sq.think(self, dt)
	for s in soldiers:
		if s.is_alive() and not s.is_vehicle:
			field_time[s.team] += dt
			if s.in_cover:
				cover_time[s.team] += dt
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
	var vehicles_only := "--shot-vehicles" in OS.get_cmdline_user_args()
	var team_only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-team="):
			team_only = int(a.trim_prefix("--shot-team="))
	for s in soldiers:
		if s.is_alive() and (s.is_vehicle or not vehicles_only) and (team_only < 0 or s.team == team_only) \
				and (not "--shot-tank" in OS.get_cmdline_user_args() or (s.is_vehicle and s.role == "tank")):
			c += s.position
			n += 1
			if vehicles_only:
				break
	camera.position = c / maxi(n, 1)
	if "--shot-wall" in OS.get_cmdline_user_args() and last_wall_down != null:
		camera.position = last_wall_down
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-at="):
			var xy := a.trim_prefix("--shot-at=").split(",")
			camera.position = Vector2(float(xy[0]), float(xy[1]))
	camera.zoom = Vector2(shot_zoom, shot_zoom)
	if "--shot-select" in OS.get_cmdline_user_args():
		for sq in _player_squads():
			sq.selected = true
	if "--shot-nohud" in OS.get_cmdline_user_args():
		hud.visible = false
	paused = true
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("polygons skipped while painting: %d" % MapPainter.skipped)
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
			var wa := 0.0 if a.is_vehicle and not b.is_vehicle else (2.0 if b.is_vehicle else 1.0)
			var wb := 0.0 if b.is_vehicle and not a.is_vehicle else (2.0 if a.is_vehicle else 1.0)
			if a.is_vehicle and b.is_vehicle:
				wa = 1.0
				wb = 1.0
			if map.walkable(map.cell_of(a.position - push * wa)):
				a.position -= push * wa
			if map.walkable(map.cell_of(b.position + push * wb)):
				b.position += push * wb


func _update_spotting() -> void:
	for s in soldiers:
		if not s.is_alive():
			continue
		var hidden := not s.is_vehicle and map.cell_cover(map.cell_of(s.position)) > 0.2 and time - s.last_fire_time > 4.0 and not s.moving
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


func resolve_shot(shooter: Soldier, target: Soldier, w: Dictionary, muzzle: Vector2) -> void:
	shots[shooter.team] += 1
	var d := shooter.position.distance_to(target.position)
	var p: float = w.acc * lerpf(1.0, 0.45, clampf(d / w.range, 0.0, 1.0))
	if target.is_vehicle:
		p = minf(0.95, p * 1.6)  # big target, and it can't hide in a crater
	else:
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
		end += Vector2.from_angle(randf() * TAU) * randf_range(8.0, 24.0) * (2.0 if w.get("blast", 0.0) > 0.0 else 1.0)
	var show := shooter.visible or target.visible
	# a miss on a man behind low cover usually strikes the cover, chewing it up
	var lc := Vector2i(-1, -1) if target.is_vehicle else map.cover_cell(target.position, shooter.position)
	if not hit and lc.x >= 0 and randf() < 0.75:
		cover_blocks[target.team] += 1
		end = map.center_of(lc) + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		if w.get("blast", 0.0) <= 0.0:
			if map.chip_low(lc, 0.6 + float(w.get("pen", 0)) * 0.9) and show:
				effects.debris(map.center_of(lc), 6)
			elif show:
				effects.puff(end, Color(0.55, 0.5, 0.4), 3.0)
	if w.get("blast", 0.0) > 0.0:
		end = map.first_obstacle(muzzle, end)  # a stray shell bursts on the first wall in its way
	if show:
		effects.tracer(muzzle, end, w.tracer, w.width)
		_shot_lights(muzzle, end, w)
	if target.is_vehicle and hit:
		var got_in: bool = target.receive_hit(w, shooter.position, shooter)
		if show:
			if got_in:
				effects.explosion(target.position + Vector2(randf_range(-8, 8), randf_range(-8, 8)), 14.0)
			else:
				effects.spark(target.position + (shooter.position - target.position).normalized() * target.radius)
	if w.get("blast", 0.0) > 0.0:
		_blast(end, w, shooter, show)
		return
	if target.is_vehicle:
		return
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


## A shot at a spot rather than a soldier: used to blow holes in walls.
func resolve_point_shot(shooter: Soldier, p: Vector2, w: Dictionary, muzzle: Vector2) -> void:
	shots[shooter.team] += 1
	var spread: float = lerpf(3.0, 26.0, clampf(muzzle.distance_to(p) / w.range, 0.0, 1.0)) * (1.2 - w.acc)
	var end := p + Vector2.from_angle(randf() * TAU) * randf() * spread
	end = map.first_obstacle(muzzle, end + (end - muzzle).normalized() * 8.0)
	var show := shooter.visible or effects_visible_at(end)
	if show:
		effects.tracer(muzzle, end, w.tracer, w.width)
		_shot_lights(muzzle, end, w)
	_blast(end, w, shooter, show)


## The muzzle flash lights up the shooter's surroundings and the bolt, tracer or
## rocket lights the ground as it flies.
func _shot_lights(muzzle: Vector2, end: Vector2, w: Dictionary) -> void:
	var col: Color = w.tracer
	var size: float = w.width
	light_fx.flash(muzzle, col, 0.9 + size * 0.15, 36.0 + size * 10.0, 0.08)
	light_fx.streak(muzzle, end, col, 0.55 + size * 0.1, 26.0 + size * 9.0, Effects.TRACER_TIME * 1.1)


## Smoke that keeps rising from a hit for a while afterwards.
func add_smoke(pos: Vector2, duration: float, size: float) -> void:
	if not map_view.enabled:
		return
	var sm := SimpleParticles.new()
	sm.texture = _dot_tex if _dot_tex != null else _soft_dot(64)
	sm.position = pos
	sm.amount = int(14 + size * 8)
	sm.lifetime = 6.0
	sm.emission_radius = 6.0 * size
	sm.direction = Vector2(0.4, -1)
	sm.spread = 25.0
	sm.gravity = Vector2(7, -6)
	sm.velocity_min = 6.0
	sm.velocity_max = 14.0
	sm.scale_min = 0.35 * size
	sm.scale_max = 0.7 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.8))
	sm.scale_curve = curve
	sm.color_ramp = _ramp([Color(0.2, 0.19, 0.18, 0.0), Color(0.2, 0.19, 0.18, 0.45), Color(0.34, 0.33, 0.31, 0.0)])
	sm.z_index = 5
	add_child(sm)
	smokes.append([sm, duration])
	while smokes.size() > 18:
		var old: SimpleParticles = smokes.pop_front()[0]
		old.emitting = false
		get_tree().create_timer(6.5).timeout.connect(old.queue_free)


func _dust_burst(pos: Vector2, size: float) -> void:
	if not map_view.enabled:
		return
	var d := SimpleParticles.new()
	d.texture = _dot_tex if _dot_tex != null else _soft_dot(64)
	d.position = pos
	d.one_shot = true
	d.amount = 26
	d.lifetime = 2.6
	d.emission_radius = 8.0
	d.spread = 180.0
	d.gravity = Vector2(4, -3)
	d.velocity_min = 15.0
	d.velocity_max = 45.0
	d.damping = 25.0
	d.scale_min = 0.4 * size
	d.scale_max = 0.9 * size
	d.color_ramp = _ramp([Color(0.5, 0.46, 0.4, 0.6), Color(0.45, 0.42, 0.38, 0.3), Color(0.4, 0.38, 0.35, 0.0)])
	d.z_index = 5
	d.emitting = true
	add_child(d)
	get_tree().create_timer(3.0).timeout.connect(d.queue_free)


func effects_visible_at(p: Vector2) -> bool:
	for s in soldiers:
		if s.team == player_team and s.is_alive() and s.position.distance_to(p) < SIGHT:
			return true
	return autotest


## High explosive: hurts and pins every soldier near the impact, friend or foe,
## and knocks chunks out of nearby walls.
func _blast(at: Vector2, w: Dictionary, shooter: Soldier, show: bool) -> void:
	var r: float = w.blast
	if show:
		effects.explosion(at, r)
		light_fx.flash(at, Color(1.0, 0.6, 0.3), 2.4, r * 3.0 + 40.0, 0.6, true)
	decals.add_scorch(at, r * 0.7)
	if w.get("wall", 0.0) > 0.0:
		var hit_wall := map.wall_near(at, r * 0.5 + BattleMap.CELL)
		var fell := map.damage_walls(at, r, w.wall)
		walls_destroyed += fell.size()
		if hit_wall:
			add_smoke(at, 20.0 + randf() * 15.0, 1.0)  # the shattered wall smoulders
		if not fell.is_empty():
			_dust_burst(map.center_of(fell[0]), 1.4)
		for c in fell:
			effects.debris(map.center_of(c))
			last_wall_down = map.center_of(c)
			if autotest and "--log-walls" in OS.get_cmdline_user_args():
				print("  wall down at %s, t=%d" % [map.center_of(c), int(time)])
	for o in soldiers.duplicate():
		if not o.is_alive() or o.is_vehicle:
			continue
		var d: float = o.position.distance_to(at)
		if d > r * 2.5:
			continue
		o.add_suppression(w.supp * (1.0 - d / (r * 2.5)), time)
		if d < r:
			var chance: float = 0.85 * (1.0 - d / r) * (1.0 - map.cover_vs(o.position, at) * 0.6)
			if randf() < chance and randf() >= o.armor * (1.0 - w.ap):
				o.take_hit(w.dmg, shooter)


func on_vehicle_destroyed(v: Vehicle, killer: Soldier) -> void:
	if autotest:
		print("  vehicle lost: %s at %ds, killed by %s" % [v.squad.name, int(time), killer.kind if killer != null else "?"])
	effects.explosion(v.position, 40.0)
	light_fx.flash(v.position, Color(1.0, 0.55, 0.25), 3.2, 240.0, 1.3, true)
	decals.add_scorch(v.position, 40.0)
	add_fire(v.position + Vector2(randf_range(-6, 6), randf_range(-6, 6)))
	for o in soldiers:
		if o.is_alive() and not o.is_vehicle and o.team == v.team and o.position.distance_to(v.position) < 200.0:
			o.morale -= 10.0 * o.nerve
	if killer != null:
		for o in killer.squad.members:
			if o.is_alive():
				o.morale = minf(o.max_morale, o.morale + 10.0)
	if v.team == player_team or v.visible:
		var col := "#e8c070" if v.team == player_team else "#9fd0ff"
		log_message("[color=%s]%s has been destroyed![/color]" % [col, v.squad.name])


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
		if s.is_effective() and not s.is_vehicle and map.objective_rect.has_point(s.position):
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
		if s.is_present():
			eff[s.team] += s.strength
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
	var vlost := [0, 0]
	for s in soldiers:
		if s.is_alive():
			left[s.team] += 1
		elif s.state == Soldier.State.DEAD:
			dead[s.team] += 1
			if s.is_vehicle:
				vlost[s.team] += 1
		else:
			fled[s.team] += 1
	if autotest:
		print("RESULT winner=%s time=%d shots=%s hits=%s left=%s/%s dead=%s/%s fled=%s/%s vehicles_lost=%s/%s walls=%d cover=%d%%/%d%% blocked=%s %s" % [
				factions[winner] if winner >= 0 else "draw", int(time), shots, hits,
				left[0], left[1], dead[0], dead[1], fled[0], fled[1], vlost[0], vlost[1], walls_destroyed, int(100 * cover_time[0] / maxf(field_time[0], 1)), int(100 * cover_time[1] / maxf(field_time[1], 1)), cover_blocks, reason])
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


func _soldier_at(p: Vector2, team: int, extra := 8.0) -> Soldier:
	var best: Soldier = null
	var bd := INF
	for s in soldiers:
		if s.team != team or not s.is_alive() or not s.visible:
			continue
		var d := s.position.distance_to(p)
		if d < s.radius + extra and d < bd:
			bd = d
			best = s
	return best


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		_touch_input(e)
		return
	if touch_mode and (e is InputEventMouseButton or e is InputEventMouseMotion) and e.device == InputEvent.DEVICE_ID_EMULATION:
		return  # the same touch, already handled above
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
				if mb.pressed and mb.alt_pressed:
					_pick_soldier(wp)
				elif mb.pressed:
					dragging = true
					drag_start = wp
				elif dragging:
					dragging = false
					_select(drag_start, wp, mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if not started or over:
					return
				if mb.pressed:
					rdragging = true
					rdrag_start = wp
				elif rdragging:
					rdragging = false
					if mb.ctrl_pressed:
						_order_face(wp)
					elif rdrag_start.distance_to(wp) > 24.0:
						_order_line(rdrag_start, wp, mb.shift_pressed)
					else:
						_order(rdrag_start, mb.shift_pressed)
	elif e is InputEventMouseMotion and panning:
		camera.position -= (e as InputEventMouseMotion).relative / camera.zoom
		_clamp_camera()
	elif e is InputEventKey and e.is_pressed() and not e.is_echo():
		var k := (e as InputEventKey).keycode
		if k == KEY_SPACE and started and not over:
			paused = not paused
		elif k == KEY_F1:
			hud.toggle_help()
		elif k == KEY_U:
			for sq in _player_squads():
				var v = sq.vehicle()
				if sq.selected and v != null:
					v.unload()
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


## Alt+click: pick out individual soldiers of a squad to order on their own.
func _pick_soldier(wp: Vector2) -> void:
	var s := _soldier_at(wp, player_team)
	if s == null or s.is_vehicle:
		return
	if not s.squad.selected:
		for sq in squads:
			sq.selected = false
			sq.sub.clear()
		s.squad.selected = true
	if s.squad.sub.has(s):
		s.squad.sub.erase(s)
	else:
		s.squad.sub.append(s)


## The facing a line order gets: square to the line, away from where the squad is now.
func line_facing(sq: Squad, a: Vector2, b: Vector2) -> Vector2:
	var n := (b - a).orthogonal().normalized()
	var mid := (a + b) * 0.5
	if (sq.center() - mid).dot(n) > 0.0:
		n = -n
	return n


func _order_line(a: Vector2, b: Vector2, run: bool) -> void:
	var sel: Array = _player_squads().filter(func(sq): return sq.selected and not sq.alive().is_empty() and sq.vehicle() == null)
	if sel.is_empty():
		return
	# several squads share the line out between them, in order along it
	var total := 0
	for sq in sel:
		total += sq.movers().size()
	var dir := (b - a).normalized()
	sel.sort_custom(func(x, y): return (x.center() - a).dot(dir) < (y.center() - a).dot(dir))
	var done := 0
	for sq in sel:
		var n: int = sq.movers().size()
		var sa := a.lerp(b, float(done) / total)
		var sb := a.lerp(b, float(done + n - 1) / maxf(total - 1, 1))
		if sel.size() == 1:
			sa = a
			sb = b
		sq.focus = null
		sq.order_line(map, sa, sb, line_facing(sq, a, b), run)
		done += n
	effects.marker(a, Color(0.5, 1.0, 0.5))
	effects.marker(b, Color(0.5, 1.0, 0.5))


func _order_face(wp: Vector2) -> void:
	for sq in _player_squads():
		if sq.selected and not sq.alive().is_empty():
			sq.order_face(wp - sq.center())
	effects.marker(wp, Color(0.6, 0.8, 1.0))


func _select(a: Vector2, b: Vector2, add: bool) -> void:
	if not add:
		for sq in squads:
			sq.selected = false
			sq.sub.clear()
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
	var own := _soldier_at(wp, player_team)
	if own != null and own.is_vehicle and own.free_space() > 0:
		var boarding := false
		for sq in sel:
			if sq.vehicle() == null and sq.carrier() == null:
				sq.order_board(own)
				boarding = true
		if boarding:
			effects.marker(own.position, Color(0.5, 0.8, 1.0))
			return
	var enemy := _soldier_at(wp, 1 - player_team)
	if enemy == null and map.get_t(map.cell_of(wp)) == BattleMap.T.WALL:
		var shelling := false
		for sq in sel:
			if sq.can_breach():
				sq.order_fire_at(wp)
				shelling = true
		if shelling:
			effects.marker(wp, Color(1.0, 0.6, 0.2))
			return
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
		var c = sq.carrier()
		if c != null:
			c.squad.order_move(map, wp + off, run)  # troops aboard: drive their carrier
		else:
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
	var half := get_viewport_rect().size / camera.zoom * 0.5
	for axis in 2:
		if half[axis] * 2.0 >= ws[axis]:
			camera.position[axis] = ws[axis] * 0.5
		else:
			camera.position[axis] = clampf(camera.position[axis], half[axis], ws[axis] - half[axis])


# ---------------------------------------------------------------- touch

func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


## One finger: tap to select / order, drag to line a selected squad up (or to
## scroll when nothing is selected). Two fingers: scroll and pinch to zoom.
func _touch_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			if touches.is_empty() and hud.is_over_ui(st.position):
				return  # a button or panel: the interface handles it
			touches[st.index] = st.position
			if touches.size() == 1:
				t_start = st.position
				t_mode = ""
			elif touches.size() == 2:
				t_mode = "pinch"
				rdragging = false
				_pinch_begin()
		else:
			if not touches.has(st.index):
				return
			var single := touches.size() == 1
			touches.erase(st.index)
			if single:
				var wp := _screen_to_world(st.position)
				if t_mode == "line":
					rdragging = false
					_order_line(rdrag_start, wp, run_toggle)
				elif t_mode == "":
					_tap(wp)
				t_mode = ""
			elif touches.size() == 1:
				t_mode = "done"  # the finger left after a pinch shouldn't count as a tap
			if touches.size() == 2:
				_pinch_begin()
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		if not touches.has(sd.index):
			return
		touches[sd.index] = sd.position
		if touches.size() >= 2:
			var pts: Array = touches.values()
			var centre: Vector2 = (pts[0] + pts[1]) * 0.5
			var dist: float = pts[0].distance_to(pts[1])
			camera.position -= (centre - pinch_prev_center) / camera.zoom
			if pinch_prev_dist > 10.0:
				var before := _screen_to_world(centre)
				var z := clampf(camera.zoom.x * dist / pinch_prev_dist, 0.5, 3.0)
				camera.zoom = Vector2(z, z)
				camera.position += before - _screen_to_world(centre)  # zoom about the fingers
			pinch_prev_center = centre
			pinch_prev_dist = dist
			_clamp_camera()
			return
		if t_mode == "" and sd.position.distance_to(t_start) > 18.0:
			if started and not over and _player_squads().any(func(q): return q.selected and q.vehicle() == null and not q.alive().is_empty()):
				t_mode = "line"
				rdragging = true
				rdrag_start = _screen_to_world(t_start)
			else:
				t_mode = "pan"
		if t_mode == "pan":
			camera.position -= sd.relative / camera.zoom
			_clamp_camera()
		pointer_world = _screen_to_world(sd.position)


func _pinch_begin() -> void:
	var pts: Array = touches.values()
	pinch_prev_center = (pts[0] + pts[1]) * 0.5
	pinch_prev_dist = pts[0].distance_to(pts[1])


func _tap(wp: Vector2) -> void:
	if not started or over:
		return
	if face_mode:
		_order_face(wp)
		face_mode = false
		hud.sync_touch("Face", false)
		return
	var s := _soldier_at(wp, player_team, 16.0)
	if s != null:
		if pick_mode and not s.is_vehicle:
			_pick_soldier(wp)
			return
		var infantry_selected := _player_squads().any(func(q): return q.selected and q.vehicle() == null)
		if s.is_vehicle and s.free_space() > 0 and infantry_selected and not s.squad.selected:
			_order(wp, false)  # climb aboard
			return
		if s.squad.selected:
			for sq in squads:
				sq.selected = false
				sq.sub.clear()
			return
		for sq in squads:
			sq.sub.clear()
		select_squad(s.squad, false)
		return
	if _player_squads().any(func(q): return q.selected):
		_order(wp, run_toggle)


## The touch bar's buttons.
func touch_button(key: String, on: bool) -> void:
	match key:
		"Run":
			run_toggle = on
		"Face":
			face_mode = on
		"Pick":
			pick_mode = on
			if not on:
				for sq in squads:
					sq.sub.clear()
		"Halt":
			for sq in _player_squads():
				if sq.selected:
					sq.halt()
		"Unload":
			for sq in _player_squads():
				var v = sq.vehicle()
				if sq.selected and v != null:
					v.unload()
		"Squads":
			hud.set_squads_visible(on)
		"Pause":
			if started and not over:
				paused = on
		"?":
			hud.toggle_help()
