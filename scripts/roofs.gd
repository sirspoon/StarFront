class_name Roofs
extends Node2D
## The buildings' roofs, drawn over everything inside them. A building's roof fades
## away while any of the player's soldiers is inside it or just outside it, so the
## player can see in. Roofs are repainted when shells break them or walls fall.

const C := BattleMap.CELL

var main: Node
var map: BattleMap
var nodes: Array = []      # one RoofPiece per building
var alpha: Array = []      # current opacity of each roof
var check_timer := 0.0


func setup(m: Node) -> void:
	main = m
	map = m.map
	z_index = 3  # above soldiers and wrecks, below smoke, fire and shots
	for i in map.buildings.size():
		var piece := RoofPiece.new()
		piece.roofs = self
		piece.index = i
		piece.light_mask = 2  # only the moon lights roofs: no wall shadows or fire glow cut into blocks
		add_child(piece)
		nodes.append(piece)
		alpha.append(1.0)
	map.roof_changed.connect(func(b): nodes[b].queue_redraw())


## Is any of the player's soldiers in or right beside building i?
func player_near(i: int) -> bool:
	var r: Rect2i = map.buildings[i]
	var area := Rect2(Vector2(r.position * C), Vector2(r.size * C)).grow(C * 2.0)
	for s in main.soldiers:
		if s.team == main.player_team and s.is_alive() and area.has_point(s.position):
			return true
	return false


var textured := false


func _process(dt: float) -> void:
	if not textured and main.map_view.ready_drawn:
		textured = true  # the ground textures are ready: repaint with them
		for n in nodes:
			n.queue_redraw()
	check_timer -= dt
	if check_timer <= 0.0:
		check_timer = 0.2
		for i in nodes.size():
			nodes[i].set_meta("open", player_near(i))
	for i in nodes.size():
		var target := 0.0 if nodes[i].get_meta("open", false) else 1.0
		alpha[i] = move_toward(alpha[i], target, dt * 3.0)
		nodes[i].modulate.a = alpha[i]
		nodes[i].visible = alpha[i] > 0.01


## Whether a roof hides point p (used to mark spotted enemies under one).
func hides(p: Vector2) -> bool:
	var c := map.cell_of(p)
	if not map.in_bounds(c) or map.roof_at(c) <= 0.0:
		return false
	var b := map.building_of[c.y * BattleMap.W + c.x]
	return b >= 0 and alpha[b] > 0.5


