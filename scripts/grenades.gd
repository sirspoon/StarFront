class_name Grenades
extends Node2D
## Grenades: the player picks a spot and the selected squads throw what suits it. At
## enemy armour they throw tank-breaker charges, at enemy infantry frag grenades, and at
## open ground smoke grenades, laying a screen there. Squads out of range move up until
## a man who has the right grenade can reach. Also keeps the smoke screens, which block
## sight (BattleMap.los_clear checks them).

const RANGE := GameData.THROW_RANGE
const G := GameData.GRENADES

var main: Node
var flying: Array = []   # {from, to, t, dur, kind, thrower}
var screens: Array = []  # {pos, r, t, node}
var check := 0.0


func setup(m: Node) -> void:
	main = m
	z_index = 6  # in flight, grenades pass over everything on the ground


## What a squad would throw at p, and at whom: [kind, target or null], or [message, null]
## when it has nothing suitable. kind is "he", "ap" or "smoke".
func choose(sq: Squad, p: Vector2) -> Array:
	var veh: Soldier = null
	var inf: Soldier = null
	var vd := INF
	var idist := INF
	for e in main.soldiers:
		if e.team == sq.team or not e.is_alive() or not e.seen_by[sq.team] or e.state == Soldier.State.EMBARKED:
			continue
		var d: float = e.position.distance_to(p)
		if e.is_vehicle and d < e.radius + 30.0 and d < vd:
			vd = d
			veh = e
		elif not e.is_vehicle and d < 60.0 and d < idist:
			idist = d
			inf = e
	if veh != null:
		return ["ap", veh] if sq.grenade_count("ap") > 0 else ["no anti-tank charges left", null]
	if inf != null:
		return ["he", inf] if sq.grenade_count("he") > 0 else ["no frag grenades left", null]
	return ["smoke", null] if sq.grenade_count("smoke") > 0 else ["no smoke grenades left", null]


## The player's order: the squad throws at p. Returns a line for the battle log.
func order(sq: Squad, p: Vector2) -> String:
	if sq.vehicle() != null or sq.effective().is_empty():
		return ""
	var c := choose(sq, p)
	if c[1] == null and c[0] != "smoke":
		return "%s: %s." % [sq.name, c[0]]
	var n: int = {"he": 2, "ap": 1, "smoke": 2}[c[0]]
	sq.grenade_order = {"point": p, "kind": c[0], "target": c[1], "left": mini(n, sq.grenade_count(c[0])),
			"next": 0.0, "moved": false, "age": 0.0, "thrown": 0}
	return "%s: %s!" % [sq.name, {"he": "frag out", "ap": "tank-breaker", "smoke": "smoke screen"}[c[0]]]


func _process(dt: float) -> void:
	if main.paused or not main.started:
		return
	for g in flying.duplicate():
		g.t += dt
		if g.t >= g.dur:
			flying.erase(g)
			_burst(g)
	queue_redraw()
	for s in screens.duplicate():
		s.t -= dt
		s.r = minf(float(G.smoke.r), s.r + dt * 30.0)  # billows out over the first second or so
		if s.t <= 7.0 and s.node != null and s.node.emitting:
			s.node.emitting = false  # thins out and drifts away
		if s.t <= 0.0:
			screens.erase(s)
			if s.node != null:
				s.node.queue_free()
	var circles: Array = []
	for s in screens:
		if s.t > 2.0:
			circles.append([s.pos, s.r * (1.0 if s.t > 7.0 else s.t / 7.0)])
	main.map.smoke_screens = circles
	check -= dt
	if check > 0.0:
		return
	check = 0.2
	for sq in main.squads:
		if sq.grenade_order != null:
			_carry_out(sq, 0.2)


func _carry_out(sq: Squad, dt: float) -> void:
	var o: Dictionary = sq.grenade_order
	o.age += dt
	o.next -= dt
	var kind: String = o.kind
	var t = o.target
	if t != null and (not is_instance_valid(t) or not t.is_alive()):
		if o.thrown > 0:
			sq.grenade_order = null  # got him
			return
		t = null
		o.target = null
	var aim: Vector2 = t.position if t != null else o.point
	if o.age > 25.0 or o.left <= 0 or sq.grenade_count(kind) <= 0:
		sq.grenade_order = null
		return
	if o.next > 0.0:
		return
	var best: Soldier = null
	var bd := INF
	var nearest: Soldier = null  # nearest man with the grenade, clear throw or not
	var nd := INF
	for m in sq.effective():
		if m.state != Soldier.State.READY or m.in_melee or m.grenades.get(kind, 0) <= 0:
			continue
		var d: float = m.position.distance_to(aim)
		if d < nd:
			nd = d
			nearest = m
		if d <= RANGE and d < bd and _clear_throw(m, aim, kind):
			bd = d
			best = m
	if nearest == null:
		return  # nobody able just now (pinned, fighting): try again shortly
	if best == null:
		if not o.moved and not sq.effective().any(func(m): return m.moving):
			# out of reach, or a wall in the way: move up to a spot with a clear throw
			o.moved = true
			sq.order_move(main.map, aim + (nearest.position - aim).normalized() * RANGE * 0.6, false, false, true)
		elif o.moved and not sq.effective().any(func(m): return m.moving):
			o.moved = false  # got there and still no clear throw: try again from here
		return
	var spot := aim
	if kind == "smoke" and o.left > 0:
		# two grenades side by side make a screen across the line of sight
		var across := (aim - best.position).normalized().orthogonal()
		spot += across * (20.0 if o.thrown % 2 == 0 else -20.0)
	_throw(best, kind, spot)
	o.left -= 1
	o.thrown += 1
	o.next = 0.4


