extends Control
## WorldSelect — the campaign map: worlds of ten levels, each level a big button showing its
## number, solved tick and best part count. Locked levels are dimmed. Portrait, scrollable.

const C_BG := Color("fbf6ea")
const C_INK := Color("1f1a2e")
const C_PANEL := Color("2d2a4a")
const C_PANEL_TXT := Color("fbf6ea")
const C_GO := Color("7bd389")
const C_ACCENT := Color("ff5d73")
const C_LOCK := Color("c9c2b6")
const BTN := 180.0

var _scroll: ScrollContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = C_PANEL
	st.content_margin_left = 32
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	top.add_theme_stylebox_override("panel", st)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = 160
	add_child(top)
	var h := HBoxContainer.new()
	top.add_child(h)
	var title := Label.new()
	title.text = "Tinker"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", C_PANEL_TXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var solved := Label.new()
	solved.text = "%d / %d solved" % [App.save.solved_count(), Campaign.level_count()]
	solved.add_theme_font_size_override("font_size", 32)
	solved.add_theme_color_override("font_color", Color(C_PANEL_TXT, 0.8))
	solved.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(solved)
	var pad := Control.new()
	pad.custom_minimum_size.x = 32
	h.add_child(pad)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 160
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 24)
	_scroll.add_child(v)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	v.add_child(spacer)

	for w in Campaign.worlds():
		v.add_child(_world_block(w))
	var bottom := Control.new()
	bottom.custom_minimum_size.y = 48
	v.add_child(bottom)


func _world_block(w: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	var name_l := Label.new()
	name_l.text = "World %d — %s" % [int(w["number"]), str(w["name"])]
	name_l.add_theme_font_size_override("font_size", 40)
	name_l.add_theme_color_override("font_color", C_INK)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 32)
	m.add_child(name_l)
	box.add_child(m)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	var gm := MarginContainer.new()
	gm.add_theme_constant_override("margin_left", 32)
	gm.add_theme_constant_override("margin_right", 32)
	gm.add_child(grid)
	box.add_child(gm)
	for l in w["levels"]:
		grid.add_child(_level_button(int(l["number"]), str(l["title"])))
	return box


func _level_button(number: int, title: String) -> Control:
	var unlocked := Campaign.is_unlocked(number, App.save)
	var best := App.save.best(number)
	var solved := bool(best.get("solved", false))
	var b := Button.new()
	b.custom_minimum_size = Vector2(BTN, BTN)
	b.focus_mode = Control.FOCUS_NONE
	b.name = "Level%d" % number
	var style := StyleBoxFlat.new()
	style.bg_color = C_GO if solved else (Color("4a4670") if unlocked else C_LOCK)
	style.set_corner_radius_all(28)
	style.border_color = C_INK
	style.set_border_width_all(5)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	var pressed := style.duplicate()
	pressed.bg_color = style.bg_color.darkened(0.2)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", style)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.disabled = not unlocked
	b.tooltip_text = title
	# Number big, best parts small below.
	b.text = str(number)
	b.add_theme_font_size_override("font_size", 56)
	b.add_theme_color_override("font_color", C_INK if solved else C_PANEL_TXT)
	b.add_theme_color_override("font_disabled_color", Color(C_INK, 0.35))
	if solved:
		var sub := Label.new()
		sub.text = "%d part%s" % [int(best["best_parts"]), "" if int(best["best_parts"]) == 1 else "s"]
		sub.add_theme_font_size_override("font_size", 24)
		sub.add_theme_color_override("font_color", C_INK)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		sub.offset_top = -40
		sub.offset_bottom = -10
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sub)
	b.pressed.connect(func() -> void: App.open_level(number))
	return b
