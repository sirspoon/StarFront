class_name UnitCard
extends PanelContainer
## The card shown in place of the squad list while one of the player's squads is selected:
## what the unit is, how it's holding up, what it carries, how it moves and fights, and bars
## for how hard it hits men in light, medium and heavy armour and armoured vehicles.

const BRASS := Color(0.62, 0.5, 0.28)
const TARGETS := [
	["Light infantry", {"armor": 0.15, "hp": 1}],
	["Medium infantry", {"armor": 0.5, "hp": 3}],
	["Heavy infantry", {"armor": 0.75, "hp": 4}],
	["Armour", {"vehicle": 7, "hp": 14}],  # a side-on tank
]
static var _refs := []  # the strongest full-strength unit in the game against each target, and in close combat

var squad: Squad = null
var title: Label
var text: RichTextLabel
var chart: CardChart
var head: RichTextLabel
var status_chart: CardChart
var small := false


func _init(touch: bool) -> void:
	small = touch
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 15 if small else 17)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	v.add_child(title)
	head = _rich()
	v.add_child(head)
	status_chart = CardChart.new()
	status_chart.small = small
	status_chart.custom_minimum_size = Vector2(300 if small else 340, 2 * 15.0 + 4)
	v.add_child(status_chart)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(300 if small else 340, 0)
	text.add_theme_font_size_override("normal_font_size", 12 if small else 13)
	text.add_theme_font_size_override("bold_font_size", 12 if small else 13)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text)
	chart = CardChart.new()
	chart.small = small
	chart.custom_minimum_size = Vector2(300 if small else 340, TARGETS.size() * 15.0 + 4)
	v.add_child(chart)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(300 if small else 340, 0)
	r.add_theme_font_size_override("normal_font_size", 12 if small else 13)
	r.add_theme_font_size_override("bold_font_size", 12 if small else 13)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func show_squad(sq: Squad, others: int) -> void:
	squad = sq
	if _refs.is_empty():
		_make_refs()
	var v = sq.vehicle()
	title.text = sq.name + ("   (+%d more selected)" % others if others > 0 else "")
	if v != null:
		head.text = "[b]Armoured vehicle[/b]    [b]%s[/b]" % sq.status()
		text.text = _vehicle_lines(v)
	else:
		var aboard: int = sq.members.filter(func(m): return m.state == Soldier.State.EMBARKED).size()
		head.text = "[b]Men[/b] %d / %d%s    [b]%s[/b]" % [sq.alive().size() + aboard, sq.start_size,
				" (%d aboard)" % aboard if aboard > 0 else "", sq.status()]
		text.text = _infantry_lines(sq)
	# the bars: what the men still standing (bright) can do, against the full unit (dim)
	var now := unit_power(_weapons_now(sq) + _grenades(sq, true), _melee_now(sq))
	var full := unit_power(_weapons_full(sq) + _grenades(sq, false), _melee_full(sq))
	var rows: Array = []
	for i in TARGETS.size():
		var ref: float = _refs[3] if i == 3 else _refs[0]  # the three kinds of infantry share one scale
		rows.append([TARGETS[i][0], _scale(now[i], ref), _scale(full[i], ref), ""])
	chart.rows = rows
	chart.queue_redraw()
	# health and morale
	var hp := 0
	var max_hp := 0
	if v != null:
		hp = maxi(v.hp, 0)
		max_hp = v.max_hp
	else:
		for m in sq.members:
			max_hp += m.max_hp
			if m.is_alive():
				hp += maxi(m.hp, 0)
	var srows: Array = [["Hull" if v != null else "Health", float(hp) / maxf(1.0, max_hp), 1.0, "%d / %d" % [hp, max_hp]]]
	if v == null:
		srows.append(["Morale", sq.avg_morale(), 1.0, ""])
	status_chart.rows = srows
	status_chart.custom_minimum_size.y = srows.size() * 15.0 + 4
	status_chart.queue_redraw()


func _bar(frac: float, n := 10) -> String:
	var k := clampi(roundi(frac * n), 0, n)
	return "[color=#d9b25e]%s[/color][color=#4a4030]%s[/color]" % ["■".repeat(k), "■".repeat(n - k)]


