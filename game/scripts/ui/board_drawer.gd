class_name BoardDrawer
extends Control
## BoardDrawer — the leaderboard sliding in from the right edge of the map (a trophy tab is always
## visible on the edge). Tap the tab or swipe left to open, tap outside / the tab / swipe right to close.

const TAB_W := 92.0
const TAB_H := 200.0

var view: BoardView
var _panel: PanelContainer
var _dim: ColorRect
var _tab: Button
var _open := false
var _tween: Tween
var _swipe_from := Vector2.INF


func _ready() -> void:
	name = "BoardDrawer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.04, 0.12, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed or e is InputEventScreenTouch and e.pressed:
			close())
	add_child(_dim)
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiKit.PANEL
	st.border_color = UiKit.INK
	st.border_width_left = 6
	st.corner_radius_top_left = 36
	st.corner_radius_bottom_left = 36
	st.content_margin_left = 28
	st.content_margin_right = 24
	st.content_margin_top = 28
	st.content_margin_bottom = 28
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", st)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.label("Leaderboard", 48, UiKit.PANEL_TXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := UiKit.button("Close", UiKit.MUTED, UiKit.PANEL_TXT, 88)
	x.add_theme_font_size_override("font_size", 28)
	x.pressed.connect(close)
	head.add_child(x)
	view = BoardView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(view)
	_tab = Button.new()
	_tab.name = "BoardTab"
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.flat = true
	_tab.custom_minimum_size = Vector2(TAB_W, TAB_H)
	_tab.mouse_filter = Control.MOUSE_FILTER_STOP
	_tab.draw.connect(_draw_tab)
	_tab.pressed.connect(func() -> void: close() if _open else open())
	add_child(_tab)
	get_viewport().size_changed.connect(_place)
	_place()


func _panel_w() -> float:
	return minf(get_viewport_rect().size.x * 0.92, 980.0)


func _place() -> void:
	var vs := get_viewport_rect().size
	var w := _panel_w()
	_panel.size = Vector2(w, vs.y - 200.0)
	_panel.position = Vector2(vs.x - (w if _open else 0.0), 180.0)
	if not _open:
		_panel.position.x = vs.x + 30.0
	_tab.position = Vector2(_panel.position.x - TAB_W + 6.0, vs.y * 0.42)


func is_open() -> bool:
	return _open


func open(t: String = "") -> void:
	if not _open and (t != "" or not view.loaded):
		view.load_tab(t if t != "" else view.tab, view.scope)
	elif t != "":
		view.load_tab(t, view.scope)
	_open = true
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_slide()
	if has_node("/root/App"):
		App.audio.sfx("place")


func close() -> void:
	if not _open:
		return
	_open = false
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide()


func _slide() -> void:
	var vs := get_viewport_rect().size
	var to := vs.x - _panel_w() if _open else vs.x + 30.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "position:x", to, 0.32)
	_tween.tween_property(_tab, "position:x", to - TAB_W + 6.0, 0.32)
	_tween.tween_property(_dim, "color:a", 0.55 if _open else 0.0, 0.32)
	_tween.chain().tween_callback(func() -> void: _tab.queue_redraw())
	FramePacer.busy(500)


func _input(e: InputEvent) -> void:
	# Horizontal swipe on the drawer (or from the right edge) opens / closes it.
	var pos := Vector2.INF
	var pressed := false
	if e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
	else:
		return
	if pressed:
		var vs := get_viewport_rect().size
		_swipe_from = pos if (_open and pos.x > _panel.position.x) or (not _open and pos.x > vs.x - 40.0) else Vector2.INF
	elif _swipe_from != Vector2.INF:
		var d := pos - _swipe_from
		_swipe_from = Vector2.INF
		if absf(d.x) > 140.0 and absf(d.x) > absf(d.y) * 1.5:
			if d.x > 0 and _open:
				close()
			elif d.x < 0 and not _open:
				open()


## A tab on the right edge with a trophy, so the board is always one tap away.
func _draw_tab() -> void:
	var r := Rect2(Vector2.ZERO, _tab.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("ffd43b")
	sb.border_color = UiKit.INK
	sb.set_border_width_all(5)
	sb.border_width_right = 0
	sb.corner_radius_top_left = 28
	sb.corner_radius_bottom_left = 28
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	_tab.draw_style_box(sb, r)
	var c := Vector2(r.size.x * 0.55, r.size.y * 0.42)
	# Trophy: cup, handles, stem, base.
	var cup := PackedVector2Array([c + Vector2(-24, -30), c + Vector2(24, -30), c + Vector2(18, 4), c + Vector2(0, 14), c + Vector2(-18, 4)])
	_tab.draw_colored_polygon(cup, UiKit.INK)
	var inner := PackedVector2Array([c + Vector2(-19, -26), c + Vector2(19, -26), c + Vector2(14, 1), c + Vector2(0, 9), c + Vector2(-14, 1)])
	_tab.draw_colored_polygon(inner, Color("f2a93b"))
	_tab.draw_arc(c + Vector2(-24, -16), 11, PI * 0.5, PI * 1.5, 12, UiKit.INK, 5.0)
	_tab.draw_arc(c + Vector2(24, -16), 11, -PI * 0.5, PI * 0.5, 12, UiKit.INK, 5.0)
	_tab.draw_rect(Rect2(c + Vector2(-5, 12), Vector2(10, 16)), UiKit.INK)
	_tab.draw_rect(Rect2(c + Vector2(-20, 27), Vector2(40, 10)), UiKit.INK)
	var f := ThemeDB.fallback_font
	var s := "TOP"
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_tab.draw_string(f, Vector2(r.size.x * 0.55 - w / 2.0, r.size.y - 30), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiKit.INK)
