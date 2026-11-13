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
		if sq.grenade_order != null:
			var go: Dictionary = sq.grenade_order
			var gp: Vector2 = go.target.position if go.target != null and is_instance_valid(go.target) else go.point
			draw_dashed_line(sq.center(), gp, _grenade_col(go.kind, 0.5), 1.5, 5.0)
			draw_arc(gp, 9.0, 0, TAU, 16, _grenade_col(go.kind, 0.9), 1.5)
	# picking where to throw: how far each selected squad can throw, and what would go there
	if main.grenade_mode and main.started:
		var p: Vector2 = main.pointer_world
		for sq in main._player_squads():
			if not sq.selected or sq.vehicle() != null or sq.effective().is_empty():
				continue
			for m in sq.effective():
				if not m.grenades.is_empty() and m.grenades.values().any(func(n): return n > 0):
					draw_arc(m.position, GameData.THROW_RANGE, 0, TAU, 48, Color(1.0, 0.85, 0.4, 0.12), 1.0)
			if not main.touch_mode:
				var c: Array = main.grenades.choose(sq, p)
				if c[1] != null or c[0] == "smoke":
					var rr: float = GameData.GRENADES.smoke.r if c[0] == "smoke" else GameData.GRENADES[c[0]].blast
					draw_arc(p, rr, 0, TAU, 32, _grenade_col(c[0], 0.8), 1.5)
					draw_string(ThemeDB.fallback_font, p + Vector2(12, -10), {"he": "FRAG", "ap": "TANK-BREAKER", "smoke": "SMOKE"}[c[0]],
							HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _grenade_col(c[0], 0.95))
				else:
					draw_string(ThemeDB.fallback_font, p + Vector2(12, -10), c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.5, 0.4, 0.9))
	# spotted enemies under a roof: a red mark so they can still be targeted
	if main.roofs != null:
		for s in main.soldiers:
			if s.team != main.player_team and s.is_alive() and s.visible and main.roofs.hides(s.position):
				draw_arc(s.position, s.radius + 4.0, 0, TAU, 20, Color(1.0, 0.3, 0.2, 0.85), 1.6)
				draw_circle(s.position, 2.0, Color(1.0, 0.3, 0.2, 0.85))
	var chosen: Array = main.squads.filter(func(q): return q.team == main.player_team and q.selected)
	if main.started and chosen.size() <= 2:  # with more selected the rings would only clutter
		for sq in chosen:
			_draw_sight(sq)
	for sq in main.squads:
		if sq.team == main.player_team and (sq.selected or main.paused):
			_draw_route(sq)
	for sq in main.squads:
		if not sq.selected or sq.vehicle() != null:
			continue
		_draw_links(sq)
		if sq.facing != Vector2.ZERO and not sq.alive().is_empty():
			_arrow(sq.center(), sq.center() + sq.facing * 46.0, Color(0.6, 0.8, 1.0, 0.75))
	if main.t_mode == "face":
		var fa: Vector2 = main.face_anchor
		var fb: Vector2 = main.pointer_world
		draw_arc(fa, 16.0 / main.camera.zoom.x, 0, TAU, 28, Color(0.6, 0.8, 1.0, 0.9), 2.5 / main.camera.zoom.x)
		if fa.distance_to(fb) > 4.0:
			_arrow(fa, fa + (fb - fa).normalized() * maxf(40.0, fa.distance_to(fb)), Color(0.6, 0.8, 1.0, 0.95))
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


## A facing arrow: a solid white arrow with a dark edge, the same size on screen at any zoom
## (col's alpha sets how strongly it shows).
func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	var z: float = clampf(1.0 / main.camera.zoom.x, 0.2, 3.0)
	var d := (b - a).normalized()
	if d == Vector2.ZERO:
		return
	var n := d.orthogonal()
	var hw := 5.0 * z      # half the shaft's width
	var hl := 20.0 * z     # the head's length
	var hh := 13.0 * z     # half the head's width
	var tip := b
	var base := b - d * hl
	if base.distance_to(a) < hl * 0.3:
		base = a + d * hl * 0.3
	var pts := PackedVector2Array([a + n * hw, base + n * hw, base + n * hh, tip, base - n * hh, base - n * hw, a - n * hw])
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, col.a))
	draw_polyline(edge, Color(0.0, 0.0, 0.0, col.a * 0.6), 1.5 * z, true)


