class_name CoverView
extends Node2D
## The Cover view: colours the ground by what it gives a soldier, so it's clear at a glance
## which walls still stand and where men can take cover. Shown with the Cover button (C), and
## by itself while a move order is being dragged out. Redrawn only when the view moves or the
## map changes.
##   green  - low cover (sandbags, barricades, low walls): good cover, men fire over it
##   blue   - windows: cover, and men can shoot through
##   white  - standing walls and wrecks: block sight and shots, no way through
##   yellow - rubble and craters: some cover
##   olive  - bushes (hide a still man) and hedges (block sight)
##   red    - barbed wire: no cover, very slow to cross
## Collapsed walls are left uncoloured: they're gone.

const C := BattleMap.CELL

var main: Node
var map: BattleMap
var window := Rect2i()
var showing := false


func setup(m: Node) -> void:
	main = m
	map = m.map
	z_index = 9
	map.cells_changed.connect(func(_c): queue_redraw())


func wanted() -> bool:
	return main.cover_mode or main.t_mode in ["line", "line_face", "held"] or main.right_held


func _process(_dt: float) -> void:
	var want: bool = wanted() and main.started
	if want != showing:
		showing = want
		visible = want
		queue_redraw()
	if not showing:
		return
	var cam: Camera2D = main.camera
	var half := get_viewport_rect().size * 0.5 / cam.zoom
	var w := Rect2i(map.cell_of(cam.position - half) - Vector2i(2, 2), Vector2i((half * 2.0) / C) + Vector2i(5, 5))
	if w != window:
		window = w
		queue_redraw()


func _draw() -> void:
	if not showing:
		return
	for y in range(maxi(window.position.y, 0), mini(window.end.y, BattleMap.H)):
		for x in range(maxi(window.position.x, 0), mini(window.end.x, BattleMap.W)):
			var c := Vector2i(x, y)
			var r := Rect2(Vector2(c) * C, Vector2(C, C))
			match map.get_t(c):
				BattleMap.T.LOW:
					draw_rect(r.grow(-1), Color(0.3, 1.0, 0.35, 0.38))
					draw_rect(r.grow(-1), Color(0.4, 1.0, 0.45, 0.85), false, 1.2)
				BattleMap.T.WINDOW:
					draw_rect(r.grow(-1), Color(0.35, 0.7, 1.0, 0.45))
					draw_rect(r.grow(-1), Color(0.5, 0.8, 1.0, 0.9), false, 1.2)
				BattleMap.T.WALL, BattleMap.T.WRECK:
					draw_rect(r, Color(0.95, 0.95, 1.0, 0.22))
					draw_rect(r.grow(-0.5), Color(1, 1, 1, 0.75), false, 1.0)
				BattleMap.T.TRENCH:
					draw_rect(r, Color(0.75, 0.45, 0.2, 0.4))
				BattleMap.T.RUBBLE, BattleMap.T.CRATER:
					draw_rect(r.grow(-2), Color(1.0, 0.85, 0.3, 0.2))
				BattleMap.T.BUSH:
					draw_circle(r.get_center(), 5.0, Color(0.6, 0.75, 0.3, 0.35))
				BattleMap.T.HEDGE:
					draw_rect(r.grow(-1), Color(0.45, 0.6, 0.25, 0.5))
					draw_rect(r.grow(-1), Color(0.6, 0.75, 0.35, 0.9), false, 1.0)
				BattleMap.T.WIRE:
					draw_line(r.position + Vector2(3, 3), r.end - Vector2(3, 3), Color(1.0, 0.3, 0.25, 0.9), 1.4)
					draw_line(Vector2(r.position.x + 3, r.end.y - 3), Vector2(r.end.x - 3, r.position.y + 3), Color(1.0, 0.3, 0.25, 0.9), 1.4)
