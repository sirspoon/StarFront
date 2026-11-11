extends Node2D
## Draws world-space UI on top of the battle: objective, selection box, orders.

var main: Node


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r: Rect2 = main.map.objective_rect
	var owner_team: int = main.objective_owner
	var col := Color(0.85, 0.8, 0.6, 0.5)
	if owner_team >= 0:
		col = Color(GameData.FACTIONS[main.factions[owner_team]].ui, 0.7)
	draw_rect(r.grow(4), col, false, 2.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		draw_circle(corner, 4.0, col)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(0, -26), "THE ASHEN CHAPEL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	# orders of the selected squads
	for sq in main.squads:
		if not sq.selected:
			continue
		for m in sq.members:
			if m.is_alive() and m.path_i < m.path.size():
				draw_line(m.position, m.path[m.path.size() - 1], Color(0.5, 1.0, 0.5, 0.25), 1.0)
		if sq.fire_point != null:
			var fp: Vector2 = sq.fire_point
			draw_line(sq.center(), fp, Color(1.0, 0.6, 0.2, 0.45), 1.5)
			draw_line(fp + Vector2(-6, -6), fp + Vector2(6, 6), Color(1.0, 0.6, 0.2, 0.9), 2.0)
			draw_line(fp + Vector2(-6, 6), fp + Vector2(6, -6), Color(1.0, 0.6, 0.2, 0.9), 2.0)
		if sq.focus != null and is_instance_valid(sq.focus) and sq.focus.is_alive():
			draw_line(sq.center(), sq.focus.position, Color(1.0, 0.3, 0.2, 0.4), 1.5)
	if main.dragging:
		var a: Vector2 = main.drag_start
		var b: Vector2 = get_global_mouse_position()
		var box := Rect2(a, b - a).abs()
		if box.size.length() > 8.0:
			draw_rect(box, Color(0.5, 1.0, 0.5, 0.12))
			draw_rect(box, Color(0.5, 1.0, 0.5, 0.7), false, 1.0)
