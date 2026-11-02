class_name Tutorial
extends Control
## Tutorial — first-run walkthrough on campaign level 1 (M6).
##
## A speech bubble under the top bar and a bouncing arrow that points at what to touch next.
## It only READS the level screen (placements, run state, last result) and moves on by itself:
##   1. "Drag the plank from the tray onto the board"      -> arrow at the first tray part
##   2. "Tilt it with the round handle... then press RUN" -> arrow at RUN   (also mentions "i")
##   3. after the run: solved -> done (saved); not solved -> "STOP, adjust, try again"
## Skip ends it. Settings -> "Show tutorial again" clears App.settings.tutorial_done.
## Never blocks input: everything here ignores the mouse except the Skip button.

var screen: Node  # LevelScreen
var top_offset := 236.0  # height of the level screen's top bar (set by the caller)
var bottom_offset := 320.0  # height of the tray (set by the caller)
var _step := 0
var _bubble: PanelContainer
var _text: Label
var _arrow: Control
var _t := 0.0


static func start(parent: Node, p_screen: Node) -> Tutorial:
	var t := Tutorial.new()
	t.name = "Tutorial"
	t.screen = p_screen
	parent.add_child(t)
	return t


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble = PanelContainer.new()
	var st := UiKit.style(Color("fff4c2"), 24)
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	_bubble.add_theme_stylebox_override("panel", st)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(h)
	_text = UiKit.label("", 30)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_text)
	var skip := UiKit.button("Skip", UiKit.MUTED, UiKit.PANEL_TXT, 88)
	skip.name = "TutorialSkip"
	skip.add_theme_font_size_override("font_size", 28)
	skip.pressed.connect(finish)
	h.add_child(skip)
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.custom_minimum_size = Vector2(80, 80)
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_show(0)


func _show(step: int) -> void:
	_step = step
	match step:
		0:
			_text.text = "Drag the plank from the tray onto the board."
		1:
			_text.text = "Tilt it with the round handle so the ball rolls into the basket, then press RUN. Tap i on a part to see what it does."
		2:
			_text.text = "Not quite. Press STOP, move or tilt the plank, and try again."


func _process(delta: float) -> void:
	_t += delta
	var vs := get_viewport_rect().size
	# Inside the tray panel, right of the tray parts: never covers the board (ball, ramps, basket).
	var left := 24.0 + 220.0 + 24.0
	_bubble.size = Vector2(vs.x - left - 24.0, 0)
	_bubble.position = Vector2(left, vs.y - bottom_offset + 76.0)
	var placed: bool = screen.placements.size() > 0
	match _step:
		0:
			if placed:
				_show(1)
		1:
			if not placed:
				_show(0)
			elif screen.run_ended and screen.last_result != "goal":
				_show(2)
		2:
			if not screen.run_ended and not screen.sim.running:
				_show(1 if placed else 0)
	if screen.run_ended and screen.last_result == "goal":
		finish()
		return
	# Arrow target: the first tray part, then RUN.
	var target := Rect2()
	if _step == 0 and screen.tray.visible and screen.tray_items.get_child_count() > 0:
		target = screen.tray_items.get_child(0).get_global_rect()
	elif _step >= 1:
		target = screen.play_btn.get_global_rect()
	_arrow.visible = target.size != Vector2.ZERO
	if _arrow.visible:
		var bob := sin(_t * 6.0) * 12.0
		_arrow.position = Vector2(target.get_center().x - 40, target.position.y - 96 + bob)
		_arrow.queue_redraw()


func _draw_arrow() -> void:
	var pts := PackedVector2Array([Vector2(20, 0), Vector2(60, 0), Vector2(60, 40), Vector2(80, 40), Vector2(40, 80), Vector2(0, 40), Vector2(20, 40)])
	_arrow.draw_colored_polygon(pts, UiKit.INK)
	var inner := PackedVector2Array([Vector2(26, 6), Vector2(54, 6), Vector2(54, 46), Vector2(66, 46), Vector2(40, 72), Vector2(14, 46), Vector2(26, 46)])
	_arrow.draw_colored_polygon(inner, Color("ffd43b"))


func finish() -> void:
	var app := get_node_or_null("/root/App")
	if app:
		app.settings.tutorial_done = true
		app.settings.save()
	queue_free()
