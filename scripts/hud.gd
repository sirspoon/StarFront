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
var top_panel: PanelContainer
var squad_panel: PanelContainer
var help_label: Label
var obj_name := "the Ashen Chapel"
var obj_word := "chapel"
var unit_card: UnitCard
var squads_on := true
var touch_bar: HBoxContainer
var touch_buttons := {}
var loading_label: Label
var backdrop: ColorRect      # hides the battlefield until it is fully drawn
var load_bar: ProgressBar
var load_text: Label
var pending_faction := ""    # a side picked before loading finished


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
	top_panel = top
	top_label = Label.new()
	top.add_child(top_label)

	var sp := PanelContainer.new()
	sp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	sp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sp.position += Vector2(10, -(76 if main.touch_mode else 56))  # clear of the command bar
	root.add_child(sp)
	squad_panel = sp
	squad_box = VBoxContainer.new()
	sp.add_child(squad_box)
	if main.touch_mode:
		squad_box.add_theme_constant_override("separation", 1)
	# shown instead of the list while one of the player's squads is selected
	unit_card = UnitCard.new(main.touch_mode)
	unit_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	unit_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	unit_card.position += Vector2(10, -(76 if main.touch_mode else 56))
	unit_card.visible = false
	root.add_child(unit_card)

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
	help_label = help
	help.text = "CONTROLS  (F1 hides)\n" \
			+ "Left click / drag a box: select squads (Shift adds)\n" \
			+ "Right click: move there   (Shift: add a waypoint)\n" \
			+ "Right drag: line up along it, in cover\n" \
			+ "   pause at the end, keep dragging: set facing\n" \
			+ "Right drag from your selected squad, or from the\n" \
			+ "   last waypoint: face that way\n" \
			+ "Right click an enemy: focus fire   your carrier: board\n" \
			+ "Right click a wall (tank / lance team): shell it\n" \
			+ "R assault   G get down   H halt   U unload\n" \
			+ "V gun setting: beam / pulse, AP / HE, carrier HE / smoke\n" \
			+ "C cover view: green low cover, blue windows,\n" \
			+ "   white standing walls, yellow rubble, red wire\n" \
			+ "T then click: grenades. At armour: tank-breakers,\n" \
			+ "   at infantry: frags, at open ground: smoke screen.\n" \
			+ "   Carriers fire a salvo of their loaded round there\n" \
			+ "1-9: select squads\n" \
			+ "Space: pause (orders still work)\n" \
			+ "WASD / arrows / screen edge / middle-drag: scroll\n" \
			+ "Wheel: zoom\n\n" \
			+ "Hold the Ashen Chapel. Sandbags, barricades and\n" \
			+ "low walls stop most fire from their far side.\n" \
			+ "Men must stay in contact with their squad.\n" \
			+ "Raiders and Oathblades charge enemies who come\n" \
			+ "   close (not while Down). Up close, blades win,\n" \
			+ "   and anyone pinned or lying Down is easy meat.\n" \
			+ "Heavy Gun Teams set up when stopped by cover or a\n" \
			+ "   window, or when Down: then they're far more accurate.\n" \
			+ "Bushes hide men who keep still; hedges block sight;\n" \
			+ "   barbed wire is very slow to cross. Vehicles flatten them."
	help_panel.add_child(help)
	if main.touch_mode:
		help.text = "TOUCH CONTROLS  (? hides)\n" \
				+ "Tap a soldier or vehicle: select it\n" \
				+ "Double-tap ground: move there\n" \
				+ "Hold, then drag: move there, spread along the drag\n" \
				+ "   (pause at the end, then keep dragging to set facing)\n" \
				+ "Hold on your selected squad, then drag: face that way\n" \
				+ "   (or the way they'll face at the end of their route;\n" \
				+ "   hold-drag the last waypoint to set it too)\n" \
				+ "Hold and let go: add a waypoint (again for more;\n" \
				+ "   finish with a double-tap or hold-drag)\n" \
				+ "Drag: scroll   Pinch: zoom   Tap empty ground: deselect\n" \
				+ "First order after selecting replaces old orders\n" \
				+ "Tap an enemy: focus fire   Double-tap your carrier: board\n" \
				+ "Double-tap a wall (tank / lance team): shell it\n" \
				+ "Face, then tap: look that way   Pause: orders still work\n" \
				+ "Grenade, then tap: tank-breakers at armour, frags at\n" \
				+ "   infantry, smoke screen on open ground\n\n" \
				+ "Hold the Ashen Chapel. Sandbags, barricades and\n" \
				+ "low walls stop most fire from their far side.\n" \
				+ "Men must stay in contact with their squad."
	help_panel.visible = false  # the "?" button (or F1) shows it
	_build_touch_bar()
	loading_label = Label.new()
	loading_label.visible = false  # replaced by the loading bar in the menu
	loading_label.text = "Preparing the battlefield..."
	loading_label.add_theme_font_size_override("font_size", 18)
	loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	loading_label.position.y += 48
	loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(loading_label)
	main.log_message("Battle plans ready.")


