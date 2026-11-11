class_name FlatMap
extends Node2D
## The plainest possible map: one flat colour per cell, drawn directly. Used in
## the web minimal mode (?safe or ?bake=0) to check whether the detailed map is
## what a device can't cope with.

var map: BattleMap

const COLOURS := [Color(0.3, 0.28, 0.25), Color(0.38, 0.36, 0.33), Color(0.18, 0.16, 0.14),
		Color(0.33, 0.31, 0.28), Color(0.52, 0.5, 0.47), Color(0.2, 0.18, 0.16), Color(0.45, 0.4, 0.3)]


func _draw() -> void:
	var c := float(BattleMap.CELL)
	draw_rect(Rect2(Vector2.ZERO, map.world_size()), COLOURS[0])
	for y in BattleMap.H:
		for x in BattleMap.W:
			var t := map.get_t(Vector2i(x, y))
			if t != BattleMap.T.OPEN:
				draw_rect(Rect2(x * c, y * c, c, c), COLOURS[t])
