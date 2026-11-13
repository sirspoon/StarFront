extends Node2D
## Builds the battle, runs the simulation and turns the player's input into orders.
##
## Test without a screen:  godot --headless --fixed-fps 20 -- --autotest [--seed=N]
## (both sides are computer-controlled and the result is printed).

const SIGHT := 560.0          # how far soldiers can spot an enemy in the open
const SIGHT_HIDDEN := 260.0   # ...one in cover who hasn't fired lately
const HOLD_TO_WIN := 240.0    # seconds of holding the chapel unchallenged to win early
const OverlayScript := preload("res://scripts/overlay.gd")
const DecalsScript := preload("res://scripts/decals.gd")

var map: BattleMap
var map_view: MapView
var roofs: Roofs
var effects: Effects
var grenades: Grenades
var mortars: Mortars
var target_mode := false  # the Target button: the next tap gives the mortars a fire mission
var grenade_mode := false
var cover_mode := false   # the Cover view (C): colours the ground by the cover it gives
var cover_view: CoverView  # the next click / tap picks where to throw grenades
var grenades_thrown := [0, 0]
var heavy_kills := [0, 0]
var friendly_kills := [0, 0]
var peeks := [0, 0]  # men leaning out round cover to shoot
var kill_sources := {}  # test aid: what killed whom ("kind" or "kind/melee")   # men killed by their own side (stray grenades, shells)
var bastion_kills := [0, 0]    # kills by the Sworn's heavy-armoured flamers and hail cannons: [flamer, hail]
var heavy_time := [0.0, 0.0]   # seconds a heavy gun was on the field, per side...
var heavy_set_time := [0.0, 0.0]  # ...and of those, set up
var light_fx: LightFX
var sfx: Sfx
var fire_sound_at := {}  # shooter+weapon -> time its burst sound last started
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
var battle_length := 0.0  # seconds; 0 = no time limit (computer-v-computer tests use 600)
var spot_timer := 0.0
var objective_owner := -1
var hold_streak := 0.0
var started := false
var over := false
var paused := false
var autotest := false
var dragging := false
var rdragging := false
var current_seed := 0
var phone := Settings.is_phone()
var previous_stage := ""  # where the last visit got to (web only), shown if it didn't finish
var ran_ok := false
var touch_mode := false       # phone / tablet controls
var touches := {}             # finger index -> screen position
var t_start := Vector2.ZERO   # where the current one-finger touch began
var t_mode := ""              # "" (maybe a tap), "line", "pan", "pinch" or "done"
var pinch_prev_dist := 0.0
var pinch_prev_center := Vector2.ZERO
var run_toggle := false
var autotest_hide_outline := false  # (kept false; a switch for comparison screenshots)
const DOUBLE_TAP_MS := 450
var tap_pending := false  # a lone tap on the ground that may become a double tap
var tap_time := 0
var tap_frame := 0
var tap_screen := Vector2.ZERO
var t_second := false       # this touch began just after a tap close by (double tap / tap-drag)
var t_press_ms := 0         # when the current one-finger touch began (for tap-hold)
const HOLD_MS := 500
var face_squads: Array = []  # squads being turned by a hold-drag
var face_anchor := Vector2.ZERO
var line_still_at := Vector2.ZERO  # while drawing a line: where the finger last moved
var line_still_ms := 0
var line_still_frame := 0
var line_b := Vector2.ZERO          # the line's end, once fixed by pausing
var board_from: Array = []  # infantry that were selected when their carrier was tapped (a double tap boards them)
var board_carrier = null    # that carrier's squad
var plan_fresh := true      # the next order replaces the selected squads' orders (else it's added to the route)
var tap_pos := Vector2.ZERO
var face_mode := false
var pointer_world := Vector2.ZERO  # where the mouse or dragging finger is on the map
var rdrag_start := Vector2.ZERO
var drag_start := Vector2.ZERO
var panning := false
var shot_path := ""  # --shot=file.png saves a screenshot (needs a display)
var shot_time := 60.0
var shot_zoom := 1.2
var walls_destroyed := 0
var perf_log := "--perf" in OS.get_cmdline_user_args()  # test aid: print the slowest frame regularly
var perf_last := 0
var perf_parts: Array = []
var draw_us := 0  # test aid: time spent building soldier drawings
var draw_n := 0
var always_draw := Settings._q().contains("alwaysdraw")  # test aid: redraw every soldier every frame (the old way)  # test aid: time spent in each part of the simulation
var perf_worst := 0.0
var perf_frames := 0
var cover_blocks := [0, 0]   # shots at each side stopped by low cover
var cover_time := [0.0, 0.0] # soldier-seconds spent in cover, per side
var field_time := [0.0, 0.0]
var last_wall_down = null
var flank_shots := [0, 0]
var no_flank := "--no-flank" in OS.get_cmdline_user_args()  # test aid: flanking off
var crossfire_time := [0.0, 0.0]
var blows := [0, 0]          # close-combat blows struck by each side
var melee_kills := [0, 0]
var assault_kills := [0, 0]  # kills by each side's assault squad (any weapon)
var shots := [0, 0]
var hits := [0, 0]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = "--autotest" in args
	var seed_value := randi()
	if Settings.next_seed >= 0:
		seed_value = Settings.next_seed  # restarting the same battle: the same battlefield
		Settings.next_seed = -1
	current_seed = seed_value
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
	if "--test-restart" in args:
		_test_restart.call_deferred()
	if Settings.next_faction != "":
		hud._choose.call_deferred(Settings.next_faction)  # restarted: straight back into battle
		Settings.next_faction = ""
	if OS.has_feature("web") and Settings._q().contains("massdemo"):
		hud._choose.call_deferred("legion")  # test aid in the browser: start, then order everyone about
		_web_mass.call_deferred()
	if autotest:
		battle_length = 1800.0  # test battles still end
		print("StarFront autotest, seed %d" % seed_value)
		start_battle("sworn" if "--side=sworn" in args else "legion")
		if "--demo-damage" in args:
			_demo_damage()
		if "--perf-blast" in args:
			_perf_blast()
		if "--test-orders" in args:
			_test_orders()
		if "--test-carrier" in args:
			_test_carrier()
		if "--test-follow" in args:
			_test_follow()
		if "--test-voice" in args:
			_test_voice()
		if "--test-mortar" in args:
			_test_mortar()
		if "--test-pace" in args:
			_test_pace()
		if "--test-grenades" in args:
			_test_grenades()
		if "--demo-flame" in args:
			_demo_flame()
		if "--demo-burn" in args:
			_demo_burn.call_deferred()
		if "--gallery" in args:
			_gallery()
		if "--test-mass" in args:
			_test_mass()
		if "--test-touch" in args:
			_test_touch()
		if "--test-reach" in args:
			_test_reach()
		if "--prone" in args:  # test aid: the Legion fights in the Down stance
			for sq in _player_squads():
				sq.set_prone(true)
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
	# a planned route: two waypoints then a line
	var c2 := sq.center()
	var w1 := c2 + Vector2(150, 0)
	var w2 := c2 + Vector2(150, 150)
	sq.enqueue(map, {"kind": "move", "a": w1, "b": w1, "face": Vector2.ZERO, "run": false}, true)
	sq.enqueue(map, {"kind": "move", "a": w2, "b": w2, "face": Vector2.ZERO, "run": false}, false)
	sq.enqueue(map, {"kind": "line", "a": w2 + Vector2(100, -60), "b": w2 + Vector2(100, 60), "face": Vector2(1, 0), "run": false}, false)
	var seen_w1 := false
	for k in 40:
		await get_tree().create_timer(1.0).timeout
		if sq.center().distance_to(w1) < 60.0:
			seen_w1 = true
	print("route: passed waypoint 1 %s, now %d px from the final line's centre, orders left %d" % [seen_w1, sq.center().distance_to(w2 + Vector2(100, 0)), sq.route().size()])
	# facing: at the end of a new route, then straight away with no route
	var w3 := sq.center() + Vector2(120, 0)
	sq.enqueue(map, {"kind": "move", "a": w3, "b": w3, "face": Vector2.ZERO, "run": false}, true)
	sq.set_final_facing(Vector2(0, 1))
	for k in 20:
		await get_tree().create_timer(1.0).timeout
	var looking := 0
	for m in sq.alive():
		if absf(wrapf(m.facing - PI / 2, -PI, PI)) < 0.3:
			looking += 1
	print("facing at end of route: squad faces %s, %d of %d men looking that way" % [sq.facing.snapped(Vector2(0.01, 0.01)), looking, sq.alive().size()])
	sq.set_final_facing(Vector2(-1, 0))
	print("facing with no route: squad now faces %s" % sq.facing)


## Test aid: one tap on your carrier selects it; a double tap makes the selected infantry board.
func _test_carrier() -> void:
	ais = ais.filter(func(ai): return ai.team != 0)
	var car: Vehicle = soldiers.filter(func(x): return x.is_vehicle and x.team == player_team and x.capacity > 0)[0]
	car.unload()
	await get_tree().create_timer(1.0).timeout
	var inf: Squad = _player_squads().filter(func(q): return q.vehicle() == null and q.carrier() == null and q.members.size() >= 5)[0]
	started = true
	select_squad(inf, false)
	_tap(car.position, Vector2(100, 100))
	await get_tree().process_frame
	print("single tap on carrier: carrier selected=%s, infantry still selected=%s" % [car.squad.selected, inf.selected])
	select_squad(inf, false)
	_tap(car.position, Vector2(100, 100))
	_double_tap(car.position)
	var boarding := inf.members.filter(func(m): return m.board_vehicle == car).size()
	await get_tree().create_timer(1.0).timeout
	print("double tap on carrier: %d men ordered to board, carrier selected=%s, infantry selected=%s" % [boarding, car.squad.selected, inf.selected])


## Test aid: during a real battle, order the player's squads to move every few
## seconds and report any soldier who didn't go, and why.
## Test aid: a squad told to lay smoke out of its reach moves up and throws two grenades;
## the screen then blocks sight through it.
## Test aid: the player's mortar team: a fire mission (HE) at a spot ahead, then smoke.
func _test_mortar() -> void:
	var sq: Squad = null
	for q in _player_squads():
		if q.has_mortars():
			sq = q
	if sq == null:
		print("mortar test: no mortar team")
		return
	sq.no_ai = true
	var open_spot := sq.center() + Vector2(40 if player_team == 0 else -40, 0)
	sq.order_move(map, open_spot, false)  # stop and set up (in the open) near where they are
	await get_tree().create_timer(12.0).timeout
	var c := sq.center()
	var spot := c + Vector2(520 if player_team == 0 else -520, 0)
	var set_up := sq.members.filter(func(m): return m.mortar and m.mortar_set >= 1.0).size()
	print("mortar test: %d tubes set up; HE mission at %s: %s" % [set_up, spot.round(), mortars.order(sq, spot)])
	var times: Array = []
	var lands: Array = []
	for i in 30:
		await get_tree().create_timer(0.5).timeout
		for g in grenades.flying:
			if g.kind == "mortar" and not g.has("seen"):
				g.seen = true
				times.append(snappedf(time, 0.1))
				lands.append(g.to.distance_to(spot))
		if times.size() >= 6:
			break
	print("  rounds fired at %s; landed %s px from the aim" % [times, lands.map(func(d): return int(d))])
	sq.mortar_kind = "smoke"
	print("  smoke mission: %s" % mortars.order(sq, spot + Vector2(0, 80)))
	var screens0 := grenades.screens.size()
	for i in 30:
		await get_tree().create_timer(0.5).timeout
		if grenades.screens.size() >= screens0 + 3:
			break
	await get_tree().create_timer(2.0).timeout
	print("  smoke screens made: %d; now loaded with %s; mission %s" % [grenades.screens.size() - screens0, sq.mortar_kind, "ended" if sq.fire_mission == null else "still on"])


