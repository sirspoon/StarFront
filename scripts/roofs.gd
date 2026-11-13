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
	if not Settings.is_phone():
		# smoke from working chimneys: the works and taverns, and now and then a home
		for i in map.buildings.size():
			var kind: String = map.building_kind[i] if i < map.building_kind.size() else ""
			if kind != "industry" and kind != "tavern" and not (kind == "home" and _hh(i, 1) < 0.35):
				continue
			for p in chimneys(i):
				var sm := SimpleParticles.new()
				sm.texture = main._dot_tex if main._dot_tex != null else main._soft_dot(64)
				sm.position = p
				sm.amount = 10
				sm.lifetime = 5.0
				sm.preprocess = 5.0
				sm.emission_radius = 2.0
				sm.direction = Vector2(0.6, -1)
				sm.spread = 15.0
				sm.gravity = Vector2(6, -4)
				sm.velocity_min = 5.0
				sm.velocity_max = 10.0
				sm.scale_min = 0.25
				sm.scale_max = 0.45
				var curve := Curve.new()
				curve.add_point(Vector2(0, 0.4))
				curve.add_point(Vector2(1, 2.0))
				sm.scale_curve = curve
				sm.color_ramp = main._ramp([Color(0.3, 0.29, 0.28, 0.0), Color(0.32, 0.31, 0.3, 0.35), Color(0.4, 0.39, 0.38, 0.0)])
				sm.z_index = 5
				sm.emitting = true
				main.add_child(sm)


## Chimney stacks on building i's roof: two big ones on the works, one on taverns and on
## some homes. Picked from the map seed, so they're the same every time.
func chimneys(i: int) -> Array:
	var r: Rect2i = map.buildings[i]
	var kind: String = map.building_kind[i] if i < map.building_kind.size() else ""
	var n := 2 if kind == "industry" else (1 if kind == "tavern" or (kind == "home" and _hh(i, 0) < 0.6) else 0)
	var out: Array = []
	for k in n:
		var c := Vector2i(r.position.x + 1 + int(_hh(i, 10 + k) * maxi(1, r.size.x - 2)), r.position.y + 1 + int(_hh(i, 20 + k) * maxi(1, r.size.y - 2)))
		out.append(Vector2(c) * C + Vector2(C, C) * 0.5)
	return out


