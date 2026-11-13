class_name Support
extends Node2D
## Support from above, called with the Support button and a line drawn on the map:
## - the Legion's Kestrel gunship: a strafing run straight down the line a few seconds after
##   the call, cannon fire and rockets raking it (5 a battle, 60 s apart);
## - the Sworn's Oathfall bombardment: ten seconds after the call, a row of tungsten rods from
##   orbit lands along the line, each a huge blast that leaves the ground molten, cooling over
##   the next minute to scorched earth (3 a battle, 90 s apart).
## Both hit whoever is there, friend or foe. The computer calls them on knots of the enemy,
## clear of its own men. Strikes on the way are marked on the map for both sides.

const KINDS := {
	"gunship": {"name": "Kestrel gunship", "uses": 5, "cooldown": 60.0, "first": 40.0, "delay": 4.0, "max_len": 440.0,
		"cannon": {"blast": 20.0, "dmg": 2, "ap": 0.65, "pen": 5, "vdmg": 2, "wall": 14.0, "supp": 30.0},
		"rocket": {"blast": 30.0, "dmg": 3, "ap": 0.7, "pen": 7, "vdmg": 3, "wall": 55.0, "supp": 45.0}},
	"orbital": {"name": "Oathfall bombardment", "uses": 3, "cooldown": 90.0, "first": 60.0, "delay": 10.0, "max_len": 380.0,
		"rods": 8, "rod": {"blast": 46.0, "dmg": 4, "ap": 0.95, "pen": 10, "vdmg": 8, "wall": 220.0, "supp": 70.0}},
}
const GUNSHIP_SPEED := 340.0
const ROD_FALL := 0.25  # seconds a rod is seen streaking straight down before it hits

var main: Node
var kind := ["gunship", "orbital"]  # per team
var left := [0, 0]                  # calls left
var wait := [0.0, 0.0]              # seconds until the next is ready
var strikes: Array = []             # called: {team, kind, a, b, t (s since called)}
var molten: Array = []              # {pos, r, t, seed}
var planes: Array = []              # gunships in flight: {from, dir, s, len, a, b, team, fired, rockets}
var falling: Array = []             # rods on the way down: {pos, t, team}
var kills := [0, 0]                 # test aid: men killed by each side's support
var ai_think := 0.0
var lights: Array = []              # glow of fresh molten ground: [PointLight2D, molten entry]


var sky: SkyLayer


class SkyLayer:
	extends Node2D
	var sup: Support

	func _draw() -> void:
		sup.draw_sky(self)


func setup(m: Node) -> void:
	main = m
	z_index = -4  # the molten ground: on the ground, under the men
	sky = SkyLayer.new()
	sky.sup = self
	sky.z_as_relative = false
	sky.z_index = 30
	add_child(sky)
	_arm()


var _armed_for := ""


## Each side's support, by its faction (set when the battle starts, so read then).
func _arm() -> void:
	var key := "%s-%s" % [main.factions[0], main.factions[1]]
	if key == _armed_for:
		return
	_armed_for = key
	for t in 2:
		kind[t] = "orbital" if main.factions[t] == "sworn" else "gunship"
		left[t] = KINDS[kind[t]].uses
		wait[t] = KINDS[kind[t]].first


func info(team: int) -> Dictionary:
	return KINDS[kind[team]]


func ready_for(team: int) -> bool:
	return left[team] > 0 and wait[team] <= 0.0 and not strikes.any(func(s): return s.team == team)


## The player (or the computer) calls a strike along a-b (clipped to the longest line allowed).
func call_strike(team: int, a: Vector2, b: Vector2) -> String:
	if not ready_for(team):
		return ""
	var k: Dictionary = info(team)
	if a.distance_to(b) > k.max_len:
		b = a + (b - a).normalized() * k.max_len
	if a.distance_to(b) < 12.0:
		b = a + Vector2(24.0, 0)  # (a tap: all the rods close together on the spot)
	left[team] -= 1
	wait[team] = k.cooldown
	strikes.append({"team": team, "kind": kind[team], "a": a, "b": b, "t": 0.0})
	main.sfx.play("smoke", a, -8.0, 0.1)  # (the signal flare)
	return "%s inbound, %d s!" % [k.name, int(k.delay)]


