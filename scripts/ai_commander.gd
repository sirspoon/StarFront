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


func _think(sq: Squad) -> void:
	var ready := sq.effective()
	if ready.is_empty():
		return
	var c := sq.center()
	var rng: float = ready[0].weapon.range
	var busy := ready.any(func(m): return m.moving)
	var enemy: Soldier = main.nearest_seen_enemy(team, c)
	if enemy != null:
		var d := c.distance_to(enemy.position)
		if d < rng * 0.8:
			if busy and sq.running:
				sq.order_move(main.map, c, false)  # stop running and get into cover here
			return
		if d < rng * 1.6 and not busy:
			sq.order_move(main.map, c.move_toward(enemy.position, 110.0), false)
			return
	if busy:
		return
	if not goals.has(sq):
		var r: Rect2 = main.map.objective_rect
		goals[sq] = r.position + Vector2(randf(), randf()) * r.size
	var goal: Vector2 = goals[sq]
	if c.distance_to(goal) < 50.0:
		return
	sq.order_move(main.map, c.move_toward(goal, 260.0), enemy == null and c.distance_to(goal) > 450.0)