## The button bar: toggles for Run, Down, Face, Grenade and Cover,
## and one-tap orders.
func _build_touch_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y -= 6
	root.add_child(panel)
	touch_bar = HBoxContainer.new()
	touch_bar.add_theme_constant_override("separation", 6)
	panel.add_child(touch_bar)
	# orders for what's selected (only those that apply are shown), then a gap, then the
	# buttons that are always there
	for spec in [["Pace", false], ["Gun", false], ["Target", true], ["Grenade", true], ["Unload", false], ["Face", true], ["Halt", false],
			["|", false], ["Support", true], ["Cover", true], ["Squads", true], ["Pause", true], ["Menu", false]]:
		if spec[0] == "|":
			var gap := VSeparator.new()
			gap.custom_minimum_size = Vector2(10, 0)
			touch_bar.add_child(gap)
			bar_gap = gap
			continue
		var b := Button.new()
		b.text = ""
		b.toggle_mode = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(56, 44) if main.touch_mode else Vector2(44, 38)
		var ic := BarIcon.new()
		ic.kind = spec[0]
		ic.key = "" if main.touch_mode else HINTS.get(spec[0], "")
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		bar_icons[spec[0]] = ic
		b.add_theme_font_size_override("font_size", 16 if main.touch_mode else 13)
		b.tooltip_text = TIPS.get(spec[0], "") + ("" if main.touch_mode or not HINTS.has(spec[0]) else "  [%s]" % HINTS[spec[0]])
		touch_bar.add_child(b)
		touch_buttons[spec[0]] = b
		var key: String = spec[0]
		if spec[1]:
			b.toggled.connect(func(on): main.touch_button(key, on))
		else:
			b.pressed.connect(func(): main.touch_button(key, true))
	touch_buttons["Squads"].set_pressed_no_signal(true)
	bar_panel = panel
	_context_buttons()


var bar_panel: PanelContainer
var bar_icons := {}
var last_sel_sig := ""
var bar_gap: Control
const HINTS := {"Pace": "R/G", "Target": "F", "Support": "Q", "Halt": "H", "Unload": "U", "Gun": "V", "Grenade": "T", "Cover": "C", "Pause": "Space", "Menu": "Esc"}
const TIPS := {"Pace": "Pace (tap to change): crouched and walking; running (faster, charge into close combat, but fire less and easier to hit); or lying down (much harder to hit, crawl when moving)",
		"Gun": "Switch the gun setting: a tank's main gun (beam / pulse, AP / HE), or the round a carrier's launchers fire (HE / smoke)",
		"Grenade": "Then tap a spot: infantry throw frags at men, tank-breakers at armour, smoke on open ground; carriers fire a salvo of the loaded round",
		"Target": "Then tap a spot: the mortars shell it (no sight needed). Halt or a move order ends the mission",
		"Unload": "Passengers get out", "Face": "Then drag: which way the squad faces", "Halt": "Stop and forget orders",
		"Support": "Call in support from above: press, then draw a line on the map. Hits everyone on the line",
		"Cover": "Show where the cover is", "Squads": "Show the squad list", "Pause": "Pause (orders still work)", "Menu": "Restart, options, controls"}


## A button's words: what it's set to now where it's a choice ("Pace: Run"), plus the key on a PC.
func _button_text(key: String, on: bool, extra := "") -> String:
	var t: String = key
	match key:
		"Assault":
			t = "Pace: Run" if on else "Pace: Walk"
		"Down":
			t = "Stance: Down" if on else "Stance: Up"
		"Gun":
			t = "Gun: " + extra if extra != "" else "Gun"
	if not main.touch_mode and HINTS.has(key):
		t += " (%s)" % HINTS[key]
	return t


