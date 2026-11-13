class_name AICommander
extends RefCounted
## The computer's commander. It splits its infantry between three lanes (north, centre,
## south) so they come at the objective from several sides; squads sharing a lane take turns
## to move while the others cover them (fire and movement); when one squad is in a firefight
## the others nearby swing out wide and come at the enemy from the side their lane is on;
## heavy guns and mortars hang back as a base of fire. Each squad still fights from cover
## and stops to shoot when the enemy is in range.
## (--ai-old=0|1|all: that side uses the old, simpler commander, for comparisons.)

var main: Node
var team := 1
var timer := 1.0
var goals := {}
var old := false
var lane := {}     # squad -> -1 (north), 0 (centre), 1 (south)
var support := {}  # squads that hang back as the base of fire (heavy guns, stubbers, mortars)


func _init(m: Node, t: int) -> void:
	main = m
	team = t
	for a in OS.get_cmdline_user_args():
		if a == "--ai-old=all" or a == "--ai-old=%d" % t:
			old = true


## Lanes: spread the line squads across north, centre and south (the assault troops out on a
## flank), and keep the heavy weapons back as support.
func _plan() -> void:
	var line: Array = []
	for sq in main.squads:
		if sq.team != team or sq.vehicle() != null:
			continue
		var heavy: bool = sq.members.any(func(m): return m.heavy or m.mortar) or sq.members.all(func(m): return m.kind == "gunner" or m.is_leader)
		if heavy:
			support[sq] = true
			lane[sq] = 0
		else:
			line.append(sq)
	var order := [-1, 1, 0]
	var i := randi() % 3
	for sq in line:
		if sq.members.any(func(m): return m.charger):
			lane[sq] = [-1, 1][randi() % 2]  # assault troops go round a flank
		else:
			lane[sq] = order[i % 3]
			i += 1


## Where a squad heads next: along its lane until level with the objective, then in.
func _waypoint(sq: Squad, c: Vector2) -> Vector2:
	var goal := _goal(sq)
	var l: int = lane.get(sq, 0)
	if l == 0:
		return goal
	var obj: Rect2 = main.map.objective_rect
	var lane_y: float = obj.get_center().y + l * (obj.size.y * 0.5 + 280.0)
	lane_y = clampf(lane_y, 120.0, BattleMap.H * BattleMap.CELL - 120.0)
	var dx := absf(c.x - goal.x)
	if dx > 260.0 and absf(c.y - lane_y) > 90.0:
		return Vector2(c.x + signf(goal.x - c.x) * minf(dx * 0.5, 300.0), lane_y)  # out into the lane
	if dx > 260.0:
		return Vector2(goal.x - signf(goal.x - c.x) * 200.0, lane_y)  # up the lane, level with the objective
	return goal


## Fire and movement: a squad moves up only while another of its lane (or the support) is
## in place to cover it. Alone, it just goes.
func _covered(sq: Squad) -> bool:
	var l: int = lane.get(sq, 0)
	var mates := 0
	for o in main.squads:
		if o == sq or o.team != team or o.vehicle() != null or o.effective().is_empty():
			continue
		if lane.get(o, 99) != l and not support.has(o):
			continue
		mates += 1
		if not o.busy() and o.status() != "Pinned" and o.status() != "Routing":
			return true
	return mates == 0


func tick(dt: float) -> void:
	if "--debug-assault" in OS.get_cmdline_user_args():
		debug(dt)
	timer -= dt
	if timer > 0.0:
		return
	timer = randf_range(2.0, 3.0)
	if not old and lane.is_empty():
		_plan()
	_note_spread()
	for sq in main.squads:
		if sq.team == team and not sq.no_ai:
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
	var idx: int = v.squad.members.find(v)
	goal += Vector2(0, (idx - 1) * 70.0) if v.squad.members.size() > 1 else Vector2.ZERO  # a squadron spreads out
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
		for o in sq.vehicles():
			_think_vehicle(o)
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
	if sq.has_mortars():
		_think_mortar(sq, ready, c)
		return
	if not old:
		_think_line(sq, ready, c)
		return
	if ready.any(func(m): return m.heavy):
		if _think_heavy(sq, ready, c):
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


