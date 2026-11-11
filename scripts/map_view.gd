class_name MapView
extends Node2D
## Shows the battlefield. The map is cut into tiles; each is painted by a MapPainter
## into a texture at twice the map's resolution once at the start, and painted again
## whenever a wall in or near it is damaged or falls. Each tile also gets a normal
## map (from a HeightPainter pass plus the colour detail) so lights pick out walls,
## rubble and craters in relief. Without a screen (headless
## tests) nothing is painted.

var use_normals := true
var _where := ""  # for the crash breadcrumbs
var SCALE := 2.0  # map pixels drawn per world pixel (detail level)
var BATCH := 4  # tiles prepared at once (1 on phones: each tile is a lot of drawing for one frame)
const CHUNK := Vector2i(20, 20)  # tile size in cells
## When walls are damaged only small patches around the damage are repainted and laid
## over the big tiles, so a shell landing doesn't stall the game repainting whole tiles.
const PATCH := Vector2i(5, 5)
var patches := {}  # Vector2i patch -> Sprite2D (drawn over the tiles)

var map: BattleMap
var enabled := true
var ready_drawn := false
var tiles_total := 1  # for the loading bar
var tiles_done := 0
var sprites := {}  # Vector2i tile -> Sprite2D
var occluders := {}  # row -> Array of LightOccluder2D: walls cast shadows from lights
var dirty := {}
var baking := false
var ground_big: Texture2D
var ground_fine: Texture2D
var ground_grit: Texture2D
var normal_shader: Shader = preload("res://scripts/normal_from_height.gdshader")


func setup(m: BattleMap) -> void:
	map = m
	map.cells_changed.connect(_on_cells_changed)
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	if not Settings.on("bake", true):
		# minimal mode: a plain flat map, no off-screen drawing at all
		var flat := FlatMap.new()
		flat.map = map
		add_child(flat)
		ready_drawn = true
		Settings.stage("flat map shown (%s)" % Settings.summary())
		return
	Settings.stage("making ground textures")
	await _make_ground_textures()
	var all: Array = []
	tiles_done = 0
	for cx in ceili(float(BattleMap.W) / CHUNK.x):
		for cy in ceili(float(BattleMap.H) / CHUNK.y):
			all.append(Vector2i(cx, cy))
	if Settings.on("shadows", not Settings.is_phone()):
		for y in BattleMap.H:
			_build_occluders(y)
	tiles_total = all.size()
	SCALE = Settings.detail()
	use_normals = Settings.on("normals", true)
	BATCH = Settings.batch()
	for i in range(0, all.size(), BATCH):
		_where = "map tiles %d-%d of %d (%s)" % [i + 1, mini(i + BATCH, all.size()), all.size(), Settings.summary()]
		await _bake(all.slice(i, i + BATCH))
		tiles_done = mini(i + BATCH, all.size())
		if BATCH == 1:
			for f in 3:
				await get_tree().process_frame  # let the phone's graphics catch up between tiles
	Settings.stage("map ready (%s)" % Settings.summary())
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
		# matches the raised top of the wall as drawn, so lights in front still reach its face
		var lift := MapPainter.WALL_H
		poly.polygon = PackedVector2Array([Vector2(x0 * c, y * c - lift), Vector2(x * c, y * c - lift),
				Vector2(x * c, (y + 1) * c - lift), Vector2(x0 * c, (y + 1) * c - lift)])
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


func _tile_cells(k: Vector2i, size := CHUNK) -> Rect2i:
	var r := Rect2i(k * size, size)
	return r.intersection(Rect2i(0, 0, BattleMap.W, BattleMap.H))