func _infantry_lines(sq: Squad) -> String:
	var s := ""
	# armour and pace, from the men themselves
	var arm := 0.0
	var slowest := 999.0
	for m in sq.members:
		arm = maxf(arm, float(m.data.armor))
		slowest = minf(slowest, float(m.data.speed))
	var arm_name := "Light" if arm < 0.3 else ("Medium" if arm < 0.7 else "Heavy")
	var tough := ""
	if sq.members[0].max_hp > 1:
		tough = ", %d wounds each" % sq.members[0].max_hp
	s += "[b]Armour[/b] %s%s    [b]Move[/b] %s\n" % [arm_name, tough, _pace(slowest)]
	# weapons, grouped
	var guns := {}
	var blades := {}
	for m in sq.members:
		var wn: String = GameData.WEAPONS[m.data.weapon].name
		guns[wn] = guns.get(wn, 0) + 1
		var mn: String = GameData.MELEE[m.data.get("melee", "gun_butt")].name
		blades[mn] = blades.get(mn, 0) + 1
	var gl: Array[String] = []
	for k in guns:
		var w: Dictionary = _weapon_named(k)
		gl.append("%s%s (%s)" % ["%d× " % guns[k] if guns[k] > 1 else "", k, _reach(w)])
	s += "[b]Weapons[/b] " + ", ".join(gl) + "\n"
	var bl: Array[String] = []
	for k in blades:
		bl.append("%s%s" % ["%d× " % blades[k] if blades[k] > 1 else "", k])
	var cc := _scale(unit_power([], _melee_now(sq))[4], _refs[4])
	s += "[b]Close combat[/b] %s  %s\n" % [_bar(cc, 5), ", ".join(bl)]
	var gr: Array[String] = []
	for k in [["he", "frag"], ["ap", "tank-breaker"], ["smoke", "smoke"]]:
		var n: int = sq.grenade_count(k[0])
		if n > 0:
			gr.append("%d %s" % [n, k[1]])
	if not gr.is_empty():
		s += "[b]Grenades[/b] " + ", ".join(gr) + "\n"
	var sp := _specials(sq)
	if not sp.is_empty():
		s += "[b]Special[/b] " + "; ".join(sp) + "\n"
	s += "[color=#a09070]Attack against:[/color]"
	return s


func _vehicle_lines(v) -> String:
	var s := "[b]Armour[/b] front %d, sides %d, rear %d\n" % [v.armour[0], v.armour[1], v.armour[2]]
	s += "[b]Move[/b] %s, turns %s\n" % [_pace(float(v.vdata.speed)), "slowly" if float(v.vdata.turn) < 1.2 else "quickly"]
	var gl: Array[String] = []
	for sl in v.slots:
		var w: Dictionary = sl.weapon
		var nm: String = w.name
		if not sl.modes.is_empty():
			nm = "%s [%s] (%s / %s, V switches)" % [sl.modes[0].name.split(" (")[0], w.get("mode", ""), sl.modes[0].get("mode", ""), sl.modes[1].get("mode", "")]
		else:
			nm += " (%s)" % _reach(w)
		gl.append(nm)
	s += "[b]Weapons[/b] " + ", ".join(gl) + "\n"
	s += "[b]Close combat[/b] none, but it can run men down\n"
	var sp: Array[String] = []
	if v.capacity > 0:
		sp.append("carries %d men (%d aboard)" % [v.capacity, v.passengers.size()])
	if v.can_breach():
		sp.append("main gun knocks down walls")
	if not sp.is_empty():
		s += "[b]Special[/b] " + "; ".join(sp) + "\n"
	s += "[color=#a09070]Attack against:[/color]"
	return s


