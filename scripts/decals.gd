extends Node2D
## Marks left on the ground by the battle: blast scorches, small burn marks where shots
## strike, blood and track ruts. Drawn under the soldiers, in a grid of chunks: a new mark
## only redraws its own chunk (a few times a second at most), chunks off screen aren't
## drawn, and lights only light the chunks they reach. The oldest small marks and ruts go
## once there are many.

const MAX_SMALL := 700
const MAX_TRACKS := 900
const CHUNK := 320.0  # pixels

var marks: Array = []   # blast scorches: [pos, radius, seed]
var small: Array = []   # [kind, pos, dir, size, seed, colour]  kind: "burn", "blood", "smear", "wall"
var tracks: Array = []  # vehicle track marks: [from, to, gap, tread width]
var chunks := {}        # Vector2i -> Chunk
var dirty := {}         # chunks waiting to be redrawn
var redraw_timer := 0.0


func _chunk_at(p: Vector2) -> Chunk:
	var k := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	var ch: Chunk = chunks.get(k)
	if ch == null:
		ch = Chunk.new()
		ch.light_mask = light_mask
		add_child(ch)
		chunks[k] = ch
	return ch


func _touch(ch: Chunk) -> void:
	dirty[ch] = true


func add_scorch(pos: Vector2, r: float) -> void:
	for m in marks:
		if m[0].distance_to(pos) < r * 0.6:
			return  # already blackened here; don't pile marks up into a black blot
	var m := [pos, r, randi()]
	marks.append(m)
	var ch := _chunk_at(pos)
	ch.marks.append(m)
	_touch(ch)


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
	var t := [a, b, gap, tread]
	tracks.append(t)
	var ch := _chunk_at((a + b) * 0.5)
	ch.tracks.append(t)
	_touch(ch)
	if tracks.size() > MAX_TRACKS:
		var old: Array = tracks.pop_front()
		var oc := _chunk_at((old[0] + old[1]) * 0.5)
		oc.tracks.erase(old)
		_touch(oc)


## A smear or trail of blood (a wounded man dragged or crawling).
func add_smear(pos: Vector2, dir: Vector2, length: float, col: Color) -> void:
	_add(["smear", pos, dir.normalized(), length, randi(), col])


func _add(m: Array) -> void:
	small.append(m)
	var ch := _chunk_at(m[1])
	ch.small.append(m)
	_touch(ch)
	if small.size() > MAX_SMALL:
		var old: Array = small.pop_front()
		var oc := _chunk_at(old[1])
		oc.small.erase(old)
		_touch(oc)


func _process(dt: float) -> void:
	redraw_timer -= dt
	if not dirty.is_empty() and redraw_timer <= 0.0:
		redraw_timer = 0.25
		for ch in dirty:
			ch.queue_redraw()
		dirty.clear()


## One square of the ground's marks.
class Chunk:
	extends Node2D
	var marks: Array = []
	var small: Array = []
	var tracks: Array = []

	## A round mark. Tiny ones (most blood drops and burn specks) are drawn as small squares:
	## the same at that size, and a fraction of the triangles a circle takes.
	func _dot(p: Vector2, r: float, col: Color) -> void:
		if r < 1.6:
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), col)
		elif r < 4.0:
			# an octagon
			var pts := PackedVector2Array()
			for k in 8:
				pts.append(p + Vector2.from_angle(k * TAU / 8.0) * r)
			draw_colored_polygon(pts, col)
		else:
			draw_circle(p, r, col)

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
					k += 5.0
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
		_dot(p, size * 1.6, Color(0.05, 0.04, 0.03, 0.18))
		_dot(p, size * 0.8, Color(0.03, 0.02, 0.02, 0.45))
		for i in 4:
			var a := rng.randf() * TAU
			draw_line(p, p + Vector2.from_angle(a) * size * rng.randf_range(1.5, 2.6), Color(0.03, 0.02, 0.02, 0.3), 0.8)


	## Droplets and streaks fanned out away from the shooter: the further a drop flew,
	## the smaller it is and the more it is drawn out along its path.
	func _draw_blood(p: Vector2, dir: Vector2, amount: float, col: Color, rng: RandomNumberGenerator) -> void:
		var dark := Color(col.darkened(0.45), 0.65)  # old blood soaks into dust: dark and dull
		_dot(p + dir * 2.0, 1.8 * amount, Color(dark, 0.55))
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
				_dot(tail, s * 0.4, Color(dark, 0.6))
			_dot(q, s * 0.8, Color(dark, 0.6))


	func _draw_wall_blood(p: Vector2, dir: Vector2, amount: float, col: Color, rng: RandomNumberGenerator) -> void:
		var c := Color(col.darkened(0.25), 0.8)
		var side := dir.orthogonal()
		_dot(p, 2.6 * amount, c)  # the splat
		for i in int(8 * amount) + 3:  # droplets fanned out across the wall face
			var q := p + side * rng.randf_range(-9.0, 9.0) * amount + dir * rng.randf_range(-1.5, 2.0)
			_dot(q, rng.randf_range(0.5, 1.4), c)
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