## Paint the given tiles (or, with as_patches, the given repair patches).
func _bake(keys: Array, as_patches := false) -> void:
	var jobs: Array = []
	for k in keys:
		var rect := _tile_cells(k, PATCH if as_patches else CHUNK)
		var size := Vector2i(Vector2(rect.size * BattleMap.CELL) * SCALE)
		var vp := _viewport(size)
		vp.add_child(_painter(MapPainter.new(), rect))
		var hvp: SubViewport = null
		if use_normals:
			hvp = _viewport(size)
			hvp.add_child(_painter(HeightPainter.new(), rect))
		jobs.append([k, vp, rect, hvp, null])
	Settings.stage(_where + ": drawing colour tiles")
	await RenderingServer.frame_post_draw
	Settings.stage(_where + ": colour tiles drawn")
	# second pass: turn each tile's height and colour into a normal map
	for j in jobs:
		if not use_normals:
			break
		var vp: SubViewport = j[1]
		var hvp: SubViewport = j[3]
		var nvp := _viewport(vp.size)
		var mat := ShaderMaterial.new()
		mat.shader = normal_shader
		mat.set_shader_parameter("height_tex", hvp.get_texture())
		mat.set_shader_parameter("albedo_tex", vp.get_texture())
		mat.set_shader_parameter("texel", Vector2(1.0 / vp.size.x, 1.0 / vp.size.y))
		var rect_node := ColorRect.new()
		rect_node.size = Vector2(vp.size)
		rect_node.material = mat
		nvp.add_child(rect_node)
		j[4] = nvp
	if use_normals:
		await RenderingServer.frame_post_draw
		Settings.stage(_where + ": normal maps drawn")
	if as_patches:
		_show_patches(jobs)
		return
	Settings.stage(_where + ": reading tiles back")
	for j in jobs:
		var vp: SubViewport = j[1]
		var img := vp.get_texture().get_image()
		img.generate_mipmaps()
		var tex := CanvasTexture.new()
		tex.diffuse_texture = ImageTexture.create_from_image(img)
		if use_normals:
			var nimg: Image = j[4].get_texture().get_image()
			nimg.generate_mipmaps()
			tex.normal_texture = ImageTexture.create_from_image(nimg)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var k: Vector2i = j[0]
		var store: Dictionary = patches if as_patches else sprites
		var spr: Sprite2D = store.get(k)
		if spr == null:
			spr = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			spr.scale = Vector2(1.0 / SCALE, 1.0 / SCALE)
			var rect: Rect2i = j[2]
			spr.position = Vector2(rect.position * BattleMap.CELL)
			add_child(spr)
			store[k] = spr
		spr.texture = tex
		if "--debug-normals" in OS.get_cmdline_user_args():
			spr.texture = tex.normal_texture  # test aid: show the normal maps themselves
		vp.queue_free()
		if use_normals:
			j[3].queue_free()
			j[4].queue_free()


## Repair patches are shown straight from the viewports they were painted in. Reading
## them back into images (as the big tiles are) makes the graphics chip finish all its
## work first, which is what stalled the game when a shell hit a wall.
var patch_vps := {}  # Vector2i patch -> [colour viewport, normal viewport or null]


func _show_patches(jobs: Array) -> void:
	for j in jobs:
		var k: Vector2i = j[0]
		var vp: SubViewport = j[1]
		var tex := CanvasTexture.new()
		tex.diffuse_texture = vp.get_texture()
		if use_normals:
			tex.normal_texture = j[4].get_texture()
			j[3].queue_free()  # the height pass is no longer needed once the normal map is drawn
		var spr: Sprite2D = patches.get(k)
		if spr == null:
			spr = Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			spr.scale = Vector2(1.0 / SCALE, 1.0 / SCALE)
			var rect: Rect2i = j[2]
			spr.position = Vector2(rect.position * BattleMap.CELL)
			add_child(spr)
			patches[k] = spr
		spr.texture = tex
		for old in patch_vps.get(k, []):
			if old != null:
				old.queue_free()
		patch_vps[k] = [vp, j[4] if use_normals else null]


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	vp.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_ENABLED
	add_child(vp)
	return vp


func _painter(p: MapPainter, rect: Rect2i) -> MapPainter:
	p.map = map
	p.cells = rect
	p.ground_big = ground_big
	p.ground_fine = ground_fine
	p.ground_grit = ground_grit
	p.scale = Vector2(SCALE, SCALE)
	p.position = -Vector2(rect.position * BattleMap.CELL) * SCALE
	return p


func _on_cells_changed(cells: Array) -> void:
	if not enabled:
		return
	for ch in get_children():
		if ch is FlatMap:
			ch.queue_redraw()
			return
	var rows := {}
	for c in cells:
		rows[c.y] = true
	if Settings.on("shadows", not Settings.is_phone()):
		for y in rows:
			_build_occluders(y)
	for c in cells:
		# walls are drawn raised and cast shadows, so neighbouring patches may need it too
		for d in [Vector2i(0, 0), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
			var k := Vector2i((c.x + d.x) / PATCH.x, (c.y + d.y) / PATCH.y)
			if (c + d).x >= 0 and (c + d).y >= 0 and k.x * PATCH.x < BattleMap.W and k.y * PATCH.y < BattleMap.H:
				dirty[k] = true


func _process(_dt: float) -> void:
	if baking or dirty.is_empty() or not ready_drawn:
		return
	baking = true
	var keys := dirty.keys().slice(0, 1)  # one small patch at a time, so the work is spread over frames
	for k in keys:
		dirty.erase(k)
	await _bake(keys, true)
	baking = false