class RoofPiece:
	extends Node2D
	var roofs: Roofs
	var index := 0

	const HOLE := Color(0.06, 0.05, 0.05, 0.9)

	func _h(a: int, b: int, k: int) -> float:
		return float(hash(Vector3i(a, b, k + roofs.map.map_seed)) % 10000) / 10000.0

	## A broken roof edge from a to b, the hole lying in direction d: the edge wanders,
	## biting into the roof here (dark, the torn slates' shadow) and leaving broken slates
	## hanging out over the hole there. The ends depend only on the corner they sit on,
	## so the edges of neighbouring cells join up.
	func _ragged_edge(a: Vector2, b: Vector2, d: Vector2i, x: int, y: int, col: Color) -> void:
		var inward := -Vector2(d)
		var n := 8
		# the depth at each end belongs to the corner it sits on (a wide, slow wander shared
		# with the next cell), plus a smaller bump in between and a little splintering
		var e0 := (_h(int(a.x), int(a.y), 200 + d.x * 2 + d.y) - 0.4) * 14.0
		var e1 := (_h(int(b.x), int(b.y), 200 + d.x * 2 + d.y) - 0.4) * 14.0
		var bump := (_h(x, y, 205 + d.x * 2 + d.y) - 0.5) * 8.0
		var base := PackedVector2Array()
		var prof := PackedVector2Array()
		var depth := PackedFloat32Array()
		for k in n + 1:
			var t := float(k) / n
			var p := a.lerp(b, t)
			var dep := lerpf(e0, e1, smoothstep(0.0, 1.0, t)) + bump * sin(t * PI)
			if k > 0 and k < n:
				dep += (_h(x * 9 + k, y, 210 + d.x * 2 + d.y) - 0.5) * 3.0
			base.append(p)
			depth.append(dep)
			prof.append(p + inward * dep)
		var none := PackedVector2Array()
		for k in n:
			var b0 := base[k]
			var b1 := base[k + 1]
			var c0 := HOLE if depth[k] > 0.0 else col
			var c1 := HOLE if depth[k + 1] > 0.0 else col
			if (depth[k] > 0.0) == (depth[k + 1] > 0.0):
				draw_primitive(PackedVector2Array([b0, prof[k], prof[k + 1], b1]), PackedColorArray([c0, c0, c0, c0]), none)
			else:  # the edge crosses the cell's border: split where it does
				var m := b0.lerp(b1, depth[k] / (depth[k] - depth[k + 1]))
				draw_primitive(PackedVector2Array([b0, prof[k], m]), PackedColorArray([c0, c0, c0]), none)
				draw_primitive(PackedVector2Array([m, prof[k + 1], b1]), PackedColorArray([c1, c1, c1]), none)
		# the torn edge: a dark lip of broken slate, and its shadow falling into the hole
		var shade := Color(0, 0, 0, 0.3)
		for k in n:
			draw_primitive(PackedVector2Array([prof[k], prof[k] + Vector2(d) * 3.5, prof[k + 1] + Vector2(d) * 3.5, prof[k + 1]]),
				PackedColorArray([shade, Color(0, 0, 0, 0), Color(0, 0, 0, 0), shade]), none)
		draw_polyline(prof, col.darkened(0.55), 1.0)
		# a rafter sometimes sticks out into the hole
		if _h(x, y, 40 + d.x + d.y * 3) < 0.4:
			var t := 0.3 + _h(x, y, 45 + d.x) * 0.4
			var m := a.lerp(b, t) + inward * lerpf(e0, e1, t)
			draw_line(m + inward * 3.0, m + Vector2(d) * (4.0 + _h(x, y, 47 + d.y) * 6.0), Color(0.3, 0.21, 0.13), 1.6)


	func _draw() -> void:
		var map: BattleMap = roofs.map
		var r: Rect2i = map.buildings[index]
		var horiz := r.size.x >= r.size.y  # the ridge runs along the longer side
		var ridge := (r.position.y + r.size.y * 0.5) * C if horiz else (r.position.x + r.size.x * 0.5) * C
		var is_chapel := r == map.chapel
		var slate := Color(0.23, 0.235, 0.245) if not is_chapel else Color(0.31, 0.31, 0.3)  # chapel: old lead
		slate = slate.lightened((_h(index, 0, 1) - 0.5) * 0.1)
		var has := func(c: Vector2i) -> bool: return map.in_bounds(c) and map.roof_at(c) > 0.0 and r.has_point(c)
		# shadow thrown on the ground beyond the eaves
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				if has.call(Vector2i(x, y)):
					draw_rect(Rect2(Vector2(x, y) * C + Vector2(5, 6), Vector2(C, C)), Color(0, 0, 0, 0.3))
		for pass_no in 3:  # slates, then damage, then edges: nothing gets cut off at a cell border
			for x in range(r.position.x, r.end.x):
				for y in range(r.position.y, r.end.y):
					var c := Vector2i(x, y)
					if not has.call(c):
						continue
					var o := Vector2(c) * C
					var centre := o + Vector2(C, C) * 0.5
					# a pitched roof: the side facing the top-left catches the light
					var lit: bool = (centre.y < ridge) if horiz else (centre.x < ridge)
					var col := slate.lightened(0.06) if lit else slate.darkened(0.12)
					if pass_no == 0:
						draw_rect(Rect2(o, Vector2(C, C)).grow(0.3), col)
						var mv = roofs.main.map_view
						if mv.ground_grit != null:  # weathering: the same grit as the ground and walls
							var g: Texture2D = mv.ground_grit
							var gs := Vector2(g.get_width(), g.get_height())
							var src := Rect2(Vector2(fposmod(o.x * 2.0, gs.x - 32.0), fposmod(o.y * 2.0, gs.y - 32.0)), Vector2(32, 32))
							draw_texture_rect_region(g, Rect2(o, Vector2(C, C)), src, Color(1, 1, 1, 0.9))
						# courses of slates, staggered
						for k in 4:
							var along := k * 4.0
							var off := 2.0 if (y * 4 + k) % 2 == 0 else 0.0
							if horiz:
								draw_line(o + Vector2(0, along), o + Vector2(C, along), col.darkened(0.35), 0.6)
								var sx := off
								while sx < C:
									draw_line(o + Vector2(sx, along), o + Vector2(sx, along + 4), col.darkened(0.3), 0.4)
									sx += 4.0
							else:
								draw_line(o + Vector2(along, 0), o + Vector2(along, C), col.darkened(0.35), 0.6)
								var sy := off
								while sy < C:
									draw_line(o + Vector2(along, sy), o + Vector2(along + 4, sy), col.darkened(0.3), 0.4)
									sy += 4.0
						# moss, soot and slipped slates
						if _h(x, y, 3) < 0.15:
							draw_circle(o + Vector2(_h(x, y, 4), _h(x, y, 5)) * C, 2.0 + _h(x, y, 6) * 2.5, Color(0.2, 0.24, 0.16, 0.35))
						# the ridge cap
						if horiz and absf(centre.y - ridge) < C * 0.5:
							draw_rect(Rect2(o.x, ridge - 1.2, C, 2.4), slate.lightened(0.12))
						elif not horiz and absf(centre.x - ridge) < C * 0.5:
							draw_rect(Rect2(ridge - 1.2, o.y, 2.4, C), slate.lightened(0.12))
					elif pass_no == 1:
						var hp := map.roof_at(c)
						if hp < 70.0:
							# battered: soot spreading in soft blots, slates knocked askew showing the battens
							var heavy := hp <= 40.0
							for k in (3 if heavy else 2):
								var sp := o + Vector2(_h(x, y, 60 + k), _h(x, y, 70 + k)) * C
								var sr := 4.0 + _h(x, y, 80 + k) * 6.0
								var room := Rect2(Vector2(r.position * C), Vector2(r.size * C))  # keep soot off the ground outside
								sr = minf(sr, minf(minf(sp.x - room.position.x, room.end.x - sp.x), minf(sp.y - room.position.y, room.end.y - sp.y)))
								for ring in 3:
									draw_circle(sp, sr * (1.0 - ring * 0.3), Color(0.04, 0.03, 0.02, 0.12 if heavy else 0.08))
							for k in (3 if heavy else 1):
								var p := o + Vector2(_h(x, y, 10 + k), _h(x, y, 20 + k)) * (C - 4.0) + Vector2(2, 2)
								var ang := _h(x, y, 90 + k) * TAU
								var sz := 1.2 + _h(x, y, 100 + k) * 1.8
								var pts := PackedVector2Array()
								for v in 5:  # an irregular gap where slates have gone
									var va := ang + v * TAU / 5.0 + (_h(x * 7 + v, y, 110 + k) - 0.5) * 0.9
									pts.append(p + Vector2.from_angle(va) * sz * (0.6 + _h(x, y * 7 + v, 120 + k) * 0.7))
								draw_colored_polygon(pts, Color(0.1, 0.09, 0.085, 0.8))
								draw_line(p - Vector2.from_angle(ang) * sz, p + Vector2.from_angle(ang) * sz, Color(0.26, 0.19, 0.13, 0.7), 0.4)
					else:
						# edges: clean eaves at the building's edge, ragged broken edges round holes
						var hole_side := {}
						for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							if has.call(c + d):
								continue
							var a: Vector2
							var b: Vector2
							match d:
								Vector2i(1, 0):
									a = o + Vector2(C, 0)
									b = o + Vector2(C, C)
								Vector2i(-1, 0):
									a = o
									b = o + Vector2(0, C)
								Vector2i(0, 1):
									a = o + Vector2(0, C)
									b = o + Vector2(C, C)
								_:
									a = o
									b = o + Vector2(C, 0)
							if r.has_point(c + d):
								hole_side[d] = true
								_ragged_edge(a, b, d, x, y, col)
							else:
								draw_line(a, b, slate.darkened(0.5), 1.4)  # the eave
						# a corner between two broken edges is bitten away rather than left square
						for pair in [[Vector2i(1, 0), Vector2i(0, 1)], [Vector2i(1, 0), Vector2i(0, -1)], [Vector2i(-1, 0), Vector2i(0, 1)], [Vector2i(-1, 0), Vector2i(0, -1)]]:
							if hole_side.has(pair[0]) and hole_side.has(pair[1]):
								var corner: Vector2 = centre + Vector2(pair[0] + pair[1]) * C * 0.5
								var s1: float = 3.0 + _h(x, y, 130 + pair[0].x + pair[1].y * 3) * 5.0
								var s2: float = 3.0 + _h(x, y, 140 + pair[0].x + pair[1].y * 3) * 5.0
								draw_primitive(PackedVector2Array([corner, corner - Vector2(pair[0]) * s1, corner - Vector2(pair[1]) * s2]),
									PackedColorArray([HOLE, HOLE, HOLE]), PackedVector2Array())
						# the inside corner of a hole: broken slates from both sides meet across it
						for dd in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
							var diag: Vector2i = c + dd
							if r.has_point(diag) and not has.call(diag) and has.call(c + Vector2i(dd.x, 0)) and has.call(c + Vector2i(0, dd.y)):
								var corner: Vector2 = centre + Vector2(dd) * C * 0.5
								var s1: float = 3.0 + _h(x, y, 150 + dd.x + dd.y * 3) * 6.0
								var s2: float = 3.0 + _h(x, y, 160 + dd.x + dd.y * 3) * 6.0
								var sc := col
								draw_primitive(PackedVector2Array([corner, corner + Vector2(dd.x, 0) * s1, corner + Vector2(0, dd.y) * s2]),
									PackedColorArray([sc, sc, sc]), PackedVector2Array())