func _process(dt: float) -> void:
	if main.paused or not main.started or main.over or main.deploying:
		return
	if main.time < 1.0:
		_arm()
	for t in 2:
		if left[t] > 0:
			wait[t] = maxf(0.0, wait[t] - dt)
	for s in strikes.duplicate():
		s.t += dt
		if s.t >= info(s.team).delay:
			strikes.erase(s)
			if s.kind == "gunship":
				_launch_gunship(s)
			else:
				_drop_rods(s)
	_fly(dt)
	for r in falling.duplicate():
		r.t -= dt
		if r.t <= 0.0:
			falling.erase(r)
			_rod_lands(r)
	for mo in molten.duplicate():
		mo.t += dt
		if mo.t > 70.0:
			molten.erase(mo)
	for l in lights.duplicate():
		var heat := 1.0 - float(l[1].t) / 20.0
		if heat <= 0.0:
			l[0].queue_free()
			lights.erase(l)
		else:
			l[0].energy = main.light_fx.boosted(2.2 * heat)
	ai_think -= dt
	if ai_think <= 0.0:
		ai_think = 3.0
		for t in 2:
			if (t != main.player_team or main.autotest) and ready_for(t):
				_ai_call(t)
	queue_redraw()
	sky.queue_redraw()


# ---------------------------------------------------------------- the gunship

func _launch_gunship(s: Dictionary) -> void:
	var dir: Vector2 = (s.b - s.a).normalized()
	var lead := 650.0
	planes.append({"from": s.a - dir * lead, "dir": dir, "s": 0.0, "len": s.a.distance_to(s.b), "lead": lead,
			"a": s.a, "b": s.b, "team": s.team, "gun_t": 0.0, "rockets": [0.08, 0.2, 0.32, 0.44, 0.56, 0.68, 0.8, 0.92]})
	main.sfx.play("engine_rev", s.a, 6.0, 0.05)


func _fly(dt: float) -> void:
	var k: Dictionary = KINDS.gunship
	for p in planes.duplicate():
		p.s += GUNSHIP_SPEED * dt
		var pos: Vector2 = p.from + p.dir * p.s
		# it fires on the line ahead of it: the rounds land a little in front of the nose
		var along: float = p.s - p.lead + 110.0
		if along >= 0.0 and along <= p.len:
			p.gun_t -= dt
			if p.gun_t <= 0.0:
				p.gun_t = 0.03
				var hit: Vector2 = p.a + p.dir * along + p.dir.orthogonal() * randf_range(-14, 14) + p.dir * randf_range(-10, 10)
				main.effects.tracer(pos, hit, Color(1.0, 0.8, 0.45), 2.0)
				_hit(hit, k.cannon, p.team, false)
				if randi() % 3 == 0:
					main.sfx.play("rotor", hit, -2.0, 0.1)
			for r in p.rockets.duplicate():
				if along >= r * p.len:
					p.rockets.erase(r)
					var hit: Vector2 = p.a + p.dir * along + p.dir.orthogonal() * randf_range(-10, 10)
					main.effects.tracer(pos, hit, Color(1.0, 0.6, 0.3), 3.0)
					_hit(hit, k.rocket, p.team, false)
		if p.s > p.lead * 2.0 + p.len:
			planes.erase(p)


# ---------------------------------------------------------------- the bombardment

func _drop_rods(s: Dictionary) -> void:
	var k: Dictionary = KINDS.orbital
	var n: int = k.rods
	# evenly spaced from one end of the line to the other (a short line packs them close), and
	# they walk down it fast, one after another
	for i in n:
		var f := float(i) / maxf(1.0, n - 1)
		falling.append({"pos": s.a.lerp(s.b, f), "t": ROD_FALL + 0.09 * i, "team": s.team, "idx": i})


func _rod_lands(r: Dictionary) -> void:
	var p: Vector2 = r.pos
	_hit(p, KINDS.orbital.rod, r.team, true)
	main.shake(p, 9.0)
	main.sfx.play("explosion_big", p, 6.0, 0.05)
	if main.effects_visible_at(p):
		main.effects.explosion(p, 70.0)
		main.effects.debris(p, 18)
		# eight of these land within a second: each is bright, but not all at full blast,
		# and only every other one throws shadows
		var idx: int = int(r.get("idx", 0))
		main.light_fx.flash(p, Color(1.0, 0.8, 0.55), 2.6, 260.0, 0.7, idx % 2 == 0)
	var mo := {"pos": p, "r": 30.0 + randf() * 8.0, "t": 0.0, "seed": randi()}
	molten.append(mo)
	if main.light_fx.enabled_fx and main.light_fx.tex != null and lights.size() < (2 if Settings.is_phone() else 6):
		var l := PointLight2D.new()
		l.texture = main.light_fx.tex
		l.color = Color(1.0, 0.45, 0.15)
		l.texture_scale = 1.1
		l.height = 10.0
		l.position = p
		main.light_fx.add_child(l)
		lights.append([l, mo])