## Test aid: three squads at different paces; selecting each should show its own pace.
func _test_pace() -> void:
	await get_tree().create_timer(2.0).timeout
	var inf := _player_squads().filter(func(q): return q.vehicle() == null and not q.alive().is_empty())
	inf[0].set_assault(true)
	inf[1].set_assault(false)
	inf[1].prone = false
	inf[2].set_prone(true)
	var out := []
	for i in [0, 1, 2, 0, 1]:
		select_squad(inf[i], false)
		out.append("%s=%s/%s run_toggle=%s" % [inf[i].name, pace_state(), hud.bar_icons.Pace.variant, run_toggle])
	print("pace test: " + ";  ".join(out))


func _test_grenades() -> void:
	await get_tree().create_timer(2.0).timeout
	var sq: Squad = null
	for q in _player_squads():
		if q.vehicle() == null and q.carrier() == null and q.grenade_count("smoke") > 0:
			sq = q
			break
	var c := sq.center()
	var spot := c + Vector2(260, 0)
	while not map.walkable(map.cell_of(spot)):
		spot += Vector2(0, 16)
	var before := sq.grenade_count("smoke")
	print("grenade test: %s at %s, smoke %d, ordered at %s: %s" % [sq.name, c.round(), before, spot.round(), grenades.order(sq, spot)])
	for i in 12:
		await get_tree().create_timer(2.0).timeout
		if grenades.screens.size() >= 2:
			break
	print("  after: squad at %s, smoke left %d, screens %d, order done %s" % [sq.center().round(), sq.grenade_count("smoke"), grenades.screens.size(), sq.grenade_order == null])
	await get_tree().create_timer(3.0).timeout
	var s0: Vector2 = grenades.screens[0].pos if not grenades.screens.is_empty() else spot
	print("  sight through the smoke: %s (should be false); beside it: %s" % [map.los_clear(s0 - Vector2(0, 120), s0 + Vector2(0, 120)), map.los_clear(s0 + Vector2(120, -120), s0 + Vector2(120, 120))])
	# a carrier told to smoke a spot off to its side: it should turn, then fire six
	for q in _player_squads():
		var v = q.vehicle()
		if v != null and v.launcher and v.is_alive():
			v.go_to(v.position, false)  # stop where it is
			var spot2: Vector2 = v.position + Vector2.from_angle(v.facing + PI * 0.5) * 110.0
			v.launch_kind = "smoke"  # (as if the player had switched it with Gun)
			var smoke0: int = v.launch_ammo.smoke
			var screens0 := grenades.screens.size()
			print("launcher test: %s facing %.2f, ordered at %s (%.2f off its front): %s" % [q.name, v.facing, spot2.round(),
					wrapf((spot2 - v.position).angle() - v.facing, -PI, PI), grenades.order(q, spot2)])
			for i in 16:
				await get_tree().create_timer(1.0).timeout
				if v.launch_order == null:
					break
			await get_tree().create_timer(2.0).timeout
			var near := 0
			for sc in grenades.screens.slice(screens0):
				if sc.pos.distance_to(spot2) < 70.0:
					near += 1
			print("  after: off its front %.2f, smoke salvos %d -> %d, new screens %d (%d near the spot)" % [
					wrapf((spot2 - v.position).angle() - v.facing, -PI, PI), smoke0, v.launch_ammo.smoke, grenades.screens.size() - screens0, near])
			break


func _web_mass() -> void:
	while not started:
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(2.0).timeout
	var last := Time.get_ticks_usec()
	var total := 0.0
	for f in 60:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		total += (now - last) / 1000.0
		last = now
	print("MASS before any order: average frame %.1f ms" % (total / 60.0))
	_test_mass()


static var _restart_check := {}


## Test aid: start a battle, restart it, and check the same battlefield and side came back.
func _test_restart() -> void:
	if _restart_check.is_empty():
		hud._choose("sworn")
		while not started:
			await get_tree().create_timer(0.3).timeout
		await get_tree().create_timer(1.0).timeout
		_restart_check = {"seed": current_seed, "side": factions[player_team], "buildings": map.buildings.size()}
		restart(true)
		return
	while not started:
		await get_tree().create_timer(0.3).timeout
	print("RESTART same seed %s, same side %s, same map %s" % [current_seed == _restart_check.seed,
			factions[player_team] == _restart_check.side, map.buildings.size() == _restart_check.buildings])
	get_tree().quit()


## Back into a battle from the start: the same battlefield and side, or a new battle
## (back to the title screen).
func restart(same: bool) -> void:
	if same:
		Settings.next_faction = factions[player_team]
		Settings.next_seed = current_seed
	get_tree().paused = false
	get_tree().reload_current_scene()