## While right-dragging: where each selected soldier will stand, and which way they'll face.
func _draw_line_preview() -> void:
	var a: Vector2 = main.rdrag_start
	var b: Vector2 = main.pointer_world
	var fixed_face := Vector2.ZERO
	if main.t_mode == "line_face":
		b = main.line_b
		var mid := (a + b) * 0.5
		draw_arc(b, 16.0 / main.camera.zoom.x, 0, TAU, 28, Color(0.6, 0.8, 1.0, 0.9), 2.5 / main.camera.zoom.x)
		if main.pointer_world.distance_to(mid) > 14.0 / main.camera.zoom.x:
			fixed_face = (main.pointer_world - mid).normalized()
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
		var face: Vector2 = fixed_face if fixed_face != Vector2.ZERO else main.line_facing(sq, a, b)
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
		if last and o.face != Vector2.ZERO:
			_arrow(p, p + o.face * 30.0, Color(0.6, 0.8, 1.0, 0.85))
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


func _grenade_col(kind: String, a: float) -> Color:
	return Color({"he": Color(1.0, 0.45, 0.25), "ap": Color(1.0, 0.8, 0.3), "smoke": Color(0.8, 0.85, 0.9)}[kind], a)


var sight_cache := {}  # squad -> [time worked out, centre, outline points]
const RAYS := 96


## What a selected squad can see: an area out to sight range, cut off by walls, wrecks,
## hedges and smoke; a fainter ring where they can still pick out men keeping still in
## cover; and a ring for the reach of each of their weapons.
func _draw_sight(sq: Squad) -> void:
	var men: Array = sq.effective()
	if men.is_empty():
		return
	var c := Vector2.ZERO
	for m in men:
		c += m.position
	c /= men.size()
	var map: BattleMap = main.map
	var cached = sight_cache.get(sq)
	var pts: PackedVector2Array
	if cached == null or main.time - float(cached[0]) > 0.3 or c.distance_to(cached[1]) > 8.0 or main.paused:
		pts = PackedVector2Array()
		var reach: float = main.SIGHT
		for i in RAYS:
			var dir := Vector2.from_angle(i * TAU / RAYS)
			var d := 12.0
			var start := map.cell_of(c)
			while d < reach:
				var p := c + dir * d
				var cell := map.cell_of(p)
				var t := map.get_t(cell)
				if cell != start and (map.blocks(t) or t == BattleMap.T.HEDGE):
					break
				var smoked := false
				for s in map.smoke_screens:
					if p.distance_to(s[0]) < float(s[1]):
						smoked = true
				if smoked:
					break
				d += 8.0
			pts.append(c + dir * minf(d, reach))
		sight_cache[sq] = [main.time, c, pts]
	else:
		pts = cached[2]
	var fill := Color(1.0, 0.95, 0.7, 0.07)
	var none := PackedVector2Array()
	for i in pts.size():
		draw_primitive(PackedVector2Array([c, pts[i], pts[(i + 1) % pts.size()]]), PackedColorArray([fill, fill, fill]), none)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(1.0, 0.95, 0.7, 0.35), 1.0)
	draw_arc(c, main.SIGHT_HIDDEN, 0, TAU, 64, Color(1.0, 0.95, 0.7, 0.18), 1.0)  # spots men keeping still in cover
	# weapon reach: one ring per weapon, labelled
	var seen := {}
	var weapons: Array = []
	var v = sq.vehicle()
	if v != null:
		for sl in v.slots:
			weapons.append(sl.weapon)
	else:
		for m in men:
			weapons.append(m.weapon)
	var k := 0
	for w in weapons:
		if seen.has(w.name):
			continue
		seen[w.name] = true
		var r: float = w.range
		draw_arc(c, r, 0, TAU, 96, Color(1.0, 0.55, 0.25, 0.55), 1.4)
		draw_string(ThemeDB.fallback_font, c + Vector2(-40, -r - 4 - k * 0.0), w.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.65, 0.35, 0.9))
		k += 1
