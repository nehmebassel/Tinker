class_name UiKit
extends RefCounted
## Shared look for menu screens (world select, board, settings): flat fills, thick ink outlines.

const BG := Color("fbf6ea")
const INK := Color("1f1a2e")
const PANEL := Color("2d2a4a")
const PANEL_TXT := Color("fbf6ea")
const GO := Color("7bd389")
const ACCENT := Color("ff5d73")
const MUTED := Color("4a4670")


static func background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)


static func label(text: String, size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func style(c: Color, radius: int = 28) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.border_color = INK
	s.set_border_width_all(5)
	s.content_margin_left = 24
	s.content_margin_right = 24
	return s


static func button(text: String, fill: Color = MUTED, txt: Color = PANEL_TXT, h: float = 120.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(h, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 34)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, txt)
	b.add_theme_color_override("font_disabled_color", Color(txt, 0.4))
	b.add_theme_stylebox_override("normal", style(fill))
	b.add_theme_stylebox_override("hover", style(fill))
	b.add_theme_stylebox_override("pressed", style(fill.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", style(fill.darkened(0.35)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Dark top bar with a back button and a title; returns the HBox so callers can add to it.
static func top_bar(parent: Control, title: String, on_back: Callable) -> HBoxContainer:
	var top := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	top.add_theme_stylebox_override("panel", st)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = 160
	parent.add_child(top)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	top.add_child(h)
	if on_back.is_valid():
		var back := button("<", MUTED, PANEL_TXT, 112)
		back.name = "BackButton"
		back.pressed.connect(on_back)
		h.add_child(back)
	var t := label(title, 52, PANEL_TXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(t)
	return h
