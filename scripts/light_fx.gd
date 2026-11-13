class_name LightFX
extends Node2D
## Short-lived lights from combat: muzzle flashes, bolts and rockets that light the
## ground as they fly, and explosions. A fixed pool of lights is reused, so heavy
## firefights can't create an unlimited number.

const POOL := 40
const PHONE_POOL := 8  # each light means more work drawing the lit map: phones get few

var tex: Texture2D
var pool: Array[PointLight2D] = []
var active: Array = []  # {light, t, dur, e0, s0, from, to, moving}
var next := 0
var enabled_fx := true
var shadows_ok := true
var boost := 1.0  # the Options' lighting strength: brighter, wider flashes and deeper shadows


func setup(light_tex: Texture2D) -> void:
	tex = light_tex
	boost = Settings.light_boost()
	for i in (PHONE_POOL if Settings.is_phone() else POOL):
		var l := PointLight2D.new()
		l.texture = tex
		l.enabled = false
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_color = Color(0, 0, 0, minf(0.95, 0.75 + (boost - 1.0) * 0.15))
		add_child(l)
		pool.append(l)


func _take() -> PointLight2D:
	# reuse the oldest light if every one is busy
	var l := pool[next]
	next = (next + 1) % pool.size()
	for a in active:
		if a.light == l:
			active.erase(a)
			break
	return l


## A light that flares at pos and fades over dur seconds.
func flash(pos: Vector2, color: Color, energy: float, radius: float, dur: float, shadows := false) -> void:
	if _restack(pos, energy, dur, false):
		return
	_start(pos, pos, color, energy, radius, dur, shadows, false)
	if active.is_empty():
		return  # lights are off
	active[-1].light.height = clampf(radius * 0.25, 14.0, 60.0)  # bigger flashes come from higher up


## A light that travels from a to b over dur seconds (a bolt, tracer or rocket).
func streak(a: Vector2, b: Vector2, color: Color, energy: float, radius: float, dur: float) -> void:
	if _restack(a, energy, dur, true):
		return
	_start(a, b, color, energy, radius, dur, false, true)
	if active.is_empty():
		return
	active[-1].light.height = 10.0  # bolts skim low over the ground


## A light's energy with the lighting strength option applied, never blinding (for lights kept
## outside the pool too: fires, the lance's beam, molten ground).
func boosted(energy: float) -> float:
	return minf(energy * boost, 5.5)


## Rapid fire from one gun: a new small light where one was started a moment ago would pile up
## on it (three buggies firing six-round bursts blew the screen out white). Instead the light
## already there keeps burning. Big lights (explosions, the lance) always get their own.
func _restack(pos: Vector2, energy: float, dur: float, moving: bool) -> bool:
	if energy >= 1.8:
		return false
	for a in active:
		if a.moving == moving and a.t < 0.07 and a.from.distance_squared_to(pos) < 24.0 * 24.0:
			a.t = 0.0
			a.dur = maxf(a.dur, dur)
			return true
	return false


func _start(a: Vector2, b: Vector2, color: Color, energy: float, radius: float, dur: float, shadows: bool, moving: bool) -> void:
	if tex == null or not enabled_fx:
		return
	var l := _take()
	l.position = a
	l.color = color
	# the lighting strength option: big lights (explosions, the lance) take the full boost, small
	# ones (muzzle flashes, bolts) only part of it; and nothing gets blinding, however strong
	var bf := boost if energy >= 1.8 else lerpf(1.0, boost, 0.4)
	energy = minf(energy * 1.3 * bf, 5.5)  # (normal-mapped surfaces take a little less light, so push it up)
	l.energy = energy
	l.texture_scale = radius / 128.0 * sqrt(bf)
	l.shadow_enabled = shadows and shadows_ok
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
