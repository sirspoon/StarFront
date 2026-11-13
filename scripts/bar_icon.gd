class_name BarIcon
extends Control
## A white icon drawn on a command bar button (with a dark edge so it reads on any
## background), and on a PC the button's key in the corner. Some change with what the
## button is set to: walk / run, standing / down, beam / pulse, AP / HE, pause / play.

const W := Color(0.96, 0.94, 0.88)
const EDGE := Color(0.0, 0.0, 0.0, 0.55)

var kind := ""
var variant := ""  # e.g. "on", "Beam", "Pulse", "AP", "HE", "paused"
var key := ""      # the keyboard shortcut, shown small on a PC


func set_variant(v: String) -> void:
	if v != variant:
		variant = v
		queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y) * (0.78 if key != "" else 0.86)
	var o := (size - Vector2(s, s)) * 0.5
	if key != "":
		o.y -= size.y * 0.04
	# a dark pass offset a touch, then the white
	for layer in 2:
		var off := Vector2(0.9, 0.9) if layer == 0 else Vector2.ZERO
		draw_set_transform(o + off, 0.0, Vector2(s / 24.0, s / 24.0))
		_icon(EDGE if layer == 0 else W)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if key != "":
		var f := get_theme_default_font()
		draw_string(f, Vector2(size.x - 2 - f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, size.y - 1), key,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.78, 0.6, 0.85))


func _man(c: Color, at: Vector2, run: bool) -> void:
	# a striding figure on a 24 grid
	draw_circle(at + Vector2(0, -8), 2.6, c)
	draw_line(at + Vector2(0, -5), at + Vector2(1.5 if run else 0.0, 2), c, 2.6)  # body (leaning when running)
	if run:
		draw_polyline(PackedVector2Array([at + Vector2(1.5, 2), at + Vector2(5, 5), at + Vector2(3.5, 10)]), c, 2.2)
		draw_polyline(PackedVector2Array([at + Vector2(1.5, 2), at + Vector2(-3, 6), at + Vector2(-7, 7)]), c, 2.2)
		draw_polyline(PackedVector2Array([at + Vector2(0.5, -3), at + Vector2(4, -1), at + Vector2(6, -4)]), c, 2.0)
		draw_polyline(PackedVector2Array([at + Vector2(0.5, -3), at + Vector2(-3, -1), at + Vector2(-5, 2)]), c, 2.0)
	else:
		draw_line(at + Vector2(0, 2), at + Vector2(2.5, 10), c, 2.2)
		draw_line(at + Vector2(0, 2), at + Vector2(-2.5, 10), c, 2.2)
		draw_line(at + Vector2(0, -3), at + Vector2(2.5, 3), c, 2.0)
		draw_line(at + Vector2(0, -3), at + Vector2(-2.5, 3), c, 2.0)


