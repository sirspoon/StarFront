extends Node2D
## Marks left on the ground by the battle (blast scorches). Drawn under the soldiers.

var marks: Array = []  # [pos, radius, seed]


func add_scorch(pos: Vector2, r: float) -> void:
	marks.append([pos, r, randi()])
	queue_redraw()


func _draw() -> void:
	for m in marks:
		var p: Vector2 = m[0]
		var r: float = m[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = m[2]
		draw_circle(p, r, Color(0.05, 0.04, 0.03, 0.35))
		draw_circle(p, r * 0.55, Color(0.03, 0.03, 0.02, 0.5))
		for i in 7:
			var a := rng.randf() * TAU
			draw_line(p, p + Vector2.from_angle(a) * r * rng.randf_range(0.8, 1.4), Color(0.04, 0.03, 0.02, 0.4), 2.0)
