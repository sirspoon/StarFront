class_name Effects
extends Node2D
## Short-lived combat effects: tracers, impact puffs, armour sparks and order markers.

const TRACER_TIME := 0.12

var tracers: Array = []  # {from, to, color, width, t}
var puffs: Array = []    # {pos, color, t, size}
var sparks: Array = []   # {pos, t, seed}
var markers: Array = []  # {pos, color, t}
var blasts: Array = []   # {pos, r, t}
var chunks: Array = []   # flying debris {pos, vel, t, size, color}
var flames: Array = []   # jets of fire {from, to, cone, t, seed}
var beams: Array = []    # the lumen lance's beam this frame {from, to, color, width, t}
var blasts_m: Array = [] # a big gun's muzzle blast {pos, dir, color, t}
const FLAME_TIME := 0.55


func tracer(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	tracers.append({"from": from, "to": to, "color": color, "width": width, "t": 0.0})


func puff(pos: Vector2, color: Color, size: float = 6.0) -> void:
	puffs.append({"pos": pos, "color": color, "t": 0.0, "size": size})


## A shot glancing off: a bright streak flying off at an angle, and sparks.
func ricochet(pos: Vector2, incoming: Vector2) -> void:
	var out := incoming.normalized().reflect(Vector2.from_angle(randf() * TAU)).rotated(randf_range(-0.6, 0.6))
	if out.dot(incoming) > 0.3:
		out = -out
	tracers.append({"from": pos, "to": pos + out.normalized() * randf_range(40, 110), "color": Color(1.0, 0.9, 0.6), "width": 1.0, "t": 0.0})
	spark(pos)


func spark(pos: Vector2) -> void:
	sparks.append({"pos": pos, "t": 0.0, "seed": randf() * TAU})


func explosion(pos: Vector2, r: float) -> void:
	blasts.append({"pos": pos, "r": r, "t": 0.0})


## Stones thrown out when a wall breaks.
func debris(pos: Vector2, n: int = 10) -> void:
	for i in n:
		chunks.append({"pos": pos + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
				"vel": Vector2.from_angle(randf() * TAU) * randf_range(30, 120), "t": 0.0,
				"size": randf_range(1.0, 3.0), "color": Color(0.5, 0.47, 0.43).darkened(randf() * 0.4)})
	puff(pos, Color(0.55, 0.5, 0.44), 16.0)
	puff(pos + Vector2(randf_range(-8, 8), randf_range(-8, 8)), Color(0.5, 0.46, 0.4), 12.0)


func beam(from: Vector2, to: Vector2, color: Color, width: float, key: int = 0) -> void:
	# one beam per gun: each update replaces the last (so it shows however slow the frames are)
	beams = beams.filter(func(e): return e.key != key)
	beams.append({"from": from, "to": to, "color": color, "width": width, "t": 0.0, "key": key})


func muzzle_blast(pos: Vector2, dir: Vector2, color: Color) -> void:
	blasts_m.append({"pos": pos, "dir": dir, "color": color, "t": 0.0})


func flame(from: Vector2, to: Vector2, cone: float) -> void:
	flames.append({"from": from, "to": to, "cone": cone, "t": 0.0, "seed": randf() * 100.0})


func marker(pos: Vector2, color: Color) -> void:
	markers.append({"pos": pos, "color": color, "t": 0.0})


func _process(dt: float) -> void:
	if get_parent().paused:
		return  # freeze tracers and blasts while the game is paused
	for list in [tracers, puffs, sparks, markers, blasts, chunks, flames, beams, blasts_m]:
		for e in list:
			e.t += dt
	tracers = tracers.filter(func(e): return e.t < TRACER_TIME)
	puffs = puffs.filter(func(e): return e.t < 0.7)
	sparks = sparks.filter(func(e): return e.t < 0.15)
	markers = markers.filter(func(e): return e.t < 0.7)
	blasts = blasts.filter(func(e): return e.t < 0.8)
	chunks = chunks.filter(func(e): return e.t < 0.6)
	flames = flames.filter(func(e): return e.t < FLAME_TIME)
	beams = beams.filter(func(e): return e.t < 0.15)
	blasts_m = blasts_m.filter(func(e): return e.t < 0.5)
	for e in chunks:
		e.pos += e.vel * dt
		e.vel *= 1.0 - minf(1.0, dt * 4.0)
	queue_redraw()


func _draw() -> void:
	for e in tracers:
		var from: Vector2 = e.from
		var to: Vector2 = e.to
		var length := from.distance_to(to)
		if length < 1.0:
			continue
		var p: float = e.t / TRACER_TIME
		var head := from.lerp(to, minf(1.0, p * 1.15))
		var tail := from.lerp(to, maxf(0.0, p * 1.15 - 45.0 / length))
		var col: Color = e.color
		draw_line(tail, head, Color(col, 0.25), e.width * 3.0)
		draw_line(tail, head, col.lightened(0.4), e.width)
	for e in puffs:
		var k: float = e.t / 0.7
		var col: Color = e.color
		draw_circle(e.pos, e.size * (0.5 + k), Color(col, 0.6 * (1.0 - k)))
	for e in sparks:
		for i in 5:
			var a: float = e.seed + i * TAU / 5.0
			var p: Vector2 = e.pos
			draw_line(p, p + Vector2.from_angle(a) * (4.0 + e.t * 60.0), Color(1.0, 0.9, 0.5), 1.2)
	for e in blasts:
		var k: float = e.t / 0.8
		var r: float = e.r
		var p: Vector2 = e.pos
		draw_circle(p, r * (0.6 + k * 1.2), Color(0.3, 0.27, 0.22, 0.5 * (1.0 - k)))  # dust
		if k < 0.45:
			var f := k / 0.45
			draw_circle(p, r * (0.4 + f * 0.6), Color(1.0, 0.5, 0.15, 0.85 * (1.0 - f)))  # fireball
			draw_circle(p, r * 0.5 * (1.0 - f), Color(1.0, 0.95, 0.7, 1.0 - f))  # flash
	for e in chunks:
		var col: Color = e.color
		draw_rect(Rect2(e.pos - Vector2(e.size, e.size) * 0.5, Vector2(e.size, e.size)), Color(col, 1.0 - e.t / 0.6))
	for e in flames:
		# the jet roars out, widening, then gutters away as burning blobs
		var k: float = e.t / FLAME_TIME
		var from: Vector2 = e.from
		var to: Vector2 = e.to
		var head: Vector2 = from.lerp(to, minf(1.0, e.t / 0.14))
		var d := from.distance_to(head)
		if d < 2.0:
			continue
		var dir := (head - from) / d
		var side := dir.orthogonal()
		var fade := 1.0 - maxf(0.0, (k - 0.5) / 0.5)
		var wide: float = tan(e.cone) * d * 0.75
		# billowing fire: dark red-orange at the edges and the far end, a yellow-white core near the nozzle
		for layer in 3:
			var n := 14
			for i in n:
				var f := float(i + 1) / float(n)
				var wob := sin(e.seed + i * 2.3 + layer * 1.7 + e.t * 28.0)
				var wob2 := cos(e.seed * 0.7 + i * 1.3 + e.t * 21.0)
				var p := from.lerp(head, f) + side * wob * wide * f * (0.55 - layer * 0.15) + dir * wob2 * 3.0
				var rad := (1.5 + f * wide * (0.75 - layer * 0.22)) * (1.0 + 0.35 * k)
				var col: Color
				match layer:
					0: col = Color(0.75, 0.18, 0.04, 0.35 * fade)   # smoky red edge
					1: col = Color(1.0, 0.48, 0.1, 0.45 * fade)     # orange body
					_: col = Color(1.0, 0.88, 0.5, (0.7 - f * 0.5) * fade)  # hot core, fading out along the jet
				var soft: Texture2D = get_parent()._dot_tex
				if soft != null:  # soft-edged puffs that melt into each other
					draw_texture_rect(soft, Rect2(p - Vector2(rad, rad) * 1.5, Vector2(rad, rad) * 3.0), false, Color(col, minf(1.0, col.a * 1.6)))
				else:
					draw_circle(p, rad, col)
	for e in beams:
		# a searing beam: a wide soft glow, a bright core, and a white-hot heart that flickers
		var from: Vector2 = e.from
		var to: Vector2 = e.to
		var col: Color = e.color
		var wdt: float = e.width * (0.9 + randf() * 0.25)
		draw_line(from, to, Color(col, 0.18), wdt * 4.5)
		draw_line(from, to, Color(col, 0.45), wdt * 2.2)
		draw_line(from, to, col.lightened(0.35), wdt)
		draw_line(from, to, Color(1.0, 0.97, 0.85), wdt * 0.4)
		draw_circle(to, wdt * 1.8, Color(col, 0.5))
		draw_circle(to, wdt, Color(1.0, 0.95, 0.8, 0.9))
		draw_circle(from, wdt * 1.3, Color(1.0, 0.9, 0.7, 0.9))
	for e in blasts_m:
		# the main gun's blast: a cone of fire out of the muzzle, a ring of shock racing outward
		var k: float = e.t / 0.5
		var p: Vector2 = e.pos
		var dir: Vector2 = e.dir
		var col: Color = e.color
		var side := dir.orthogonal()
		if k < 0.35:
			var f := k / 0.35
			var reach := 34.0 * (0.6 + f)
			draw_colored_polygon(PackedVector2Array([p, p + dir * reach + side * reach * 0.45, p + dir * reach * 1.3, p + dir * reach - side * reach * 0.45]),
					Color(col, 0.8 * (1.0 - f)))
			draw_circle(p + dir * 6.0, 14.0 * (1.0 - f) + 4.0, Color(1.0, 1.0, 0.92, 1.0 - f))
			for s in [-1.0, 1.0]:  # side jets from the muzzle brake
				draw_line(p, p + side * s * 18.0 * (0.5 + f), Color(col, 0.7 * (1.0 - f)), 5.0)
		draw_arc(p, 20.0 + k * 90.0, 0, TAU, 40, Color(1.0, 0.95, 0.85, 0.45 * (1.0 - k)), 2.0 + 3.0 * (1.0 - k))
	for e in markers:
		var k: float = e.t / 0.7
		var col: Color = e.color
		draw_arc(e.pos, 6.0 + 14.0 * k, 0, TAU, 24, Color(col, 1.0 - k), 2.0)