func _specials(sq: Squad) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for m in sq.members:
		var d: Dictionary = m.data
		var w: Dictionary = GameData.WEAPONS[d.weapon]
		for pair in [["leader", "%s leads: steadies the men near him" % d.name], ["charger", "assault troops: charge into close combat"],
				["heavy", "heavy gun: sets up to fire, covering an arc"], ["loader", "loader keeps the heavy gun fed"],
				["bastion", "bastion armour: shrugs off most small arms"], ["steadfast", "steadfast: never flanked"]]:
			if d.get(pair[0], false) and not seen.has(pair[0]):
				seen[pair[0]] = true
				out.append(pair[1])
		if w.get("flame", false) and not seen.has("flame"):
			seen["flame"] = true
			out.append("flamer: ignores cover, sets things alight")
		if float(w.get("blast", 0.0)) > 0.0 and float(w.get("wall", 0.0)) >= 40.0 and not seen.has("wall"):
			seen["wall"] = true
			out.append("can blast through walls")
	return out


func _pace(sp: float) -> String:
	if sp < 30.0:
		return "Slow"
	if sp < 40.0:
		return "Steady"
	if sp < 50.0:
		return "Average"
	return "Fast"


func _reach(w: Dictionary) -> String:
	var r := float(w.range)
	return "short range" if r < 230.0 else ("medium range" if r < 480.0 else "long range")


func _weapon_named(n: String) -> Dictionary:
	for k in GameData.WEAPONS:
		if GameData.WEAPONS[k].name == n:
			return GameData.WEAPONS[k]
	return {}


# ---------------------------------------------------------------- how hard it hits

func _weapons_now(sq: Squad) -> Array:
	var v = sq.vehicle()
	if v != null:
		return v.slots.map(func(sl): return sl.weapon) if v.is_alive() else []
	return sq.alive().map(func(m): return GameData.WEAPONS[m.data.weapon])


func _weapons_full(sq: Squad) -> Array:
	var v = sq.vehicle()
	if v != null:
		return v.slots.map(func(sl): return sl.weapon)
	return sq.members.map(func(m): return GameData.WEAPONS[m.data.weapon])


## Grenades count a little: as if each were thrown once a minute.
static func grenade_weapons(counts: Dictionary) -> Array:
	var out: Array = []
	for k in ["he", "ap"]:
		var g: Dictionary = GameData.GRENADES[k].duplicate()
		g.merge({"acc": 0.6, "burst": 1, "gap": 0.0, "cooldown": 60.0})
		for i in int(counts.get(k, 0)):
			out.append(g)
	return out


func _grenades(sq: Squad, now: bool) -> Array:
	if sq.vehicle() != null:
		return []
	var counts := {}
	if now:
		for k in ["he", "ap"]:
			counts[k] = sq.grenade_count(k)
	else:
		for m in sq.members:
			for k in m.data.get("grenades", {}):
				counts[k] = counts.get(k, 0) + int(m.data.grenades[k])
	return grenade_weapons(counts)


func _melee_now(sq: Squad) -> Array:
	return [] if sq.vehicle() != null else sq.alive().map(func(m): return GameData.MELEE[m.data.get("melee", "gun_butt")])


func _melee_full(sq: Squad) -> Array:
	return [] if sq.vehicle() != null else sq.members.map(func(m): return GameData.MELEE[m.data.get("melee", "gun_butt")])


## A rough measure of harm per second at middle range in the open, against each kind of
## target (light / medium / heavy infantry, armour), then close combat. Only for comparing.
static func unit_power(weapons: Array, blades: Array) -> Array:
	var out := [0.0, 0.0, 0.0, 0.0, 0.0]
	for w in weapons:
		for i in TARGETS.size():
			out[i] += weapon_power(w, TARGETS[i][1])
	for b in blades:
		out[4] += float(b.hit) * float(b.dmg) * (1.0 + float(b.ap)) / float(b.cooldown)
	return out


