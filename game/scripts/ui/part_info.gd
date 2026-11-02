class_name PartInfoCard
extends Control
## PartInfoCard — "what does this part do?"
##
## Modal card: part name, its one-line description (from game/parts/<id>.json), what it works with,
## and a LIVE looping demo: the real Simulation running the part's demo scene
## (levels/demos/<id>.json, copied from a CI-verified test scene) in a small SubViewport.
## The demo has its own physics world (SubViewport + Simulation's fresh World2D), so it cannot
## touch the level being built. Opened from the "i" on a tray part or by tapping a fixed part.

const DEMO_DIR := "res://levels/demos/"
const VIEW := Vector2i(900, 640)
const PAPER := Color("fdfaf1")
const GRID := Color("e2ebf3")

var part_id: String
var _sim: Simulation
var _cam: Camera2D
var _timer: Timer


static func open(parent: Node, p_part: String) -> PartInfoCard:
	var c := PartInfoCard.new()
	c.part_id = p_part
	c.name = "PartInfo"
	parent.add_child(c)
	return c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var def := PartRegistry.get_def(part_id)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.05, 0.14, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var st := UiKit.style(UiKit.PANEL, 36)
	st.set_border_width_all(6)
	st.content_margin_left = 32
	st.content_margin_right = 32
	st.content_margin_top = 28
	st.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)

	var title := UiKit.label(str(def.get("name", part_id)), 56, UiKit.PANEL_TXT)
	v.add_child(title)
	var desc := UiKit.label(str(def.get("description", "")), 32, Color(UiKit.PANEL_TXT, 0.9))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = VIEW.x
	v.add_child(desc)

	# Live demo.
	var frame := PanelContainer.new()
	var fst := StyleBoxFlat.new()
	fst.bg_color = Color("b07a45")
	fst.set_corner_radius_all(16)
	fst.set_border_width_all(5)
	fst.border_color = UiKit.INK
	fst.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", fst)
	v.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(VIEW)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(svc)
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.transparent_bg = false
	vp.handle_input_locally = false
	svc.add_child(vp)
	var paper := Node2D.new()
	paper.z_index = -10
	paper.draw.connect(func() -> void: _draw_paper(paper))
	vp.add_child(paper)
	_sim = Simulation.new()
	_sim.name = "DemoSimulation"
	vp.add_child(_sim)
	_cam = Camera2D.new()
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS  # project uses physics interpolation
	vp.add_child(_cam)
	_cam.make_current()

	var with: Array = []
	for other in def.get("interacts_with", []):
		with.append(str(PartRegistry.get_def(str(other)).get("name", other)))
	if not with.is_empty():
		var w := UiKit.label("Works with: " + ", ".join(with), 28, Color(UiKit.PANEL_TXT, 0.75))
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size.x = VIEW.x
		v.add_child(w)
	var close_btn := UiKit.button("Got it", UiKit.GO, UiKit.INK, 110)
	close_btn.name = "CloseInfo"
	close_btn.pressed.connect(close)
	v.add_child(close_btn)

	_start_demo()


func _start_demo() -> void:
	var path := DEMO_DIR + part_id + ".json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	var level := LevelData.load_from_file(path)
	if level == null:
		return
	_sim.load_level(level)
	_frame_camera()
	var secs := float(data.get("demo_seconds", 5)) if data is Dictionary else 5.0
	_timer = Timer.new()
	_timer.wait_time = secs
	_timer.timeout.connect(_restart)
	add_child(_timer)
	# Show the starting layout for a beat, then run; restart every `secs` seconds.
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(_sim):
			_sim.start()
			_timer.start())


func _restart() -> void:
	_sim.stop()
	_sim.start()


## Frame the demo: start on the parts' layout, then widen to everything that moves (a launched
## ball, a rising balloon, a falling bucket), easing the camera so the view never jumps.
var _box := Rect2()
var _target_zoom := 1.0
var _target_pos := Vector2.ZERO


func _frame_camera() -> void:
	_box = Rect2()
	var first := true
	for p in _sim.parts:
		var r := Rect2(p.global_position - Vector2(130, 130), Vector2(260, 260))
		_box = r if first else _box.merge(r)
		first = false
	_retarget()
	_cam.zoom = Vector2(_target_zoom, _target_zoom)
	_cam.position = _target_pos


func _retarget() -> void:
	var b := _box.grow(60)
	_target_zoom = clampf(minf(VIEW.x / b.size.x, VIEW.y / b.size.y), 0.22, 1.4)
	_target_pos = b.get_center()


func _process(delta: float) -> void:
	if _sim == null or _cam == null:
		return
	if _sim.running:
		var stage := Rect2(Vector2.ZERO, Vector2(Grid.STAGE_PX))
		var grew := false
		for p in _sim.parts:
			if p.get_meta("out", false) or not stage.has_point(p.global_position):
				continue
			var r := Rect2(p.global_position - Vector2(110, 110), Vector2(220, 220))
			if not _box.encloses(r):
				_box = _box.merge(r)
				grew = true
		if grew:
			_retarget()
	var t := clampf(delta * 3.0, 0.0, 1.0)
	_cam.zoom = _cam.zoom.lerp(Vector2(_target_zoom, _target_zoom), t)
	_cam.position = _cam.position.lerp(_target_pos, t)


func _draw_paper(n: Node2D) -> void:
	var r := Rect2(Vector2(-2000, -2000), Vector2(5200, 5600))
	n.draw_rect(r, PAPER)
	var step := Grid.TILE
	var x := r.position.x
	while x < r.end.x:
		n.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), GRID, 2.0)
		x += step
	var y := r.position.y
	while y < r.end.y:
		n.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), GRID, 2.0)
		y += step


func close() -> void:
	if _timer:
		_timer.stop()
	queue_free()
