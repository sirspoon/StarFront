class_name HeightPainter
extends MapPainter
## Paints one tile as a height map (black = low, white = high) for the lighting.
## Only the big shapes are drawn here: raised walls with sloping front faces,
## rubble mounds, sunken craters, slab footings and wrecks. The fine detail (stones,
## cracks, joints) comes from the colour tile when the normal map is worked out.

const GROUND := 0.35


func _hc(v: float) -> Color:
	return Color(v, v, v)


func _draw() -> void:
	var area := _cell_area()
	var r := Rect2(Vector2(cells.position * C), Vector2(cells.size * C)).grow(40)
	draw_rect(r, _hc(GROUND))
	for pd in map.puddles:
		if _near(pd[0], pd[1] + 4):
			_poly(_blob(pd[0], pd[1], pd[2], 0.35, int(pd[0].x + pd[0].y * 3)), _hc(GROUND - 0.03))
	for i in map.craters.size():
		var cr: Array = map.craters[i]
		var p: Vector2 = cr[0]
		var rad: float = cr[1]
		if not _near(p, rad + 30):
			continue
		# a raised lip, then a bowl that deepens towards the middle
		_poly(_blob(p, rad + 9, 1.0, 0.35, i * 13), _hc(GROUND + 0.05))
		_poly(_blob(p, rad + 4, 1.0, 0.3, i * 13 + 1), _hc(GROUND + 0.08))
		for k in 5:
			var f := 1.0 - k * 0.18
			_poly(_blob(p + Vector2(rad * 0.04 * k, rad * 0.05 * k), rad * f, 1.0, 0.25, i * 13 + 2), _hc(GROUND - 0.04 - k * 0.05))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			var t := map.get_t(c)
			if t == T.RUBBLE:
				_mound(c)
			elif t == T.FLOOR and _is_fallen(c):
				draw_rect(Rect2(Vector2(c) * C, Vector2(C, C)), _hc(GROUND + 0.06))
	for wk in map.wrecks:
		var rr: Rect2i = wk[0]
		if rr.intersects(area):
			var hull := Rect2(Vector2(rr.position * C), Vector2(rr.size * C)).grow(-2)
			draw_rect(hull, _hc(0.6))
			draw_rect(hull.grow(-6), _hc(0.72))
			draw_circle(hull.get_center(), 11, _hc(0.85))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if map.get_t(Vector2i(x, y)) == T.WALL:
				_wall(Vector2i(x, y))


## A heap of rubble: a soft mound, higher where a wall came down.
func _mound(c: Vector2i) -> void:
	var o := Vector2(c) * C + Vector2(8, 8)
	var top := 0.5 if map.fallen[c.y * BattleMap.W + c.x] == 1 else 0.44
	for k in 4:
		var f := 1.0 - k * 0.24
		_poly(_blob(o, 10.0 * f, 1.0, 0.45, c.x * 977 + c.y + k), _hc(lerpf(GROUND + 0.02, top, float(k + 1) / 4.0)))


func _wall(c: Vector2i) -> void:
	var g := _wall_geom(c)
	var top := 1.0 if map.wall_stage(c) < 2 else 0.8
	var face: PackedVector2Array = g.face
	if not face.is_empty():
		# the front face slopes from the top down to the ground in front of it
		var n: int = g.chain.size()
		var cols := PackedColorArray()
		for i in face.size():
			cols.append(_hc(top) if i < n else _hc(GROUND))
		if not Geometry2D.triangulate_polygon(face).is_empty():
			draw_polygon(face, cols)
	_poly(g.poly, _hc(top))