## Show only the orders that apply to the selected squads (any of them), with words that
## say what they're set to. Modes left on for something no longer selected are switched off.
func _context_buttons() -> void:
	if touch_buttons.is_empty():
		return
	var inf := false
	var mortars := false
	var any := false
	var grenades := false
	var unload := false
	var mode := ""
	for sq in main.squads:
		if sq.team != main.player_team or not sq.selected:
			continue
		var v = sq.vehicle()
		if v != null:
			if not v.is_alive():
				continue
			any = true
			if v.gun_mode() != "" and mode == "":
				mode = v.gun_mode()
			if v.launcher and (int(v.launch_ammo.he) > 0 or int(v.launch_ammo.smoke) > 0):
				grenades = true
			if v.passengers.size() > 0:
				unload = true
		elif not sq.alive().is_empty() or sq.carrier() != null:
			any = true
			inf = true
			if sq.carrier() != null:
				unload = true
			for k in ["he", "ap", "smoke"]:
				if sq.grenade_count(k) > 0:
					grenades = true
			if sq.has_mortars():
				mortars = true
				if mode == "":
					mode = "HE" if sq.mortar_kind == "he" else "Smoke"
	var sel_sig := ""
	for sq in main.squads:
		if sq.selected:
			sel_sig += str(sq.get_instance_id()) + ","
	if sel_sig != last_sel_sig:
		last_sel_sig = sel_sig
		main.sync_pace_to_selection()
	var show := {"Pace": inf, "Gun": mode != "", "Target": mortars, "Grenade": grenades, "Unload": unload,
			"Face": any, "Halt": any}
	var changed := false
	for k in show:
		var b: Button = touch_buttons[k]
		if b.visible != show[k]:
			b.visible = show[k]
			changed = true
			if not show[k] and b.toggle_mode and b.button_pressed and k in ["Grenade", "Face", "Target"]:
				b.button_pressed = false  # (switches the mode off too)
		bar_icons[k].set_variant(mode if k == "Gun" else (main.pace_state() if k == "Pace" else ("on" if b.button_pressed else "")))
	bar_icons["Pause"].set_variant("paused" if main.paused else "")
	if main.support != null:
		var st = main.support
		var pt: int = main.player_team
		var si: BarIcon = bar_icons["Support"]
		si.set_variant(st.kind[pt])
		si.badge = str(st.left[pt])
		si.progress = 1.0 - st.wait[pt] / float(st.info(pt).cooldown) if st.left[pt] > 0 else 0.0
		si.queue_redraw()
		var sb: Button = touch_buttons["Support"]
		sb.disabled = not st.ready_for(pt) and not sb.button_pressed
		sb.tooltip_text = "%s: %d left%s. Press, then draw a line on the map; it hits everyone on the line  [Q]" % [st.info(pt).name, st.left[pt],
				("" if st.ready_for(pt) else (", ready in %d s" % ceili(st.wait[pt]) if st.left[pt] > 0 else ""))]
	bar_gap.visible = any
	if changed:
		bar_panel.reset_size()
	var ms := bar_panel.get_combined_minimum_size()
	bar_panel.size = ms
	bar_panel.position = Vector2((root.size.x - ms.x) * 0.5, root.size.y - ms.y - 6.0)


## Keeps the toggle buttons in step when the game changes a mode itself.
func sync_touch(key: String, on: bool) -> void:
	if touch_buttons.has(key):
		touch_buttons[key].set_pressed_no_signal(on)


func _gun_buttons() -> void:
	_context_buttons()


## Keep the card's bottom edge just above the command bar as its contents change.
func place_card() -> void:
	var ms := unit_card.get_combined_minimum_size()
	unit_card.size = ms
	unit_card.position = Vector2(10, root.size.y - ms.y - (76 if main.touch_mode else 56))


## The battle's objective (the chapel, or the Prime Factorium on the Foundry District map).
func set_objective(name: String, word: String) -> void:
	obj_name = name
	obj_word = word
	if help_label != null:
		help_label.text = help_label.text.replace("the Ashen Chapel", name).replace("the Prime Factorium", name)


## The deployment banner: what to do, and the Begin battle button.
var deploy_panel: PanelContainer = null


func show_deploy(on: bool) -> void:
	if deploy_panel != null and is_instance_valid(deploy_panel):
		deploy_panel.queue_free()
		deploy_panel = null
	if not on:
		return
	deploy_panel = PanelContainer.new()
	deploy_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	deploy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	deploy_panel.position.y += 48
	root.add_child(deploy_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	deploy_panel.add_child(h)
	var l := Label.new()
	l.text = "DEPLOYMENT  ·  Move your squads within the shaded ground" if not main.touch_mode else "DEPLOYMENT  ·  place your squads"
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := Button.new()
	b.text = "Begin battle"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 44 if main.touch_mode else 32)
	b.pressed.connect(main.begin_battle)
	h.add_child(b)


func set_squads_visible(on: bool) -> void:
	squads_on = on
	squad_panel.visible = on and not unit_card.visible


