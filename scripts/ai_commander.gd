class_name AICommander
extends RefCounted
## A simple computer opponent: advance on the chapel from cover to cover,
## stop and fight when the enemy is in range, close in when they're a bit further.

var main: Node
var team := 1
var timer := 1.0
var goals := {}


func _init(m: Node, t: int) -> void:
	main = m
	team = t


func tick(dt: float) -> void:
	if "--debug-assault" in OS.get_cmdline_user_args():
		debug(dt)
	timer -= dt
	if timer > 0.0:
		return
	timer = randf_range(2.0, 3.0)
	for sq in main.squads:
		if sq.team == team:
			_think(sq)


func _goal(sq: Squad) -> Vector2:
	if not goals.has(sq):
		var r: Rect2 = main.map.objective_rect
		goals[sq] = r.position + Vector2(randf(), randf()) * r.size
	return goals[sq]


## Carriers drive their squad up and drop it off near the chapel or when the enemy
## gets close; tanks advance and stop to shoot when they find targets.
func _think_vehicle(v: Vehicle) -> void:
	if not v.is_alive():
		return
	var c := v.position
	var goal := _goal(v.squad)
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	var d: float = INF if enemy == null else c.distance_to(enemy.position)
	if v.passengers.size() > 0:
		if d < 330.0 or c.distance_to(goal) < 280.0 or v.hp < v.max_hp * 0.5:
			v.halt()
			v.unload()
		elif not v.moving:
			v.go_to(c.move_toward(goal, 400.0), true)
		return
	if d < v.main_range() * 0.85:
		if v.moving:
			v.halt()
		return
	if v.moving:
		return
	if d < v.main_range() * 1.5:
		v.go_to(c.move_toward(enemy.position, 150.0), false)
	elif c.distance_to(goal) > 200.0:
		v.go_to(c.move_toward(goal, 240.0), false)


func _think(sq: Squad) -> void:
	var v = sq.vehicle()
	if v != null:
		_think_vehicle(v)
		return
	var ready := sq.effective()
	if ready.is_empty():
		return
	var c := sq.center()
	if sq.grenade_order != null or _grenade(sq, ready):
		return  # busy throwing
	if ready.any(func(m): return m.charger):
		_think_assault(sq, ready, c)
		return
	var rng: float = ready[0].weapon.range
	var busy := ready.any(func(m): return m.moving)
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	if enemy != null:
		var d := c.distance_to(enemy.position)
		sq.facing = (enemy.position - c).normalized()  # watch the enemy
		if d < rng * 0.8:
			if busy and sq.running:
				sq.order_move(main.map, c, false)  # stop running and get into cover here
			return
		if d < rng * 1.6 and not busy:
			# if another of ours is already fighting this enemy, come at them from the side
			var engaged = null
			for o in main.squads:
				if o != sq and o.team == team and not o.effective().is_empty() and o.center().distance_to(enemy.position) < rng * 0.85:
					engaged = o
					break
			if engaged != null and not "--no-ai-flank" in OS.get_cmdline_user_args():
				var axis: Vector2 = (enemy.position - engaged.center()).normalized()
				var side := axis.orthogonal()
				if (c - enemy.position).dot(side) < 0.0:
					side = -side  # swing round on whichever side we're already on
				var flank_spot: Vector2 = enemy.position + side * rng * 0.6 - axis * 40.0
				sq.order_move(main.map, c.move_toward(flank_spot, 160.0), false)
			else:
				sq.order_move(main.map, c.move_toward(enemy.position, 110.0), false)
			return
	if busy:
		return
	var goal := _goal(sq)
	if c.distance_to(goal) < 50.0:
		return
	sq.order_move(main.map, c.move_toward(goal, 260.0), enemy == null and c.distance_to(goal) > 450.0)


## Assault troops close in on the nearest enemy foot soldiers, from cover to cover while
## they're far off and at a run for the last stretch; the men charge in themselves.
func _think_assault(sq: Squad, ready: Array, c: Vector2) -> void:
	var enemy: Soldier = null
	var bd := INF
	for s in main.soldiers:
		if s.team == team or s.is_vehicle or not s.is_alive() or not s.seen_by[team] or s.state == Soldier.State.ROUTING:
			continue
		var d := c.distance_to(s.position)
		if d < bd:
			bd = d
			enemy = s
	if ready.any(func(m): return m.in_melee or m.charging != null):
		return  # already stuck in
	if enemy == null:
		if not ready.any(func(m): return m.moving):
			var goal := _goal(sq)
			if c.distance_to(goal) > 50.0:
				sq.order_move(main.map, c.move_toward(goal, 260.0), c.distance_to(goal) > 450.0)
		return
	sq.facing = (enemy.position - c).normalized()
	if bd < 190.0:
		sq.order_move(main.map, enemy.position, true)  # go in hard for the last stretch
	elif not ready.any(func(m): return m.moving):
		sq.order_move(main.map, c.move_toward(enemy.position, minf(140.0, bd - 120.0)), false)  # cover to cover


var dbg_t := 0.0
func debug(dt: float) -> void:
	dbg_t -= dt
	if dbg_t > 0.0:
		return
	dbg_t = 10.0
	for sq in main.squads:
		if sq.team == team and sq.members.any(func(m): return m.charger):
			var st := []
			for m in sq.members:
				st.append("%s%s%s" % [["R", "P", "X", "D", "F", "E"][m.state], "M" if m.in_melee else "", "C" if m.charging != null else ""])
			var e: Soldier = main.nearest_seen_enemy(team, sq.center())
			print("t=%d %s at %s run=%s enemy_d=%d %s" % [main.time, sq.name, sq.center().round(), sq.running, -1 if e == null else int(e.position.distance_to(sq.center())), " ".join(st)])


## Throw a grenade when it's worth it: a tank-breaker at armour in reach, now and then a
## frag at enemy infantry close by (more often if they're dug in or lying low).
func _grenade(sq: Squad, ready: Array) -> bool:
	if "--no-ai-grenades" in OS.get_cmdline_user_args():
		return false
	var reach := GameData.THROW_RANGE * 0.9
	for e in main.soldiers:
		if e.team == team or not e.is_alive() or not e.seen_by[team] or e.state == Soldier.State.EMBARKED:
			continue
		var near := false
		for m in ready:
			if m.position.distance_to(e.position) < reach and main.map.los_clear(m.position, e.position):
				near = true
				break
		if not near:
			continue
		if e.is_vehicle and sq.grenade_count("ap") > 0:
			main.grenades.order(sq, e.position)
			return true
		if not e.is_vehicle and sq.grenade_count("he") > 0:
			var cover: float = main.map.cell_cover(main.map.cell_of(e.position))
			if randf() < (0.5 if cover > 0.2 or e.grounded() else 0.2):
				main.grenades.order(sq, e.position)
				return true
	return false
