class_name LightFX
extends Node2D
## Short-lived lights from combat: muzzle flashes, bolts and rockets that light the
## ground as they fly, and explosions. A fixed pool of lights is reused, so heavy
## firefights can't create an unlimited number.

const POOL := 40

var tex: Texture2D
var pool: Array[PointLight2D] = []
var active: Array = []  # {light, t, dur, e0, s0, from, to, moving}
var next := 0


func setup(light_tex: Texture2D) -> void:
	tex = light_tex
	for i in POOL:
		var l := PointLight2D.new()
		l.texture = tex
		l.enabled = false
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_color = Color(0, 0, 0, 0.75)
		add_child(l)
		pool.append(l)


func _take() -> PointLight2D:
	# reuse the oldest light if every one is busy
	var l := pool[next]
	next = (next + 1) % POOL
	for a in active:
		if a.light == l:
			active.erase(a)
			break
	return l


## A light that flares at pos and fades over dur seconds.
func flash(pos: Vector2, color: Color, energy: float, radius: float, dur: float, shadows := false) -> void:
	_start(pos, pos, color, energy, radius, dur, shadows, false)
	active[-1].light.height = clampf(radius * 0.25, 14.0, 60.0)  # bigger flashes come from higher up


## A light that travels from a to b over dur seconds (a bolt, tracer or rocket).
func streak(a: Vector2, b: Vector2, color: Color, energy: float, radius: float, dur: float) -> void:
	_start(a, b, color, energy, radius, dur, false, true)
	active[-1].light.height = 10.0  # bolts skim low over the ground


func _start(a: Vector2, b: Vector2, color: Color, energy: float, radius: float, dur: float, shadows: bool, moving: bool) -> void:
	if tex == null:
		return
	var l := _take()
	l.position = a
	l.color = color
	energy *= 1.3  # normal-mapped surfaces take a little less light, so push it up
	l.energy = energy
	l.texture_scale = radius / 128.0
	l.shadow_enabled = shadows
	l.enabled = true
	active.append({"light": l, "t": 0.0, "dur": dur, "e0": energy, "from": a, "to": b, "moving": moving})


func _process(dt: float) -> void:
	if get_parent().paused:
		return  # freeze flashes while the game is paused
	for a in active.duplicate():
		a.t += dt
		var l: PointLight2D = a.light
		var k: float = a.t / a.dur
		if k >= 1.0:
			l.enabled = false
			active.erase(a)
			continue
		if a.moving:
			l.position = a.from.lerp(a.to, k)
			l.energy = a.e0 * (1.0 - k * 0.3)
		else:
			l.energy = a.e0 * pow(1.0 - k, 1.6)
