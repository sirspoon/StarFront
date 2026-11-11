class_name MapView
extends Node2D
## Shows the battlefield. The map is cut into tiles; each is painted by a MapPainter
## into a texture at twice the map's resolution once at the start, and painted again
## whenever a wall in or near it is damaged or falls. Without a screen (headless
## tests) nothing is painted.

const SCALE := 2.0
const CHUNK := Vector2i(20, 20)  # tile size in cells

var map: BattleMap
var enabled := true
var ready_drawn := false
var sprites := {}  # Vector2i tile -> Sprite2D
var occluders := {}  # row -> Array of LightOccluder2D: walls cast shadows from lights
var dirty := {}
var baking := false
var ground_big: Texture2D
var ground_fine: Texture2D
var ground_grit: Texture2D


func setup(m: BattleMap) -> void:
	map = m
	map.cells_changed.connect(_on_cells_changed)
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	await _make_ground_textures()
	var all: Array = []
	for cx in ceili(float(BattleMap.W) / CHUNK.x):
		for cy in ceili(float(BattleMap.H) / CHUNK.y):
			all.append(Vector2i(cx, cy))
	for y in BattleMap.H:
		_build_occluders(y)
	await _bake(all)
	ready_drawn = true


## One occluder per run of wall cells in a row, so fires and explosions throw
## shadows past walls and light spills through gaps and doorways.
func _build_occluders(y: int) -> void:
	for o in occluders.get(y, []):
		o.queue_free()
	var list: Array = []
	var x := 0
	while x < BattleMap.W:
		if map.get_t(Vector2i(x, y)) != BattleMap.T.WALL:
			x += 1
			continue
		var x0 := x
		while x < BattleMap.W and map.get_t(Vector2i(x, y)) == BattleMap.T.WALL:
			x += 1
		var poly := OccluderPolygon2D.new()
		var c := float(BattleMap.CELL)
		poly.polygon = PackedVector2Array([Vector2(x0 * c, y * c), Vector2(x * c, y * c),
				Vector2(x * c, (y + 1) * c), Vector2(x0 * c, (y + 1) * c)])
		var occ := LightOccluder2D.new()
		occ.occluder = poly
		add_child(occ)
		list.append(occ)
	occluders[y] = list


func _noise_tex(w: int, h: int, freq: float, octaves: int, seamless: bool, cellular: bool, ramp: Gradient) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = w
	t.height = h
	t.seamless = seamless
	var n := FastNoiseLite.new()
	n.seed = map.rng.randi()
	n.frequency = freq
	n.fractal_octaves = octaves
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	t.noise = n
	t.color_ramp = ramp
	t.generate_mipmaps = true
	return t


func _grad(cols: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(offsets[i], cols[i])
	return g


func _make_ground_textures() -> void:
	var big := _noise_tex(1280, 800, 0.006, 5, false, false,
			_grad([Color(0.19, 0.18, 0.16), Color(0.3, 0.27, 0.23), Color(0.36, 0.33, 0.28), Color(0.44, 0.41, 0.35)], [0, 0.4, 0.6, 1]))
	var fine := _noise_tex(512, 512, 0.045, 4, true, false,
			_grad([Color(0, 0, 0, 0.32), Color(0, 0, 0, 0.0), Color(1, 0.95, 0.85, 0.09)], [0, 0.5, 1]))
	var grit := _noise_tex(512, 512, 0.09, 1, true, true,
			_grad([Color(1, 0.95, 0.85, 0.08), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.22)], [0, 0.45, 1]))
	for t in [big, fine, grit]:
		while t.get_image() == null:
			await get_tree().process_frame
	ground_big = big
	ground_fine = fine
	ground_grit = grit


func _tile_cells(k: Vector2i) -> Rect2i:
	var r := Rect2i(k * CHUNK, CHUNK)
	return r.intersection(Rect2i(0, 0, BattleMap.W, BattleMap.H))


func _bake(keys: Array) -> void:
	var jobs: Array = []
	for k in keys:
		var rect := _tile_cells(k)
		var vp := SubViewport.new()
		vp.size = Vector2i(Vector2(rect.size * BattleMap.CELL) * SCALE)
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		vp.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_ENABLED
		var p := MapPainter.new()
		p.map = map
		p.cells = rect
		p.ground_big = ground_big
		p.ground_fine = ground_fine
		p.ground_grit = ground_grit
		p.scale = Vector2(SCALE, SCALE)
		p.position = -Vector2(rect.position * BattleMap.CELL) * SCALE
		vp.add_child(p)
		add_child(vp)
		jobs.append([k, vp, rect])
	await RenderingServer.frame_post_draw
	for j in jobs:
		var vp: SubViewport = j[1]
		var img := vp.get_texture().get_image()
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		var k: Vector2i = j[0]
		var spr: Sprite2D = sprites.get(k)
		if spr == null:
			spr = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			spr.scale = Vector2(1.0 / SCALE, 1.0 / SCALE)
			var rect: Rect2i = j[2]
			spr.position = Vector2(rect.position * BattleMap.CELL)
			add_child(spr)
			sprites[k] = spr
		spr.texture = tex
		vp.queue_free()


func _on_cells_changed(cells: Array) -> void:
	if not enabled:
		return
	var rows := {}
	for c in cells:
		rows[c.y] = true
	for y in rows:
		_build_occluders(y)
	for c in cells:
		# walls are drawn raised and cast shadows, so neighbouring tiles may need it too
		for d in [Vector2i(0, 0), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
			var k := Vector2i((c.x + d.x) / CHUNK.x, (c.y + d.y) / CHUNK.y)
			if (c + d).x >= 0 and (c + d).y >= 0 and k.x * CHUNK.x < BattleMap.W and k.y * CHUNK.y < BattleMap.H:
				dirty[k] = true


func _process(_dt: float) -> void:
	if baking or dirty.is_empty() or not ready_drawn:
		return
	baking = true
	var keys := dirty.keys()
	dirty.clear()
	await _bake(keys)
	baking = false
