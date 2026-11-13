class_name UnitCard
extends PanelContainer
## The card shown in place of the squad list while one of the player's squads is selected.
## Mostly drawn: icons for men, armour, pace, health, morale, range, close combat, grenades
## and special abilities, bars for how hard the unit hits each kind of target, and weapon
## and ability tags that show their details on the bottom line when hovered or tapped.

const BRASS := Color(0.62, 0.5, 0.28)
const GOLD := Color(0.9, 0.76, 0.45)
const TEXT := Color(0.86, 0.81, 0.7)
const MAX_RANGE := 620.0  # the longest reach in the game: the range scale's full width
const TARGETS := [
	["light", "Light", {"armor": 0.15, "hp": 1}],
	["medium", "Medium", {"armor": 0.5, "hp": 3}],
	["heavy", "Heavy", {"armor": 0.75, "hp": 4}],
	["vehicle", "Armour", {"vehicle": 7, "hp": 14}],  # a side-on tank
]
const SPECIALS := {
	"leader": ["Leader", "Leader: steadies the men close to him; if he falls they waver"],
	"charger": ["Assault", "Assault troops: charge home into close combat (R)"],
	"heavy": ["Heavy gun", "Heavy gun: must set up to fire, then covers an arc"],
	"loader": ["Loader", "Loader: keeps the heavy gun fed (faster reloads)"],
	"bastion": ["Bastion", "Bastion armour: shrugs off most small-arms fire"],
	"steadfast": ["Steadfast", "Steadfast: can't be flanked or caught in crossfire"],
	"flame": ["Flamer", "Flamer: a jet of fire round cover; sets the scenery alight"],
	"breach": ["Breacher", "Breaks walls: can shell or blast a way through buildings"],
	"carrier": ["Carrier", "Carrier: men board it (right click it) and unload (U)"],
	"modes": ["2 settings", "Main gun has two settings: V switches them"],
	"launcher": ["Launchers", "Grenade launchers: Grenade (T) then tap a spot to fire six of the loaded round there (it turns to face the spot); Gun (V) switches HE / smoke. Three salvos of each"],
}
static var _refs := []  # the strongest full-strength unit's power: [infantry, -, -, armour, close combat]

var small := false
var box: VBoxContainer
var squad: Squad = null
var sig := ""
var title: Label
var status_lbl: Label
var men_lbl: Label
var health: CardBar
var morale: CardBar
var attack: Array = []  # CardBar per target
var info: Label             # the details of whatever was hovered or tapped...
var popup: PanelContainer   # ...shown in a small window over the card, not in it
var info_hold := 0.0
var W := 330.0


func _init(touch: bool) -> void:
	small = touch
	W = 270.0 if small else 330.0
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 1 if small else 3)
	add_child(box)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_squad(sq: Squad, others: int) -> void:
	if _refs.is_empty():
		_make_refs()
	var v = sq.vehicle()
	var s := "%d|%d|%d|%d|%s|%s|%s" % [sq.get_instance_id(), sq.alive().size(), _aboard(sq), others,
			sq.grenade_count("he") * 100 + sq.grenade_count("ap") * 10 + sq.grenade_count("smoke"),
			v.gun_mode() if v != null else "", (str(v.passengers.size()) + str(v.launch_ammo) + str(v.plate_off) + str(v.track_off)) if v != null else ""]
	if s != sig or squad != sq:
		sig = s
		squad = sq
		_build(sq, others)
	_update(sq)


func _aboard(sq: Squad) -> int:
	return sq.members.filter(func(m): return m.state == Soldier.State.EMBARKED).size()


# ---------------------------------------------------------------- building the card

func _label(t: String, size := 13, col := TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size - (1 if small else 0))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _icon(kind: String, level := 0, tip := "") -> CardIcon:
	var ic := CardIcon.new()
	ic.kind = kind
	ic.level = level
	ic.custom_minimum_size = Vector2(16, 16) if small else Vector2(18, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tip != "":
		_hover(ic, tip)
	else:
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


## Hovering (or tapping) shows the details on the bottom line.
func _hover(c: Control, tip: String) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_entered.connect(func(): _show_info(tip, 0.0))
	c.mouse_exited.connect(func(): if info_hold <= 0.0: _show_info("", 0.0))
	c.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_show_info(tip, 4.0))


