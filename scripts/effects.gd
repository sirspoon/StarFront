class_name Effects
extends Node2D
## Short-lived combat effects: tracers, impact puffs, armour sparks and order markers.

const TRACER_TIME := 0.12

var tracers: Array = []  # {from, to, color, width, t}
var puffs: Array = []    # {pos, color, t, size}
var sparks: Array = []   # {pos, t, seed}
var markers: Array = []  # {pos, color, t}
var blasts: Array = []   # {pos, r, t}


func tracer(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	tracers.append({"from": from, "to": to, "color": color, "width": width, "t": 0.0})


func puff(pos: Vector2, color: Color, size: float = 6.0) -> void:
	puffs.append({"pos": pos, "color": color, "t": 0.0, "size": size})


func spark(pos: Vector2) -> void:
	sparks.append({"pos": pos, "t": 0.0, "seed": randf() * TAU})


func explosion(pos: Vector2, r: float) -> void:
	blasts.append({"pos": pos, "r": r, "t": 0.0})


func marker(pos: Vector2, color: Color) -> void:
	markers.append({"pos": pos, "color": color, "t": 0.0})


func _process(dt: float) -> void:
	for list in [tracers, puffs, sparks, markers, blasts]:
		for e in list:
			e.t += dt
	tracers = tracers.filter(func(e): return e.t < TRACER_TIME)
	puffs = puffs.filter(func(e): return e.t < 0.7)
	sparks = sparks.filter(func(e): return e.t < 0.15)
	markers = markers.filter(func(e): return e.t < 0.7)
	blasts = blasts.filter(func(e): return e.t < 0.8)
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
	for e in markers:
		var k: float = e.t / 0.7
		var col: Color = e.color
		draw_arc(e.pos, 6.0 + 14.0 * k, 0, TAU, 24, Color(col, 1.0 - k), 2.0)
