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
			sq.order_move(main.map, c.move_toward(enemy.position, 110.0), false)
			return
	if busy:
		return
	var goal := _goal(sq)
	if c.distance_to(goal) < 50.0:
		return
	sq.order_move(main.map, c.move_toward(goal, 260.0), enemy == null and c.distance_to(goal) > 450.0)