func _show_info(t: String, hold: float) -> void:
	if popup == null:
		if get_parent() == null:
			return
		popup = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.075, 0.055, 0.96)
		sb.border_color = BRASS
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(7)
		popup.add_theme_stylebox_override("panel", sb)
		info = _label("", 12, Color(0.95, 0.88, 0.65))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(W - 14, 0)
		popup.add_child(info)
		popup.mouse_filter = Control.MOUSE_FILTER_STOP
		popup.gui_input.connect(func(e):
			if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
				_show_info("", 0.0))  # tap the window to close it
		get_parent().add_child(popup)
	info.text = t
	popup.visible = t != "" and visible
	info_hold = hold
	if popup.visible:
		_place_popup.call_deferred()


## The details window sits just above the card (or beside it if there's no room above).
func _place_popup() -> void:
	if popup == null or not popup.visible:
		return
	var ms := popup.get_combined_minimum_size()
	popup.size = ms
	var p := Vector2(position.x, position.y - ms.y - 6.0)
	if p.y < 44.0:
		p = Vector2(position.x + size.x + 6.0, maxf(44.0, position.y + size.y - ms.y))
	popup.position = p


func _row(parts: Array, sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in parts:
		h.add_child(p)
	return h


func _bar(kind: String, h := 12.0) -> CardBar:
	var b := CardBar.new()
	b.kind = kind
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _tag(text: String, tip: String, icon := "") -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.16, 0.11)
	sb.border_color = BRASS.darkened(0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3
	sb.content_margin_right = 5
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	var h := _row([], 3)
	if icon != "":
		var ic := _icon(icon)
		ic.custom_minimum_size = Vector2(14, 14)
		h.add_child(ic)
	h.add_child(_label(text, 12))
	p.add_child(h)
	_hover(p, tip)
	return p


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 3)
	f.custom_minimum_size = Vector2(W - 26, 0)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build(sq: Squad, others: int) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	attack.clear()
	_show_info("", 0.0)
	var v = sq.vehicle()
	# title and what they're doing
	title = _label(sq.name + ("  +%d" % others if others > 0 else ""), 15 if small else 16, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl = _label("", 13)
	box.add_child(_row([title, status_lbl]))
	# men / armour / pace
	var top := _row([], 4)
	if v == null:
		men_lbl = _label("", 13)
		top.add_child(_icon("men", 0, "Men left / at the start (and aboard a carrier)"))
		top.add_child(men_lbl)
		var arm := 0.0
		var slowest := 999.0
		for m in sq.members:
			arm = maxf(arm, float(m.data.armor))
			slowest = minf(slowest, float(m.data.speed))
		var lvl := 1 if arm < 0.3 else (2 if arm < 0.7 else 3)
		var an: String = ["", "Light", "Medium", "Heavy"][lvl]
		var wounds: int = sq.members[0].max_hp
		top.add_child(_spacer(8))
		top.add_child(_icon("armour", lvl, "%s armour%s" % [an, (", %d wounds each" % wounds) if wounds > 1 else ""]))
		top.add_child(_label(an + (" ×%d" % wounds if wounds > 1 else ""), 13))
		top.add_child(_spacer(8))
		var pl := _pace_level(slowest)
		top.add_child(_icon("speed", pl, "Pace: %s (%d), the slowest man's" % [_pace_name(pl), int(slowest)]))
		top.add_child(_label(_pace_name(pl), 13))
	else:
		men_lbl = null
		top.add_child(_icon("armour", 4, "Armour: front %d, sides %d, rear %d (a weapon's pen must match it)" % [v.armour[0], v.armour[1], v.armour[2]]))
		top.add_child(_label("%d / %d / %d" % [v.armour[0], v.armour[1], v.armour[2]], 13))
		top.add_child(_spacer(8))
		var pl := _pace_level(float(v.vdata.speed))
		top.add_child(_icon("speed", pl, "Pace: %s (%d), turns %s" % [_pace_name(pl), int(v.vdata.speed), "slowly" if float(v.vdata.turn) < 1.2 else "quickly"]))
		top.add_child(_label(_pace_name(pl), 13))
		if v.capacity > 0:
			top.add_child(_spacer(8))
			top.add_child(_icon("men", 0, "Men aboard / room for"))
			men_lbl = _label("", 13)
			top.add_child(men_lbl)
	box.add_child(top)
	# health and morale
	health = _bar("status")
	var hrow := _row([_icon("health", 0, "Hull left" if v != null else "Wounds left across the squad"), health])
	box.add_child(hrow)
	if v == null:
		morale = _bar("status")
		var mi := _icon("morale", 0, "Morale: low morale pins men down, then they run")
		if small:  # side by side on a phone
			hrow.add_child(mi)
			hrow.add_child(morale)
		else:
			box.add_child(_row([mi, morale]))
	else:
		morale = null
	# weapons as tags, and their reach on one scale
	var guns := _gun_list(sq)
	var wf := _flow()
	var ranges: Array = []
	for g in guns:
		var w: Dictionary = g[0]
		wf.add_child(_tag(("%d× " % g[1] if g[1] > 1 else "") + g[2], _weapon_info(w, g[2])))
		ranges.append([float(w.range), g[2]])
	box.add_child(_row([_icon("gun", 0, "Weapons (hover or tap one for details)"), wf]))
	var rb := CardRange.new()
	rb.ranges = ranges
	rb.step = 6.0 if small else 8.0
	rb.custom_minimum_size = Vector2(0, 8 + rb.step * ranges.size())
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rtip: Array[String] = []
	for r in ranges:
		rtip.append("%s %d" % [r[1], int(r[0])])
	var rt := "Range, on a scale to %d (the longest in the battle): %s" % [int(MAX_RANGE), ", ".join(rtip)]
	_hover(rb, rt)
	box.add_child(_row([_icon("range", 0, rt), rb]))
	# close combat and grenades on one line (on a phone, the special abilities join them)
	var cc: Container = _flow() if small else _row([], 4)
	if v == null:
		var blades := {}
		for m in sq.members:
			var b: Dictionary = GameData.MELEE[m.data.get("melee", "gun_butt")]
			blades[b.name] = blades.get(b.name, 0) + 1
		var bl: Array[String] = []
		for k in blades:
			bl.append(("%d× " % blades[k] if blades[k] > 1 else "") + k)
		var tip := "Close combat (full squad): " + ", ".join(bl)
		cc.add_child(_icon("melee", 0, tip))
		var pips := CardPips.new()
		pips.value = _scale(unit_power([], _melee_full(sq))[4], _refs[4])
		pips.custom_minimum_size = Vector2(50, 14)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hover(pips, tip)
		cc.add_child(pips)
		for k in [["he", "frag", "Frag grenades: a burst against men"], ["ap", "ap", "Tank-breaker charges: against armour and walls"],
				["smoke", "smoke", "Smoke grenades: a screen that blocks sight"]]:
			var n: int = sq.grenade_count(k[0])
			if n > 0:
				cc.add_child(_spacer(6))
				var t := "%s (%d left; T then click to throw)" % [k[2], n]
				cc.add_child(_icon(k[1], 0, t))
				cc.add_child(_label(str(n), 13))
	else:
		cc.add_child(_icon("melee", 0, "No close combat, but it can run men down"))
		cc.add_child(_label("Runs men down", 12, TEXT.darkened(0.2)))
	box.add_child(cc)
	# special abilities as tags
	var sp := _specials(sq)
	if not sp.is_empty():
		var f: Container = cc if small else _flow()
		for k in sp:
			var name: String = SPECIALS[k][0]
			if k == "launcher":
				name = "HE %d · Smoke %d" % [int(v.launch_ammo.he), int(v.launch_ammo.smoke)]
			f.add_child(_tag(name, SPECIALS[k][1], k))
		if not small:
			box.add_child(_row([_icon("star", 0, "Special abilities (hover or tap for details)"), f]))
	# how hard it hits each kind of target
	var pair: HBoxContainer = null
	for t in TARGETS:
		var b := _bar("attack", 10.0 if small else 11.0)
		attack.append(b)
		var what: String = t[1].to_lower() + (" infantry" if t[0] != "vehicle" else "")
		var ic := _icon(t[0], 0, "Attack against %s: bright = the men still standing, dim = the full unit" % what)
		if small:  # two to a row, pictures only
			if pair == null or pair.get_child_count() >= 4:
				pair = _row([], 3)
				box.add_child(pair)
			pair.add_child(ic)
			pair.add_child(b)
		else:
			var lbl := _label(t[1], 12)
			lbl.custom_minimum_size = Vector2(52, 0)
			box.add_child(_row([ic, lbl, b], 4))
	if "--shot-tag" in OS.get_cmdline_user_args() and not guns.is_empty():
		_show_info.call_deferred(_weapon_info(guns[0][0], guns[0][2]), 9999.0)  # test aid: a weapon's details in the shot


func _update(sq: Squad) -> void:
	var v = sq.vehicle()
	var st: String = sq.status()
	status_lbl.text = st
	status_lbl.add_theme_color_override("font_color", {"Pinned": Color(0.95, 0.6, 0.3), "Routing": Color(0.95, 0.35, 0.3),
			"Lost": Color(0.6, 0.55, 0.5)}.get(st, Color(0.7, 0.85, 0.6)))
	if v == null:
		var ab := _aboard(sq)
		men_lbl.text = "%d/%d%s" % [sq.alive().size() + ab, sq.start_size, " (%d in)" % ab if ab > 0 else ""]
		var hp := 0
		var max_hp := 0
		for m in sq.members:
			max_hp += m.max_hp
			if m.is_alive():
				hp += maxi(m.hp, 0)
		health.set_values(float(hp) / maxf(1.0, max_hp), 1.0, "%d/%d" % [hp, max_hp])
		morale.set_values(sq.avg_morale(), 1.0, "")
	else:
		health.set_values(float(maxi(v.hp, 0)) / v.max_hp, 1.0, "%d/%d" % [maxi(v.hp, 0), v.max_hp])
		if men_lbl != null:
			men_lbl.text = "%d/%d" % [v.passengers.size(), v.capacity]
	var now := unit_power(_weapons_now(sq) + _grenades(sq, true), [])
	var full := unit_power(_weapons_full(sq) + _grenades(sq, false), [])
	for i in TARGETS.size():
		var ref: float = _refs[3] if i == 3 else _refs[0]  # the three kinds of infantry share one scale
		attack[i].set_values(_scale(now[i], ref), _scale(full[i], ref), "")


func _process(dt: float) -> void:
	if popup != null and popup.visible and not visible:
		popup.visible = false
	if info_hold > 0.0:
		info_hold -= dt
		if info_hold <= 0.0:
			_show_info("", 0.0)


# ---------------------------------------------------------------- words for the details line

func _gun_list(sq: Squad) -> Array:
	var v = sq.vehicle()
	var out: Array = []  # [weapon, count, name]
	if v != null:
		for sl in v.slots:
			var nm: String = sl.weapon.name
			if not sl.modes.is_empty():
				nm = "%s: %s" % [String(sl.modes[0].name).split(" (")[0], sl.weapon.get("mode", "")]
			out.append([sl.weapon, 1, nm])
		return out
	var idx := {}
	for m in sq.members:
		var w: Dictionary = GameData.WEAPONS[m.data.weapon]
		if idx.has(w.name):
			out[idx[w.name]][1] += 1
		else:
			idx[w.name] = out.size()
			out.append([w, 1, w.name])
	return out


func _weapon_info(w: Dictionary, nm: String) -> String:
	var parts: Array[String] = [nm, "range %d" % int(w.range)]
	if float(w.get("beam", 0.0)) > 0.0:
		parts.append("%.0f s beam every %.1f s" % [float(w.beam), float(w.cooldown)])
	elif int(w.burst) > 1:
		parts.append("%d-shot bursts every %.1f s" % [int(w.burst), float(w.cooldown)])
	else:
		parts.append("a shot every %.1f s" % float(w.cooldown))
	parts.append("damage %d" % int(w.dmg))
	parts.append("pierces %d%% of body armour" % int(round(float(w.ap) * 100.0)))
	parts.append("pen %d vs vehicles" % int(w.get("pen", 0)))
	if float(w.get("blast", 0.0)) > 0.0:
		parts.append("blast %d" % int(w.blast))
	if w.get("flame", false):
		parts.append("flame")
	if w.has("mode"):
		parts.append("V switches setting")
	return " · ".join(parts)


func _specials(sq: Squad) -> Array:
	var out: Array = []
	var v = sq.vehicle()
	if v != null:
		if v.capacity > 0:
			out.append("carrier")
		if v.can_breach():
			out.append("breach")
		if v.launcher:
			out.append("launcher")
		elif v.gun_mode() != "":
			out.append("modes")
		return out
	for m in sq.members:
		var d: Dictionary = m.data
		var w: Dictionary = GameData.WEAPONS[d.weapon]
		for k in ["leader", "charger", "heavy", "loader", "bastion", "steadfast"]:
			if d.get(k, false) and not k in out:
				out.append(k)
		if w.get("flame", false) and not "flame" in out:
			out.append("flame")
		if float(w.get("blast", 0.0)) > 0.0 and float(w.get("wall", 0.0)) >= 40.0 and not "breach" in out:
			out.append("breach")
	return out


func _pace_level(sp: float) -> int:
	return 1 if sp < 30.0 else (2 if sp < 40.0 else (3 if sp < 50.0 else 4))


func _pace_name(l: int) -> String:
	return ["", "Slow", "Steady", "Average", "Fast"][l]


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


func _melee_full(sq: Squad) -> Array:
	return [] if sq.vehicle() != null else sq.members.map(func(m): return GameData.MELEE[m.data.get("melee", "gun_butt")])


## A rough measure of harm per second at middle range in the open, against each kind of
## target (light / medium / heavy infantry, armour), then close combat. Only for comparing.
static func unit_power(weapons: Array, blades: Array) -> Array:
	var out := [0.0, 0.0, 0.0, 0.0, 0.0]
	for w in weapons:
		for i in TARGETS.size():
			out[i] += weapon_power(w, TARGETS[i][2])
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


# ---------------------------------------------------------------- drawn parts

## A bar: "status" (health, morale: red to green) or "attack" (bright now, dim full unit).
class CardBar:
	extends Control
	var kind := "status"
	var value := 0.0
	var full := 1.0
	var text := ""

	func set_values(v: float, f: float, t: String) -> void:
		if absf(v - value) > 0.001 or absf(f - full) > 0.001 or t != text:
			value = v
			full = f
			text = t
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.1, 0.09, 0.07))
		if kind == "attack":
			draw_rect(Rect2(r.position, Vector2(r.size.x * full, r.size.y)), Color(0.45, 0.37, 0.22, 0.55))
		var col := Color(0.85, 0.3, 0.2).lerp(Color(0.88, 0.75, 0.35), clampf(value * 2.0, 0.0, 1.0))
		if value > 0.5:
			col = col.lerp(Color(0.55, 0.85, 0.4), (value - 0.5) * 2.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x * value, r.size.y)), col)
		for k in range(1, 5):
			var x := r.size.x * k / 5.0
			draw_line(Vector2(x, 0), Vector2(x, r.size.y), Color(0, 0, 0, 0.45), 1.0)
		draw_rect(r, Color(0.62, 0.5, 0.28, 0.7), false, 1.0)
		if text != "":
			draw_string(get_theme_default_font(), Vector2(4, r.size.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 11, Color(0.05, 0.04, 0.03))


## The weapons' reach on one scale (to the longest range in the battle): a line per weapon,
## over short / medium / long bands.
class CardRange:
	extends Control
	var ranges: Array = []  # [range, name]
	var step := 8.0

	func _draw() -> void:
		var w := size.x - 26.0  # room for the number at the end of the longest line
		var font := get_theme_default_font()
		for band in [[0.0, 230.0, 0.16], [230.0, 480.0, 0.1], [480.0, MAX_RANGE, 0.05]]:
			draw_rect(Rect2(w * band[0] / MAX_RANGE, 0, w * (band[1] - band[0]) / MAX_RANGE, size.y), Color(0.9, 0.75, 0.4, band[2]))
		for k in range(0, int(MAX_RANGE) + 1, 100):
			var x := w * k / MAX_RANGE
			draw_line(Vector2(x, 0), Vector2(x, 3), Color(0.62, 0.5, 0.28, 0.9), 1.0)
		for i in ranges.size():
			var y := 7.0 + i * step
			var x: float = w * minf(float(ranges[i][0]) / MAX_RANGE, 1.0)
			draw_line(Vector2(0, y), Vector2(x, y), Color(0.88, 0.72, 0.4), 3.0)
			draw_circle(Vector2(x, y), 2.5, Color(1.0, 0.9, 0.6))
			draw_string(font, Vector2(x + 5.0, y + 4), "%d" % int(ranges[i][0]), HORIZONTAL_ALIGNMENT_LEFT, 26, 10, Color(0.86, 0.81, 0.7))


## Five pips for close combat strength.
class CardPips:
	extends Control
	var value := 0.0

	func _draw() -> void:
		var n := clampi(roundi(value * 5.0), 0, 5)
		for i in 5:
			var r := Rect2(i * 10.0, 2, 8, size.y - 4)
			draw_rect(r, Color(0.85, 0.7, 0.38) if i < n else Color(0.25, 0.21, 0.15))
			draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)