func _icon(c: Color) -> void:
	match kind:
		"Assault":  # pace: walking or running
			_man(c, Vector2(12, 12), variant == "on")
			if variant == "on":
				for k in 3:
					draw_line(Vector2(1, 8 + k * 4), Vector2(5 - k, 8 + k * 4), c, 1.4)  # speed lines
		"Down":  # stance: standing, or flat on the ground
			if variant == "on":
				draw_circle(Vector2(4.5, 15), 2.6, c)
				draw_line(Vector2(7, 16), Vector2(20, 17), c, 2.8)
				draw_line(Vector2(9, 17), Vector2(6, 19.5), c, 1.8)
				draw_line(Vector2(1, 20.5), Vector2(23, 20.5), c, 1.4)
			else:
				draw_circle(Vector2(12, 4), 2.6, c)
				draw_line(Vector2(12, 7), Vector2(12, 14), c, 2.8)
				draw_line(Vector2(12, 14), Vector2(10, 20), c, 2.2)
				draw_line(Vector2(12, 14), Vector2(14, 20), c, 2.2)
				draw_line(Vector2(12, 9), Vector2(8.5, 13), c, 2.0)
				draw_line(Vector2(12, 9), Vector2(15.5, 13), c, 2.0)
				draw_line(Vector2(1, 20.5), Vector2(23, 20.5), c, 1.4)
		"Gun":
			match variant:
				"Beam":  # a full, thick beam
					draw_line(Vector2(2, 12), Vector2(22, 12), c, 5.0)
					draw_circle(Vector2(22, 12), 3.0, c)
				"Pulse":  # bolts, dashed
					for k in 4:
						draw_line(Vector2(2 + k * 6, 12), Vector2(5.5 + k * 6, 12), c, 3.2)
				"AP":  # a pointed armour-piercing round
					draw_colored_polygon(PackedVector2Array([Vector2(3, 9), Vector2(15, 9), Vector2(22, 12), Vector2(15, 15), Vector2(3, 15)]), c)
					draw_line(Vector2(6, 8), Vector2(6, 16), EDGE if c == W else c, 1.0)
				"HE":  # a burst
					var pts := PackedVector2Array()
					for k in 16:
						pts.append(Vector2(12, 12) + Vector2.from_angle(k * TAU / 16.0) * (10.0 if k % 2 == 0 else 4.5))
					draw_colored_polygon(pts, c)
				_:
					draw_line(Vector2(2, 12), Vector2(22, 12), c, 3.0)
		"Grenade":
			draw_circle(Vector2(11, 15), 7.0, c)
			draw_rect(Rect2(8.5, 4.5, 5, 4), c)
			draw_polyline(PackedVector2Array([Vector2(13.5, 6), Vector2(18, 4), Vector2(20, 8)]), c, 1.6)  # the lever
			if c == W:
				for k in 2:  # the casing's grooves
					draw_line(Vector2(5.5, 13 + k * 4), Vector2(16.5, 13 + k * 4), EDGE, 1.0)
		"Unload":  # out of a box, arrow leaving
			draw_rect(Rect2(2, 6, 11, 13), c, false, 2.0)
			draw_line(Vector2(8, 12.5), Vector2(19, 12.5), c, 2.6)
			draw_colored_polygon(PackedVector2Array([Vector2(17, 8), Vector2(23, 12.5), Vector2(17, 17)]), c)
		"Face":  # an arrow out from a line, as the squad will face
			draw_line(Vector2(3, 18), Vector2(21, 18), c, 2.6)
			draw_line(Vector2(12, 18), Vector2(12, 9), c, 3.2)
			draw_colored_polygon(PackedVector2Array([Vector2(6.5, 10), Vector2(12, 3), Vector2(17.5, 10)]), c)
		"Halt":  # a raised hand, palm forward
			draw_rect(Rect2(7, 10, 11, 10), c)
			draw_circle(Vector2(12.5, 20), 5.5, c)
			for k in 4:
				var x := 7.6 + k * 2.75
				var top := 3.5 if k == 1 or k == 2 else 5.0
				draw_rect(Rect2(x, top, 2.2, 10.0 - top + 2.0), c)
				draw_circle(Vector2(x + 1.1, top), 1.1, c)
			draw_colored_polygon(PackedVector2Array([Vector2(7, 14), Vector2(3, 10), Vector2(2, 11.5), Vector2(6, 18)]), c)  # thumb
		"Cover":  # a shield
			draw_colored_polygon(PackedVector2Array([Vector2(4, 4), Vector2(20, 4), Vector2(20, 12), Vector2(12, 21), Vector2(4, 12)]), c)
			if c == W:
				draw_colored_polygon(PackedVector2Array([Vector2(7, 7), Vector2(17, 7), Vector2(17, 11.5), Vector2(12, 17), Vector2(7, 11.5)]), EDGE)
		"Squads":  # three heads: the squad list
			for k in 3:
				var x := 5.0 + k * 7.0
				var y := 10.0 if k == 1 else 12.0
				draw_circle(Vector2(x, y - 3), 2.6, c)
				draw_rect(Rect2(x - 3, y, 6, 7), c)
		"Pause":
			if variant == "paused":  # play
				draw_colored_polygon(PackedVector2Array([Vector2(7, 4), Vector2(20, 12), Vector2(7, 20)]), c)
			else:
				draw_rect(Rect2(6, 4, 4, 16), c)
				draw_rect(Rect2(14, 4, 4, 16), c)
		"Menu":  # three lines
			for k in 3:
				draw_rect(Rect2(4, 5.5 + k * 5.5, 16, 2.6), c)