## Line infantry (and support), the new way: lanes, fire and movement, wide flanking.
func _think_line(sq: Squad, ready: Array, c: Vector2) -> void:
	if ready.any(func(m): return m.heavy):
		if _think_heavy(sq, ready, c):
			return
	var rng: float = ready[0].weapon.range
	var busy := ready.any(func(m): return m.moving)
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	if enemy != null:
		var d := c.distance_to(enemy.position)
		sq.facing = (enemy.position - c).normalized()
		if d < rng * 0.8:
			if busy and sq.running:
				sq.order_move(main.map, c, false)  # stop running and get into cover here
			return
		if support.has(sq):
			if not busy and d < rng * 1.4:
				sq.order_move(main.map, c.move_toward(enemy.position, minf(100.0, d - rng * 0.75)), false)
			elif not busy:
				sq.order_move(main.map, c.move_toward(enemy.position, 140.0), false)
			return
		if d < rng * 2.0 and not busy:
			# someone of ours already fighting this enemy? then come at them wide, from our lane's side
			var engaged = null
			for o in main.squads:
				if o != sq and o.team == team and not o.effective().is_empty() and o.center().distance_to(enemy.position) < rng * 0.9:
					engaged = o
					break
			if engaged != null and not "--no-ai-flank" in OS.get_cmdline_user_args():
				var axis: Vector2 = (enemy.position - engaged.center()).normalized()
				var side := axis.orthogonal()
				var l: int = lane.get(sq, 0)
				var want := side if l == 0 else (side if side.y * l > 0 else -side)
				if l == 0 and (c - enemy.position).dot(side) < 0.0:
					want = -side
				var flank_spot: Vector2 = enemy.position + want * rng * 0.8 - axis * 20.0
				# a long way round: run the open stretches
				sq.order_move(main.map, c.move_toward(flank_spot, 200.0), c.distance_to(flank_spot) > 260.0)
			elif _covered(sq):
				sq.order_move(main.map, c.move_toward(enemy.position, 120.0), false)  # a bound forward, covered
			return
	if busy:
		return
	var wp := _waypoint(sq, c)
	if c.distance_to(wp) < 50.0:
		return
	if enemy != null and not _covered(sq):
		return  # wait for cover before the next bound
	sq.order_move(main.map, c.move_toward(wp, 240.0), enemy == null and c.distance_to(wp) > 450.0)


## Test aid: how widely each side's infantry spreads north-south (on the way in), every think.
func _note_spread() -> void:
	if main.time > 240.0:
		return
	var ys: Array = []
	for sq in main.squads:
		if sq.team == team and sq.vehicle() == null and not sq.alive().is_empty():
			ys.append(sq.center().y)
	if ys.size() < 2:
		return
	var mean := 0.0
	for y in ys:
		mean += y
	mean /= ys.size()
	var v := 0.0
	for y in ys:
		v += (y - mean) * (y - mean)
	main.ai_spread[team][0] += sqrt(v / ys.size())
	main.ai_spread[team][1] += 1


## Mortar teams stay back: once enemies are within reach they stop and fire (the barrage
## picks its own targets, see Mortars); otherwise they move up behind the line, keeping
## well clear of the enemy.
func _think_mortar(sq: Squad, ready: Array, c: Vector2) -> void:
	if ready.any(func(m): return m.moving):
		return
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	var reach: float = GameData.WEAPONS.mortar.range
	if enemy != null:
		var d := c.distance_to(enemy.position)
		sq.facing = (enemy.position - c).normalized()
		if d < 330.0:
			sq.order_move(main.map, c + (c - enemy.position).normalized() * 160.0, true)  # too close: fall back
			return
		if d < reach * 0.8:
			return
	var goal := _goal(sq)
	if c.distance_to(goal) > reach * 0.6:
		sq.order_move(main.map, c.move_toward(goal, 200.0), false)


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


## Heavy gun teams: in range of the enemy, stop and get the gun set up (lying Down if
## there's nothing to rest it on); otherwise get up and move like anyone else.
func _think_heavy(sq: Squad, ready: Array, c: Vector2) -> bool:
	var gunner = ready.filter(func(m): return m.heavy)[0]
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	var rng: float = gunner.weapon.range
	if enemy != null and c.distance_to(enemy.position) < rng * 0.85:
		sq.facing = (enemy.position - c).normalized()
		if ready.any(func(m): return m.moving):
			sq.order_move(main.map, c, false)  # stop here
		elif not gunner.can_brace() and not sq.prone:
			sq.set_prone(true)
		return true
	if sq.prone:
		sq.set_prone(false)
	return false