## A strike's blast: men and walls (the usual burst), and vehicles caught in it (from above:
## the thin top and rear armour).
func _hit(at: Vector2, w: Dictionary, team: int, big: bool) -> void:
	var before := 0
	for o in main.soldiers:
		if o.is_alive():
			before += 1
	main._blast(at, w, null, main.effects_visible_at(at))
	for v in main.soldiers:
		if v.is_vehicle and v.is_alive() and v.position.distance_to(at) < float(w.blast) * 0.5 + v.radius:
			v.receive_hit(w, v.position - Vector2.from_angle(v.facing) * 20.0, null)
	var after := 0
	for o in main.soldiers:
		if o.is_alive():
			after += 1
	kills[team] += before - after


# ---------------------------------------------------------------- the computer's calls

func _ai_call(team: int) -> void:
	var best_c := Vector2.ZERO
	var best_n := 0
	for e in main.soldiers:
		if e.team == team or not e.is_alive() or e.is_vehicle or not e.seen_by[team] or e.state == Soldier.State.EMBARKED:
			continue
		var n := 0
		var c := Vector2.ZERO
		for o in main.soldiers:
			if o.team == e.team and o.is_alive() and not o.is_vehicle and o.position.distance_to(e.position) < 90.0:
				n += 1
				c += o.position
		if n > best_n:
			best_n = n
			best_c = c / n
	if best_n < 4:
		return
	# along the enemy's line (roughly north-south), short enough to stay clear of our own men
	var half: float = info(team).max_len * 0.4
	var a := best_c - Vector2(0, half)
	var b := best_c + Vector2(0, half)
	for o in main.soldiers:
		if o.team == team and o.is_alive() and Geometry2D.get_closest_point_to_segment(o.position, a, b).distance_to(o.position) < 110.0:
			return  # too close to our own
	call_strike(team, a, b)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	# molten ground: white-hot, then orange, then a dull red crust, cooling to scorch
	for mo in molten:
		var heat := clampf(1.0 - float(mo.t) / 55.0, 0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = mo.seed
		var r: float = mo.r
		var hot := Color(1.0, 0.95, 0.7).lerp(Color(1.0, 0.45, 0.1), clampf((1.0 - heat) * 2.0, 0.0, 1.0)).lerp(Color(0.4, 0.06, 0.02), clampf((1.0 - heat) * 1.4 - 0.4, 0.0, 1.0))
		var pts := PackedVector2Array()
		for i in 16:
			pts.append(mo.pos + Vector2.from_angle(i * TAU / 16.0) * r * rng.randf_range(0.75, 1.1))
		draw_colored_polygon(pts, Color(0.06, 0.04, 0.03, 0.8))  # the blasted pit
		var glow := Color(hot, 0.85 * heat + 0.1 * (1.0 - heat))
		for k in 3:
			var inner := PackedVector2Array()
			var rr := r * (0.8 - k * 0.22)
			for i in 12:
				inner.append(mo.pos + Vector2.from_angle(i * TAU / 12.0 + k) * rr * rng.randf_range(0.7, 1.05))
			draw_colored_polygon(inner, Color(glow, glow.a * (0.6 + k * 0.2)))
		for i in 7:  # glowing cracks running out into the cooling crust
			var a := rng.randf() * TAU
			var p0: Vector2 = mo.pos + Vector2.from_angle(a) * r * 0.3
			var p1: Vector2 = mo.pos + Vector2.from_angle(a + rng.randf_range(-0.3, 0.3)) * r * rng.randf_range(1.0, 1.5)
			draw_line(p0, p1, Color(hot, 0.9 * heat), 1.4)


## Above everything (roofs included): strikes on the way, rods falling, gunships.
func draw_sky(ci: CanvasItem) -> void:
	var z: float = 1.0 / main.camera.zoom.x
	var now: float = main.time
	# strikes on the way: marked for both sides (red), with a countdown
	for s in strikes:
		var k: Dictionary = info(s.team)
		var left_t: float = k.delay - s.t
		var pulse := 0.5 + 0.5 * sin(now * 8.0)
		var col := Color(1.0, 0.25, 0.15, 0.45 + 0.35 * pulse)
		ci.draw_dashed_line(s.a, s.b, col, 3.0 * z, 12.0 * z)
		for e in [s.a, s.b]:
			ci.draw_arc(e, 10.0 * z, 0, TAU, 20, col, 2.0 * z)
		var mid: Vector2 = (s.a + s.b) * 0.5
		ci.draw_string(ThemeDB.fallback_font, mid + Vector2(-10, -14) * z, "%d" % ceili(left_t), HORIZONTAL_ALIGNMENT_CENTER, -1, int(16 * z), col)
	# rods streaking down: a white-hot line out of the sky onto the spot
	for r in falling:
		var f := clampf(1.0 - r.t / ROD_FALL, 0.0, 1.0)
		if f <= 0.0:
			continue
		# straight down out of the sky: the white-hot streak shortens onto the spot as it comes in
		var top: Vector2 = r.pos - Vector2(0, 520.0 * (1.0 - f) + 18.0)
		ci.draw_line(top, r.pos, Color(1.0, 0.6, 0.25, 0.35), 14.0 * z)
		ci.draw_line(top, r.pos, Color(1.0, 0.97, 0.88, 0.95), 4.0 * z)
		ci.draw_circle(r.pos, (5.0 + 22.0 * f) * z, Color(1.0, 0.9, 0.6, 0.3 * f))
	# gunships: their shadow on the ground, and the aircraft itself
	for p in planes:
		var pos: Vector2 = p.from + p.dir * p.s
		_draw_gunship(ci, pos + Vector2(28, 36), p.dir, true)
		_draw_gunship(ci, pos, p.dir, false)


## The Legion's Kestrel: a blunt armoured fuselage, stubby wings with a rocket pod and an engine
## nacelle on each, twin tail booms, a cockpit glowing amber and the gunner's chin turret.
func _draw_gunship(ci: CanvasItem, c: Vector2, dir: Vector2, shadow: bool) -> void:
	ci.draw_set_transform(c, dir.angle(), Vector2(1.6, 1.6))
	var body := Color(0.3, 0.32, 0.24) if not shadow else Color(0, 0, 0, 0.3)
	var dark := Color(0.12, 0.13, 0.1) if not shadow else Color(0, 0, 0, 0.0)
	var fus := PackedVector2Array([Vector2(26, 0), Vector2(18, -6), Vector2(-14, -6), Vector2(-26, -3), Vector2(-26, 3), Vector2(-14, 6), Vector2(18, 6)])
	ci.draw_colored_polygon(fus, body)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(6, -6), Vector2(-4, -30), Vector2(-12, -30), Vector2(-10, -6)]), body)  # wings
	ci.draw_colored_polygon(PackedVector2Array([Vector2(6, 6), Vector2(-4, 30), Vector2(-12, 30), Vector2(-10, 6)]), body)
	for sgn in [-1.0, 1.0]:
		ci.draw_rect(Rect2(Vector2(-12, sgn * 22 - 3), Vector2(14, 6)), body.darkened(0.2) if not shadow else body)  # engine nacelles
		ci.draw_line(Vector2(-22, sgn * 4), Vector2(-34, sgn * 9), body, 3.0)  # tail booms
	ci.draw_rect(Rect2(Vector2(-38, -11), Vector2(5, 22)), body)
	if not shadow:
		ci.draw_polyline(fus + PackedVector2Array([fus[0]]), dark, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(24, 0), Vector2(16, -4), Vector2(12, -4), Vector2(12, 4), Vector2(16, 4)]), Color(1.0, 0.7, 0.3, 0.9))  # cockpit
		for sgn in [-1.0, 1.0]:
			ci.draw_circle(Vector2(-12, sgn * 22), 3.0, Color(1.0, 0.55, 0.2, 0.8))  # engine glow
			ci.draw_rect(Rect2(Vector2(-2, sgn * 15 - 2), Vector2(8, 4)), dark)  # rocket pods
		ci.draw_circle(Vector2(22, 0), 2.2, dark)  # chin turret
		ci.draw_line(Vector2(-6, -2), Vector2(4, 2), Color(0.75, 0.62, 0.32), 1.0)  # the Legion's mark
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
