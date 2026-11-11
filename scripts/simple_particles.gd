class_name SimpleParticles
extends Node2D
## A small particle emitter for fire, smoke, dust and ash, drawn with plain
## textured quads. Godot's built-in CPU particles lose their colours in some web
## browsers (white ash turned cyan, flames green), so we draw our own.

var texture: Texture2D
var amount := 20
var lifetime := 1.0
var emitting := true
var one_shot := false
var preprocess := 0.0
var emission_radius := 0.0
var emission_rect := Vector2.ZERO   # half-extents; used instead of the radius when set
var direction := Vector2(0, -1)
var spread := 30.0                  # degrees either side of direction
var gravity := Vector2.ZERO
var velocity_min := 10.0
var velocity_max := 20.0
var damping := 0.0                  # speed lost per second
var scale_min := 1.0
var scale_max := 1.0
var scale_curve: Curve
var color := Color.WHITE
var color_ramp: Gradient

var parts: Array = []  # [global position, velocity, age, scale]
var spawn_acc := 0.0
var spawned := 0
var free_when_done := false


func _ready() -> void:
	var t := 0.0
	while t < preprocess:
		_step(0.1)
		t += 0.1


func _process(dt: float) -> void:
	_step(dt)
	queue_redraw()
	if free_when_done and not emitting and parts.is_empty():
		queue_free()


func _spawn() -> void:
	var p := global_position
	if emission_rect != Vector2.ZERO:
		p += Vector2(randf_range(-1, 1) * emission_rect.x, randf_range(-1, 1) * emission_rect.y)
	elif emission_radius > 0.0:
		p += Vector2.from_angle(randf() * TAU) * sqrt(randf()) * emission_radius
	var a := direction.angle() + deg_to_rad(randf_range(-spread, spread))
	parts.append([p, Vector2.from_angle(a) * randf_range(velocity_min, velocity_max), 0.0, randf_range(scale_min, scale_max)])
	spawned += 1


func _step(dt: float) -> void:
	if emitting:
		if one_shot:
			while spawned < amount:
				_spawn()
			emitting = false
		else:
			spawn_acc += dt * amount / lifetime
			while spawn_acc >= 1.0:
				spawn_acc -= 1.0
				if parts.size() < amount:
					_spawn()
	var i := 0
	while i < parts.size():
		var q: Array = parts[i]
		q[2] += dt
		if q[2] >= lifetime:
			parts.remove_at(i)
			continue
		q[1] += gravity * dt
		if damping > 0.0:
			q[1] = q[1].move_toward(Vector2.ZERO, damping * dt)
		q[0] += q[1] * dt
		i += 1


func _draw() -> void:
	if texture == null:
		return
	var base := texture.get_size()
	for q in parts:
		var k: float = q[2] / lifetime
		var col := color_ramp.sample(k) if color_ramp != null else color
		var s: float = q[3] * (scale_curve.sample(k) if scale_curve != null else 1.0)
		var size := base * s
		draw_texture_rect(texture, Rect2(to_local(q[0]) - size * 0.5, size), false, col)