## Can m throw at aim without it hitting a wall on the way, or bursting on top of himself
## or his own side?
func _clear_throw(m: Soldier, aim: Vector2, kind: String) -> bool:
	if main.map.first_obstacle(m.position, aim) != aim:
		return false  # a wall between: it would bounce back at him
	if kind == "smoke":
		return true
	var safe: float = float(G[kind].blast) + 12.0
	if m.position.distance_to(aim) < safe + 6.0:
		return false  # too close to throw it safely
	for f in main.soldiers:
		if f.team == m.team and f.is_alive() and not f.is_vehicle and f.state != Soldier.State.EMBARKED \
				and f.position.distance_to(aim) < safe:
			return false  # one of ours is in the blast
	return true


func _throw(m: Soldier, kind: String, spot: Vector2) -> void:
	m.grenades[kind] -= 1
	m.facing = (spot - m.position).angle()
	m.swing = 1.0
	m.cooldown = maxf(m.cooldown, 1.2)
	m.burst_left = 0
	var d := m.position.distance_to(spot)
	var land := spot + Vector2.from_angle(randf() * TAU) * randf() * d * 0.12  # nobody throws perfectly
	var hit_wall: Vector2 = main.map.first_obstacle(m.position, land)
	if hit_wall != land:
		land = hit_wall.move_toward(m.position, 6.0)  # glanced off a wall
	if kind != "smoke" and land.distance_to(m.position) < float(G[kind].blast) + 10.0:
		land = spot  # never let the scatter drop it at his own feet
	flying.append({"from": m.position, "to": land, "t": 0.0, "dur": 0.45 + d / 320.0, "kind": kind, "thrower": m})
	main.grenades_thrown[m.team] += 1


func _burst(g: Dictionary) -> void:
	var at: Vector2 = g.to
	var thrower: Soldier = g.thrower if is_instance_valid(g.thrower) else null
	var show: bool = main.effects_visible_at(at) or (thrower != null and thrower.visible)
	match g.kind:
		"he":
			main._blast(at, G.he, thrower, show)
		"ap":
			main._blast(at, G.ap, thrower, show)
			for v in main.soldiers:
				if v.is_vehicle and v.is_alive() and v.position.distance_to(at) < v.radius + 10.0:
					var from: Vector2 = thrower.position if thrower != null else at
					var got_in: bool = v.receive_hit(G.ap, from, thrower)
					if show:
						if got_in:
							main.effects.explosion(v.position, 14.0)
						else:
							main.effects.spark(at)
							main.sfx.play("clang", at, 0.0, 0.1)
					break
		"smoke":
			main.sfx.play("smoke", at)
			screens.append({"pos": at, "r": 8.0, "t": float(G.smoke.duration), "node": _smoke_node(at)})


func _smoke_node(at: Vector2) -> Node2D:
	if not main.map_view.enabled:
		return null
	var sm := SimpleParticles.new()
	sm.texture = main._dot_tex if main._dot_tex != null else main._soft_dot(64)
	sm.position = at
	sm.amount = 70
	sm.lifetime = 7.0
	sm.preprocess = 0.0
	sm.emission_radius = 24.0
	sm.direction = Vector2(0.5, -0.3)
	sm.spread = 180.0
	sm.gravity = Vector2(3, -1)
	sm.velocity_min = 4.0
	sm.velocity_max = 16.0
	sm.damping = 2.0
	sm.scale_min = 1.1
	sm.scale_max = 1.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	sm.scale_curve = curve
	sm.color_ramp = main._ramp([Color(0.62, 0.62, 0.6, 0.0), Color(0.6, 0.6, 0.58, 0.8), Color(0.55, 0.55, 0.53, 0.0)])
	sm.z_index = 5
	sm.emitting = true
	main.add_child(sm)
	return sm


func _draw() -> void:
	for g in flying:
		var k: float = g.t / g.dur
		var p: Vector2 = g.from.lerp(g.to, k)
		var h: float = sin(k * PI) * g.from.distance_to(g.to) * 0.25  # the arc of the throw
		draw_circle(p + Vector2(2, 2), 2.0, Color(0, 0, 0, 0.35))
		var col: Color = {"he": Color(0.25, 0.27, 0.2), "ap": Color(0.3, 0.25, 0.15), "smoke": Color(0.5, 0.5, 0.48)}[g.kind]
		draw_circle(p - Vector2(0, h), 2.4, col)
		draw_arc(p - Vector2(0, h), 2.4, 0, TAU, 8, Color(0, 0, 0, 0.6), 0.8)