## Small drawn icons (on a 16 x 16 grid, scaled to the control).
class CardIcon:
	extends Control
	var kind := ""
	var level := 0
	const C := Color(0.85, 0.72, 0.45)
	const D := Color(0.08, 0.07, 0.05)

	func _star(r1: float, r2: float) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			pts.append(Vector2(8, 8.5) + Vector2.from_angle(-PI / 2 + i * PI / 5.0) * (r1 if i % 2 == 0 else r2))
		draw_colored_polygon(pts, C)

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
		draw_set_transform(o, 0.0, Vector2(s / 16.0, s / 16.0))
		match kind:
			"men":
				draw_circle(Vector2(8, 4.5), 3.0, C)
				draw_colored_polygon(PackedVector2Array([Vector2(2.5, 15), Vector2(3.5, 9), Vector2(8, 7.5), Vector2(12.5, 9), Vector2(13.5, 15)]), C)
			"armour":
				draw_colored_polygon(PackedVector2Array([Vector2(2, 2), Vector2(14, 2), Vector2(14, 8), Vector2(8, 15), Vector2(2, 8)]), C)
				if level >= 4:
					draw_rect(Rect2(4.5, 5, 7, 4), D)  # a hull plate
				else:
					for i in level:
						draw_line(Vector2(4.5, 5 + i * 3), Vector2(11.5, 5 + i * 3), D, 1.6)
			"speed":
				for i in maxi(level, 1):
					var x := 1.5 + i * 3.5
					draw_polyline(PackedVector2Array([Vector2(x, 3), Vector2(x + 4, 8), Vector2(x, 13)]), C, 2.0)
			"health":
				var red := Color(0.85, 0.3, 0.25)
				draw_circle(Vector2(5.2, 6), 3.4, red)
				draw_circle(Vector2(10.8, 6), 3.4, red)
				draw_colored_polygon(PackedVector2Array([Vector2(1.9, 7), Vector2(14.1, 7), Vector2(8, 14.5)]), red)
			"morale":
				draw_line(Vector2(3, 1), Vector2(3, 15), C, 1.5)
				draw_colored_polygon(PackedVector2Array([Vector2(3.5, 2), Vector2(14, 4), Vector2(9.5, 6), Vector2(14, 9), Vector2(3.5, 9)]), C)
			"gun":
				draw_rect(Rect2(1, 6, 13, 3), C)
				draw_rect(Rect2(3, 8, 3, 6), C)
				draw_rect(Rect2(9, 8.5, 2, 3), C)
			"range":
				draw_arc(Vector2(8, 8), 5.5, 0, TAU, 20, C, 1.5)
				draw_line(Vector2(8, 0.5), Vector2(8, 5), C, 1.5)
				draw_line(Vector2(8, 11), Vector2(8, 15.5), C, 1.5)
				draw_line(Vector2(0.5, 8), Vector2(5, 8), C, 1.5)
				draw_line(Vector2(11, 8), Vector2(15.5, 8), C, 1.5)
			"melee":
				draw_line(Vector2(2, 2), Vector2(13, 13), C, 2.0)
				draw_line(Vector2(14, 2), Vector2(3, 13), C, 2.0)
				draw_line(Vector2(9.5, 13.5), Vector2(13.5, 9.5), C, 2.0)
				draw_line(Vector2(6.5, 13.5), Vector2(2.5, 9.5), C, 2.0)
			"frag":
				draw_circle(Vector2(8, 9.5), 5.0, Color(0.55, 0.6, 0.4))
				draw_rect(Rect2(6.5, 2, 3, 3), C)
				draw_line(Vector2(9.5, 3), Vector2(13, 6), C, 1.2)
			"ap":
				draw_rect(Rect2(3, 5, 10, 9), Color(0.75, 0.45, 0.25))
				draw_rect(Rect2(6.5, 1.5, 3, 4), C)
				draw_line(Vector2(3, 9.5), Vector2(13, 9.5), D, 1.5)
			"smoke":
				for p in [Vector2(5, 10), Vector2(10, 9), Vector2(8, 5.5), Vector2(12.5, 12)]:
					draw_circle(p, 3.6, Color(0.75, 0.75, 0.72))
			"star":
				_star(7.0, 3.0)
			"leader":
				_star(6.5, 2.8)
			"charger":
				draw_colored_polygon(PackedVector2Array([Vector2(1, 6), Vector2(9, 6), Vector2(9, 2), Vector2(15, 8), Vector2(9, 14), Vector2(9, 10), Vector2(1, 10)]), C)
			"heavy":
				draw_rect(Rect2(2, 4, 12, 3), C)
				draw_line(Vector2(8, 7), Vector2(3, 15), C, 1.5)
				draw_line(Vector2(8, 7), Vector2(13, 15), C, 1.5)
				draw_line(Vector2(8, 7), Vector2(8, 15), C, 1.5)
			"loader":
				draw_rect(Rect2(2, 5, 12, 9), C)
				for i in 3:
					draw_line(Vector2(5 + i * 3, 6), Vector2(5 + i * 3, 13), D, 1.2)
			"bastion":
				draw_colored_polygon(PackedVector2Array([Vector2(1.5, 1.5), Vector2(14.5, 1.5), Vector2(14.5, 9), Vector2(8, 15.5), Vector2(1.5, 9)]), C)
				draw_colored_polygon(PackedVector2Array([Vector2(4.5, 4), Vector2(11.5, 4), Vector2(11.5, 8.5), Vector2(8, 12), Vector2(4.5, 8.5)]), D)
			"steadfast":
				draw_rect(Rect2(3, 2, 10, 12), C)
			"flame":
				draw_colored_polygon(PackedVector2Array([Vector2(8, 1), Vector2(13, 9), Vector2(11.5, 14), Vector2(4.5, 14), Vector2(3, 9), Vector2(6, 6)]), Color(0.95, 0.55, 0.2))
				draw_colored_polygon(PackedVector2Array([Vector2(8, 7), Vector2(10.5, 11), Vector2(9.5, 14), Vector2(6.5, 14), Vector2(5.5, 11)]), Color(1.0, 0.85, 0.4))
			"breach":
				for row in 3:
					for col in 2:
						if row == 1 and col == 1:
							continue  # the hole
						var x0 := 1.5 + col * 7.0 + (3.5 if row % 2 == 1 else 0.0)
						draw_rect(Rect2(x0, 2 + row * 4.5, 6, 3.5), C)
			"carrier":
				draw_rect(Rect2(1, 5, 14, 7), C)
				draw_rect(Rect2(1, 12, 14, 2.5), D)
				draw_rect(Rect2(10, 6.5, 3, 3), D)
			"launcher":
				for k in 3:
					draw_rect(Rect2(2 + k * 4.2, 5 + absf(k - 1) * 2.0, 3.2, 8), C)
					draw_circle(Vector2(3.6 + k * 4.2, 4 + absf(k - 1) * 2.0), 1.4, Color(0.55, 0.6, 0.4))
			"modes":
				draw_line(Vector2(2, 5), Vector2(12, 5), C, 1.6)
				draw_colored_polygon(PackedVector2Array([Vector2(11, 2), Vector2(15, 5), Vector2(11, 8)]), C)
				draw_line(Vector2(4, 11), Vector2(14, 11), C, 1.6)
				draw_colored_polygon(PackedVector2Array([Vector2(5, 8), Vector2(1, 11), Vector2(5, 14)]), C)
			"light", "medium", "heavy":
				var bulk: float = {"light": 0.0, "medium": 1.0, "heavy": 2.0}[kind]
				draw_circle(Vector2(8, 4), 2.6 + bulk * 0.3, C)
				draw_colored_polygon(PackedVector2Array([Vector2(4.5 - bulk, 15), Vector2(5 - bulk, 8), Vector2(8, 6.8), Vector2(11 + bulk, 8), Vector2(11.5 + bulk, 15)]), C)
				for i in int(bulk):
					draw_line(Vector2(5.5 - bulk, 9.5 + i * 2.5), Vector2(10.5 + bulk, 9.5 + i * 2.5), D, 1.2)
			"vehicle":
				draw_rect(Rect2(1, 6, 13, 8), C)
				draw_circle(Vector2(7, 8), 3.0, C.darkened(0.25))
				draw_line(Vector2(7, 8), Vector2(15.5, 4), C, 2.0)
				draw_line(Vector2(1, 14), Vector2(14, 14), D, 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
