extends Node2D
## Marks left on the ground by the battle (blast scorches). Drawn under the soldiers.

var marks: Array = []  # [pos, radius, seed]


func add_scorch(pos: Vector2, r: float) -> void:
	for m in marks:
		if m[0].distance_to(pos) < r * 0.6:
			return  # already blackened here; don't pile marks up into a black blot
	marks.append([pos, r, randi()])
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
