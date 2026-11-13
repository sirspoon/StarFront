class_name Mortars
extends Node
## Mortar teams fire as a battery: when the squad's salvo is ready, every set-up tube fires
## within half a second or so of the others, so the rounds land together as a barrage.
## They lob their rounds over walls, so need no sight of the target themselves: they shell
## the spot the player gave them (a fire mission), or else the nearest enemy any of their
## side can see. The rounds scatter widely, more at long range, but each salvo at the
## same mission lands a little tighter as they range in. Smoke: one salvo, then the tubes
## go back to HE and the mission ends.

const W := GameData.WEAPONS
var main: Node
var pending: Array = []  # rounds about to leave the tube: [time, gunner, aim point, kind]


func setup(m: Node) -> void:
	main = m


func _process(dt: float) -> void:
	if main.paused or not main.started or main.over or main.deploying:
		return
	var now: float = main.time
	for p in pending.duplicate():
		if now >= p[0]:
			pending.erase(p)
			_fire(p[1], p[2], p[3])
	for sq in main.squads:
		if not sq.has_mortars():
			continue
		sq.barrage_t -= dt
		if sq.barrage_t > 0.0:
			continue
		var tubes: Array = sq.members.filter(func(m): return m.mortar and m.is_alive() and m.state == Soldier.State.READY \
				and m.mortar_set >= 1.0 and not m.moving and main.map.roof_at(main.map.cell_of(m.position)) <= 0.0)
		if tubes.is_empty():
			continue
		var target = _target(sq, tubes)
		if target == null:
			sq.barrage_t = 1.0
			continue
		var kind: String = sq.mortar_kind
		if kind == "smoke":
			if sq.smoke_left <= 0:
				sq.mortar_kind = "he"  # (none left)
				sq.fire_mission = null
				continue
			sq.smoke_left -= 1  # one of the battle's smoke salvos
		# the salvo: each tube fires within half a second or so of the others
		for i in tubes.size():
			pending.append([now + i * 0.22 + randf() * 0.18, tubes[i], target, kind])
		var pinned: bool = sq.alive().any(func(m): return m.state == Soldier.State.PINNED)
		sq.barrage_t = float(W.mortar.cooldown) * randf_range(0.9, 1.1) * (1.8 if pinned else 1.0)
		if sq.fire_mission != null:
			sq.ranging += 1
		if kind == "smoke":
			# one salvo of smoke, then back to HE, and the mission is done
			sq.mortar_kind = "he"
			sq.fire_mission = null
			sq.ranging = 0
			if sq.team == main.player_team:
				main.log_message("[color=#e8c070]%s: smoke on the way (%d smoke salvos left). Back to HE.[/color]" % [sq.name, sq.smoke_left])


## Where the salvo goes: the fire mission, or the nearest enemy their side can see in range.
func _target(sq: Squad, tubes: Array):
	var c: Vector2 = tubes[0].position
	if sq.fire_mission != null:
		var d: float = c.distance_to(sq.fire_mission)
		if d <= float(W.mortar.range) and d >= float(W.mortar.min_range):
			return sq.fire_mission
		return null
	if sq.mortar_kind == "smoke":
		return null  # smoke only goes where it's told
	var best = null
	var bd := INF
	for e in main.soldiers:
		if e.team == sq.team or not e.is_alive() or not e.seen_by[sq.team] or e.state == Soldier.State.EMBARKED:
			continue
		var d: float = c.distance_to(e.position)
		if d > float(W.mortar.range) or d < float(W.mortar.min_range) + 30.0:
			continue
		# men in the open or a knot of them are worth more than one man in a building
		var near := 0
		for o in main.soldiers:
			if o.team == e.team and o.is_alive() and not o.is_vehicle and o.position.distance_to(e.position) < 50.0:
				near += 1
		var score := d - near * 60.0 + (150.0 if e.is_vehicle else 0.0)
		if score < bd:
			bd = score
			best = e.position
	return best


func _fire(m: Soldier, aim: Vector2, kind: String) -> void:
	if not is_instance_valid(m) or not m.is_alive() or m.moving:
		return
	var d := m.position.distance_to(aim)
	# wide scatter, worse at long range, tighter as they range in on a mission
	var spread := (24.0 + d * 0.075) * maxf(0.5, 1.0 - 0.15 * m.squad.ranging)
	var land := aim + Vector2.from_angle(randf() * TAU) * spread * sqrt(randf())
	land = land.clamp(Vector2(8, 8), Vector2(BattleMap.W * BattleMap.CELL - 8, BattleMap.H * BattleMap.CELL - 8))
	m.facing = (aim - m.position).angle()
	m.flash = 0.18
	m.last_fire_time = main.time
	for o in m.squad.members:  # his loader drops the next round in
		if o.is_alive() and o.data.get("mortar_loader", false) and o.position.distance_to(m.position) < 40.0:
			o.swing = 1.0
			break
	main.grenades.lob(m, land, "mortar" if kind == "he" else "smoke", 1.6 + d / 520.0)
	if m.visible or main.effects_visible_at(m.position):
		var muzzle := m.position + Vector2.from_angle(m.facing) * (m.radius + 14.0)
		main.effects.puff(muzzle, Color(0.6, 0.58, 0.54), 7.0)
		main.light_fx.flash(muzzle, Color(1.0, 0.8, 0.5), 1.4, 60.0, 0.15)
	main.sfx.play("cannon", m.position, -7.0, 0.15)


## Tell a squad's mortars to shell p. Returns a line for the battle log.
func order(sq: Squad, p: Vector2) -> String:
	if not sq.has_mortars():
		return ""
	var c := sq.center()
	var d := c.distance_to(p)
	if d > float(W.mortar.range):
		return "%s: out of range (%d, the mortars reach %d)." % [sq.name, int(d), int(W.mortar.range)]
	if d < float(W.mortar.min_range):
		return "%s: too close to fire on." % sq.name
	if sq.fire_mission == null or sq.fire_mission.distance_to(p) > 40.0:
		sq.ranging = 0
	sq.fire_mission = p
	return "%s: fire mission%s!" % [sq.name, ", smoke" if sq.mortar_kind == "smoke" else ""]
