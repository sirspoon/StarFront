class_name HUD
extends CanvasLayer
## Screen UI built in code: top bar, squad cards, battle log, help, menus.

const BONE := Color(0.9, 0.85, 0.72)
const BRASS := Color(0.62, 0.5, 0.28)

var main: Node
var root: Control
var top_label: Label
var squad_box: VBoxContainer
var rows := {}  # Squad -> {button, bar, label}
var log_label: RichTextLabel
var log_panel: PanelContainer
var help_panel: PanelContainer
var menu_panel: PanelContainer
var end_panel: PanelContainer
var end_label: Label
var messages: Array[String] = []
var last_status := {}
var refresh_timer := 0.0


func setup(m: Node) -> void:
	main = m
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_add_vignette()

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top_label = Label.new()
	top.add_child(top_label)

	var sp := PanelContainer.new()
	sp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	sp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sp.position += Vector2(10, -10)
	root.add_child(sp)
	squad_box = VBoxContainer.new()
	sp.add_child(squad_box)

	var lp := PanelContainer.new()
	lp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lp.position += Vector2(-10, -10)
	lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lp)
	log_panel = lp
	lp.visible = false
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.custom_minimum_size = Vector2(380, 0)
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lp.add_child(log_label)

	help_panel = PanelContainer.new()
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help_panel.position += Vector2(-10, 44)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_panel)
	var help := Label.new()
	help.text = "CONTROLS  (F1 hides)\n" \
			+ "Left click / drag: select squads\n" \
			+ "Right click ground: move   (Shift: run)\n" \
			+ "Right drag: line up along it, in cover\n" \
			+ "Ctrl + right click: face that way\n" \
			+ "Alt + click: pick out single soldiers\n" \
			+ "Right click enemy: focus fire on it\n" \
			+ "Right click your carrier: climb aboard   U: unload\n" \
			+ "Right click a wall (tank / lance team): shell it\n" \
			+ "H: halt   1-9: pick squad   Space: pause\n" \
			+ "WASD / arrows / middle-drag: scroll   Wheel: zoom\n\n" \
			+ "Hold the Ashen Chapel. Sandbags, barricades and\n" \
			+ "low walls stop most fire from their far side.\n" \
			+ "Men must stay in contact with their squad.\n" \
			+ "Fire pins men down and breaks their morale."
	help_panel.add_child(help)
	main.log_message("Battle plans ready.")


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.06, 0.05, 0.88)
	panel.border_color = BRASS
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color(0.16, 0.13, 0.1), "hover": Color(0.26, 0.2, 0.13),
				"pressed": Color(0.34, 0.26, 0.14), "focus": Color(0.16, 0.13, 0.1)}[state]
		b.border_color = BRASS.darkened(0.3)
		b.set_border_width_all(1)
		b.set_content_margin_all(6)
		t.set_stylebox(state, "Button", b)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", BONE)
	t.set_color("font_color", "Label", BONE)
	t.set_color("default_color", "RichTextLabel", BONE)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.04, 0.03)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.7, 0.58, 0.3)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	return t


func _add_vignette() -> void:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.55))
	g.add_point(0.55, Color(0, 0, 0, 0))
	gt.gradient = g
	var v := TextureRect.new()
	v.texture = gt
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)


func build_squad_cards() -> void:
	for sq in main.squads:
		if sq.team != main.player_team:
			continue
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = sq.name
		b.custom_minimum_size = Vector2(200, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): main.select_squad(sq, Input.is_key_pressed(KEY_SHIFT)))
		row.add_child(b)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(80, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.01
		bar.tooltip_text = "Morale"
		row.add_child(bar)
		var l := Label.new()
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		squad_box.add_child(row)
		rows[sq] = {"button": b, "bar": bar, "label": l}


func _process(dt: float) -> void:
	refresh_timer -= dt
	if refresh_timer > 0.0:
		return
	refresh_timer = 0.2
	_refresh()


func _refresh() -> void:
	var f0: Dictionary = GameData.FACTIONS[main.factions[0]]
	var f1: Dictionary = GameData.FACTIONS[main.factions[1]]
	var t := int(main.time)
	var total := int(main.battle_length)
	var chapel := "unclaimed"
	if main.objective_owner >= 0:
		chapel = "%s  (%d / %d s to win)" % [GameData.FACTIONS[main.factions[main.objective_owner]].short,
				int(main.hold_streak), int(main.HOLD_TO_WIN)]
	top_label.text = "STARFRONT v%s      %s  vs  %s      Time %d:%02d / %d:%02d      Chapel: %s%s" % [
			GameData.VERSION, f0.name, f1.name, t / 60, t % 60, total / 60, total % 60, chapel,
			"      [ PAUSED ]" if main.paused else ""]
	for sq in main.squads:
		var st: String = sq.status()
		if last_status.get(sq, "") != st:
			if main.started and st in ["Pinned", "Routing", "Lost"] and sq.vehicle() == null:
				var mine: bool = sq.team == main.player_team
				var col := "#e8c070" if mine else "#9fd0ff"
				# only report enemy squads the player can actually see
				if mine or st == "Lost" or sq.alive().any(func(s): return s.visible):
					var verb: String = {"Pinned": "is pinned down!", "Routing": "is breaking and running!",
							"Lost": "has been wiped out."}[st]
					main.log_message("[color=%s]%s %s[/color]" % [col, sq.name, verb])
			last_status[sq] = st
		if rows.has(sq):
			var r: Dictionary = rows[sq]
			r.bar.value = sq.avg_morale()
			var v = sq.vehicle()
			if v != null:
				r.label.text = "Hull %d/%d  %s" % [maxi(v.hp, 0), v.max_hp, st]
				if v.passengers.size() > 0:
					r.label.text += "  +%d" % v.passengers.size()
				r.bar.tooltip_text = "Hull"
			else:
				r.label.text = "%d/%d  %s" % [sq.present().size(), sq.start_size, st]
			r.button.modulate = Color(0.6, 1.0, 0.6) if sq.selected else Color.WHITE


func add_message(text: String) -> void:
	messages.append(text)
	while messages.size() > 7:
		messages.pop_front()
	if log_label:
		log_panel.visible = true
		log_label.text = "\n".join(messages)


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func _centre_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	return p


func show_menu() -> void:
	menu_panel = _centre_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	menu_panel.add_child(v)
	var title := Label.new()
	title.text = "STARFRONT"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Battle for the Ashen Chapel   ·   prototype v%s" % GameData.VERSION
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var intro := Label.new()
	intro.text = "The hive-city of Vell is ash and rubble. At its heart stands a ruined chapel\n" \
			+ "that both sides have sworn to take. Choose who you command."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(intro)
	for key in ["legion", "sworn"]:
		var f: Dictionary = GameData.FACTIONS[key]
		var b := Button.new()
		b.text = "Command %s\n%s" % [f.name, f.blurb]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(620, 72)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			menu_panel.queue_free()
			main.start_battle(key))
		v.add_child(b)


func show_end(text: String) -> void:
	end_panel = _centre_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	end_panel.add_child(v)
	end_label = Label.new()
	end_label.text = text
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.add_theme_font_size_override("font_size", 22)
	v.add_child(end_label)
	var b := Button.new()
	b.text = "Fight again"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): main.get_tree().reload_current_scene())
	v.add_child(b)
