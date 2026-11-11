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
		if not sq.selected and not (main.paused and sq.team == main.player_team):
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
	for sq in main.squads:
		if sq.team == main.player_team and (sq.selected or main.paused):
			_draw_route(sq)
	for sq in main.squads:
		if not sq.selected or sq.vehicle() != null:
			continue
		_draw_links(sq)
		if sq.facing != Vector2.ZERO and not sq.alive().is_empty():
			_arrow(sq.center(), sq.center() + sq.facing * 46.0, Color(0.6, 0.8, 1.0, 0.75))
	if main.t_mode == "held":
		var hp: Vector2 = main._screen_to_world(main.t_start)
		draw_arc(hp, 16.0 / main.camera.zoom.x, 0, TAU, 28, Color(0.55, 1.0, 0.6, 0.9), 2.5 / main.camera.zoom.x)
	if main.rdragging:
		_draw_line_preview()
	if main.dragging:
		var a: Vector2 = main.drag_start
		var b: Vector2 = get_global_mouse_position()
		var box := Rect2(a, b - a).abs()
		if box.size.length() > 8.0:
			draw_rect(box, Color(0.5, 1.0, 0.5, 0.12))
			draw_rect(box, Color(0.5, 1.0, 0.5, 0.7), false, 1.0)


## Thin links between squad-mates in contact; a red link means a soldier is out of contact.
func _draw_links(sq: Squad) -> void:
	var live: Array = sq.members.filter(func(m): return m.is_alive() and m.state != Soldier.State.ROUTING)
	var coherent := sq.is_coherent()
	for m in live:
		var near = null
		for o in live:
			if o != m and (near == null or o.position.distance_to(m.position) < near.position.distance_to(m.position)):
				near = o
		if near == null:
			continue
		var ok: bool = near.position.distance_to(m.position) <= Squad.COH
		var col := Color(0.5, 1.0, 0.5, 0.22) if ok else Color(1.0, 0.3, 0.2, 0.7)
		draw_line(m.position, near.position, col, 1.0 if ok else 1.6)
	if not coherent:
		draw_string(ThemeDB.fallback_font, sq.center() + Vector2(-26, -20), "out of contact",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.45, 0.35, 0.8))


func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	draw_line(a, b, col, 2.0)
	var d := (b - a).normalized()
	draw_line(b, b - d.rotated(0.5) * 9.0, col, 2.0)
	draw_line(b, b - d.rotated(-0.5) * 9.0, col, 2.0)


## While right-dragging: where each selected soldier will stand, and which way they'll face.
func _draw_line_preview() -> void:
	var a: Vector2 = main.rdrag_start
	var b: Vector2 = main.pointer_world
	if a.distance_to(b) <= 24.0 or Input.is_key_pressed(KEY_CTRL):
		if Input.is_key_pressed(KEY_CTRL):
			for sq in main.squads:
				if sq.selected and not sq.alive().is_empty():
					_arrow(sq.center(), sq.center() + (b - sq.center()).normalized() * 46.0, Color(0.6, 0.8, 1.0, 0.9))
		return
	draw_line(a, b, Color(0.5, 1.0, 0.5, 0.5), 1.5)
	var sel: Array = main.squads.filter(func(sq): return sq.team == main.player_team and sq.selected and sq.vehicle() == null and not sq.alive().is_empty())
	if sel.is_empty():
		return
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
		var face: Vector2 = main.line_facing(sq, a, b)
		var spots: Array = sq.line_positions(main.map, sa, sb, n, face)
		for p in spots:
			var good: bool = main.map.cell_cover_dir(main.map.cell_of(p), face) >= 0.6
			draw_circle(p, 4.0, Color(0.4, 1.0, 0.5, 0.8) if good else Color(1.0, 1.0, 1.0, 0.55))
		if not spots.is_empty():
			var mid: Vector2 = (spots[0] + spots[spots.size() - 1]) * 0.5
			_arrow(mid, mid + face * 40.0, Color(0.6, 0.8, 1.0, 0.9))
		done += n


## A squad's planned route: numbered waypoints joined up, ending in its final spot
## (or the line it will spread along).
func _draw_route(sq: Squad) -> void:
	var r: Array = sq.route()
	if r.is_empty() or sq.alive().is_empty() and sq.vehicle() == null:
		return
	var col := Color(0.55, 1.0, 0.6, 0.75)
	var prev := sq.center()
	for i in r.size():
		var o: Dictionary = r[i]
		var p: Vector2 = (o.a + o.b) * 0.5 if o.kind == "line" else o.b
		if o.run:
			col = Color(1.0, 0.8, 0.35, 0.8)
		_dashed(prev, p, col)
		if o.kind == "line":
			draw_line(o.a, o.b, col, 2.0)
			draw_circle(o.a, 3.0, col)
			draw_circle(o.b, 3.0, col)
		var last := i == r.size() - 1
		draw_circle(p, 7.0 if last else 6.0, Color(0, 0, 0, 0.55))
		draw_arc(p, 7.0 if last else 6.0, 0, TAU, 20, col, 1.5)
		draw_string(ThemeDB.fallback_font, p + Vector2(-3.5, 4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		prev = p


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var dir := (b - a) / d
	var t := 0.0
	while t < d:
		draw_line(a + dir * t, a + dir * minf(t + 6.0, d), col, 1.2)
		t += 11.0