## True if a screen position is over a panel or button, so a touch there
## isn't also taken as an order on the battlefield.
func is_over_ui(pos: Vector2) -> bool:
	for c in [top_panel, deploy_panel, squad_panel, unit_card, unit_card.popup if unit_card != null else null, help_panel, touch_bar.get_parent() if touch_bar else null,
			menu_panel, end_panel]:
		if c != null and is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


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
		b.custom_minimum_size = Vector2(150 if main.touch_mode else 200, 26 if main.touch_mode else 0)
		if main.touch_mode:
			b.add_theme_font_size_override("font_size", 13)
			b.add_theme_constant_override("outline_size", 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): main.focus_squad(sq, Input.is_key_pressed(KEY_SHIFT)))
		row.add_child(b)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(50 if main.touch_mode else 80, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.01
		bar.tooltip_text = "Morale"
		row.add_child(bar)
		var l := Label.new()
		l.custom_minimum_size = Vector2(110 if main.touch_mode else 130, 0)
		if main.touch_mode:
			l.add_theme_font_size_override("font_size", 13)
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
	if main.map != null and obj_word != main.map.objective_word():
		set_objective(main.map.objective_name(), main.map.objective_word())
	_update_loading()
	if loading_label.visible and (main.map_view.ready_drawn or not main.map_view.enabled):
		loading_label.visible = false
	var f0: Dictionary = GameData.FACTIONS[main.factions[0]]
	var f1: Dictionary = GameData.FACTIONS[main.factions[1]]
	var t := int(main.time)
	var total := int(main.battle_length)
	var clock := "%d:%02d" % [t / 60, t % 60] + (" / %d:%02d" % [total / 60, total % 60] if total > 0 else "")
	var chapel := "unclaimed"  # (the objective: the chapel or the factorium)
	if main.objective_owner >= 0:
		chapel = "%s  (%d / %d s to win)" % [GameData.FACTIONS[main.factions[main.objective_owner]].short,
				int(main.hold_streak), int(main.HOLD_TO_WIN)]
	top_label.text = "STARFRONT v%s      %s  vs  %s      Time %s      %s: %s%s" % [
			GameData.VERSION, f0.name, f1.name, clock, obj_word.capitalize(), chapel,
			"      [ DEPLOYMENT ]" if main.deploying else ("      [ PAUSED ]" if main.paused else "")]
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
					if mine and sq.faction == "legion" and st != "Lost":
						main.sfx.voice("legion_pinned" if st == "Pinned" else "legion_rout")  # the men cry out
			last_status[sq] = st
		if rows.has(sq):
			var r: Dictionary = rows[sq]
			r.bar.value = sq.avg_morale()
			var v = sq.vehicle()
			if v != null:
				var hp := 0
				var mx := 0
				for o in sq.vehicles():
					hp += maxi(o.hp, 0)
					mx += o.max_hp
				r.label.text = "Hull %d/%d  %s" % [hp, mx, st]
				if v.gun_mode() != "":
					r.label.text += "  " + v.gun_mode()
				if v.passengers.size() > 0:
					r.label.text += "  +%d" % v.passengers.size()
				r.bar.tooltip_text = "Hull"
			else:
				r.label.text = "%d/%d  %s" % [sq.present().size(), sq.start_size, st]
				var gr := ""
				for k in [["he", "F"], ["ap", "T"], ["smoke", "S"]]:  # grenades left: frag, tank-breaker, smoke
					var n: int = sq.grenade_count(k[0])
					if n > 0:
						gr += " %s%d" % [k[1], n]
				if gr != "":
					r.label.text += "  " + gr
			r.button.modulate = Color(0.6, 1.0, 0.6) if sq.selected else Color.WHITE
	_gun_buttons()
	# the unit card replaces the list while a squad of ours is selected
	var sel: Array = main.squads.filter(func(q): return q.team == main.player_team and q.selected and q.alive().size() > 0)
	if sel.is_empty() or not main.started or main.over:
		unit_card.visible = false
		squad_panel.visible = squads_on
	else:
		unit_card.show_squad(sel[0], sel.size() - 1)
		unit_card.visible = true
		place_card()
		squad_panel.visible = false


func add_message(text: String) -> void:
	messages.append(text)
	while messages.size() > 7:
		messages.pop_front()
	if log_label:
		log_panel.visible = true
		log_label.text = "\n".join(messages)


var battle_menu: PanelContainer = null
var options_panel: PanelContainer = null
var paused_before := false


## A full-screen dimmed backdrop under a menu panel (freed along with it).
func _dim_under(panel: Control) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.02, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	root.move_child(dim, panel.get_index())
	panel.tree_exiting.connect(dim.queue_free)


func _menu_button(v: Container, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 48 if main.touch_mode else 34)
	b.add_theme_font_size_override("font_size", 18 if main.touch_mode else 15)
	b.pressed.connect(action)
	v.add_child(b)
	return b


## The in-battle menu (Menu button or Esc): the battle pauses while it's open.
func toggle_battle_menu() -> void:
	if battle_menu != null and is_instance_valid(battle_menu):
		battle_menu.queue_free()
		battle_menu = null
		main.paused = paused_before
		sync_touch("Pause", main.paused)
		return
	paused_before = main.paused
	main.paused = true
	sync_touch("Pause", true)
	battle_menu = _centre_panel()
	_dim_under(battle_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	battle_menu.add_child(v)
	var t := Label.new()
	t.text = "BATTLE PAUSED"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	_menu_button(v, "Resume", toggle_battle_menu)
	_menu_button(v, "Restart this battle", func(): main.restart(true))
	_menu_button(v, "New battle", func(): main.restart(false))
	_menu_button(v, "Options", show_options)
	_menu_button(v, "Controls (F1)", func():
		toggle_battle_menu()
		toggle_help())


## Graphics and sound options, kept on the device. Applying them prepares the battlefield
## again, so it restarts the battle (or the title screen).
func show_options() -> void:
	if options_panel != null and is_instance_valid(options_panel):
		return
	options_panel = _centre_panel()
	_dim_under(options_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	options_panel.add_child(v)
	var t := Label.new()
	t.text = "OPTIONS"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	var detail := OptionButton.new()
	for d in [["Map detail: high (sharpest, slowest to prepare)", 2.0], ["Map detail: medium", 1.5], ["Map detail: low (quickest)", 1.0]]:
		detail.add_item(d[0])
		detail.set_item_metadata(detail.item_count - 1, d[1])
	var cur := Settings.detail()
	detail.select(0 if cur >= 2.0 else (1 if cur >= 1.5 else 2))
	detail.focus_mode = Control.FOCUS_NONE
	detail.custom_minimum_size = Vector2(420, 44 if main.touch_mode else 30)
	v.add_child(detail)
	var mtype := OptionButton.new()
	for d in [["Battlefield: Old Town (homes, shops, parks)", "town"], ["Battlefield: Foundry District (warehouses, works, machinery)", "foundry"],
			["Battlefield: either, at random", "random"]]:
		mtype.add_item(d[0])
		mtype.set_item_metadata(mtype.item_count - 1, d[1])
	var curm := str(Settings.saved("map_type", "town"))
	mtype.select(0 if curm == "town" else (1 if curm == "foundry" else 2))
	mtype.focus_mode = Control.FOCUS_NONE
	mtype.custom_minimum_size = Vector2(420, 44 if main.touch_mode else 30)
	v.add_child(mtype)
	var lightfx := OptionButton.new()
	for d in [["Lighting effects: normal", 1.0], ["Lighting effects: strong", 1.6], ["Lighting effects: very strong (bright flashes, deep shadows)", 2.4]]:
		lightfx.add_item(d[0])
		lightfx.set_item_metadata(lightfx.item_count - 1, d[1])
	var curl := Settings.light_boost()
	lightfx.select(0 if curl < 1.3 else (1 if curl < 2.0 else 2))
	lightfx.focus_mode = Control.FOCUS_NONE
	lightfx.custom_minimum_size = Vector2(420, 44 if main.touch_mode else 30)
	v.add_child(lightfx)
	var checks := {}
	for o in [["trenches", "Trench lines dug across the battlefield", false],
			["shadows", "Wall shadows from fires and explosions", not Settings.is_phone()],
			["normals", "Raised, lit surfaces (normal maps)", true],
			["lights", "Combat lights and moonlight", true],
			["sound", "Sound", true]]:
		var c := CheckButton.new()
		c.text = o[1]
		c.button_pressed = Settings.on(o[0], o[2])
		c.focus_mode = Control.FOCUS_NONE
		c.custom_minimum_size = Vector2(420, 44 if main.touch_mode else 28)
		v.add_child(c)
		checks[o[0]] = c
	var prev: String = main.previous_stage
	if prev != "" and prev != "ran fine" and not prev.begins_with("menu up"):
		var last := Label.new()  # where the last game got to, if it didn't finish: to track down crashes
		last.text = "Last game stopped: " + prev
		last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		last.custom_minimum_size = Vector2(420, 0)
		last.add_theme_font_size_override("font_size", 11)
		last.add_theme_color_override("font_color", Color(0.6, 0.57, 0.5))
		v.add_child(last)
	var note := Label.new()
	note.text = "Applying prepares the battlefield again" + (" and restarts this battle." if main.started else ".")
	note.add_theme_font_size_override("font_size", 12)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_menu_button(row, "Apply", func():
		Settings.save_option("detail", detail.get_item_metadata(detail.selected))
		Settings.save_option("map_type", mtype.get_item_metadata(mtype.selected))
		Settings.save_option("light_boost", lightfx.get_item_metadata(lightfx.selected))
		for k in checks:
			Settings.save_option(k, checks[k].button_pressed)
		if main.started:
			main.restart(true)
		else:
			main.get_tree().reload_current_scene())
	_menu_button(row, "Cancel", func():
		options_panel.queue_free()
		options_panel = null)


var cover_key: Label = null


## The key to the Cover view's colours, under the top bar while it's on.
func show_cover_key(on: bool) -> void:
	if cover_key == null:
		cover_key = Label.new()
		cover_key.text = "COVER:  green low cover (fire over it)   blue windows   white standing walls   " \
				+ "yellow rubble/craters   brown trenches   olive bushes/hedges   red wire   (no colour: open, or the wall has collapsed)"
		cover_key.add_theme_font_size_override("font_size", 12)
		cover_key.add_theme_color_override("font_color", Color(0.9, 0.88, 0.75))
		cover_key.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		cover_key.add_theme_constant_override("outline_size", 4)
		cover_key.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		cover_key.position = Vector2(10, 40)
		cover_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(cover_key)
	cover_key.visible = on


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
	if main.map != null:
		set_objective(main.map.objective_name(), main.map.objective_word())
	backdrop = ColorRect.new()
	backdrop.color = Color(0.06, 0.055, 0.05)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)
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
	var sub_row := HBoxContainer.new()
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(sub_row)
	var sub := Label.new()
	sub.text = "Battle for %s   ·   " % obj_name
	sub_row.add_child(sub)
	var ver := LinkButton.new()  # the version: click it for what's new
	ver.text = "prototype v%s  (what's new)" % GameData.VERSION
	ver.focus_mode = Control.FOCUS_NONE
	ver.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	ver.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.5))
	ver.pressed.connect(_show_whats_new)
	sub_row.add_child(ver)
	var intro := Label.new()
	intro.text = ("The hive-city of Vell is ash and rubble. At its heart stands a ruined chapel\n" \
			+ "that both sides have sworn to take. Choose who you command.") if obj_word == "chapel" else \
			("The foundries of Vell lie cold and broken. At their heart stands the Prime Factorium,\n" \
			+ "whose engines both sides have sworn to seize. Choose who you command.")
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(intro)
	var prev: String = main.previous_stage
	if Settings._q().contains("debug") and prev != "":
		# ?debug in the address: where the last visit got to (to track down crashes)
		var last := Label.new()
		last.text = "Last visit: %s" % prev
		last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		last.custom_minimum_size = Vector2(620, 0)
		last.add_theme_font_size_override("font_size", 11)
		last.add_theme_color_override("font_color", Color(0.6, 0.57, 0.5))
		last.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(last)
	_tick_breadcrumbs()
	if "--shot-whatsnew" in OS.get_cmdline_user_args() or "--shot-menu" in OS.get_cmdline_user_args() \
			or "--shot-options" in OS.get_cmdline_user_args():
		_shot_whats_new.call_deferred()
	if "--shot-army" in OS.get_cmdline_user_args():
		show_army.call_deferred("sworn" if "--side=sworn" in OS.get_cmdline_user_args() else "legion")
	var info := Label.new()
	info.text = "Graphics: " + Settings.summary()
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.6, 0.57, 0.5))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	load_text = Label.new()
	load_text.text = "Preparing the battlefield..."
	load_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(load_text)
	load_bar = ProgressBar.new()
	load_bar.custom_minimum_size = Vector2(620, 14)
	load_bar.show_percentage = false
	load_bar.max_value = 1.0
	v.add_child(load_bar)
	for key in ["legion", "sworn"]:
		var f: Dictionary = GameData.FACTIONS[key]
		var b := Button.new()
		b.text = "Command %s\n%s" % [f.name, f.blurb]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(620, 72)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): show_army(key))
		v.add_child(b)
	var ob := Button.new()
	ob.text = "Options"
	ob.focus_mode = Control.FOCUS_NONE
	ob.pressed.connect(show_options)
	v.add_child(ob)


