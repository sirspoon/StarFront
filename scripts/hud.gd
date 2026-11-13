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
			+ "V switch gun setting: tank beam / pulse or AP / HE,\n" \
			+ "   carrier launchers HE / smoke.  B fire a launcher salvo\n" \
			+ "C cover view: green low cover, blue windows,\n" \
			+ "   white standing walls, yellow rubble, red wire\n" \
			+ "T then click: grenades. At armour: tank-breakers,\n" \
			+ "   at infantry: frags, at open ground: smoke screen\n" \
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
	for spec in [["Assault", true], ["Down", true], ["Face", true], ["Grenade", true], ["Cover", true], ["Halt", false], ["Unload", false], ["Gun", false], ["Launch", false],
			["Squads", true], ["Pause", true], ["?", false], ["Menu", false]]:
		var b := Button.new()
		var hints := {"Assault": "R", "Down": "G", "Halt": "H", "Unload": "U", "Gun": "V", "Launch": "B", "Grenade": "T", "Cover": "C", "Pause": "Space", "?": "F1", "Menu": "Esc"}
		b.text = spec[0] if main.touch_mode or not hints.has(spec[0]) else "%s (%s)" % [spec[0], hints[spec[0]]]
		b.toggle_mode = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(64, 44) if main.touch_mode else Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 16 if main.touch_mode else 13)
		touch_bar.add_child(b)
		touch_buttons[spec[0]] = b
		var key: String = spec[0]
		if spec[1]:
			b.toggled.connect(func(on): main.touch_button(key, on))
		else:
			b.pressed.connect(func(): main.touch_button(key, true))
	touch_buttons["Squads"].set_pressed_no_signal(true)


## Keeps the toggle buttons in step when the game changes a mode itself.
func sync_touch(key: String, on: bool) -> void:
	if touch_buttons.has(key):
		touch_buttons[key].set_pressed_no_signal(on)


## The Gun and Launch buttons say what they'd do for the selected vehicles, and are
## greyed out when nothing selected has a gun setting or launchers.
func _gun_buttons() -> void:
	if not touch_buttons.has("Gun"):
		return
	var mode := ""
	var launch := ""
	for sq in main.squads:
		var v = sq.vehicle()
		if sq.team == main.player_team and sq.selected and v != null and v.is_alive():
			if mode == "" and v.gun_mode() != "":
				mode = v.gun_mode()
			if launch == "" and v.launcher:
				launch = "%s %d" % [v.gun_mode(), int(v.launch_ammo[v.launch_kind])]
	var hint: bool = not main.touch_mode
	var g: Button = touch_buttons["Gun"]
	g.text = ("Gun: %s" % mode if mode != "" else "Gun") + (" (V)" if hint else "")
	g.disabled = mode == ""
	g.tooltip_text = "Switch the selected vehicle's gun setting (tank main gun, or the carrier's launcher rounds)"
	var l: Button = touch_buttons["Launch"]
	l.text = ("Launch: %s" % launch if launch != "" else "Launch") + (" (B)" if hint else "")
	l.disabled = launch == ""
	l.tooltip_text = "Fire a salvo of six grenades from the selected carrier's launchers over the ground ahead"


## Keep the card's bottom edge just above the command bar as its contents change.
func place_card() -> void:
	var ms := unit_card.get_combined_minimum_size()
	unit_card.size = ms
	unit_card.position = Vector2(10, root.size.y - ms.y - (76 if main.touch_mode else 56))


func set_squads_visible(on: bool) -> void:
	squads_on = on
	squad_panel.visible = on and not unit_card.visible


## True if a screen position is over a panel or button, so a touch there
## isn't also taken as an order on the battlefield.
func is_over_ui(pos: Vector2) -> bool:
	for c in [top_panel, squad_panel, unit_card, help_panel, touch_bar.get_parent() if touch_bar else null,
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
	_update_loading()
	if loading_label.visible and (main.map_view.ready_drawn or not main.map_view.enabled):
		loading_label.visible = false
	var f0: Dictionary = GameData.FACTIONS[main.factions[0]]
	var f1: Dictionary = GameData.FACTIONS[main.factions[1]]
	var t := int(main.time)
	var total := int(main.battle_length)
	var clock := "%d:%02d" % [t / 60, t % 60] + (" / %d:%02d" % [total / 60, total % 60] if total > 0 else "")
	var chapel := "unclaimed"
	if main.objective_owner >= 0:
		chapel = "%s  (%d / %d s to win)" % [GameData.FACTIONS[main.factions[main.objective_owner]].short,
				int(main.hold_streak), int(main.HOLD_TO_WIN)]
	top_label.text = "STARFRONT v%s      %s  vs  %s      Time %s      Chapel: %s%s" % [
			GameData.VERSION, f0.name, f1.name, clock, chapel,
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
	sub.text = "Battle for the Ashen Chapel   ·   "
	sub_row.add_child(sub)
	var ver := LinkButton.new()  # the version: click it for what's new
	ver.text = "prototype v%s  (what's new)" % GameData.VERSION
	ver.focus_mode = Control.FOCUS_NONE
	ver.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	ver.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.5))
	ver.pressed.connect(_show_whats_new)
	sub_row.add_child(ver)
	var intro := Label.new()
	intro.text = "The hive-city of Vell is ash and rubble. At its heart stands a ruined chapel\n" \
			+ "that both sides have sworn to take. Choose who you command."
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
		b.pressed.connect(func(): _choose(key))
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
