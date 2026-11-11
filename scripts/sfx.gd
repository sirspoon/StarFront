class_name Sfx
extends Node2D
## Plays the game's sound effects (made by tools/make_sounds.py) at places on the map,
## so they pan and fade with distance from the camera. A pool of players is reused,
## and the same sound isn't restarted on top of itself many times a second.

const VARIANTS := {
	"explosion_big": 3, "explosion_small": 3, "cannon": 2, "fusion": 2, "fusion_small": 2,
	"laser": 4, "stubber": 2, "carbine": 3, "rotor": 2, "ricochet": 4, "clang": 2,
	"collapse": 2, "lance": 2,
}
const VOLUME := {  # dB, to balance them against each other
	"explosion_big": 2.0, "explosion_small": -2.0, "cannon": 1.0, "fusion": 0.0, "fusion_small": -4.0,
	"laser": -9.0, "stubber": -5.0, "carbine": -4.0, "rotor": -3.0, "ricochet": -13.0, "clang": -11.0,
	"collapse": -1.0, "lance": -5.0,
}
## Which sound each weapon makes (once per burst).
const WEAPON_SOUND := {
	"lumen_rifle": "laser", "heavy_stubber": "stubber", "mass_carbine": "carbine",
	"rotor_cannon": "rotor", "lance_launcher": "lance", "fusion_carbine": "fusion_small",
	"siege_cannon": "cannon", "fusion_cannon": "fusion",
}
const POOL := 40

var enabled := true
var streams := {}
var pool: Array[AudioStreamPlayer2D] = []
var next := 0
var recent := {}  # name -> [msec, position]
var engine_stream: AudioStreamWAV


func setup(camera: Camera2D) -> void:
	if DisplayServer.get_name() == "headless" or not Settings.on("sound", true):
		enabled = false
		return
	for n in VARIANTS:
		streams[n] = []
		for i in VARIANTS[n]:
			streams[n].append(load("res://sounds/%s_%d.wav" % [n, i]))
	engine_stream = load("res://sounds/engine_0.wav")
	engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_stream.loop_begin = 0
	engine_stream.loop_end = int(engine_stream.get_length() * engine_stream.mix_rate)
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 2400.0
		p.attenuation = 1.4
		p.panning_strength = 0.7
		add_child(p)
		pool.append(p)
	var ear := AudioListener2D.new()
	camera.add_child(ear)
	ear.make_current()


## Play a sound at a map position. Repeats of the same sound within a few
## hundredths of a second close by are dropped, so a firefight doesn't turn to mush.
func play(n: String, pos: Vector2, vol_db := 0.0, pitch_var := 0.07) -> void:
	if not enabled or not streams.has(n):
		return
	var now := Time.get_ticks_msec()
	var r = recent.get(n)
	if r != null and now - r[0] < 45 and r[1].distance_to(pos) < 120.0:
		return
	recent[n] = [now, pos]
	var p := _free_player()
	var vs: Array = streams[n]
	p.stream = vs[randi() % vs.size()]
	p.position = pos
	p.volume_db = VOLUME.get(n, 0.0) + vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func _free_player() -> AudioStreamPlayer2D:
	for i in POOL:
		var p := pool[(next + i) % POOL]
		if not p.playing:
			next = (next + i + 1) % POOL
			return p
	var p := pool[next]  # all busy: cut the oldest
	next = (next + 1) % POOL
	return p


## A looping engine sound for a vehicle.
func make_engine() -> AudioStreamPlayer2D:
	if not enabled:
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = engine_stream
	p.max_distance = 1600.0
	p.attenuation = 1.6
	p.volume_db = -16.0
	return p