## Test aid: select every squad and order them all across the map at once, a few times,
## timing the order itself and the slowest frames that follow.
func _test_mass() -> void:
	ais = ais.filter(func(ai): return ai.team != 0)
	for round_i in 4:
		await get_tree().create_timer(3.0).timeout
		for sq in _player_squads():
			sq.selected = true
		var dest := Vector2((40 + round_i * 25) * BattleMap.CELL, (30 + (round_i % 2) * 40) * BattleMap.CELL)
		draw_us = 0
		var t0 := Time.get_ticks_usec()
		_order(dest, false)
		var order_ms := (Time.get_ticks_usec() - t0) / 1000.0
		draw_n = 0
		var game_t0 := time
		var worst := 0.0
		var total := 0.0
		var frames := 0
		var last := Time.get_ticks_usec()
		for f in 60:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			worst = maxf(worst, ms)
			total += ms
			frames += 1
		print("MASS order %.1f ms; next 60 frames: worst %.1f ms, average %.1f ms; drawing soldiers %.2f ms a frame, %d soldier redraws a game second" % [order_ms, worst, total / frames, draw_us / 60000.0, int(draw_n / maxf(time - game_t0, 0.01))])
		draw_us = 0
		var n: float = maxf(1.0, perf_parts[4])
		print("  engine: process %.2f ms, physics %.2f ms, objects %d, nodes %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		print("  per frame: soldiers %.2f ms, separation %.2f, spotting %.2f, squads %.2f" % [perf_parts[0] / n / 1000.0, perf_parts[1] / n / 1000.0, perf_parts[2] / n / 1000.0, perf_parts[3] / n / 1000.0])
		perf_parts = []
	get_tree().quit()


## Test aid: one of each kind of soldier lined up in the chapel square, the battle paused,
## for a screenshot (--shot-at=1280,800 --shot-time=1).
func _gallery() -> void:
	await get_tree().create_timer(0.3).timeout
	var seen := {}
	var row := [0, 0]
	for s in soldiers:
		if s.is_vehicle or seen.has(s.kind):
			continue
		seen[s.kind] = true
		if s.state == Soldier.State.EMBARKED:
			s.carrier.passengers.erase(s)
			s.state = Soldier.State.READY
			s.carrier = null
		s.position = Vector2(map.plaza.position * BattleMap.CELL) + Vector2(40 + row[s.team] * 56, 42 - s.team * 34)
		row[s.team] += 1
		s.facing = 0.0
		s.halt()
		s.visible = true
		if s.heavy:
			s.setup_t = 1.0
		if s.kind == "oathblade":
			s.in_melee = true
	for s in soldiers:
		if not seen.has(s.kind) or not s.position.distance_to(Vector2(map.plaza.position * BattleMap.CELL)) < 900:
			pass
	paused = true


## Test aid: set alight everything that will burn near --shot-at (or the map centre).
func _demo_burn() -> void:
	var at := Vector2(BattleMap.W, BattleMap.H) * BattleMap.CELL * 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-at="):
			var xy := a.trim_prefix("--shot-at=").split(",")
			at = Vector2(float(xy[0]), float(xy[1]))
	if not "--shot-at" in " ".join(OS.get_cmdline_user_args()) and not map.parks.is_empty():
		at = Vector2(map.parks[0].get_center() * BattleMap.CELL)  # a park: bushes and hedges to burn
	demo_burn_at = at
	var c0 := map.cell_of(at)
	var n := 0
	for r in range(0, 30):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				for c in [c0 + Vector2i(dx, dy), c0 + Vector2i(dy, dx)]:
					if n < 14 and map.flammable(c) and not burning.has(c):
						ignite(c)
						n += 1
	print("demo burn: %d cells alight" % n)
	await get_tree().create_timer(45.0).timeout
	var charred := 0
	for i in map.crushed.size():
		if map.crushed[i] == 20:
			charred += 1
	print("demo burn after 45 s: %d still burning, %d cells burnt away" % [burning.size(), charred])


## Test aid: a flame jet every second at --shot-at (or the map centre), to look at the drawing.
func _demo_flame() -> void:
	var at := Vector2(BattleMap.W, BattleMap.H) * BattleMap.CELL * 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-at="):
			var xy := a.trim_prefix("--shot-at=").split(",")
			at = Vector2(float(xy[0]), float(xy[1]))
	while true:
		effects.flame(at - Vector2(55, 0), at + Vector2(60, 0), 0.35)
		await get_tree().create_timer(1.0).timeout


func _test_follow() -> void:
	ais = ais.filter(func(ai): return ai.team != 0)
	if "--no-enemy" in OS.get_cmdline_user_args():
		ais.clear()  # nobody fights: checks orders away from any combat
	var stuck_total := 0
	var orders := 0
	for round_i in 30:
		await get_tree().create_timer(0.5 if round_i == 0 else 4.0).timeout
		if over:
			break
		for sq in _player_squads():
			if sq.vehicle() != null or sq.carrier() != null or sq.alive().size() < 2:
				continue
			var c := sq.center()
			var dest := c + Vector2(randf_range(80, 220), randf_range(-160, 160))
			var before := {}
			for m in sq.alive():
				before[m] = m.position
			sq.enqueue(map, {"kind": "move", "a": dest, "b": dest, "face": Vector2.ZERO, "run": false}, true)
			orders += 1
			await get_tree().create_timer(3.0).timeout
			for m in sq.alive():
				if before.has(m) and m.position.distance_to(before[m]) < 6.0 and m.position.distance_to(dest) > 60.0:
					stuck_total += 1
					print("STUCK t=%d %s state=%s supp=%d path=%d/%d wait=%s pos=%s cell=%s dist_to_dest=%d" % [time, sq.name, Soldier.State.keys()[m.state],
							m.suppression, m.path_i, m.path.size(), m.wait_for_squad, m.position, map.get_t(map.cell_of(m.position)), m.position.distance_to(dest)])
	print("FOLLOW orders=%d stuck=%d" % [orders, stuck_total])


## Test aid: give orders the way a phone does (tap a soldier, then double-tap or
## hold-drag a destination) with nobody fighting, and report anyone who didn't go.
func _test_touch() -> void:
	ais.clear()
	touch_mode = true
	var stuck := 0
	var n := 0
	for round_i in 6:
		for sq in _player_squads():
			if sq.vehicle() != null or sq.carrier() != null or sq.alive().size() < 2:
				continue
			await get_tree().create_timer(0.3).timeout
			var tapped: Soldier = sq.alive()[randi() % sq.alive().size()]
			_tap(tapped.position, Vector2(100, 100))
			var dest := sq.center() + Vector2(randf_range(100, 250), randf_range(-150, 150))
			var how: String = ["double", "line", "hold"][round_i % 3]
			match how:
				"double":
					_double_tap(dest)
				"line":
					_plan("line", dest - Vector2(0, 50), dest + Vector2(0, 50), true)
				"hold":
					_plan("move", dest, dest, false)
			var before := {}
			for m in sq.alive():
				before[m] = m.position
			await get_tree().create_timer(4.0).timeout
			n += 1
			await get_tree().create_timer(8.0).timeout
			if not sq.is_coherent():
				print("TSPLIT %s via %s:" % [sq.name, how])
				for m in sq.alive():
					print("   %s state=%s path=%d/%d wait=%s dist_to_dest=%d moved=%d run=%s prone=%s" % [m.kind, Soldier.State.keys()[m.state],
							m.path_i, m.path.size(), m.wait_for_squad, m.position.distance_to(dest), m.position.distance_to(before[m]), m.running, sq.prone])
			for m in sq.alive():
				if m.position.distance_to(before[m]) < 6.0 and m.position.distance_to(dest) > 70.0:
					stuck += 1
					print("TSTUCK %s via %s state=%s path=%d/%d wait=%s sub=%d selected=%s prone=%s dist=%d" % [sq.name, how,
							Soldier.State.keys()[m.state], m.path_i, m.path.size(), m.wait_for_squad, sq.sub.size(), sq.selected, sq.prone, m.position.distance_to(dest)])
	print("TOUCH orders=%d stuck=%d" % [n, stuck])


## Test aid: send a squad's men to spots all over the map and count spots they
## can't reach (which would leave a man standing still).
func _test_reach() -> void:
	ais.clear()
	var sq: Squad = _player_squads().filter(func(q): return q.vehicle() == null and q.carrier() == null and q.members.size() >= 5)[0]
	var bad := 0
	var total := 0
	var kinds := {}
	for i in 300:
		var dest := Vector2(randf_range(100, map.world_size().x - 100), randf_range(60, map.world_size().y - 60))
		for slot in sq.pick_slots(map, dest, sq.members.size()):
			total += 1
			var p := map.find_path(sq.members[0].position, slot)
			if p.is_empty():
				bad += 1
				var t: int = map.get_t(map.cell_of(slot))
				kinds[t] = kinds.get(t, 0) + 1
	print("REACH %d of %d spots unreachable, by terrain %s" % [bad, total, kinds])
	get_tree().quit()


## Test aid (with --side=sworn): a move order and a target order each get a spoken reply.
func _test_voice() -> void:
	await get_tree().create_timer(0.5).timeout
	var sq: Squad = _player_squads().filter(func(q): return q.vehicle() == null and q.carrier() == null)[0]
	select_squad(sq, false)
	_plan("move", sq.center() + Vector2(120, 0), sq.center() + Vector2(120, 0), true)
	print("VOICE after move order: %s %s" % [sfx.radio.playing, sfx.radio.stream.resource_path if sfx.radio.stream else "-"])
	await get_tree().create_timer(2.0).timeout
	var enemy: Soldier = soldiers.filter(func(x): return x.team != player_team and not x.is_vehicle)[0]
	enemy.visible = true
	_order(enemy.position, false)
	print("VOICE after target order: %s %s" % [sfx.radio.playing, sfx.radio.stream.resource_path if sfx.radio.stream else "-"])


## Test aid: shell the chapel's west wall so screenshots show every damage stage.
## Test aid: once the map is drawn, fire three tank shells into walls a second apart
## (with --perf, the slow frames they cause show up in the log).
func _perf_blast() -> void:
	while not map_view.ready_drawn:
		await get_tree().process_frame
	for i in 60:
		await get_tree().process_frame
	var w: Dictionary = GameData.WEAPONS["siege_cannon"]
	var b: Rect2i = map.buildings[2]
	for k in 3:
		print("PERF blast %d" % k)
		var at := map.center_of(b.position + Vector2i(2 + k * 3, 0))
		if "--perf-open" in OS.get_cmdline_user_args():
			at = Vector2(400, 300 + k * 60)  # open ground near the Legion start
		_blast(at, w, null, true)
		for i in 40:
			await get_tree().process_frame


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
	# and shells and rockets through its roof
	_blast(Vector2(bx - 40, by + 40), GameData.WEAPONS["siege_cannon"], null, true)
	_blast(Vector2(bx + 30, by + 60), GameData.WEAPONS["lance_launcher"], null, true)
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
	moon.range_item_cull_mask = 3  # the moon also lights the roofs (layer 2; fires and flashes don't)
	add_child(moon)
	map = BattleMap.new()
	add_child(map)
	map.map_type = str(Settings.saved("map_type", "town"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map.map_type = a.trim_prefix("--map=")  # test aid
	map.trenches = Settings.on("trenches", false)
	if map.map_type == "random":
		map.map_type = "town" if (seed_value % 2) == 0 else "foundry"
	map.generate(seed_value)
	if hud != null:
		hud.set_objective(map.objective_name(), map.objective_word())
	map_view = MapView.new()
	map_view.z_index = -10
	add_child(map_view)
	map_view.setup(map)
	if map_view.enabled:
		roofs = Roofs.new()
		add_child(roofs)
		if "--hide-roofs" in OS.get_cmdline_user_args():
			roofs.visible = false  # test aid
		roofs.setup(self)
	decals = DecalsScript.new()
	decals.z_index = -5
	add_child(decals)
	for arg in OS.get_cmdline_user_args():  # test aids, for finding what the drawing costs
		match arg:
			"--hide-decals": decals.visible = false
			"--decals-unlit": decals.light_mask = 0
	units_layer = Node2D.new()
	add_child(units_layer)
	effects = Effects.new()
	effects.z_index = 6
	add_child(effects)
	grenades = Grenades.new()
	add_child(grenades)
	grenades.setup(self)
	mortars = Mortars.new()
	add_child(mortars)
	mortars.setup(self)
	overlay = OverlayScript.new()
	overlay.main = self
	overlay.z_index = 10
	add_child(overlay)
	cover_view = CoverView.new()
	add_child(cover_view)
	cover_view.setup(self)
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
	sfx = Sfx.new()
	add_child(sfx)
	sfx.setup(camera)
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
	light.energy = 1.6 * Settings.light_boost()
	light.texture_scale = 1.6 * sqrt(Settings.light_boost())
	light.position = p
	light.enabled = Settings.on("lights", true)
	light.height = 36.0  # flames stand above the ground, so they light surfaces at an angle
	light.shadow_enabled = Settings.on("shadows", not Settings.is_phone())
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_color = Color(0, 0, 0, minf(0.95, 0.7 + (Settings.light_boost() - 1.0) * 0.15))
	add_child(light)
	fire_lights.append([light, 1.6 * Settings.light_boost(), randf() * TAU])

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
	smoke.amount = 50
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
	log_message("Scouts report %s advancing from the east. Take the %s!" % [f.name, map.objective_word()])


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
		if def.has("vehicles"):
			_spawn_vehicle_squad(team, def, cy, counts)
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


## A squad of vehicles (the Outriders): one squad, several vehicles, side by side.
func _spawn_vehicle_squad(team: int, def: Dictionary, cy: int, counts: Dictionary) -> void:
	var sq := Squad.new()
	sq.team = team
	sq.faction = factions[team]
	counts[def.name] = counts.get(def.name, 0) + 1
	sq.name = "%s %s" % [def.name, GameData.NUMERALS[counts[def.name] - 1]]
	var cx := 11 if team == 0 else BattleMap.W - 12
	var kinds: Array = def.vehicles
	for i in kinds.size():
		var v := Vehicle.new()
		v.setup_vehicle(self, sq, team, kinds[i])
		var c := Vector2i(cx + (i % 2) * (2 if team == 0 else -2), cy + (i - (kinds.size() - 1) / 2) * 3)
		v.position = map.center_of(map.nearest_vehicle_cell(c))
		v.facing = 0.0 if team == 0 else PI
		v.turret_angle = v.facing
		units_layer.add_child(v)
		soldiers.append(v)
		sq.members.append(v)
		start_counts[team] += v.strength
	sq.start_size = kinds.size()
	squads.append(sq)


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

var _was_paused := false


func _process(dt: float) -> void:
	if paused != _was_paused:
		# your men's outlines show more strongly while paused: redraw them
		_was_paused = paused
		for s in soldiers:
			if s.team == player_team and s.is_alive():
				s.queue_redraw()
	if perf_log:
		var now_us := Time.get_ticks_usec()
		if perf_last > 0:
			perf_worst = maxf(perf_worst, (now_us - perf_last) / 1000.0)
		perf_last = now_us
		perf_frames += 1
		if perf_frames % 40 == 0:
			print("PERF worst frame %.0f ms over last 40 frames" % perf_worst)
			perf_worst = 0.0
	_camera_keys(dt)
	if shake_amt > 0.05:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
		shake_amt = move_toward(shake_amt, 0.0, dt * 14.0)
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
	if not touch_mode:
		pointer_world = get_global_mouse_position()
	# wait for both the time and a few frames, so a slow device still sees the second tap
	if touch_mode and touches.size() == 1 and t_mode == "" and not t_second \
			and Time.get_ticks_msec() - t_press_ms >= HOLD_MS:
		# held still: release for a waypoint, or drag to spread out along the drag
		tap_pending = false
		var hw := _screen_to_world(t_start)
		var own := _soldier_at(hw, player_team, 16.0)
		face_squads = _face_targets(hw, own)
		if not face_squads.is_empty():
			t_mode = "face"  # drag to turn them (or set the facing at the end of their route)
			face_anchor = hw
			pointer_world = hw
		elif own != null:
			t_mode = "done"
			_hold(t_start)  # holding on one of your own units just selects it
		else:
			t_mode = "held"
	# drawing a line, then pausing: fix the line and go on to set the facing
	if t_mode == "line" and ((touch_mode and touches.size() == 1) or right_held) and Time.get_ticks_msec() - line_still_ms >= HOLD_MS \
			and Engine.get_process_frames() - line_still_frame > 10:
		var tp: Vector2 = touches.values()[0] if touches.size() == 1 else get_viewport().get_mouse_position()
		line_b = _screen_to_world(tp)
		if line_b.distance_to(rdrag_start) > 20.0 / camera.zoom.x:
			t_mode = "line_face"
			pointer_world = line_b
	if tap_pending and Time.get_ticks_msec() - tap_time >= DOUBLE_TAP_MS and Engine.get_process_frames() - tap_frame > 10:
		tap_pending = false
		_deselect_all()
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
	if paused and started:
		# soldiers only redraw as they act; while paused, keep their selection rings up to date
		for s in soldiers:
			if not s.is_vehicle:
				s.refresh_look()
			elif s.visible:
				s.queue_redraw()
	if not started or over or paused:
		return
	time += dt
	var crumb := 5.0 if phone else 20.0
	if "--log-mem" in OS.get_cmdline_user_args() and int(time / 30.0) != int((time - dt) / 30.0):
		# test aid: what grows over a long battle
		print("MEM %d:%02d video %d MB  static %d MB  objects %d  nodes %d  resources %d  orphans %d  patches %d  canvas items %d" % [
				int(time) / 60, int(time) % 60, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
				int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), map_view.patches_done,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		print("FRAME %d:%02d draw calls %d  primitives %d  process %.1f ms  decals %d small + %d tracks + %d scorches  lights %d" % [
				int(time) / 60, int(time) % 60, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				decals.small.size(), decals.tracks.size(), decals.marks.size(), light_fx.active.size()])
	if int(time / crumb) != int((time - dt) / crumb):
		# breadcrumbs in battle too, in case the browser's graphics give out mid-fight
		Settings.stage("in battle at %d:%02d: %d lights lit, %d tracers, %d ground marks, %d smoke screens, %d fires, %d map repairs, graphics memory %d MB (%s)" % [int(time) / 60, int(time) % 60,
				light_fx.active.size(), effects.tracers.size(), decals.small.size() + decals.tracks.size(), grenades.screens.size(), fire_lights.size(),
				map_view.patches_done, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), Settings.summary()])
	var _p0 := Time.get_ticks_usec()
	for s in soldiers:
		s.tick(dt, time)
	var _p1 := Time.get_ticks_usec()
	_separate(dt)
	var _p2 := Time.get_ticks_usec()
	spot_timer -= dt
	if spot_timer <= 0.0:
		spot_timer = 0.25
		_update_spotting()
	var _p3 := Time.get_ticks_usec()
	for sq in squads:
		sq.think(self, dt)
		sq.advance(map)
	var _p4 := Time.get_ticks_usec()
	if perf_parts.size() == 0:
		perf_parts = [0.0, 0.0, 0.0, 0.0, 0]
	perf_parts[0] += _p1 - _p0
	perf_parts[1] += _p2 - _p1
	perf_parts[2] += _p3 - _p2
	perf_parts[3] += _p4 - _p3
	perf_parts[4] += 1
	for s in soldiers:
		if s.is_alive() and not s.is_vehicle:
			field_time[s.team] += dt
			if s.in_cover:
				cover_time[s.team] += dt
			if s.heavy:
				heavy_time[s.team] += dt
				if s.is_set_up():
					heavy_set_time[s.team] += dt
			if s.squad.in_crossfire(time):
				crossfire_time[s.team] += dt
	for ai in ais:
		ai.tick(dt)
	_update_burning(dt)
	_update_objective(dt)
	_check_end()
	if shot_path != "" and time >= shot_time and (not "--shot-melee" in OS.get_cmdline_user_args() or _melee_spot() != null) \
			and (not "--shot-heavy" in OS.get_cmdline_user_args() or _heavy_spot() != null) \
			and (not "--shot-peek" in OS.get_cmdline_user_args() or _peek_spot() != null) \
			and (not "--shot-beam" in OS.get_cmdline_user_args() or _beam_frames() > 6) \
			and (not "--shot-flame" in OS.get_cmdline_user_args() or effects.flames.any(func(f): return f.t > 0.12)):
		_take_shot()


var beam_seen := 0


## Test aid: how many frames in a row a beam has been firing.
func _beam_frames() -> int:
	beam_seen = beam_seen + 1 if not effects.beams.is_empty() else 0
	return beam_seen


## Test aid: a man leaning right out round cover and firing, or null.
func _peek_spot():
	for s in soldiers:
		if s.is_alive() and not s.is_vehicle and s.peek_t > 0.0 and absf(s.lean) > 0.95 and s.flash > 0.0:
			return s.position
	return null


## Test aid: a heavy gun set up and firing (of the side given by --shot-team, if any), or null.
func _heavy_spot():
	var team_only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-team="):
			team_only = int(a.trim_prefix("--shot-team="))
	for s in soldiers:
		if s.is_alive() and s.heavy and s.is_set_up() and s.flash > 0.0 and (team_only < 0 or s.team == team_only):
			return s.position
	return null


## Test aid: where a close fight is going on (several men locked in melee), or null.
func _melee_spot():
	for s in soldiers:
		if s.is_alive() and s.in_melee and (s.swing > 0.6 or s.charger):
			var n := 0
			for o in soldiers:
				if o.is_alive() and o.in_melee and o.position.distance_to(s.position) < 60.0:
					n += 1
			if n >= 4:
				return s.position
	return null


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
	var squad_shot := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-squad="):  # centre on one of the player's squads (by number)
			var q: Squad = _player_squads()[int(a.trim_prefix("--shot-squad="))]
			camera.position = q.center()
			if "--shot-paused" in OS.get_cmdline_user_args():
				paused = true
				for s2 in soldiers:
					s2.queue_redraw()
			if "--shot-pick" in OS.get_cmdline_user_args():
				q.selected = true
				if "--shot-pace=run" in OS.get_cmdline_user_args():
					cycle_pace()
				elif "--shot-pace=down" in OS.get_cmdline_user_args():
					cycle_pace()
					cycle_pace()
				hud._refresh()  # show the unit card in the shot
	if "--shot-melee" in OS.get_cmdline_user_args():
		camera.position = _melee_spot()
	if demo_burn_at != null:
		camera.position = demo_burn_at
	if "--shot-beam" in OS.get_cmdline_user_args() and not effects.beams.is_empty():
		camera.position = (effects.beams[0].from + effects.beams[0].to) * 0.5
	if "--shot-heavy" in OS.get_cmdline_user_args():
		camera.position = _heavy_spot()
	if "--shot-peek" in OS.get_cmdline_user_args():
		camera.position = _peek_spot()
	if "--shot-flame" in OS.get_cmdline_user_args():
		var fl: Dictionary = effects.flames.filter(func(f): return f.t > 0.12)[0]
		camera.position = (fl.from + fl.to) * 0.5
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
	if "--shot-noroofs" in OS.get_cmdline_user_args() and roofs != null:
		roofs.visible = false
	if "--shot-cover" in OS.get_cmdline_user_args():
		cover_mode = true
		hud.show_cover_key(true)
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
			if (a.squeeze > 0.0 or b.squeeze > 0.0) and not a.is_vehicle and not b.is_vehicle:
				continue  # one of them is squeezing past
			var l := sqrt(l2)
			var push := d / l * (min_d - l) * 0.5 * k
			var wa := 0.0 if a.is_vehicle and not b.is_vehicle else (2.0 if b.is_vehicle else 1.0)
			var wb := 0.0 if b.is_vehicle and not a.is_vehicle else (2.0 if a.is_vehicle else 1.0)
			if a.is_vehicle and b.is_vehicle:
				wa = 1.0
				wb = 1.0
			elif not a.is_vehicle and not b.is_vehicle and a.moving != b.moving:
				# a man standing still steps aside for one who is walking
				wa = 0.2 if a.moving else 1.8
				wb = 0.2 if b.moving else 1.8
			if map.walkable(map.cell_of(a.position - push * wa)):
				a.position -= push * wa
			if map.walkable(map.cell_of(b.position + push * wb)):
				b.position += push * wb


func _update_spotting() -> void:
	for s in soldiers:
		if not s.is_alive():
			continue
		var quiet := time - s.last_fire_time > 4.0
		var hidden := not s.is_vehicle and map.cell_cover(map.cell_of(s.position)) > 0.2 and quiet and not s.moving
		var sight := SIGHT_HIDDEN if hidden else SIGHT
		if not s.is_vehicle and s.posture == "prone" and quiet:
			sight = minf(sight, SIGHT_HIDDEN if map.cell_cover(map.cell_of(s.position)) > 0.0 else 380.0)
		for team in 2:
			if team == s.team:
				s.seen_by[team] = true
				continue
			var seen := false
			for o in soldiers:
				if o.team != team or not o.is_alive() or o.state == Soldier.State.ROUTING:
					continue
				var d2 := o.position.distance_squared_to(s.position)
				var os := sight
				if o.heavy and o.is_set_up():
					os = minf(SIGHT, sight * 1.7)  # a gun team watching its arc picks out men in cover further off
				if d2 > os * os:
					continue
				if d2 < 2500.0 or map.los_clear(o.position, s.exposed_pos()):
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
	if w.get("flame", false):
		resolve_flame(shooter, target, w, muzzle)
		return
	shots[shooter.team] += 1
	_fire_sound(shooter, w, muzzle)
	var d := shooter.position.distance_to(target.position)
	var p: float = w.acc * lerpf(1.0, 0.45, clampf(d / w.range, 0.0, 1.0)) * GameData.ACCURACY
	if target.is_vehicle:
		p = minf(0.95, p * 1.6)  # big target, and it can't hide in a crater
	else:
		p *= 1.0 - map.cover_vs(target.exposed_pos(), shooter.position)
	if shooter.is_vehicle and float(w.get("blast", 0.0)) <= 0.0:
		p *= 1.5  # a vehicle's guns are on steady mounts
	if shooter.moving:
		p *= 0.3 if shooter.running else 0.5  # assaulting: firing on the run
	if target.charging != null:
		p *= 0.75  # closing fast: hard to track
	elif shooter.posture == "prone" and shooter.state != Soldier.State.PINNED:
		p *= 1.25  # lying flat, braced: a steadier aim
	if shooter.state == Soldier.State.PINNED:
		p *= 0.5
	if not shooter.is_vehicle and shooter.peek_t > 0.0:
		p *= 0.6  # snatching a shot leaning out round cover
	if shooter.heavy and not shooter.is_vehicle:
		p *= GameData.HEAVY_SET_UP if shooter.is_set_up() else GameData.HEAVY_LOOSE  # braced on its tripod, or wild
	p *= 1.0 - shooter.suppression / 200.0
	# flanking: fire from well off the squad's front, with no cover in the way, hits
	# more often and rattles them more (moderately: this is tactics, not a wipe-out)
	var flank := 0.0
	if not target.is_vehicle:
		flank = target.squad.note_fire(shooter.position - target.position, time)
		if map.cover_vs(target.exposed_pos(), shooter.position) >= 0.25 or target.data.get("steadfast", false) or no_flank:
			flank = 0.0
		flank *= float(shooter.data.get("flank_bonus", 1.0)) if not shooter.is_vehicle else 1.0
		p *= 1.0 + 0.25 * flank
		if flank > 0.0:
			flank_shots[shooter.team] += 1
	if target.posture == "prone" and not target.is_vehicle:
		p *= 0.7  # a man lying flat is a small target
		var tt := map.get_t(map.cell_of(target.position))
		if tt == BattleMap.T.RUBBLE or tt == BattleMap.T.CRATER or tt == BattleMap.T.TRENCH:
			p *= 0.7  # ...and flat in rubble, a crater or a trench, very hard to hit
	elif target.posture == "crouch":
		p *= 0.9
	var hit := randf() < p
	if hit:
		hits[shooter.team] += 1
	var end := target.position
	if not hit:
		end += Vector2.from_angle(randf() * TAU) * randf_range(8.0, 24.0) * (2.0 if w.get("blast", 0.0) > 0.0 else 1.0)
	var show := shooter.visible or target.visible
	# a miss on a man behind low cover usually strikes the cover, chewing it up
	var lc := Vector2i(-1, -1) if target.is_vehicle else map.cover_cell(target.exposed_pos(), shooter.position)
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
				var sp := target.position + (shooter.position - target.position).normalized() * target.radius
				effects.spark(sp)
				sfx.play("clang", sp, 0.0, 0.12)
				if randf() < 0.5:
					_ricochet(sp, target.position - shooter.position, w)
	if w.get("blast", 0.0) > 0.0:
		_blast(end, w, shooter, show)
		return
	if target.is_vehicle:
		return
	var supp: float = w.supp * (1.0 if hit else 0.6) * (1.0 + 0.3 * flank)
	target.add_suppression(supp, time)
	for o in soldiers:
		if o != target and o.team == target.team and o.is_alive() \
				and o.position.distance_squared_to(target.position) < 40.0 * 40.0:
			o.add_suppression(supp * 0.4, time)
	if hit:
		if randf() < target.armor * (1.0 - w.ap):
			if show:
				effects.spark(target.position)
				if randf() < 0.4:
					_ricochet(target.position, target.position - shooter.position, w)
			target.morale -= 1.0
		elif randf() > GameData.LETHALITY:
			# only a graze, or it tore through his kit: no wound, but a nasty fright
			if show:
				effects.puff(target.position, Color(0.5, 0.45, 0.38), 3.0)
			target.add_suppression(float(w.supp) * 0.5, time)
			target.morale -= 2.0 * target.nerve
		else:
			var away := (target.position - shooter.position).normalized()
			if show:
				effects.puff(target.position, Color(target.colors.blood), 5.0)
			if target.max_hp == 1 or randf() < 0.5:
				spray_blood(target, away, 0.7 + float(w.dmg) * 0.2)
			target.take_hit(w.dmg, shooter)
	else:
		# the miss lands somewhere: off cover or a wall it may glance, in the open it scorches the ground
		var t_end := map.get_t(map.cell_of(end))
		var hard := t_end == BattleMap.T.WALL or t_end == BattleMap.T.LOW or t_end == BattleMap.T.WRECK or lc.x >= 0
		if show:
			effects.puff(end, Color(0.55, 0.5, 0.42), 4.0)
			if hard and randf() < 0.25:
				_ricochet(end, end - muzzle, w)
		if randf() < (0.5 if float(w.get("pen", 0)) >= 2.0 else 0.2):
			decals.add_burn(end, 1.2 + float(w.get("pen", 0)) * 0.25)


## The Legion tank's lumen lance: a sustained beam. beam_start when it opens up; beam_tick
## every frame while it holds: the beam runs from the muzzle along the turret's aim until it
## meets a wall (which it melts) or a vehicle (which it burns into); men in its path are burnt,
## and anything flammable where it lands catches fire.
func beam_start(v: Vehicle, sl: Dictionary) -> void:
	sfx.play("beam", v.position, 2.0, 0.04)
	sl.beam_acc = 0.0
	sl.beam_n = 0
	sl.beam_vhit = 0.0
	shake(v.position, 2.0)


func beam_tick(v: Vehicle, sl: Dictionary, dt: float) -> void:
	var w: Dictionary = sl.weapon
	var from: Vector2 = v._mount_pos(sl)
	var dir := Vector2.from_angle(v.turret_angle)
	var far := from + dir * float(w.range)
	var end := map.first_obstacle(from, far)
	var hit_vehicle: Vehicle = null
	var best := from.distance_to(end)
	for o in soldiers:
		if o == v or not o.is_alive() or not o.is_vehicle or o.team == v.team:
			continue  # (the crew lay the beam over their own side's vehicles and men)
		var k := (o.position - from).dot(dir)
		if k > 0.0 and k < best and (from + dir * k).distance_to(o.position) < o.radius:
			best = k
			hit_vehicle = o
	if hit_vehicle != null:
		end = from + dir * (best - hit_vehicle.radius * 0.5)
	var show := v.visible or effects_visible_at(end)
	if show:
		effects.beam(from, end, w.tracer, w.width, v.get_instance_id())
	_beam_lights(sl, from, end, show)
	sl.beam_acc = float(sl.get("beam_acc", 0.0)) + dt
	if sl.beam_acc < 0.2:
		return
	sl.beam_acc -= 0.2
	# every fifth of a second: burn what's in the beam. A longer beam does the same harm in all,
	# spread over its length (dose: the share of the old 1.3 s beam's harm per tick)
	var dose := float(w.get("dose", 1.0))
	if show:
		effects.spark(end)
		effects.puff(end, Color(0.35, 0.3, 0.27), 6.0)
	decals.add_burn(end + Vector2(randf_range(-3, 3), randf_range(-3, 3)), 2.6)
	sl.beam_n = int(sl.get("beam_n", 0)) + 1
	if sl.beam_n % 6 == 0:
		sfx.play("beam", v.position, 2.0, 0.04)  # keep the hum going
	if hit_vehicle != null:
		sl.beam_vhit = float(sl.get("beam_vhit", 0.0)) + 0.5 * dose
		if sl.beam_vhit >= 1.0:  # burning through the armour
			sl.beam_vhit -= 1.0
			if hit_vehicle.receive_hit(w, v.position, v) and show:
				effects.explosion(end, 10.0)
	elif map.blocks(map.get_t(map.cell_of(end + dir * 4.0))):
		var fell := map.damage_walls(end + dir * 4.0, 10.0, float(w.wall) * 0.2 * dose)
		walls_destroyed += fell.size()
		for c in fell:
			effects.debris(map.center_of(c))
			last_wall_down = map.center_of(c)
		if not fell.is_empty():
			sfx.play("collapse", map.center_of(fell[0]))
	var length := from.distance_to(end)
	for s in soldiers.duplicate():
		if s.is_vehicle or not s.is_alive() or s.state == Soldier.State.EMBARKED or s.team == v.team:
			continue
		var k: float = (s.position - from).dot(dir)
		if k < 0.0 or k > length + 8.0:
			continue
		var off: float = (from + dir * k).distance_to(s.position)
		if off > s.radius + 4.0:
			if off < 40.0 and s.team != v.team:
				s.add_suppression(6.0, time)  # the beam sweeping past
			continue
		s.add_suppression(float(w.supp) * 0.3 * maxf(dose, 0.6), time)
		if randf() < 0.25 * dose * GameData.LETHALITY and randf() >= s.armor * (1.0 - float(w.ap)):
			s.take_hit(int(w.dmg), v)
	for k in 3:  # whatever burns at the far end catches
		var c := map.cell_of(end + Vector2(randf_range(-10, 10), randf_range(-10, 10)))
		if map.flammable(c) and randf() < 0.25 * maxf(dose, 0.5):
			ignite(c)


## The lance's own lights (one at the strike, one along the beam, and on PCs one at the
## muzzle), kept for the gun and moved with the beam every frame: steadier and much cheaper
## than starting fresh flashes several times a second.
func _beam_lights(sl: Dictionary, from: Vector2, end: Vector2, show: bool) -> void:
	if not sl.has("beam_lights"):
		var ls: Array = []
		if light_fx.enabled_fx and light_fx.tex != null:
			for k in (2 if Settings.is_phone() else 3):
				var l := PointLight2D.new()
				l.texture = light_fx.tex
				l.height = 20.0
				light_fx.add_child(l)
				ls.append(l)
		sl.beam_lights = ls
	var ls: Array = sl.beam_lights
	if ls.is_empty():
		return
	var boost: float = light_fx.boost
	var flick := 0.85 + randf() * 0.3
	var blen := from.distance_to(end)
	var spots := [[end, Color(1.0, 0.55, 0.25), 2.6, 110.0], [from.lerp(end, 0.5), Color(1.0, 0.5, 0.22), 1.4, clampf(blen * 0.55, 60.0, 240.0)],
			[from, Color(1.0, 0.65, 0.35), 1.7, 70.0]]
	for k in ls.size():
		var l: PointLight2D = ls[k]
		l.enabled = show
		l.position = spots[k][0]
		l.color = spots[k][1]
		l.energy = float(spots[k][2]) * 1.3 * boost * flick
		l.texture_scale = float(spots[k][3]) / 128.0 * sqrt(boost)


## The beam has stopped: its lights go out.
func beam_stop(sl: Dictionary) -> void:
	for l in sl.get("beam_lights", []):
		l.enabled = false


## The main gun of a tank going off: a great flash, a shockwave ring, gunsmoke, dust kicked up
## round the hull, the tank rocking back, and the ground shaking under the camera if it's close.
func big_gun_fx(v: Vehicle, muzzle: Vector2, dir: Vector2) -> void:
	v.hull_kick = 1.0
	if not (v.visible or effects_visible_at(muzzle)):
		return
	var col: Color = Color(0.75, 0.9, 1.0) if v.faction == "sworn" else Color(1.0, 0.8, 0.5)
	effects.muzzle_blast(muzzle, dir, col)
	light_fx.flash(muzzle, col, 3.5, 260.0, 0.35, true)
	for k in 3:
		effects.puff(muzzle + dir * (8.0 + k * 7.0) + dir.orthogonal() * randf_range(-6, 6), Color(0.5, 0.48, 0.45), 10.0 + k * 3.0)
	_dust_burst(v.position, 1.6)
	add_smoke(muzzle + dir * 12.0, 5.0, 1.0)
	shake(muzzle, 5.0)


var shake_amt := 0.0


## Shake the camera, more the closer the thing is to the middle of the view.
func shake(at: Vector2, amount: float) -> void:
	var d := at.distance_to(camera.position)
	shake_amt = maxf(shake_amt, amount * clampf(1.0 - d / 900.0, 0.0, 1.0))


## Blood sprayed away from a hit (away: the direction the blow or round was travelling),
## splashed up a wall too if he was standing close in front of one.
func spray_blood(s: Soldier, away: Vector2, amount: float) -> void:
	var col := Color(s.colors.blood)
	decals.add_blood(s.position + away * 2.0, away, amount, col)
	for d in [8.0, 13.0, 18.0, 24.0, 30.0]:
		var p: Vector2 = s.position + away * d
		if map.blocks(map.get_t(map.cell_of(p))):
			decals.add_wall_blood(s.position + away * (d - 3.0), away, amount * (1.3 - d / 40.0), col)
			break


## A jet of fire: it fills a narrow cone out to its reach (stopped by walls), licking round
## cover, and burns and terrifies everyone in it.
func resolve_flame(shooter: Soldier, target: Soldier, w: Dictionary, muzzle: Vector2) -> void:
	shots[shooter.team] += 1
	_fire_sound(shooter, w, muzzle)
	var dir := (target.position - muzzle).normalized()
	var reach: float = w.range
	var end := map.first_obstacle(muzzle, muzzle + dir * reach)
	var show := shooter.visible or target.visible
	if show:
		effects.flame(muzzle, end, w.cone)
		light_fx.flash(muzzle.lerp(end, 0.5), Color(1.0, 0.55, 0.2), 2.2, 160.0, 0.5)
	for k in 3:
		decals.add_burn(muzzle.lerp(end, 0.45 + k * 0.25) + Vector2(randf_range(-5, 5), randf_range(-5, 5)), 2.0)
	# anything that burns in the jet's path may catch: bushes, hedges, crates, barricades, furniture
	var steps := int(muzzle.distance_to(end) / 8.0)
	var lit := {}
	for k in range(2, steps + 1):
		var p := muzzle.lerp(end, float(k) / steps)
		for off in [Vector2.ZERO, (end - muzzle).normalized().orthogonal() * 8.0 * float(k) / steps, -(end - muzzle).normalized().orthogonal() * 8.0 * float(k) / steps]:
			var c := map.cell_of(p + off)
			if not lit.has(c) and map.flammable(c) and randf() < 0.3:
				lit[c] = true
				ignite(c)
	for e in soldiers.duplicate():
		if e.team == shooter.team or not e.is_alive() or e.state == Soldier.State.EMBARKED:
			continue
		var v: Vector2 = e.position - muzzle
		var d := v.length()
		if d > reach + e.radius or d < 1.0:
			continue
		if absf(wrapf(v.angle() - dir.angle(), -PI, PI)) > float(w.cone) + atan(e.radius / d):
			continue
		if not map.los_clear(muzzle, e.position):
			continue
		if e.is_vehicle:
			if randf() < 0.5:
				e.receive_hit(w, shooter.position, shooter)
			continue
		e.add_suppression(float(w.supp) * (1.0 - d / reach * 0.4), time)
		e.morale -= 3.0 * e.nerve  # men fear fire above all
		var p: float = w.acc * (1.0 - map.cover_vs(e.position, shooter.position) * 0.35) * GameData.LETHALITY  # flames get round cover
		if e.posture == "prone":
			p *= 0.85
		if randf() < p:
			hits[shooter.team] += 1
			if randf() < e.armor * (1.0 - float(w.ap)):
				continue  # his armour shrugs it off
			e.take_hit(int(w.dmg), shooter)


var burning := {}       # cell -> {t: seconds left, nodes: [fire, smoke], light}
var burn_timer := 0.0
var demo_burn_at = null  # test aid
const MAX_BURNING := 24


## Set a cell alight (bushes, hedges, crates, barricades, furniture): it burns for half a
## minute or so, may spread to its neighbours, frightens anyone in it, then goes out.
func ignite(c: Vector2i) -> void:
	if burning.has(c) or burning.size() >= (8 if phone else MAX_BURNING) or not map.flammable(c):
		return
	var p := map.center_of(c)
	var entry := {"t": randf_range(18.0, 35.0), "nodes": [], "light": null}
	if map_view.enabled:
		entry.nodes = _small_fire(p)
		if not phone and burning.values().filter(func(e): return e.light != null).size() < 6:
			var l := PointLight2D.new()
			l.texture = _light_tex if _light_tex != null else _soft_dot(256)
			l.color = Color(1.0, 0.55, 0.25)
			l.energy = 1.1 * Settings.light_boost()
			l.texture_scale = 0.8 * sqrt(Settings.light_boost())
			l.position = p
			l.enabled = Settings.on("lights", true)
			l.height = 24.0
			add_child(l)
			entry.light = l
	burning[c] = entry


func _small_fire(p: Vector2) -> Array:
	if _dot_tex == null:
		_dot_tex = _soft_dot(64)
		_light_tex = _soft_dot(256)
	var fire := SimpleParticles.new()
	fire.texture = _dot_tex
	fire.position = p
	fire.amount = 16
	fire.lifetime = 0.6
	fire.emission_radius = 6.0
	fire.direction = Vector2(0, -1)
	fire.spread = 30.0
	fire.gravity = Vector2(0, -50)
	fire.velocity_min = 8.0
	fire.velocity_max = 22.0
	fire.scale_min = 0.12
	fire.scale_max = 0.26
	fire.color_ramp = _ramp([Color(1, 0.95, 0.6, 0.9), Color(1, 0.5, 0.15, 0.8), Color(0.5, 0.1, 0.05, 0)])
	fire.z_index = 4
	fire.emitting = true
	add_child(fire)
	var smoke := SimpleParticles.new()
	smoke.texture = _dot_tex
	smoke.position = p
	smoke.amount = 14
	smoke.lifetime = 3.5
	smoke.emission_radius = 5.0
	smoke.direction = Vector2(0.4, -1)
	smoke.spread = 20.0
	smoke.gravity = Vector2(8, -6)
	smoke.velocity_min = 8.0
	smoke.velocity_max = 16.0
	smoke.scale_min = 0.3
	smoke.scale_max = 0.6
	smoke.color_ramp = _ramp([Color(0.15, 0.13, 0.12, 0.0), Color(0.15, 0.13, 0.12, 0.45), Color(0.3, 0.29, 0.28, 0)])
	smoke.z_index = 5
	smoke.emitting = true
	add_child(smoke)
	return [fire, smoke]


func _update_burning(dt: float) -> void:
	burn_timer -= dt
	if burn_timer > 0.0 or burning.is_empty():
		return
	burn_timer = 0.5
	for c in burning.keys():
		var e: Dictionary = burning[c]
		e.t -= 0.5
		var p := map.center_of(c)
		if e.light != null:
			e.light.energy = (0.9 + randf() * 0.4) * Settings.light_boost()
		for s in soldiers:  # men caught in the flames
			if s.is_alive() and not s.is_vehicle and s.state != Soldier.State.EMBARKED and s.position.distance_to(p) < 12.0:
				s.add_suppression(10.0, time)
				if randf() < 0.04 * GameData.LETHALITY:
					s.take_hit(1, null)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:  # it spreads, slowly
			var n: Vector2i = c + d
			var t := map.get_t(n)
			if (t == BattleMap.T.BUSH or t == BattleMap.T.HEDGE or t == BattleMap.T.LOW) and randf() < 0.004:
				ignite(n)
		if e.t <= 0.0:
			burning.erase(c)
			for nd in e.nodes:
				nd.emitting = false
				get_tree().create_timer(4.0).timeout.connect(nd.queue_free)
			if e.light != null:
				e.light.queue_free()
			if map.get_t(c) == BattleMap.T.FLOOR:
				decals.add_scorch(p, 9.0)  # the room's furnishings burnt black
			map.burn_out(c)


## A blow in close combat: armour may turn it, otherwise it wounds.
func resolve_blow(attacker: Soldier, foe: Soldier, m: Dictionary, landed: bool) -> void:
	blows[attacker.team] += 1
	var show := attacker.visible or foe.visible
	var at := foe.position + (attacker.position - foe.position).normalized() * foe.radius
	if not landed:
		if m.blade and foe.melee.blade and show and randf() < 0.6:
			sfx.play("melee_blade", at, 0.0, 0.05)  # blade on blade
			effects.spark(at)
		return
	if show:
		sfx.play(m.sound, at, 0.0, 0.05)
	if randf() < foe.armor * (1.0 - float(m.ap)):
		if show:
			effects.spark(at)  # glances off his armour
		foe.morale -= 1.0
		return
	if randf() > (GameData.MELEE_LETHALITY * (2.0 if foe.grounded() else 1.0)):
		foe.morale -= 3.0 * foe.nerve  # a glancing blow: shaken, not wounded (men on the ground are twice as likely to be hurt)
		return
	var away := (foe.position - attacker.position).normalized()
	if show:
		effects.puff(foe.position, Color(foe.colors.blood), 5.0)
	spray_blood(foe, away, 0.8 + float(m.dmg) * 0.2)
	foe.take_hit(int(m.dmg), attacker)
	if not foe.is_alive():
		melee_kills[attacker.team] += 1


## A shot at a spot rather than a soldier: used to blow holes in walls.
func resolve_point_shot(shooter: Soldier, p: Vector2, w: Dictionary, muzzle: Vector2) -> void:
	shots[shooter.team] += 1
	_fire_sound(shooter, w, muzzle)
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
## One sound per burst: the weapon's burst sound already holds all its rounds.
func _fire_sound(shooter: Soldier, w: Dictionary, muzzle: Vector2) -> void:
	var key := "%d:%s" % [shooter.get_instance_id(), w.name]
	var span: float = float(w.burst) * float(w.gap) + 0.05
	if time - float(fire_sound_at.get(key, -99.0)) < span:
		return
	fire_sound_at[key] = time
	sfx.play(Sfx.sound_for(w), muzzle)


func _ricochet(pos: Vector2, incoming: Vector2, w := {}) -> void:
	effects.ricochet(pos, incoming)
	var energy: bool = w.is_empty() or Sfx.ENERGY.any(func(k): return GameData.WEAPONS[k] == w)
	sfx.play("ricochet" if energy else "ricochet_bullet", pos, 0.0, 0.15)


func _shot_lights(muzzle: Vector2, end: Vector2, w: Dictionary) -> void:
	var col: Color = w.tracer
	var size: float = w.width
	if phone:
		# phones: a muzzle flash for every few rounds only, and no travelling light, so a big
		# firefight doesn't overload the graphics (it crashed the Android app)
		if randf() < 0.3:
			light_fx.flash(muzzle, col, 0.9 + size * 0.15, 36.0 + size * 10.0, 0.08)
		if float(w.get("pen", 0)) >= 2.0 and randf() < 0.4:
			effects.puff(muzzle, Color(0.42, 0.4, 0.38), 3.0 + size)
		return
	light_fx.flash(muzzle, col, 0.9 + size * 0.15, 36.0 + size * 10.0, 0.08)
	if float(w.get("pen", 0)) >= 2.0:
		effects.puff(muzzle, Color(0.42, 0.4, 0.38), 3.0 + size)  # gunsmoke from heavy weapons
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
	sfx.play("explosion_big" if r >= 40.0 else "explosion_small", at)
	if show:
		effects.explosion(at, r)
		if r >= 30.0 or randf() < 0.5:
			add_smoke(at, 6.0 + r * 0.15, clampf(r / 30.0, 0.6, 1.5))  # the burst's smoke hangs about
		light_fx.flash(at, Color(1.0, 0.6, 0.3), 2.4, r * 3.0 + 40.0, 0.6, true)
	decals.add_scorch(at, r * 0.7)
	map.damage_roof(at, r, float(w.get("wall", 25.0)) * 1.1)
	var shredded: Array = []  # bushes, hedges and wire close to the burst are blown apart
	var cr := int(ceil(r * 0.5 / BattleMap.CELL))
	var c0 := map.cell_of(at)
	for dx in range(-cr, cr + 1):
		for dy in range(-cr, cr + 1):
			var cc := c0 + Vector2i(dx, dy)
			if map.center_of(cc).distance_to(at) <= r * 0.5 + 4.0:
				shredded.append(cc)
	map.crush_cells(shredded)
	if w.get("wall", 0.0) > 0.0:
		var hit_wall := map.wall_near(at, r * 0.5 + BattleMap.CELL)
		var fell := map.damage_walls(at, r, w.wall)
		walls_destroyed += fell.size()
		if hit_wall:
			add_smoke(at, 20.0 + randf() * 15.0, 1.0)  # the shattered wall smoulders
		if not fell.is_empty():
			_dust_burst(map.center_of(fell[0]), 1.4)
			sfx.play("collapse", map.center_of(fell[0]))
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
			var chance: float = 0.85 * (1.0 - d / r) * (1.0 - map.cover_vs(o.position, at) * 0.6) * GameData.LETHALITY
			if randf() < chance and randf() >= o.armor * (1.0 - w.ap):
				o.take_hit(w.dmg, shooter)


func on_vehicle_destroyed(v: Vehicle, killer: Soldier) -> void:
	if autotest:
		print("  vehicle lost: %s at %ds, killed by %s" % [v.squad.name, int(time), killer.kind if killer != null else "?"])
	effects.explosion(v.position, 40.0)
	sfx.play("explosion_big", v.position, 4.0, 0.03)
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
	if s.heavy and not s.is_vehicle:
		_take_over_gun(s)
	if killer != null and killer.team == s.team:
		friendly_kills[s.team] += 1
	var how := "?" if killer == null else (str(killer.kind) + ("/melee" if killer.in_melee else ""))
	kill_sources[how] = kill_sources.get(how, 0) + 1
	if killer != null and killer.kind == "pyre_warden":
		bastion_kills[0] += 1
	elif killer != null and killer.kind == "bastion":
		bastion_kills[1] += 1
	if killer != null and killer.heavy and not killer.is_vehicle:
		heavy_kills[killer.team] += 1
	if killer != null and killer.charger:
		assault_kills[killer.team] += 1
	if s.faction == "sworn" and not s.is_vehicle:
		sfx.play("sworn_death", s.position, 0.0, 0.04)
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


## The gunner's down: the nearest of his team picks up the heavy gun and carries on.
func _take_over_gun(s: Soldier) -> void:
	var best: Soldier = null
	for m in s.squad.members:
		if m != s and m.is_effective() and not m.heavy and not m.charger \
				and (best == null or m.position.distance_to(s.position) < best.position.distance_to(s.position)):
			best = m
	if best == null:
		return
	best.heavy = true
	best.weapon = s.weapon
	best.setup_t = 0.0
	best.ammo = s.ammo
	best.reload_t = s.reload_t
	best.burst_left = 0
	if s.team == player_team:
		log_message("%s: the loader takes over the gun." % s.squad.name)


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
		log_message("[color=#ffd070]%s have taken %s![/color]" % [f.name, map.objective_name()])
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
		broken[t] = eff[t] <= int(start_counts[t] * 0.15)
	var names := [GameData.FACTIONS[factions[0]].name, GameData.FACTIONS[factions[1]].name]
	if broken[0] and broken[1]:
		_end(-1, "Both forces are shattered. Nobody holds the %s." % map.objective_word())
	elif broken[0] or broken[1]:
		var w := 1 if broken[0] else 0
		_end(w, "%s have broken. %s hold the field." % [names[1 - w], names[w]])
	elif objective_owner >= 0 and hold_streak >= HOLD_TO_WIN:
		_end(objective_owner, "%s have held %s unchallenged." % [names[objective_owner], map.objective_name()])
	elif battle_length > 0.0 and time >= battle_length:
		if objective_owner >= 0:
			_end(objective_owner, "Time is up. %s hold %s." % [names[objective_owner], map.objective_name()])
		else:
			_end(-1, "Time is up. The %s is still contested." % map.objective_word())


func _end(winner: int, reason: String) -> void:
	over = true
	Settings.stage("ran fine")
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
		print("RESULT winner=%s time=%d shots=%s hits=%s left=%s/%s dead=%s/%s fled=%s/%s vehicles_lost=%s/%s walls=%d cover=%d%%/%d%% blocked=%s flank=%s crossfire=%d%%/%d%% blows=%s mkills=%s raider_kills=%d blade_kills=%d grenades=%s heavy_kills=%s heavy_set=%d%%/%d%% own_side_kills=%s flamer_hail_kills=%s peeks=%s %s" % [
				factions[winner] if winner >= 0 else "draw", int(time), shots, hits,
				left[0], left[1], dead[0], dead[1], fled[0], fled[1], vlost[0], vlost[1], walls_destroyed, int(100 * cover_time[0] / maxf(field_time[0], 1)), int(100 * cover_time[1] / maxf(field_time[1], 1)), cover_blocks, flank_shots, int(100 * crossfire_time[0] / maxf(field_time[0], 1)), int(100 * crossfire_time[1] / maxf(field_time[1], 1)), blows, melee_kills, assault_kills[0], assault_kills[1], grenades_thrown, heavy_kills, int(100 * heavy_set_time[0] / maxf(heavy_time[0], 1)), int(100 * heavy_set_time[1] / maxf(heavy_time[1], 1)), friendly_kills, bastion_kills, peeks, reason])
		print("KILLS " + JSON.stringify(kill_sources))
		get_tree().quit()
		return
	var head := "DRAW"
	if winner >= 0:
		head = "VICTORY" if winner == player_team else "DEFEAT"
	hud.show_end("%s\n%s\nSurvivors: yours %d of %d, enemy %d of %d" % [head, reason,
			left[player_team], start_counts[player_team], left[1 - player_team], start_counts[1 - player_team]])


## Switch the main gun setting of the selected tanks (beam / pulse, AP / HE).
func switch_guns() -> void:
	for sq in _player_squads():
		if sq.selected and sq.has_mortars():
			sq.mortar_kind = "smoke" if sq.mortar_kind == "he" else "he"
			log_message("[color=#e8c070]%s: mortars loaded with %s[/color]" % [sq.name, "smoke" if sq.mortar_kind == "smoke" else "HE"])
		var v = sq.vehicle()
		if sq.selected and v != null and v.is_alive() and v.gun_mode() != "":
			var m: String = v.switch_gun()
			log_message("[color=#e8c070]%s: %s to %s[/color]" % [sq.name, "launchers loaded" if v.launcher else "main gun", m])
	if hud != null:
		hud._gun_buttons()


## The selected infantry's pace: "down" if any are lying down, "run" if running, else "walk".
func pace_state() -> String:
	var sel := _player_squads().filter(func(q): return q.selected and q.vehicle() == null)
	if sel.any(func(q): return q.prone):
		return "down"
	if sel.is_empty():
		return "run" if run_toggle else "walk"
	if sel.any(func(q): return q.running):
		return "run"
	return "walk"


## When the selection changes, new orders follow the selected squads' own pace (so a squad
## you pick up keeps walking or running as it was, rather than taking the last one's).
func sync_pace_to_selection() -> void:
	var sel := _player_squads().filter(func(q): return q.selected and q.vehicle() == null)
	if not sel.is_empty():
		run_toggle = sel.any(func(q): return q.running and not q.prone)


## The Pace button: crouched and walking -> running -> lying down -> crouched again.
func cycle_pace() -> void:
	match pace_state():
		"walk":
			touch_button("Down", false)
			touch_button("Assault", true)
		"run":
			touch_button("Assault", false)
			touch_button("Down", true)
		_:
			touch_button("Down", false)
			touch_button("Assault", false)
	if hud != null:
		hud._context_buttons()


func log_message(text: String) -> void:
	if autotest:
		return
	var t := int(time)
	hud.add_message("[color=#8a8070]%d:%02d[/color]  %s" % [t / 60, t % 60, text])


# ---------------------------------------------------------------- input

func select_squad(sq: Squad, add: bool) -> void:
	plan_fresh = true
	if hud != null:
		hud.sync_touch("Down", sq.prone)
	if not add:
		for o in squads:
			o.selected = false
	sq.selected = not sq.selected if add else true
	sync_pace_to_selection()
	if hud != null:
		hud._context_buttons()


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
					_zoom(1.12, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / 1.12, mb.position)
			MOUSE_BUTTON_MIDDLE:
				panning = mb.pressed
			MOUSE_BUTTON_LEFT:
				if not started or over:
					return
				if mb.pressed and target_mode:
					_order_target(wp)
				elif mb.pressed and grenade_mode:
					_order_grenade(wp)
				elif mb.pressed and face_mode:
					_order_face(wp)
					face_mode = false
					hud.sync_touch("Face", false)
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
					_right_press(mb, wp)
				else:
					_right_release(mb, wp)
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if panning:
			camera.position -= mm.relative / camera.zoom
			_clamp_camera()
		elif right_held:
			_right_motion(mm)
	elif e is InputEventKey and e.is_pressed() and not e.is_echo():
		var k := (e as InputEventKey).keycode
		if k == KEY_SPACE and started and not over:
			paused = not paused
			hud.sync_touch("Pause", paused)
		elif k == KEY_ESCAPE and started and not over:
			hud.toggle_battle_menu()
		elif k == KEY_F1:
			hud.toggle_help()
		elif k == KEY_V:
			switch_guns()

		elif k == KEY_U:
			for sq in _player_squads():
				var v = sq.vehicle()
				if sq.selected and v != null:
					v.unload()
		elif k == KEY_G:
			var any_up := _player_squads().any(func(q): return q.selected and not q.prone)
			touch_button("Down", any_up)
			hud.sync_touch("Down", any_up)
		elif k == KEY_R:
			var any_slow := _player_squads().any(func(q): return q.selected and not q.running)
			touch_button("Assault", any_slow)
			hud.sync_touch("Assault", any_slow)
		elif k == KEY_H:
			for sq in _player_squads():
				if sq.selected:
					sq.halt()
		elif k == KEY_C:
			cover_mode = not cover_mode
			hud.sync_touch("Cover", cover_mode)
			hud.show_cover_key(cover_mode)
		elif k == KEY_T:
			grenade_mode = not grenade_mode
			hud.sync_touch("Grenade", grenade_mode)
		elif k == KEY_F:
			target_mode = not target_mode
			hud.sync_touch("Target", target_mode)
		elif k >= KEY_1 and k <= KEY_9:
			var mine := _player_squads()
			var i := k - KEY_1
			if i < mine.size():
				select_squad(mine[i], (e as InputEventKey).shift_pressed)
				camera.position = mine[i].center()
				_clamp_camera()


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


## The selected squads that can take a move order, each with where its own part
## of the order goes: a spot near p (move), or its share of the line a-b.
func _plan(kind: String, a: Vector2, b: Vector2, final: bool, face_override := Vector2.ZERO) -> void:
	var sel: Array = _player_squads().filter(func(q): return q.selected and (q.vehicle() != null or not q.alive().is_empty() or q.carrier() != null))
	if sel.is_empty():
		return
	var orders: Array = []  # [squad, order]
	if kind == "line":
		var inf: Array = sel.filter(func(q): return q.vehicle() == null and q.carrier() == null)
		var total := 0
		for sq in inf:
			total += sq.movers().size()
		var dir := (b - a).normalized()
		inf.sort_custom(func(x, y): return (x.center() - a).dot(dir) < (y.center() - a).dot(dir))
		var done := 0
		for sq in inf:
			var n: int = sq.movers().size()
			var sa := a.lerp(b, float(done) / maxf(total, 1))
			var sb := a.lerp(b, float(done + n - 1) / maxf(total - 1, 1))
			if inf.size() == 1:
				sa = a
				sb = b
			orders.append([sq, {"kind": "line", "a": sa, "b": sb, "face": face_override if face_override != Vector2.ZERO else line_facing(sq, a, b), "run": run_toggle}])
			done += n
		for sq in sel:
			if not inf.has(sq):
				var mover: Squad = sq.carrier().squad if sq.carrier() != null else sq
				orders.append([mover, {"kind": "move", "a": b, "b": b, "face": Vector2.ZERO, "run": run_toggle}])
	else:
		var group_c := Vector2.ZERO
		for sq in sel:
			group_c += sq.center()
		group_c /= sel.size()
		for sq in sel:
			var off: Vector2 = (sq.center() - group_c).limit_length(120.0) if sel.size() > 1 else Vector2.ZERO
			var mover: Squad = sq.carrier().squad if sq.carrier() != null else sq
			orders.append([mover, {"kind": "move", "a": a + off, "b": a + off, "face": Vector2.ZERO, "run": run_toggle}])
	for o in orders:
		o[0].enqueue(map, o[1], plan_fresh)
	_acknowledge("move")
	plan_fresh = final
	var col := Color(1.0, 0.8, 0.3) if run_toggle else Color(0.5, 1.0, 0.5)
	effects.marker(a, col)
	if kind == "line":
		effects.marker(b, col)


## The selected squads answer an order (only the Sworn have voices so far).
## A fire mission for the selected mortar teams at a picked spot.
func _order_target(wp: Vector2) -> void:
	target_mode = false
	hud.sync_touch("Target", false)
	for sq in _player_squads():
		if sq.selected and sq.has_mortars():
			var msg := mortars.order(sq, wp)
			if msg != "":
				log_message("[color=#e8c070]%s[/color]" % msg)
	effects.marker(wp, Color(1.0, 0.45, 0.3))


## Grenades at a picked spot: each selected squad throws what suits it (see Grenades).
func _order_grenade(wp: Vector2) -> void:
	grenade_mode = false
	hud.sync_touch("Grenade", false)
	var any := false
	for sq in _player_squads():
		if sq.selected:
			var msg := grenades.order(sq, wp)
			if msg != "":
				log_message(msg)
				any = any or sq.grenade_order != null
	if any:
		_acknowledge("attack")


func _acknowledge(kind: String) -> void:
	if _player_squads().any(func(q): return q.selected and q.faction == "sworn" and (not q.alive().is_empty() or q.carrier() != null)):
		sfx.voice("sworn_" + kind)


func _has_selection() -> bool:
	return _player_squads().any(func(q): return q.selected and (q.vehicle() != null or not q.alive().is_empty() or q.carrier() != null))


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
			_acknowledge("move")
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
			_acknowledge("attack")
			return
	if enemy != null:
		for sq in sel:
			sq.focus = enemy
		effects.marker(enemy.position, Color(1.0, 0.3, 0.2))
		_acknowledge("attack")
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


## Zoom in or out, keeping the map point under the cursor where it is.
func _zoom(f: float, at_screen = null) -> void:
	var before := _screen_to_world(at_screen) if at_screen != null else camera.position
	var z := clampf(camera.zoom.x * f, 0.5, 2.5)
	camera.zoom = Vector2(z, z)
	if at_screen != null:
		camera.position += before - _screen_to_world(at_screen)
	_clamp_camera()


# ---------------------------------------------------------------- mouse orders
# Right button, mirroring the phone: click to move (Shift: add a waypoint),
# drag to spread out along a line (pause, then keep dragging, to set facing),
# drag from the selected squad or its last waypoint to turn them.

var right_held := false
var right_start_screen := Vector2.ZERO


func _right_press(mb: InputEventMouseButton, wp: Vector2) -> void:
	right_held = true
	right_start_screen = mb.position
	t_start = mb.position
	pointer_world = wp
	if mb.ctrl_pressed:
		t_mode = "ctrl"
		return
	var own := _soldier_at(wp, player_team)
	face_squads = _face_targets(wp, own)
	if not face_squads.is_empty():
		t_mode = "face"
		face_anchor = wp
	else:
		t_mode = "press"


func _right_motion(mm: InputEventMouseMotion) -> void:
	pointer_world = _screen_to_world(mm.position)
	if t_mode == "press" and mm.position.distance_to(right_start_screen) > 12.0 and _has_selection():
		t_mode = "line"
		rdragging = true
		rdrag_start = _screen_to_world(right_start_screen)
		line_still_at = mm.position
		line_still_ms = Time.get_ticks_msec()
		line_still_frame = Engine.get_process_frames()
	elif t_mode == "line" and mm.position.distance_to(line_still_at) > 6.0:
		line_still_at = mm.position  # still moving: restart the pause timer
		line_still_ms = Time.get_ticks_msec()
		line_still_frame = Engine.get_process_frames()


func _right_release(mb: InputEventMouseButton, wp: Vector2) -> void:
	if not right_held:
		return
	right_held = false
	var mode := t_mode
	t_mode = ""
	rdragging = false
	var add := mb.shift_pressed  # Shift: add to the route instead of replacing it
	match mode:
		"ctrl":
			_order_face(wp)
		"face":
			var dir := wp - face_anchor
			if dir.length() > 14.0 / camera.zoom.x:
				for sq in face_squads:
					sq.set_final_facing(dir)
				effects.marker(wp, Color(0.6, 0.8, 1.0))
			face_squads = []
		"line":
			if add:
				plan_fresh = false
			_plan("line", rdrag_start, wp, not add)
		"line_face":
			if add:
				plan_fresh = false
			var mid := (rdrag_start + line_b) * 0.5
			var fdir := wp - mid
			_plan("line", rdrag_start, line_b, not add, fdir.normalized() if fdir.length() > 14.0 / camera.zoom.x else Vector2.ZERO)
		"press":
			_right_click(wp, add)


func _right_click(wp: Vector2, add: bool) -> void:
	if not _has_selection():
		return
	# a click on an enemy, your carrier or (for tanks and lance teams) a wall is that order
	var sel: Array = _player_squads().filter(func(q): return q.selected)
	var own := _soldier_at(wp, player_team)
	var boards: bool = own != null and own.is_vehicle and own.free_space() > 0 and not own.squad.selected \
			and sel.any(func(q): return q.vehicle() == null)
	var on_enemy := _soldier_at(wp, 1 - player_team) != null
	var on_wall := map.get_t(map.cell_of(wp)) == BattleMap.T.WALL and sel.any(func(q): return q.can_breach())
	if boards or on_enemy or on_wall:
		_order(wp, run_toggle)
		return
	if add:
		plan_fresh = false
	_plan("move", wp, wp, not add)


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
	# screen-edge scrolling with the mouse
	if not touch_mode and started and DisplayServer.window_is_focused():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(mp):
			var edge := 10.0
			if mp.x < edge:
				v.x -= 1
			elif mp.x > vs.x - edge:
				v.x += 1
			if mp.y < edge:
				v.y -= 1
			elif mp.y > vs.y - edge:
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
				t_press_ms = Time.get_ticks_msec()
				# a second touch right after a tap close by: double tap, or tap-drag
				var recent := st.position.distance_to(tap_screen) < 50.0 \
						and (t_press_ms - tap_time < DOUBLE_TAP_MS or Engine.get_process_frames() - tap_frame <= 10)
				t_second = recent and (tap_pending or board_carrier != null)
				if not recent:
					board_carrier = null
				if t_second:
					tap_pending = false
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
					_plan("line", rdrag_start, wp, true)
				elif t_mode == "line_face":
					# the line was fixed by pausing; the finger since then sets the way they face
					rdragging = false
					var mid := (rdrag_start + line_b) * 0.5
					var fdir := wp - mid
					_plan("line", rdrag_start, line_b, true, fdir.normalized() if fdir.length() > 14.0 / camera.zoom.x else Vector2.ZERO)
				elif t_mode == "held":
					_hold(t_start)
				elif t_mode == "face":
					var dir := wp - face_anchor
					if dir.length() > 14.0 / camera.zoom.x:
						for sq in face_squads:
							sq.set_final_facing(dir)
						effects.marker(wp, Color(0.6, 0.8, 1.0))
					face_squads = []
				elif t_mode == "" and t_second:
					_double_tap(wp)
				elif t_mode == "":
					_tap(wp, st.position)
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
			t_mode = "pan"
		elif t_mode == "held" and sd.position.distance_to(t_start) > 18.0:
			if started and not over and _has_selection():
				t_mode = "line"  # hold, then drag: spread out along the drag
				rdragging = true
				rdrag_start = _screen_to_world(t_start)
				line_still_at = sd.position
				line_still_ms = Time.get_ticks_msec()
				line_still_frame = Engine.get_process_frames()
			else:
				t_mode = "pan"
		if t_mode == "face" or t_mode == "line_face":
			pointer_world = _screen_to_world(sd.position)
			return
		if t_mode == "line" and sd.position.distance_to(line_still_at) > 8.0:
			line_still_at = sd.position  # still moving: restart the pause timer
			line_still_ms = Time.get_ticks_msec()
			line_still_frame = Engine.get_process_frames()
		if t_mode == "pan":
			camera.position -= sd.relative / camera.zoom
			_clamp_camera()
		pointer_world = _screen_to_world(sd.position)


func _pinch_begin() -> void:
	var pts: Array = touches.values()
	pinch_prev_center = (pts[0] + pts[1]) * 0.5
	pinch_prev_dist = pts[0].distance_to(pts[1])


func _tap(wp: Vector2, screen := Vector2.ZERO) -> void:
	if not started or over:
		return
	if target_mode:
		_order_target(wp)
		return
	if grenade_mode:
		_order_grenade(wp)
		return
	if face_mode:
		_order_face(wp)
		face_mode = false
		hud.sync_touch("Face", false)
		return
	var s := _soldier_at(wp, player_team, 16.0)
	if s != null:
		tap_pending = false
		var infantry_selected := _player_squads().any(func(q): return q.selected and q.vehicle() == null)
		if s.is_vehicle and s.free_space() > 0 and infantry_selected and not s.squad.selected:
			# select the carrier straight away, but remember the infantry: if a second
			# tap follows, they climb aboard instead
			board_from = _player_squads().filter(func(q): return q.selected and q.vehicle() == null)
			board_carrier = s.squad
			tap_screen = screen
			tap_time = Time.get_ticks_msec()
			tap_frame = Engine.get_process_frames()
		for sq in squads:
			sq.sub.clear()
		select_squad(s.squad, false)
		return
	# with squads selected, a tap on an enemy or (for tanks and lance teams) a wall is an order;
	# anything else clears the selection so a drag scrolls the map. Moving takes a drag.
	var sel := _player_squads().filter(func(q): return q.selected)
	if not sel.is_empty():
		var on_enemy := _soldier_at(wp, 1 - player_team, 16.0) != null
		var on_wall := map.get_t(map.cell_of(wp)) == BattleMap.T.WALL and sel.any(func(q): return q.can_breach())
		if on_enemy or on_wall:
			_order(wp, run_toggle)
			return
		# a lone tap clears the selection, once it's clear no second tap is coming
		tap_pending = true
		tap_screen = screen
		tap_time = Time.get_ticks_msec()
		tap_frame = Engine.get_process_frames()
		tap_pos = wp
		return
	_deselect_all()


func _double_tap(wp: Vector2) -> void:
	var board_target = board_carrier
	board_carrier = null
	if not started or over:
		return
	var carrier := _soldier_at(wp, player_team, 16.0)
	if carrier != null and carrier.is_vehicle and board_target != null and carrier.squad == board_target \
			and not board_from.is_empty():
		# double-tap your carrier: the infantry that were selected climb aboard
		_deselect_all()
		for q in board_from:
			q.selected = true
		_order(wp, false)
		return
	if not _has_selection():
		return
	var on_enemy := _soldier_at(wp, 1 - player_team, 16.0) != null
	var on_wall := map.get_t(map.cell_of(wp)) == BattleMap.T.WALL
	if on_enemy or on_wall:
		_order(wp, run_toggle)
	else:
		_plan("move", wp, wp, true)


## Holding a finger still on the ground: add a waypoint to the selected squads' route.
func _hold(screen: Vector2) -> void:
	var wp := _screen_to_world(screen)
	if not started or over or not _has_selection():
		return
	var own := _soldier_at(wp, player_team, 16.0)
	if own != null:
		for sq in squads:
			sq.sub.clear()
		select_squad(own.squad, false)
		return
	_plan("move", wp, wp, false)


## Squads a hold at world point p would turn: the selected squad held on directly,
## or the selected squads whose final waypoint is under the finger.
func _face_targets(p: Vector2, own: Soldier) -> Array:
	if not started or over:
		return []
	if own != null and own.squad.selected:
		return _player_squads().filter(func(q): return q.selected)
	var reach := 22.0 / camera.zoom.x
	var out: Array = []
	for sq in _player_squads():
		if not sq.selected:
			continue
		var f = sq.final_order()
		if f == null:
			continue
		var fp: Vector2 = (f.a + f.b) * 0.5 if f.kind == "line" else f.b
		if fp.distance_to(p) <= reach:
			out.append(sq)
	return out


func _deselect_all() -> void:
	plan_fresh = true
	for sq in squads:
		sq.selected = false
		sq.sub.clear()


## Called by a squad card: select the squad and glide the camera over to it.
func focus_squad(sq: Squad, add: bool) -> void:
	select_squad(sq, add)
	if sq.alive().is_empty() and sq.carrier() == null and sq.vehicle() == null:
		return
	var from := camera.position
	camera.position = sq.center()
	_clamp_camera()
	var to := camera.position
	camera.position = from
	var tw := create_tween()
	tw.tween_property(camera, "position", to, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The touch bar's buttons.
func touch_button(key: String, on: bool) -> void:
	match key:
		"Assault":
			run_toggle = on
			if on:
				hud.sync_touch("Down", false)
			for sq in _player_squads():
				if sq.selected:
					sq.set_assault(on)  # speeds up (or slows) orders they're already carrying out
		"Down":
			for sq in _player_squads():
				if sq.selected:
					sq.set_prone(on)
			if on:
				run_toggle = false
				hud.sync_touch("Assault", false)
		"Pace":
			cycle_pace()
		"Face":
			face_mode = on
		"Grenade":
			grenade_mode = on
		"Target":
			target_mode = on
		"Cover":
			cover_mode = on
			hud.show_cover_key(on)
		"Halt":
			for sq in _player_squads():
				if sq.selected:
					sq.halt()
		"Unload":
			for sq in _player_squads():
				var v = sq.vehicle()
				if sq.selected and v != null:
					v.unload()
		"Gun":
			switch_guns()

		"Squads":
			hud.set_squads_visible(on)
		"Pause":
			if started and not over:
				paused = on
		"?":
			hud.toggle_help()
		"Menu":
			hud.toggle_battle_menu()
