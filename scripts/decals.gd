extends Node2D
## Marks left on the ground by the battle: blast scorches, small burn marks where shots
## strike, and blood. Drawn under the soldiers. Redrawn at most a few times a second,
## and the oldest small marks fade out once there are many.

const MAX_SMALL := 700

var marks: Array = []   # blast scorches: [pos, radius, seed]
var small: Array = []   # [kind, pos, dir, size, seed, colour]  kind: "burn", "blood", "smear"
var tracks: Array = []  # vehicle track marks: [from, to, gap, tread width]
const MAX_TRACKS := 900
var dirty := false
var redraw_timer := 0.0


func add_scorch(pos: Vector2, r: float) -> void:
	for m in marks:
		if m[0].distance_to(pos) < r * 0.6:
			return  # already blackened here; don't pile marks up into a black blot
	marks.append([pos, r, randi()])
	dirty = true


## A small black burn where a shot hit the ground.
func add_burn(pos: Vector2, size: float) -> void:
	_add(["burn", pos, Vector2.ZERO, size, randi(), Color.BLACK])


## Blood sprayed away from a hit: dir points away from the shooter.
func add_blood(pos: Vector2, dir: Vector2, amount: float, col: Color) -> void:
	_add(["blood", pos, dir.normalized(), amount, randi(), col])


## Blood splashed against a wall face at pos: a splat, runs and a fan of droplets.
func add_wall_blood(pos: Vector2, dir: Vector2, amount: float, col: Color) -> void:
	_add(["wall", pos, dir.normalized(), amount, randi(), col])


## Track marks pressed into the ground from a to b: two treads, gap apart.
func add_track(a: Vector2, b: Vector2, gap: float, tread: float) -> void:
	tracks.append([a, b, gap, tread])
	if tracks.size() > MAX_TRACKS:
		tracks.pop_front()
	dirty = true


## A smear or trail of blood (a wounded man dragged or crawling).
func add_smear(pos: Vector2, dir: Vector2, length: float, col: Color) -> void:
	_add(["smear", pos, dir.normalized(), length, randi(), col])


func _add(m: Array) -> void:
	small.append(m)
	if small.size() > MAX_SMALL:
		small.pop_front()
	dirty = true


func _process(dt: float) -> void:
	redraw_timer -= dt
	if dirty and redraw_timer <= 0.0:
		dirty = false
		redraw_timer = 0.25
		queue_redraw()


func _draw() -> void:
	for m in marks:
		var p: Vector2 = m[0]
		var r: float = m[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = m[2]
		for k in 3:
			var pts := PackedVector2Array()
			var rr := r * (1.0 - k * 0.3)
			for i in 14:
				pts.append(p + Vector2.from_angle(i * TAU / 14.0) * rr * rng.randf_range(0.7, 1.15))
			draw_colored_polygon(pts, Color(0.04, 0.03, 0.02, 0.14))
		for i in 6:
			var a := rng.randf() * TAU
			draw_line(p + Vector2.from_angle(a) * r * 0.3, p + Vector2.from_angle(a) * r * rng.randf_range(0.8, 1.3),
					Color(0.04, 0.03, 0.02, 0.18), 1.5)
	for tr in tracks:
		var a: Vector2 = tr[0]
		var b: Vector2 = tr[1]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var dir := d.normalized()
		var side := dir.orthogonal() * float(tr[2]) * 0.5
		var tw: float = tr[3]
		for s in [-1.0, 1.0]:
			var o: Vector2 = side * s
			draw_line(a + o, b + o, Color(0.06, 0.05, 0.04, 0.2), tw)  # the churned rut
			var k := 0.0
			while k < d.length():  # the tread plates' imprint
				var q: Vector2 = a + o + dir * k
				draw_line(q - dir.orthogonal() * tw * 0.5, q + dir.orthogonal() * tw * 0.5, Color(0.04, 0.035, 0.03, 0.22), 1.0)
				k += 3.5
	var rng2 := RandomNumberGenerator.new()
	for m in small:
		rng2.seed = m[4]
		match m[0]:
			"burn":
				_draw_burn(m[1], m[3], rng2)
			"blood":
				_draw_blood(m[1], m[2], m[3], m[5], rng2)
			"smear":
				_draw_smear(m[1], m[2], m[3], m[5], rng2)
			"wall":
				_draw_wall_blood(m[1], m[2], m[3], m[5], rng2)


func _draw_burn(p: Vector2, size: float, rng: RandomNumberGenerator) -> void:
	draw_circle(p, size * 1.6, Color(0.05, 0.04, 0.03, 0.18))
	draw_circle(p, size * 0.8, Color(0.03, 0.02, 0.02, 0.45))
	for i in 4:
		var a := rng.randf() * TAU
		draw_line(p, p + Vector2.from_angle(a) * size * rng.randf_range(1.5, 2.6), Color(0.03, 0.02, 0.02, 0.3), 0.8)


## Droplets and streaks fanned out away from the shooter: the further a drop flew,
## the smaller it is and the more it is drawn out along its path.
func _draw_blood(p: Vector2, dir: Vector2, amount: float, col: Color, rng: RandomNumberGenerator) -> void:
	var dark := Color(col.darkened(0.45), 0.65)  # old blood soaks into dust: dark and dull
	draw_circle(p + dir * 2.0, 1.8 * amount, Color(dark, 0.55))
	var n := int(7 * amount) + 3
	var reach := 34.0 * amount  # flung well clear of him, so it shows
	for i in n:
		var a := dir.angle() + rng.randf_range(-0.5, 0.5)
		var d := rng.randf_range(4.0, reach) * (0.5 + 0.5 * rng.randf())
		var q := p + Vector2.from_angle(a) * d
		var s := lerpf(2.0, 0.6, d / reach) * rng.randf_range(0.7, 1.2)
		if rng.randf() < 0.45:
			# a streak: thick near the body, tapering out along its flight
			var tail := q + Vector2.from_angle(a) * rng.randf_range(3.0, 8.0)
			draw_line(q, tail, Color(dark, 0.55), s * 0.8)
			draw_circle(tail, s * 0.4, Color(dark, 0.6))
		draw_circle(q, s * 0.8, Color(dark, 0.6))


func _draw_wall_blood(p: Vector2, dir: Vector2, amount: float, col: Color, rng: RandomNumberGenerator) -> void:
	var c := Color(col.darkened(0.25), 0.8)
	var side := dir.orthogonal()
	draw_circle(p, 2.6 * amount, c)  # the splat
	for i in int(8 * amount) + 3:  # droplets fanned out across the wall face
		var q := p + side * rng.randf_range(-9.0, 9.0) * amount + dir * rng.randf_range(-1.5, 2.0)
		draw_circle(q, rng.randf_range(0.5, 1.4), c)
	for i in int(3 * amount) + 1:  # runs down the wall
		var q := p + side * rng.randf_range(-5.0, 5.0) * amount
		draw_line(q, q + Vector2(0, rng.randf_range(4.0, 11.0)) * amount, Color(c, 0.7), rng.randf_range(0.8, 1.6))


func _draw_smear(p: Vector2, dir: Vector2, length: float, col: Color, rng: RandomNumberGenerator) -> void:
	var dark := Color(col.darkened(0.5), 0.4)
	var q := p
	for i in 6:
		var nq := q + dir.rotated(rng.randf_range(-0.25, 0.25)) * length / 6.0
		draw_line(q, nq, dark, rng.randf_range(2.0, 3.5))
		q = nq