## Test aid: a screenshot of the title screen with "What's new" open.
func _shot_whats_new() -> void:
	if "--shot-whatsnew" in OS.get_cmdline_user_args():
		_show_whats_new()
	if "--shot-options" in OS.get_cmdline_user_args():
		show_options()
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			get_viewport().get_texture().get_image().save_png(a.trim_prefix("--shot="))
	get_tree().quit()


func _show_whats_new() -> void:
	var d := AcceptDialog.new()
	d.title = "What's new"
	d.dialog_text = WhatsNew.TEXT
	d.ok_button_text = "Close"
	root.add_child(d)
	d.popup_centered()
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)


func _map_ready() -> bool:
	return main.map_view.ready_drawn or not main.map_view.enabled


## Picking the force: each unit costs points; spend up to the budget. Starts from the force
## picked last time (or the standard one). The computer picks its own.
var army_panel: PanelContainer = null
var army: Array = []


func show_army(key: String) -> void:
	menu_panel.visible = false
	var saved = Settings.saved("army_" + key, [])
	army = saved.duplicate() if saved is Array and not saved.is_empty() else GameData.default_army(key)
	army_panel = _centre_panel()
	# the preview of the last unit tapped: across the top on a PC, beside the list on a phone
	# (whose screen is wide and short)
	var outer: BoxContainer = HBoxContainer.new() if main.touch_mode else VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	army_panel.add_child(outer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	preview_box = VBoxContainer.new() if main.touch_mode else HBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 8)
	if main.touch_mode:
		outer.add_child(v)
		outer.add_child(preview_box)
	else:
		outer.add_child(v)
	var title := Label.new()
	title.text = "MUSTER: %s" % GameData.FACTIONS[key].name.to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var pts := Label.new()
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pts)
	if not main.touch_mode:
		preview_box.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(preview_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560 if main.touch_mode else 660, 330 if main.touch_mode else 300)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var rows := []
	var start := Button.new()
	var refresh := func():
		var cost := GameData.army_cost(key, army)
		pts.text = "Points: %d / %d      Units: %d / %d" % [cost, GameData.BUDGET, army.size(), GameData.MAX_UNITS]
		pts.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if cost > GameData.BUDGET else Color(0.85, 0.82, 0.7))
		for r in rows:
			var n := army.filter(func(x): return x == r.u.id).size()
			r.count.text = str(n)
			r.minus.disabled = n == 0
			r.plus.disabled = n >= int(r.u.max) or cost + int(r.u.cost) > GameData.BUDGET or army.size() >= GameData.MAX_UNITS
		start.disabled = army.is_empty() or cost > GameData.BUDGET
	var bh := 40.0 if main.touch_mode else 28.0
	army_boxes.clear()
	for u in GameData.units(key):
		# each unit in a box: tap anywhere on it (but the - and + buttons) to see it in the preview
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _unit_box_style(false))
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		list.add_child(box)
		var uu: Dictionary = u
		army_boxes[u.id] = box
		box.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
				show_unit_preview(key, uu))
		box.mouse_entered.connect(func(): if box.get_meta("chosen", false) == false: box.add_theme_stylebox_override("panel", _unit_box_style(false, true)))
		box.mouse_exited.connect(func(): if box.get_meta("chosen", false) == false: box.add_theme_stylebox_override("panel", _unit_box_style(false)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)
		var nm := Label.new()
		nm.text = "%s   (%d pts, up to %d)" % [u.name, u.cost, u.max]
		nm.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7))
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(nm)
		var ab := Label.new()
		ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ab.text = u.about
		ab.add_theme_font_size_override("font_size", 11)
		ab.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(ab)
		var minus := Button.new()
		minus.text = " - "
		minus.custom_minimum_size = Vector2(bh, bh)
		minus.focus_mode = Control.FOCUS_NONE
		row.add_child(minus)
		var count := Label.new()
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		count.custom_minimum_size = Vector2(24, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(count)
		var plus := Button.new()
		plus.text = " + "
		plus.custom_minimum_size = Vector2(bh, bh)
		plus.focus_mode = Control.FOCUS_NONE
		row.add_child(plus)
		var id: String = u.id
		minus.pressed.connect(func():
			army.erase(id)
			refresh.call())
		plus.pressed.connect(func():
			army.append(id)
			refresh.call())
		rows.append({"u": u, "count": count, "minus": minus, "plus": plus})
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bar)
	for spec in [["Standard force", func():
				army = GameData.default_army(key)
				refresh.call()],
			["Random", func():
				army = GameData.random_army(key, randi())
				refresh.call()],
			["Clear", func():
				army = []
				refresh.call()],
			["Back", func():
				army_panel.queue_free()
				army_panel = null
				menu_panel.visible = true]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, bh)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	start.text = "To battle"
	start.focus_mode = Control.FOCUS_NONE
	start.custom_minimum_size = Vector2(0, bh + 6)
	start.pressed.connect(func():
		Settings.save_option("army_" + key, army.duplicate())
		army_panel.queue_free()
		army_panel = null
		menu_panel.visible = true
		_choose(key))
	v.add_child(start)
	refresh.call()
	var first := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-unit="):  # test aid: preview this unit for the shot
			first = int(a.get_slice("=", 1))
	show_unit_preview(key, GameData.units(key)[first])
	if "--shot-army" in OS.get_cmdline_user_args():
		_shot_whats_new.call_deferred()