static func weapon_power(w: Dictionary, t: Dictionary) -> float:
	var beam := float(w.get("beam", 0.0)) > 0.0
	var rate: float = (1.0 / float(w.cooldown)) if beam else float(w.burst) / (float(w.cooldown) + float(w.burst) * float(w.gap))
	if t.has("vehicle"):
		var pen := Vehicle.pen_chance(int(w.get("pen", 0)), int(t.vehicle))
		if beam:
			return rate * 20.0 * 0.5 * float(w.get("dose", 1.0)) * pen * float(w.vdmg) / float(t.hp)
		return rate * float(w.acc) * pen * float(w.get("vdmg", w.dmg)) / float(t.hp)
	var wound := 1.0 - float(t.armor) * (1.0 - float(w.ap))
	var kill := minf(float(w.dmg), float(t.hp)) / float(t.hp)
	var many := 1.0 + float(w.get("blast", 0.0)) / 15.0
	if w.get("flame", false):
		many = 2.5
	if beam:
		return rate * 20.0 * 0.25 * float(w.get("dose", 1.0)) * 1.5 * wound * kill
	return rate * float(w.acc) * wound * kill * many


static func _make_refs() -> void:
	_refs = [0.0, 0.0, 0.0, 0.0, 0.0]
	for f in GameData.FACTIONS:
		for spec in GameData.FACTIONS[f].squads:
			var guns: Array = []
			var blades: Array = []
			if spec.has("vehicle"):
				for wd in GameData.VEHICLES[spec.vehicle].weapons:
					guns.append(GameData.WEAPONS[wd.weapon])
					if wd.has("alt"):
						guns.append(GameData.WEAPONS[wd.alt])  # (counts as the best of both settings)
			else:
				var counts := {}
				for k in spec.members:
					for g in GameData.SOLDIERS[k].get("grenades", {}):
						counts[g] = counts.get(g, 0) + int(GameData.SOLDIERS[k].grenades[g])
				guns.append_array(grenade_weapons(counts))
				for k in spec.members:
					guns.append(GameData.WEAPONS[GameData.SOLDIERS[k].weapon])
					blades.append(GameData.MELEE[GameData.SOLDIERS[k].get("melee", "gun_butt")])
			var p := unit_power(guns, blades)
			for i in 5:
				_refs[i] = maxf(_refs[i], p[i])
	_refs[0] = maxf(_refs[0], maxf(_refs[1], _refs[2]))  # (the infantry scale)


## 0..1 for the bars; a square root so small units still show against big ones.
static func _scale(v: float, ref: float) -> float:
	return sqrt(clampf(v / maxf(ref, 0.0001), 0.0, 1.0))


class CardChart:
	extends Control
	var rows: Array = []  # [label, now 0..1, full strength 0..1, text on the bar]
	var small := false

	func _draw() -> void:
		var font := get_theme_default_font()
		var fs := 12 if small else 13
		var lw := 120.0 if small else 130.0
		var h := 15.0
		for i in rows.size():
			var y := 2.0 + i * h
			var r: Array = rows[i]
			draw_string(font, Vector2(0, y + h - 4), r[0], HORIZONTAL_ALIGNMENT_LEFT, lw, fs, Color(0.85, 0.8, 0.7))
			var bw := size.x - lw - 6
			var box := Rect2(lw, y + 3, bw, h - 6)
			draw_rect(box, Color(0.1, 0.09, 0.07))
			draw_rect(Rect2(box.position, Vector2(bw * float(r[2]), box.size.y)), Color(0.4, 0.33, 0.2, 0.6))
			var col := Color(0.85, 0.3, 0.2).lerp(Color(0.85, 0.75, 0.35), float(r[1])).lerp(Color(0.55, 0.85, 0.4), maxf(0.0, float(r[1]) - 0.5) * 2.0)
			draw_rect(Rect2(box.position, Vector2(bw * float(r[1]), box.size.y)), col)
			for k in range(1, 5):  # quarter marks
				var x := box.position.x + bw * k / 5.0
				draw_line(Vector2(x, box.position.y), Vector2(x, box.end.y), Color(0, 0, 0, 0.5), 1.0)
			draw_rect(box, Color(0.62, 0.5, 0.28, 0.7), false, 1.0)
			if r.size() > 3 and r[3] != "":
				draw_string(font, Vector2(box.position.x + 4, y + h - 4), r[3], HORIZONTAL_ALIGNMENT_LEFT, bw - 8, fs - 1, Color(0.05, 0.04, 0.03))