func _hh(a: int, b: int) -> float:
	return float(hash(Vector3i(a, b, map.map_seed + 77)) % 10000) / 10000.0


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
		var is_chapel := map.chapel.encloses(r)
		var kind: String = map.building_kind[index] if index < map.building_kind.size() else "home"
		var flat := kind == "shop" or kind == "office" or kind == "bunker"  # flat roofs: tar paper or concrete
		var metal := kind == "industry" or kind == "warehouse" or kind.begins_with("factorium")  # corrugated iron on the works
		var slate := Color(0.23, 0.235, 0.245) if not is_chapel else Color(0.31, 0.31, 0.3)  # chapel: old lead
		match kind:
			"tavern": slate = Color(0.3, 0.2, 0.17)  # old clay tiles
			"shop": slate = Color(0.19, 0.19, 0.2)
			"office": slate = Color(0.27, 0.26, 0.25)
			"industry": slate = Color(0.33, 0.3, 0.27)
			"warehouse": slate = Color(0.3, 0.31, 0.3)
			"factorium", "factorium_wing": slate = Color(0.28, 0.27, 0.26)
			"bunker": slate = Color(0.33, 0.33, 0.3)
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
					var col := slate if flat else (slate.lightened(0.06) if lit else slate.darkened(0.12))
					if pass_no == 0:
						draw_rect(Rect2(o, Vector2(C, C)).grow(0.3), col)
						var mv = roofs.main.map_view
						if mv.ground_grit != null:  # weathering: the same grit as the ground and walls
							var g: Texture2D = mv.ground_grit
							var gs := Vector2(g.get_width(), g.get_height())
							var src := Rect2(Vector2(fposmod(o.x * 2.0, gs.x - 32.0), fposmod(o.y * 2.0, gs.y - 32.0)), Vector2(32, 32))
							draw_texture_rect_region(g, Rect2(o, Vector2(C, C)), src, Color(1, 1, 1, 0.9))
						if metal:
							# corrugated iron: ridges running down the slope, rust blooming through
							var k2 := 0.0
							while k2 < C:
								var a2 := o + (Vector2(k2, 0) if horiz else Vector2(0, k2))
								var b2 := a2 + (Vector2(0, C) if horiz else Vector2(C, 0))
								draw_line(a2, b2, col.lightened(0.12), 0.6)
								draw_line(a2 + (Vector2(1, 0) if horiz else Vector2(0, 1)), b2 + (Vector2(1, 0) if horiz else Vector2(0, 1)), col.darkened(0.25), 0.6)
								k2 += 2.0
							if _h(x, y, 7) < 0.25:
								draw_circle(o + Vector2(_h(x, y, 8), _h(x, y, 9)) * C, 3.0 + _h(x, y, 11) * 4.0, Color(0.45, 0.22, 0.1, 0.35))
						elif flat:
							# tar paper or concrete: seams, gravel, puddle stains
							draw_line(o + Vector2(0, 8), o + Vector2(C, 8), col.darkened(0.25), 0.5)
							draw_line(o + Vector2(8, 0), o + Vector2(8, C), col.darkened(0.15), 0.4)
							for k3 in 4:
								draw_circle(o + Vector2(_h(x * 3 + k3, y, 12), _h(x, y * 3 + k3, 13)) * C, 0.5, col.lightened(0.2))
							if _h(x, y, 14) < 0.12:
								draw_circle(o + Vector2(8, 8), 5.0, Color(0.05, 0.05, 0.06, 0.25))
						# courses of slates, staggered
						for k in (0 if metal or flat else 4):
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
						if flat:
							pass
						elif horiz and absf(centre.y - ridge) < C * 0.5:
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
		_decor(map, r, kind, has)

	## On top of the roof: chimneys, skylights and vents by what the building is, and a sign
	## over the front for shops, taverns and works.
	func _decor(map: BattleMap, r: Rect2i, kind: String, has: Callable) -> void:
		for p in roofs.chimneys(index):
			var big := kind == "industry"
			var s := 7.0 if big else 5.0
			draw_rect(Rect2(p - Vector2(s, s) * 0.5 + Vector2(3, 4), Vector2(s, s)), Color(0, 0, 0, 0.35))
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(0.4, 0.22, 0.16) if not big else Color(0.32, 0.2, 0.15))
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(0.12, 0.07, 0.05), false, 0.7)
			draw_circle(p, s * 0.3, Color(0.04, 0.03, 0.03))  # the flue, sooty
		if kind == "chapel":
			_chapel_spire(map, r)
		if kind == "factorium":
			_factorium_crown(map, r)
		if kind == "bunker":
			# sandbags laid along the roof's edges (a gap at the doorway), and an armoured periscope cupola
			var rr := Rect2(Vector2(r.position * C), Vector2(r.size * C))
			var fr: int = map.building_front[index]
			var back: int = [1, 0, 3, 2][fr]
			var mids := [Vector2(rr.get_center().x, rr.position.y), Vector2(rr.get_center().x, rr.end.y),
					Vector2(rr.position.x, rr.get_center().y), Vector2(rr.end.x, rr.get_center().y)]
			var door: Vector2 = mids[back]
			var corners := [[rr.position, Vector2(rr.end.x, rr.position.y)], [Vector2(rr.position.x, rr.end.y), rr.end],
					[rr.position, Vector2(rr.position.x, rr.end.y)], [Vector2(rr.end.x, rr.position.y), rr.end]]
			for edge in 4:
				var a: Vector2 = corners[edge][0]
				var b: Vector2 = corners[edge][1]
				var along := (b - a).normalized()
				var inward := (rr.get_center() - (a + b) * 0.5).normalized()
				for row in 2:  # two staggered rows, like the sandbag walls
					var n := int(a.distance_to(b) / 7.0)
					for k in n:
						var q := a.lerp(b, (k + 0.5 + row * 0.5) / (n + row * 0.5)) + inward * (4.0 + row * 4.5)
						if edge == back and q.distance_to(door + inward * 4.0) < 9.0:
							continue  # the doorway
						_bag(q, along, Color(0.47, 0.42, 0.31).lightened((_h(index, k + edge * 10 + row * 50, 410) - 0.5) * 0.16 + row * 0.04))
			# the doorway: a dark opening in the back wall under a concrete lintel, steps going down
			var din := (rr.get_center() - door).normalized()
			var dacross := din.orthogonal()
			var hole := PackedVector2Array([door + dacross * 6.0, door - dacross * 6.0, door - dacross * 6.0 + din * 6.0, door + dacross * 6.0 + din * 6.0])
			draw_colored_polygon(hole, Color(0.03, 0.03, 0.03))
			for k in 3:  # steps down into the dark
				var sp := door + din * (1.5 + k * 1.6)
				draw_line(sp + dacross * 5.0, sp - dacross * 5.0, Color(0.32, 0.32, 0.3, 0.8 - k * 0.25), 0.8)
			for sgn in [-1.0, 1.0]:  # door posts
				draw_rect(Rect2(door + dacross * sgn * 7.0 - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.62, 0.62, 0.58))
			# the roof juts out over the firing slit: a lit concrete ledge, the slit in shade beyond it
			var band: Rect2
			var lip: Rect2
			match fr:
				0:
					band = Rect2(rr.position.x, rr.position.y - 5, rr.size.x, 5)
					lip = Rect2(rr.position.x - 1, rr.position.y - 1, rr.size.x + 2, 5)
				1:
					band = Rect2(rr.position.x, rr.end.y, rr.size.x, 5)
					lip = Rect2(rr.position.x - 1, rr.end.y - 4, rr.size.x + 2, 5)
				2:
					band = Rect2(rr.position.x - 5, rr.position.y, 5, rr.size.y)
					lip = Rect2(rr.position.x - 1, rr.position.y - 1, 5, rr.size.y + 2)
				_:
					band = Rect2(rr.end.x, rr.position.y, 5, rr.size.y)
					lip = Rect2(rr.end.x - 4, rr.position.y - 1, 5, rr.size.y + 2)
			draw_rect(band, Color(0.01, 0.01, 0.01, 0.85))  # the slit in deep shade under the ledge
			draw_rect(lip, Color(0.72, 0.71, 0.66))  # the ledge, catching the light
			var lit_edge := Rect2(lip.position, Vector2(lip.size.x, 1.2) if fr < 2 else Vector2(1.2, lip.size.y))
			draw_rect(lit_edge, Color(0.88, 0.87, 0.82))
			draw_rect(lip, Color(0.25, 0.25, 0.23), false, 0.7)
			var cp := rr.get_center()
			draw_circle(cp + Vector2(2, 3), 5.0, Color(0, 0, 0, 0.4))
			draw_circle(cp, 5.0, Color(0.28, 0.29, 0.26))
			draw_arc(cp, 5.0, 0, TAU, 14, Color(0.1, 0.1, 0.09), 1.0)
			draw_rect(Rect2(cp + Vector2(-1, -3.5), Vector2(2, 2)), Color(0.05, 0.05, 0.05))
		if kind == "warehouse":
			# a long strip of skylights down the ridge
			var horiz := r.size.x >= r.size.y
			var n := (r.size.x if horiz else r.size.y) - 4
			for k in n:
				var c := Vector2i(r.position.x + 2 + k, r.position.y + r.size.y / 2) if horiz else Vector2i(r.position.x + r.size.x / 2, r.position.y + 2 + k)
				if not has.call(c) or k % 3 == 2:
					continue
				var rr := Rect2(Vector2(c) * C + Vector2(1, 4), Vector2(14, 8)) if horiz else Rect2(Vector2(c) * C + Vector2(4, 1), Vector2(8, 14))
				draw_rect(rr, Color(0.22, 0.27, 0.3))
				draw_rect(rr, Color(0.08, 0.08, 0.08), false, 0.7)
				if _h(index, k, 403) < 0.3:
					draw_rect(rr.grow(-2), Color(0.03, 0.03, 0.03))
		if kind == "shop" or kind == "office" or kind == "industry":
			for k in 3:  # skylights: grimy glass in iron frames
				var c := Vector2i(r.position.x + 2 + int(_h(index, k, 400) * maxi(1, r.size.x - 4)), r.position.y + 2 + int(_h(k, index, 401) * maxi(1, r.size.y - 4)))
				if not has.call(c):
					continue
				var rr := Rect2(Vector2(c) * C + Vector2(3, 3), Vector2(10, 10))
				draw_rect(rr, Color(0.2, 0.25, 0.3))
				draw_rect(rr, Color(0.08, 0.08, 0.08), false, 0.8)
				draw_line(rr.get_center() - Vector2(5, 0), rr.get_center() + Vector2(5, 0), Color(0.08, 0.08, 0.08), 0.6)
				draw_line(rr.position + Vector2(1, 1), rr.position + Vector2(5, 1), Color(0.5, 0.55, 0.6, 0.6), 0.6)
				if _h(index, k, 402) < 0.4:
					draw_rect(Rect2(rr.position + Vector2(5, 5), Vector2(5, 5)), Color(0.03, 0.03, 0.03))  # a smashed pane
		var nm: String = map.building_name[index] if index < map.building_name.size() else ""
		if nm == "":
			return
		# a small sign board on an iron bracket, jutting out over the street from the front wall
		var front: int = map.building_front[index]
		var rc := Vector2(r.position * C) + Vector2(r.size * C) * 0.5
		var off := (r.size.x if front < 2 else r.size.y) * C * (0.2 + _h(index, 0, 420) * 0.3)
		var at: Vector2
		var outd: Vector2
		match front:
			0:
				at = Vector2(rc.x - off, r.position.y * C)
				outd = Vector2(0, -1)
			1:
				at = Vector2(rc.x + off, r.end.y * C)
				outd = Vector2(0, 1)
			2:
				at = Vector2(r.position.x * C, rc.y - off)
				outd = Vector2(-1, 0)
			_:
				at = Vector2(r.end.x * C, rc.y + off)
				outd = Vector2(1, 0)
		var tip := at + outd * 9.0
		draw_line(at + Vector2(1, 1.5), tip + Vector2(1, 1.5), Color(0, 0, 0, 0.4), 1.2)
		draw_line(at, tip, Color(0.15, 0.13, 0.12), 1.0)  # the bracket
		var board := Rect2(at + outd * 3.0 - outd.orthogonal().abs() * 3.5, outd.abs() * 5.0 + outd.orthogonal().abs() * 7.0)
		board.position = board.position.min(board.end)
		var paint := Color(0.25, 0.15, 0.12) if kind == "tavern" else (Color(0.16, 0.2, 0.17) if kind == "shop" else Color(0.22, 0.22, 0.24))
		draw_rect(Rect2(board.position + Vector2(1.5, 2), board.size), Color(0, 0, 0, 0.35))
		draw_rect(board, paint)
		draw_rect(board, Color(0.55, 0.45, 0.28), false, 0.6)


	## The chapel's crown: gilded cresting along the ridge, a pinnacle at each corner, and an
	## octagonal tower at the west end rising to a spire with a gilded finial, its shadow
	## thrown long across the roof and the square.
	func _chapel_spire(map: BattleMap, r: Rect2i) -> void:
		var gold := Color(0.78, 0.62, 0.3)
		var lead := Color(0.31, 0.31, 0.3)
		var rr := Rect2(Vector2(r.position * C), Vector2(r.size * C))
		var cy := rr.get_center().y
		# cresting: little gilded trefoils along the ridge
		var x := rr.position.x + 40.0
		while x < rr.end.x - 24.0:
			draw_circle(Vector2(x, cy), 1.6, gold.darkened(0.2))
			draw_circle(Vector2(x - 1.5, cy - 1.2), 0.9, gold)
			draw_circle(Vector2(x + 1.5, cy - 1.2), 0.9, gold)
			x += 10.0
		# pinnacles at the corners
		for p in [rr.position + Vector2(6, 6), Vector2(rr.end.x - 6, rr.position.y + 6), Vector2(rr.position.x + 6, rr.end.y - 6), rr.end - Vector2(6, 6)]:
			_cone(p, 5.0, 6, lead.lightened(0.05), Vector2(10, 14))
			draw_circle(p, 1.0, gold)
		# the tower and spire at the west end
		var tc := Vector2(rr.position.x + 3.2 * C, cy)
		var tr := 2.7 * C
		var base := PackedVector2Array()
		for k in 8:
			base.append(tc + Vector2.from_angle(k * TAU / 8.0 + PI / 8.0) * tr)
		draw_colored_polygon(base, Color(0.42, 0.4, 0.37))  # the tower's stone top
		var bl := base.duplicate()
		bl.append(base[0])
		draw_polyline(bl, Color(0.15, 0.14, 0.13), 1.2)
		for k in 8:  # belfry openings round the tower
			var q := tc + Vector2.from_angle(k * TAU / 8.0) * tr * 0.92
			draw_circle(q, 2.0, Color(0.05, 0.05, 0.06))
		_cone(tc, tr * 0.82, 8, lead, Vector2(70, 90))
		draw_circle(tc, 3.0, gold.darkened(0.25))  # the finial
		draw_circle(tc - Vector2(0.8, 0.8), 1.6, gold.lightened(0.2))
		draw_line(tc - Vector2(4, 0), tc + Vector2(4, 0), gold, 1.2)  # a gilded sunburst cross-piece
		draw_line(tc - Vector2(0, 4), tc + Vector2(0, 4), gold, 1.2)


	## The Prime Factorium's roof: rows of sawtooth skylights (their glass mostly gone), a great
	## brass drive-wheel emblem on the ridge, and two tall round smokestacks at the west end
	## throwing long shadows.
	func _factorium_crown(map: BattleMap, r: Rect2i) -> void:
		var rr := Rect2(Vector2(r.position * C), Vector2(r.size * C))  # (the main hall)
		var cy := rr.get_center().y
		# sawtooth skylight rows across the machine hall (only where there's roof: not over the yard)
		var k := 0
		for cx in range(r.position.x + 11, r.end.x - 1, 3):
			for cyy in range(r.position.y + 1, r.end.y - 1):
				var cell := Vector2i(cx, cyy)
				if map.roof_at(cell) <= 0.0:
					continue
				var o2 := Vector2(cell) * C
				draw_rect(Rect2(o2.x + 4, o2.y, 7, C), Color(0.1, 0.11, 0.12))
				if _h(cx, cyy, 41) < 0.35:  # a few panes still in, catching the moon
					draw_rect(Rect2(o2.x + 5, o2.y + 5, 5, 6), Color(0.45, 0.5, 0.55, 0.7))
				draw_line(Vector2(o2.x + 11, o2.y), Vector2(o2.x + 11, o2.y + C), Color(0.42, 0.41, 0.4), 1.4)
			k += 1
		# the drive-wheel emblem
		var ec := Vector2(rr.position.x + 5.5 * C, cy)  # over the engine room
		var brass := Color(0.72, 0.56, 0.26)
		for i in 10:
			var a := i * TAU / 10.0
			draw_colored_polygon(PackedVector2Array([ec + Vector2.from_angle(a - 0.15) * 11, ec + Vector2.from_angle(a + 0.15) * 11,
					ec + Vector2.from_angle(a + 0.1) * 15, ec + Vector2.from_angle(a - 0.1) * 15]), brass)
		draw_circle(ec, 11.0, brass.darkened(0.1))
		draw_circle(ec, 6.0, Color(0.15, 0.12, 0.09))
		draw_circle(ec, 3.0, brass.lightened(0.15))
		# smokestacks
		for sy in [rr.position.y + 2.6 * C, rr.end.y - 2.6 * C]:
			var sc := Vector2(rr.position.x + 2.6 * C, sy)
			var sr := 1.6 * C
			draw_colored_polygon(PackedVector2Array([sc + Vector2(-sr, -sr * 0.3), sc + Vector2(sr * 0.3, -sr), sc + Vector2(sr, sr * 0.3) + Vector2(60, 80),
					sc + Vector2(-sr * 0.3, sr) + Vector2(60, 80)]), Color(0, 0, 0, 0.28))  # the long shadow
			draw_circle(sc, sr, Color(0.36, 0.24, 0.18))
			for band in [0.75, 0.9]:
				draw_arc(sc, sr * band, 0, TAU, 20, Color(0.22, 0.14, 0.1), 1.0)
			draw_circle(sc, sr * 0.6, Color(0.05, 0.04, 0.04))  # the sooty mouth
			draw_arc(sc, sr, 0, TAU, 24, Color(0.1, 0.07, 0.05), 1.0)


	## A pointed roof seen from above: facets meeting at the apex, lit from the top left, with a
	## long shadow (the apex's shadow lands at `throw` from it).
	func _cone(c: Vector2, rad: float, sides: int, col: Color, throw: Vector2) -> void:
		var shadow := PackedVector2Array()
		for k in sides:
			var a := k * TAU / sides + PI / sides
			var p := c + Vector2.from_angle(a) * rad
			if Vector2.from_angle(a).dot(throw.normalized().orthogonal()) > 0.0:
				shadow.append(p)
		shadow.append(c + throw)
		var hull := Geometry2D.convex_hull(PackedVector2Array(shadow + PackedVector2Array([c + Vector2.from_angle(PI / sides) * rad])))
		draw_colored_polygon(hull, Color(0, 0, 0, 0.3))
		var light := Vector2(-0.6, -0.8)
		for k in sides:
			var a0 := k * TAU / sides + PI / sides
			var a1 := (k + 1) * TAU / sides + PI / sides
			var mid := Vector2.from_angle((a0 + a1) * 0.5)
			var shade := mid.dot(light)
			var fc := col.lightened(0.25 * shade) if shade > 0.0 else col.darkened(-0.35 * shade)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * rad, c + Vector2.from_angle(a1) * rad]), fc)
			draw_line(c, c + Vector2.from_angle(a0) * rad, col.darkened(0.4), 0.5)


	## A sandbag seen from above: a fat, rounded bag lying along `along`, with its seam and a lit edge.
	func _bag(p: Vector2, along: Vector2, col: Color) -> void:
		var across := along.orthogonal()
		var pts := PackedVector2Array()
		for k in 14:
			var a := k * TAU / 14.0
			var cx := cos(a)
			var cy := sin(a)
			pts.append(p + along * signf(cx) * pow(absf(cx), 0.55) * 3.4 + across * signf(cy) * pow(absf(cy), 0.7) * 2.4)
		var sh := PackedVector2Array()
		for q in pts:
			sh.append(q + Vector2(0.8, 1.0))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.38))
		draw_colored_polygon(pts, col)
		draw_line(p - along * 2.5, p + along * 2.5, col.darkened(0.25), 0.4)  # the stitched seam
		draw_line(p - along * 3.0 - across * 1.1, p - along * 3.0 + across * 1.1, col.darkened(0.35), 0.5)  # tied end
		draw_line(p - along * 2.5 - across * 2.0, p + along * 2.5 - across * 2.0, col.lightened(0.25), 0.5)