## The Muster screen's preview of one unit (the one whose name was last tapped): its men (or
## vehicles) drawn as they look in battle, the carrier they ride in, and the unit card. It stays
## open on the screen and changes as other names are tapped.
var preview_box: Container = null
var army_boxes := {}  # unit id -> its box on the Muster screen


func _unit_box_style(chosen: bool, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.19, 0.12) if chosen else (Color(0.17, 0.14, 0.1) if hover else Color(0.12, 0.1, 0.08))
	sb.border_color = Color(0.9, 0.72, 0.38) if chosen else BRASS.darkened(0.35)
	sb.set_border_width_all(2 if chosen else 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
var preview_card: UnitCard = null


func show_unit_preview(faction: String, u: Dictionary) -> void:
	if preview_box == null or not is_instance_valid(preview_box):
		return
	for id in army_boxes:  # light up the box of the unit shown
		var bx: PanelContainer = army_boxes[id]
		if is_instance_valid(bx):
			bx.set_meta("chosen", id == u.id)
			bx.add_theme_stylebox_override("panel", _unit_box_style(id == u.id))
	for c in preview_box.get_children():
		preview_box.remove_child(c)
		c.queue_free()
	if preview_card != null and is_instance_valid(preview_card) and preview_card.popup != null:
		preview_card.popup.queue_free()
	var def: Dictionary = u.def
	var sq := Squad.new()
	sq.team = 1  # (not the player's: no outlines in the picture)
	sq.faction = faction
	sq.name = u.name
	var bodies: Array = []
	if def.has("vehicle") or def.has("vehicles"):
		for k in (def.vehicles if def.has("vehicles") else [def.vehicle]):
			bodies.append(_preview_vehicle(faction, sq, k))
	else:
		for k in def.members:
			var s := Soldier.new()
			s.setup(main, sq, 1, k)
			bodies.append(s)
	sq.members.assign(bodies)
	sq.start_size = sq.members.size()
	var carrier: Vehicle = null
	if def.has("carrier"):
		var csq := Squad.new()
		csq.faction = faction
		csq.team = 1
		carrier = _preview_vehicle(faction, csq, def.carrier)
	var small: bool = main.touch_mode
	var pw := 300.0 if small else 300.0
	var ph := 100.0 if small else 220.0
	# the picture: the men in rows facing right on a dark ground, the carrier below them
	var pic := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.16, 0.14)
	sb.border_color = BRASS.darkened(0.3)
	sb.set_border_width_all(1)
	pic.add_theme_stylebox_override("panel", sb)
	pic.clip_contents = true
	pic.custom_minimum_size = Vector2(pw, ph)
	pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview_box.add_child(pic)
	var holder := Node2D.new()
	pic.add_child(holder)
	var cols := bodies.size() if bodies.size() <= 4 or bodies[0].is_vehicle else ceili(bodies.size() / 2.0)
	var cell := Vector2.ZERO
	for b in bodies:
		cell.x = maxf(cell.x, (b.length + 16.0) if b.is_vehicle else b.radius * 2.0 + (40.0 if b.heavy or b.mortar else 18.0))
		cell.y = maxf(cell.y, (b.width + 12.0) if b.is_vehicle else b.radius * 2.0 + 14.0)
	var rows := ceili(bodies.size() / float(cols))
	var block := Vector2(cols * cell.x, rows * cell.y)
	var below := 0.0
	if carrier != null:
		below = carrier.width + 16.0
	for i in bodies.size():
		var b = bodies[i]
		b.position = Vector2((i % cols + 0.5) * cell.x, (i / cols + 0.5) * cell.y)
		b.facing = 0.0
		if b.is_vehicle:
			b.turret_angle = 0.0
		holder.add_child(b)
	if carrier != null:
		carrier.position = Vector2(block.x * 0.5, block.y + below * 0.5)
		carrier.facing = 0.0
		holder.add_child(carrier)
		block.x = maxf(block.x, carrier.length + 16.0)
	var total := Vector2(block.x, block.y + below)
	var scale := minf(3.0, minf((pw - 16.0) / maxf(total.x, 1.0), (ph - 16.0) / maxf(total.y, 1.0)))
	holder.scale = Vector2(scale, scale)
	var shift := 0.0
	if carrier != null:
		shift = (block.x - cols * cell.x) * 0.5  # centre the men over a wider carrier
		for b in bodies:
			b.position.x += shift
	holder.position = (Vector2(pw, ph) - total * scale) * 0.5
	# the unit card
	preview_card = UnitCard.new(small)
	preview_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview_box.add_child(preview_card)
	preview_card.show_squad(sq, 0)


func _preview_vehicle(faction: String, sq: Squad, k: String) -> Vehicle:
	var v := Vehicle.new()
	v.setup_vehicle(main, sq, 1, k)
	if v.engine_sound != null:
		v.engine_sound.queue_free()
		v.engine_sound = null
	return v


func _choose(key: String) -> void:
	if _map_ready():
		menu_panel.queue_free()
		main.start_battle(key)
	else:
		pending_faction = key
		load_text.text = "Starting as %s when the battlefield is ready..." % GameData.FACTIONS[key].name


## Loading bar, revealing the battlefield, and starting a battle picked early.
func _update_loading() -> void:
	if backdrop == null or not is_instance_valid(backdrop):
		return
	var mv = main.map_view
	if not _map_ready():
		load_bar.value = float(mv.tiles_done) / maxf(mv.tiles_total, 1)
		if pending_faction == "":
			load_text.text = "Preparing the battlefield...  %d%%" % int(load_bar.value * 100)
		return
	var b := backdrop
	backdrop = null
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	create_tween().tween_property(b, "modulate:a", 0.0, 0.8).finished.connect(b.queue_free)
	if is_instance_valid(load_bar):
		load_bar.visible = false
		load_text.visible = false
	if pending_faction != "":
		menu_panel.queue_free()
		main.start_battle(pending_faction)


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


## While the menu is up, note every couple of seconds that the game is still alive,
## so a crash report shows whether it died with nothing else happening.
func _tick_breadcrumbs() -> void:
	for i in 5:
		await get_tree().create_timer(2.0).timeout
		if main.started:
			return
		if main.map_view.ready_drawn:
			Settings.stage("menu up %d s, map ready (%s)" % [(i + 1) * 2, Settings.summary()])
