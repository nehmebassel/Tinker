extends Control
## LevelScreen — the play screen: stage, tray, drag/snap/rotate, play/stop, undo/redo.
##
## All editing produces integer Placements (see Grid). The screen never moves a physics body
## directly: every edit changes `placements` and asks the Simulation to rebuild, which keeps the
## thing on screen identical to what a replay would build.
##
## Touch rules (docs/DESIGN.md "Touch controls"):
##  * drag from the tray; the part floats above the finger, a ghost shows the snapped landing spot
##  * tap a placed part -> rotation ring; drag the handle in 15 degree steps; double-tap ring = quarter turn
##  * pinch to zoom, two-finger drag to pan, double-tap empty space to fit
##  * no long-press gestures; every gesture has a visible button that does the same thing
##  * minimum touch target 44 pt (we use 132 px at 1080 wide, about 48 pt on a 6" phone)

const LEVEL_PATH_DEFAULT := "res://levels/campaign/001.json"
const TOP_BAR_H := 160.0
const TRAY_H := 320.0
const TRAY_TAB_H := 72.0
const BTN := 132.0  # touch target in px at design width
const LIFT := Vector2(0, -Grid.TILE * 1.25)  # part floats above the finger
const TAP_SLOP := 14.0  # px of movement before a touch counts as a drag
const RING_R := 150.0
const RING_HANDLE_R := 34.0
const RING_GRAB := 70.0

const C_BG := Color("fbf6ea")
const C_STAGE := Color("fffdf7")
const C_GRID := Color("e6dfd0")
const C_INK := Color("1f1a2e")
const C_ACCENT := Color("ff5d73")
const C_GO := Color("7bd389")
const C_PANEL := Color("2d2a4a")
const C_PANEL_TXT := Color("fbf6ea")
const C_BAD := Color("ff3b3b")

@export var level_path: String = LEVEL_PATH_DEFAULT

var level: LevelData
var sim: Simulation
var placements: Array[Placement] = []
var history: Array = []  # Array of Array[Placement] snapshots
var future: Array = []
var selected: int = -1  # index into placements
var first_touch_msec: int = -1
var solved_msec: int = -1
var run_ended: bool = false  # a run finished (goal or not) and is waiting for Stop/rewind

# Scene nodes
var world: Node2D
var camera: Camera2D
var stage_bg: Node2D
var overlay: Node2D  # ghost, floating part, ring
var hud: CanvasLayer
var tray: PanelContainer
var tray_items: HBoxContainer
var tray_tab: Button
var play_btn: Button
var undo_btn: Button
var redo_btn: Button
var fit_btn: Button
var rot_btn: Button
var rot90_btn: Button
var title_lbl: Label
var counter_lbl: Label
var toast_lbl: Label
var result_panel: PanelContainer
var result_lbl: Label

# Touch state
var touches: Dictionary = {}  # index -> screen position
var drag: Dictionary = {}  # active single-finger gesture, see _begin_*
var pinch_start_dist: float = 0.0
var pinch_start_zoom: float = 1.0
var pinch_start_cam: Vector2 = Vector2.ZERO
var pinch_start_mid: Vector2 = Vector2.ZERO
var fit_zoom: float = 1.0
var floating: Node2D = null
var ghost: Node2D = null
var ghost_valid: bool = true
var ring_pos: Vector2 = Vector2.ZERO
var ring_visible: bool = false
var tray_collapsed: bool = false
var tray_counts: Dictionary = {}
var smoke_mode: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level_path = a.trim_prefix("--level=")
		elif a == "--smoke":
			smoke_mode = true
	_build_scene()
	_load_level(level_path)
	get_viewport().size_changed.connect(_on_resized)
	_fit_camera()
	if smoke_mode:
		_run_smoke()


# ------------------------------------------------------------------ scene construction

func _build_scene() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	stage_bg = Node2D.new()
	stage_bg.name = "StageBackground"
	stage_bg.draw.connect(_draw_stage)
	world.add_child(stage_bg)
	sim = Simulation.new()
	sim.name = "Simulation"
	sim.finished.connect(_on_run_finished)
	world.add_child(sim)
	overlay = Node2D.new()
	overlay.name = "Overlay"
	overlay.z_index = 10
	overlay.draw.connect(_draw_overlay)
	world.add_child(overlay)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = false
	world.add_child(camera)
	camera.make_current()

	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	# Top bar: title, counter, undo, redo.
	var top := PanelContainer.new()
	top.name = "TopBar"
	top.add_theme_stylebox_override("panel", _panel_style(C_PANEL, 0))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_BAR_H
	hud.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 16)
	top.add_child(top_h)
	var pad := Control.new()
	pad.custom_minimum_size.x = 8
	top_h.add_child(pad)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_h.add_child(vb)
	title_lbl = _label("", 44, C_PANEL_TXT)
	vb.add_child(title_lbl)
	counter_lbl = _label("", 30, Color(C_PANEL_TXT, 0.8))
	vb.add_child(counter_lbl)
	undo_btn = _button("Undo", BTN)
	undo_btn.pressed.connect(_undo)
	top_h.add_child(undo_btn)
	redo_btn = _button("Redo", BTN)
	redo_btn.pressed.connect(_redo)
	top_h.add_child(redo_btn)
	rot_btn = _button("Turn", BTN)
	rot_btn.pressed.connect(func() -> void: _rotate_selected(1))
	top_h.add_child(rot_btn)
	rot90_btn = _button("90°", BTN)
	rot90_btn.pressed.connect(func() -> void: _rotate_selected(6))
	top_h.add_child(rot90_btn)
	fit_btn = _button("Fit", BTN)
	fit_btn.pressed.connect(_fit_camera)
	top_h.add_child(fit_btn)
	var pad2 := Control.new()
	pad2.custom_minimum_size.x = 8
	top_h.add_child(pad2)

	# Tray at the bottom with a collapse tab.
	tray = PanelContainer.new()
	tray.name = "Tray"
	tray.add_theme_stylebox_override("panel", _panel_style(C_PANEL, 28))
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.custom_minimum_size.y = TRAY_H
	tray.offset_top = -TRAY_H
	hud.add_child(tray)
	var tray_v := VBoxContainer.new()
	tray.add_child(tray_v)
	tray_tab = _button("Hide tray", BTN)
	tray_tab.custom_minimum_size = Vector2(0, TRAY_TAB_H)
	tray_tab.flat = true
	tray_tab.pressed.connect(_toggle_tray)
	tray_v.add_child(tray_tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_v.add_child(scroll)
	tray_items = HBoxContainer.new()
	tray_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_items.add_theme_constant_override("separation", 24)
	scroll.add_child(tray_items)

	# Right-side column: Play (big), Fit, Rotate, 90.
	var side := VBoxContainer.new()
	side.name = "SideButtons"
	side.add_theme_constant_override("separation", 20)
	side.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side.offset_right = -24
	side.offset_bottom = -TRAY_H - 24
	hud.add_child(side)
	play_btn = _button("PLAY", BTN * 1.5)
	play_btn.add_theme_font_size_override("font_size", 40)
	play_btn.add_theme_stylebox_override("normal", _round_style(C_GO))
	play_btn.add_theme_stylebox_override("pressed", _round_style(C_GO.darkened(0.2)))
	play_btn.add_theme_stylebox_override("hover", _round_style(C_GO))
	play_btn.add_theme_color_override("font_color", C_INK)
	play_btn.pressed.connect(_toggle_play)
	side.add_child(play_btn)

	toast_lbl = _label("", 36, C_PANEL_TXT)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_lbl.offset_top = TOP_BAR_H + 24
	toast_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_lbl.visible = false
	hud.add_child(toast_lbl)

	# Centered via a full-rect CenterContainer so the panel sizes to its content reliably.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(center)
	result_panel = PanelContainer.new()
	var rp_style := _panel_style(C_PANEL, 36)
	rp_style.set_corner_radius_all(36)
	rp_style.border_color = C_INK
	rp_style.set_border_width_all(6)
	result_panel.add_theme_stylebox_override("panel", rp_style)
	result_panel.visible = false
	center.add_child(result_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 24)
	result_panel.add_child(rv)
	var mc := MarginContainer.new()
	for side_name in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side_name, 40)
	rv.add_child(mc)
	var rv2 := VBoxContainer.new()
	rv2.add_theme_constant_override("separation", 24)
	mc.add_child(rv2)
	result_lbl = _label("", 44, C_PANEL_TXT)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv2.add_child(result_lbl)
	var again := _button("Build again", BTN)
	again.pressed.connect(func() -> void:
		result_panel.visible = false
		_stop_run())
	rv2.add_child(again)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, min_h: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_h, min_h)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", C_PANEL_TXT)
	b.add_theme_color_override("font_hover_color", C_PANEL_TXT)
	b.add_theme_color_override("font_pressed_color", C_PANEL_TXT)
	b.add_theme_color_override("font_disabled_color", Color(C_PANEL_TXT, 0.35))
	b.add_theme_stylebox_override("normal", _round_style(Color("4a4670")))
	b.add_theme_stylebox_override("hover", _round_style(Color("4a4670")))
	b.add_theme_stylebox_override("pressed", _round_style(Color("6d68a0")))
	b.add_theme_stylebox_override("disabled", _round_style(Color("3a3758")))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	return b


func _round_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(28)
	s.border_color = C_INK
	s.set_border_width_all(5)
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s


func _panel_style(c: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


# ------------------------------------------------------------------ level

func _load_level(path: String) -> void:
	level = LevelData.load_from_file(path)
	if level == null:
		title_lbl.text = "Level failed to load"
		return
	placements = []
	history = []
	future = []
	selected = -1
	first_touch_msec = -1
	run_ended = false
	sim.load_level(level)
	title_lbl.text = level.title
	_rebuild_tray()
	_refresh_hud()
	stage_bg.queue_redraw()


func _rebuild_tray() -> void:
	for c in tray_items.get_children():
		c.queue_free()
	tray_counts = {}
	for part in level.tray:
		tray_counts[part] = level.tray[part]
	for part in level.tray:
		var item := _make_tray_item(part)
		tray_items.add_child(item)
	_refresh_tray_counts()


func _make_tray_item(part: String) -> Control:
	var item := PanelContainer.new()
	item.name = "Tray_" + part
	item.custom_minimum_size = Vector2(220, 220)
	item.add_theme_stylebox_override("panel", _round_style(Color("3a3758")))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("part", part)
	var holder := Node2D.new()
	holder.position = Vector2(110, 84)
	item.add_child(holder)
	var preview := PartFactory.create(Placement.new(part, Vector2i.ZERO, 0), 9000, false)
	if preview:
		_disable_collisions(preview)
		var def := PartRegistry.get_def(part)
		var s: Dictionary = def["shape"]
		var w: float = float(s.get("w", s.get("radius", 40) * 2.0))
		var h: float = float(s.get("h", s.get("radius", 40) * 2.0))
		var k: float = minf(170.0 / maxf(w, 1.0), 120.0 / maxf(h, 1.0))
		preview.scale = Vector2(k, k)
		holder.add_child(preview)
	var count := _label("", 30, C_PANEL_TXT)
	count.name = "Count"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	count.offset_top = -56
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(count)
	return item


func _refresh_tray_counts() -> void:
	for item in tray_items.get_children():
		var part: String = item.get_meta("part")
		var left: int = _tray_left(part)
		var def := PartRegistry.get_def(part)
		item.get_node("Count").text = "%s  ×%d" % [def.get("name", part), left]
		item.modulate.a = 1.0 if left > 0 else 0.4


func _tray_left(part: String) -> int:
	var used := 0
	for p in placements:
		if p.part == part:
			used += 1
	return int(level.tray.get(part, 0)) - used


func _refresh_hud() -> void:
	var editing := not sim.running and not run_ended
	counter_lbl.text = "%d / %d parts" % [placements.size(), level.slots] if level else ""
	undo_btn.disabled = history.is_empty() or not editing
	redo_btn.disabled = future.is_empty() or not editing
	rot_btn.disabled = selected < 0 or not editing
	rot90_btn.disabled = rot_btn.disabled
	play_btn.text = "STOP" if (sim.running or run_ended) else "PLAY"
	play_btn.add_theme_stylebox_override("normal", _round_style(C_ACCENT if (sim.running or run_ended) else C_GO))
	play_btn.add_theme_stylebox_override("hover", _round_style(C_ACCENT if (sim.running or run_ended) else C_GO))
	tray.visible = editing and not tray_collapsed
	tray_tab.text = "Show tray" if tray_collapsed else "Hide tray"
	_refresh_tray_counts()
	ring_visible = selected >= 0 and editing
	if ring_visible:
		ring_pos = Grid.cell_to_world(placements[selected].cell)
	overlay.queue_redraw()


# ------------------------------------------------------------------ camera

func _stage_viewport_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var bottom := vs.y - (TRAY_TAB_H + 24 if tray_collapsed else TRAY_H)
	return Rect2(0, TOP_BAR_H, vs.x, bottom - TOP_BAR_H)


func _fit_camera() -> void:
	var r := _stage_viewport_rect()
	var zoom := minf(r.size.x / Grid.STAGE_PX.x, r.size.y / Grid.STAGE_PX.y)
	fit_zoom = zoom
	camera.zoom = Vector2(zoom, zoom)
	# Put the stage centre at the centre of the available rect.
	var vs := get_viewport_rect().size
	var screen_center := r.get_center()
	camera.position = Vector2(Grid.STAGE_PX) / 2.0 - (screen_center - vs / 2.0) / zoom
	_clamp_camera()


func _clamp_camera() -> void:
	var z := camera.zoom.x
	var vs := get_viewport_rect().size
	var half := vs / (2.0 * z)
	var margin := Grid.TILE * 2.0
	var minp := Vector2(-margin, -margin) + half
	var maxp := Vector2(Grid.STAGE_PX) + Vector2(margin, margin) - half
	camera.position.x = clampf(camera.position.x, minf(minp.x, maxp.x), maxf(minp.x, maxp.x))
	camera.position.y = clampf(camera.position.y, minf(minp.y, maxp.y), maxf(minp.y, maxp.y))


func _on_resized() -> void:
	_fit_camera()


func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func _world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


# ------------------------------------------------------------------ input

## All touch handling lives here. Buttons are real Controls and get the (emulated) mouse
## events; a touch that starts on a Button is left alone. Mouse events are ignored on purpose:
## the project emulates touch from mouse, so desktop testing goes through the same path.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _on_hud_button(event.position):
				return
			touches[event.index] = event.position
			if touches.size() == 2:
				_cancel_drag()  # second finger means pinch/pan
				_begin_pinch()
			elif touches.size() == 1:
				var tray_part := _tray_part_at(event.position)
				if tray_part != "":
					_tray_touch(tray_part, event.index, event.position)
				else:
					_touch_down(event.index, event.position, event.double_tap)
			get_viewport().set_input_as_handled()
		else:
			if not touches.has(event.index):
				return
			if touches.size() == 2:
				pinch_start_dist = 0.0
			touches.erase(event.index)
			if drag.get("index", -1) == event.index:
				_end_drag(event.index, event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		touches[event.index] = event.position
		if touches.size() >= 2:
			_update_pinch()
		elif drag.get("index", -1) == event.index:
			_update_drag(event.index, event.position)
		get_viewport().set_input_as_handled()


func _on_hud_button(pos: Vector2) -> bool:
	for b in _all_buttons(hud):
		if b.visible and b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	return false


func _all_buttons(n: Node) -> Array:
	var out := []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_buttons(c))
	return out


func _tray_part_at(pos: Vector2) -> String:
	if not tray.visible or tray_collapsed:
		return ""
	for item in tray_items.get_children():
		if item.get_global_rect().has_point(pos):
			return item.get_meta("part")
	return ""


func _tray_touch(part: String, index: int, pos: Vector2) -> void:
	if sim.running or run_ended:
		return
	if _tray_left(part) <= 0:
		_toast("No %s left" % PartRegistry.get_def(part).get("name", part))
		return
	if placements.size() >= level.slots:
		_toast("No slots left — remove a part first")
		return
	_note_first_touch()
	_begin_tray_drag(part, index, pos)


func _touch_down(index: int, pos: Vector2, double_tap: bool) -> void:
	if sim.running or run_ended:
		return
	if not _stage_viewport_rect().has_point(pos):
		return
	var wp := _screen_to_world(pos)
	# Rotation ring handle?
	if ring_visible:
		var handle := ring_pos + Vector2(RING_R, 0).rotated(Grid.steps_to_radians(placements[selected].rot))
		if wp.distance_to(handle) <= RING_GRAB / camera.zoom.x * fit_zoom:
			_note_first_touch()
			drag = {"kind": "rotate", "index": index, "start": pos, "start_rot": placements[selected].rot}
			return
		var d := wp.distance_to(ring_pos)
		if double_tap and absf(d - RING_R) <= RING_GRAB:
			_rotate_selected(6)
			return
	# A placed, movable part?
	var hit := _part_at(wp)
	if hit >= 0:
		_note_first_touch()
		drag = {"kind": "part", "index": index, "start": pos, "pidx": hit, "moved": false}
		return
	# Empty stage: double tap fits, single tap deselects.
	if double_tap:
		_fit_camera()
	selected = -1
	_refresh_hud()


func _begin_tray_drag(part: String, index: int, pos: Vector2) -> void:
	drag = {"kind": "tray", "index": index, "start": pos, "part": part}
	_spawn_floating(Placement.new(part, Vector2i.ZERO, 0))
	_update_drag(index, pos)


func _update_drag(_index: int, pos: Vector2) -> void:
	match drag.get("kind", ""):
		"tray":
			_move_floating(pos)
		"part":
			if not drag["moved"] and pos.distance_to(drag["start"]) > TAP_SLOP:
				# Promote tap to drag: lift the part off the stage.
				drag["moved"] = true
				var pl: Placement = placements[drag["pidx"]]
				drag["lifted"] = pl.duplicate_placement()
				_remove_placement_silent(drag["pidx"])
				selected = -1
				_spawn_floating(drag["lifted"])
			if drag["moved"]:
				_move_floating(pos)
		"rotate":
			var wp := _screen_to_world(pos)
			var ang := (wp - ring_pos).angle()
			var steps := Grid.radians_to_steps(ang)
			if steps != placements[selected].rot:
				placements[selected].rot = steps
				sim.set_player_parts(placements)
				_refresh_hud()


func _end_drag(_index: int, pos: Vector2) -> void:
	match drag.get("kind", ""):
		"tray":
			_drop_floating(pos, drag["part"], null)
		"part":
			if drag["moved"]:
				_drop_floating(pos, drag["lifted"].part, drag["lifted"])
			else:
				selected = drag["pidx"]
				_refresh_hud()
		"rotate":
			if placements[selected].rot != drag["start_rot"]:
				_commit_history_with_previous(drag["start_rot"])
	drag = {}


func _cancel_drag() -> void:
	if drag.get("kind", "") == "part" and drag.get("moved", false):
		# Put the lifted part back where it was.
		placements.append(drag["lifted"])
		sim.set_player_parts(placements)
	_clear_floating()
	drag = {}
	_refresh_hud()


## Rotation commits need the pre-rotation state in history, so rebuild that snapshot.
func _commit_history_with_previous(start_rot: int) -> void:
	var prev: Array[Placement] = []
	for p in placements:
		prev.append(p.duplicate_placement())
	prev[selected].rot = start_rot
	history.append(prev)
	future.clear()
	_refresh_hud()


func _part_at(wp: Vector2) -> int:
	var space := world.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = wp
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hits := space.intersect_point(q, 8)
	var best := -1
	for h in hits:
		var node: Node = h["collider"]
		if node.has_meta("is_fixed") and not node.get_meta("is_fixed"):
			var idx: int = int(node.get_meta("part_index")) - level.fixed.size()
			if idx >= 0 and idx < placements.size():
				best = idx
	if best >= 0:
		return best
	# Generous hit area for thin parts: nearest player part centre within half a tile.
	var nearest := -1
	var nd := Grid.TILE * 0.6
	for i in placements.size():
		var d := wp.distance_to(Grid.cell_to_world(placements[i].cell))
		if d < nd:
			nd = d
			nearest = i
	return nearest


# ------------------------------------------------------------------ floating part + ghost

func _spawn_floating(pl: Placement) -> void:
	_clear_floating()
	floating = PartFactory.create(pl, 9001, false)
	ghost = PartFactory.create(pl, 9002, false)
	for n in [floating, ghost]:
		if n:
			_disable_collisions(n)
			overlay.add_child(n)
	if ghost:
		ghost.set_ghost(true)
	drag["rot"] = pl.rot


func _move_floating(pos: Vector2) -> void:
	if floating == null:
		return
	var wp := _screen_to_world(pos) + LIFT / camera.zoom.x * fit_zoom
	floating.position = wp
	floating.rotation = Grid.steps_to_radians(drag["rot"])
	var cell := Grid.world_to_cell(wp)
	var over_tray := not _stage_viewport_rect().has_point(pos)
	ghost_valid = Grid.in_stage(cell) and not over_tray and not _overlaps(cell, drag["rot"])
	ghost.visible = not over_tray
	ghost.position = Grid.cell_to_world(cell)
	ghost.rotation = floating.rotation
	ghost.modulate = Color(1, 1, 1, 0.45) if ghost_valid else Color(1, 0.3, 0.3, 0.45)
	overlay.queue_redraw()


func _drop_floating(pos: Vector2, part: String, lifted: Placement) -> void:
	var wp := _screen_to_world(pos) + LIFT / camera.zoom.x * fit_zoom
	var cell := Grid.world_to_cell(wp)
	var over_tray := not _stage_viewport_rect().has_point(pos)
	_clear_floating()
	if over_tray:
		# Returned to the tray. If it came from the stage, that is a removal (undoable).
		if lifted != null:
			placements.append(lifted)
			sim.set_player_parts(placements)
			_push_history()
			placements.pop_back()
			sim.set_player_parts(placements)
			future.clear()
		_refresh_hud()
		return
	if not Grid.in_stage(cell) or _overlaps(cell, drag["rot"]):
		_toast("Can't place it there")
		if lifted != null:
			placements.append(lifted)
			sim.set_player_parts(placements)
		_refresh_hud()
		return
	if lifted != null:
		placements.append(lifted)  # restore then record the move as one history step
	_push_history()
	if lifted != null:
		placements.pop_back()
	placements.append(Placement.new(part, cell, drag["rot"]))
	selected = placements.size() - 1
	sim.set_player_parts(placements)
	_refresh_hud()


func _clear_floating() -> void:
	for n in [floating, ghost]:
		if n and is_instance_valid(n):
			n.queue_free()
	floating = null
	ghost = null
	overlay.queue_redraw()


func _disable_collisions(n: Node) -> void:
	if n is CollisionObject2D:
		n.collision_layer = 0
		n.collision_mask = 0
	for c in n.get_children():
		_disable_collisions(c)


## True when a part of this kind at (cell, rot) would overlap an existing part.
func _overlaps(cell: Vector2i, rot: int) -> bool:
	if ghost == null:
		return false
	var space := world.get_world_2d().direct_space_state
	var def := PartRegistry.get_def(ghost.get_meta("part_id"))
	var shape := PartFactory.make_shape(def)
	if shape == null:
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(Grid.steps_to_radians(rot), Grid.cell_to_world(cell))
	q.collide_with_areas = false
	q.margin = -2.0
	var hits := space.intersect_shape(q, 8)
	for h in hits:
		var node: Node = h["collider"]
		if node.has_meta("part_index") and int(node.get_meta("part_index")) < 9000:
			return true
	return false


# ------------------------------------------------------------------ pinch / pan

func _begin_pinch() -> void:
	var pts := touches.values()
	pinch_start_dist = pts[0].distance_to(pts[1])
	pinch_start_zoom = camera.zoom.x
	pinch_start_cam = camera.position
	pinch_start_mid = (pts[0] + pts[1]) / 2.0


func _update_pinch() -> void:
	var pts := touches.values()
	if pts.size() < 2 or pinch_start_dist <= 0.0:
		return
	var dist: float = pts[0].distance_to(pts[1])
	var mid: Vector2 = (pts[0] + pts[1]) / 2.0
	var z: float = clampf(pinch_start_zoom * dist / pinch_start_dist, fit_zoom, fit_zoom * 3.0)
	camera.zoom = Vector2(z, z)
	camera.position = pinch_start_cam - (mid - pinch_start_mid) / z
	_clamp_camera()


# ------------------------------------------------------------------ editing ops

func _push_history() -> void:
	var snap: Array[Placement] = []
	for p in placements:
		snap.append(p.duplicate_placement())
	history.append(snap)
	future.clear()


func _restore(snap: Array) -> void:
	placements = []
	for p in snap:
		placements.append(p.duplicate_placement())
	selected = -1
	sim.set_player_parts(placements)
	_refresh_hud()


func _undo() -> void:
	if history.is_empty():
		return
	var cur: Array[Placement] = []
	for p in placements:
		cur.append(p.duplicate_placement())
	future.append(cur)
	_restore(history.pop_back())


func _redo() -> void:
	if future.is_empty():
		return
	var cur: Array[Placement] = []
	for p in placements:
		cur.append(p.duplicate_placement())
	history.append(cur)
	_restore(future.pop_back())


func _remove_placement_silent(idx: int) -> void:
	placements.remove_at(idx)
	sim.set_player_parts(placements)


func _rotate_selected(steps: int) -> void:
	if selected < 0 or sim.running or run_ended:
		return
	_note_first_touch()
	_push_history()
	placements[selected].rot = Grid.wrap_steps(placements[selected].rot + steps)
	sim.set_player_parts(placements)
	_refresh_hud()


func _toggle_tray() -> void:
	tray_collapsed = not tray_collapsed
	tray.custom_minimum_size.y = TRAY_TAB_H + 24 if tray_collapsed else TRAY_H
	tray.offset_top = -tray.custom_minimum_size.y
	for c in tray.get_child(0).get_children():
		if c != tray_tab:
			c.visible = not tray_collapsed
	tray.visible = true
	_fit_camera()
	_refresh_hud()
	tray.visible = not sim.running


func _note_first_touch() -> void:
	if first_touch_msec < 0:
		first_touch_msec = Time.get_ticks_msec()


# ------------------------------------------------------------------ play / stop

func _toggle_play() -> void:
	if sim.running or run_ended:
		_stop_run()
	else:
		_start_run()


func _start_run() -> void:
	if placements.is_empty() and level.slots > 0:
		_toast("Place a part first")
		return
	_cancel_drag()
	selected = -1
	run_ended = false
	result_panel.visible = false
	sim.set_player_parts(placements)
	sim.start()
	_refresh_hud()


func _stop_run() -> void:
	run_ended = false
	result_panel.visible = false
	sim.stop()
	sim.rebuild()
	_refresh_hud()


func _on_run_finished(outcome: Dictionary) -> void:
	run_ended = true
	match outcome["result"]:
		"goal":
			solved_msec = Time.get_ticks_msec()
			var secs := (solved_msec - first_touch_msec) / 1000.0 if first_touch_msec >= 0 else 0.0
			result_lbl.text = "Solved!\n%d part%s · %.1f s" % [outcome["parts_used"], "" if outcome["parts_used"] == 1 else "s", secs]
			result_panel.visible = true
		"stalled":
			_toast("Everything stopped. Press STOP to rewind.")
		"timeout":
			_toast("Time's up. Press STOP to rewind.")
	_refresh_hud()


# ------------------------------------------------------------------ drawing

func _draw_stage() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(Grid.STAGE_PX))
	stage_bg.draw_rect(r.grow(8), C_INK)
	stage_bg.draw_rect(r, C_STAGE)
	# Quarter-tile dots at tile corners so the snap grid is visible but quiet.
	for y in range(0, Grid.STAGE_CELLS.y + 1, 4):
		for x in range(0, Grid.STAGE_CELLS.x + 1, 4):
			stage_bg.draw_circle(Grid.cell_to_world(Vector2i(x, y)), 3.0, C_GRID)


func _draw_overlay() -> void:
	if ring_visible and selected >= 0 and selected < placements.size():
		var rot := Grid.steps_to_radians(placements[selected].rot)
		overlay.draw_arc(ring_pos, RING_R, 0, TAU, 64, Color(C_INK, 0.35), 10.0, true)
		# Tick marks every 15 degrees, bolder every 90.
		for i in Grid.ROT_STEPS:
			var a := Grid.steps_to_radians(i)
			var inner := RING_R - (18.0 if i % 6 == 0 else 8.0)
			overlay.draw_line(ring_pos + Vector2(inner, 0).rotated(a), ring_pos + Vector2(RING_R + 6, 0).rotated(a), Color(C_INK, 0.5), 3.0)
		var handle := ring_pos + Vector2(RING_R, 0).rotated(rot)
		overlay.draw_line(ring_pos, handle, Color(C_ACCENT, 0.6), 4.0)
		overlay.draw_circle(handle, RING_HANDLE_R, C_INK)
		overlay.draw_circle(handle, RING_HANDLE_R - 6.0, C_ACCENT)
	if ghost and ghost.visible:
		# Landing crosshair.
		var p := ghost.position
		var c := Color(C_INK, 0.5) if ghost_valid else C_BAD
		overlay.draw_line(p + Vector2(-20, 0), p + Vector2(20, 0), c, 3.0)
		overlay.draw_line(p + Vector2(0, -20), p + Vector2(0, 20), c, 3.0)


func _toast(msg: String) -> void:
	toast_lbl.text = msg
	toast_lbl.visible = true
	var t := get_tree().create_timer(2.2)
	t.timeout.connect(func() -> void:
		if toast_lbl.text == msg:
			toast_lbl.visible = false)


# ------------------------------------------------------------------ smoke test (CI)
## Drives the real input path with synthetic touches: drag a plank from the tray to the
## reference cell, rotate it with the ring, press PLAY, wait for the result. Screenshots land in
## build/shots/. Exit code 0 only if the level is solved through the UI.

func _run_smoke() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var shots_dir := "res://../build/shots"
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var ok := true
	_shot(shots_dir + "/01_start.png")
	# 1. Drag from tray item to the reference cell.
	var item: Control = tray_items.get_child(0)
	var from: Vector2 = item.get_global_rect().get_center()
	var target: Placement = level.reference_solution[0]
	var to: Vector2 = _world_to_screen(Grid.cell_to_world(target.cell) - LIFT)
	await _synthetic_drag(0, from, to, 12)
	_shot(shots_dir + "/02_dropped.png")
	ok = ok and _assert(placements.size() == 1, "one part placed")
	ok = ok and _assert(placements[0].cell == target.cell, "landed on cell %s (got %s)" % [target.cell, placements[0].cell if placements.size() else "none"])
	ok = ok and _assert(selected == 0, "dropped part is selected")
	# 2. Rotate with the ring handle to the reference rotation.
	var handle_from: Vector2 = _world_to_screen(ring_pos + Vector2(RING_R, 0).rotated(Grid.steps_to_radians(placements[0].rot)))
	var handle_to: Vector2 = _world_to_screen(ring_pos + Vector2(RING_R, 0).rotated(Grid.steps_to_radians(target.rot)))
	await _synthetic_drag(0, handle_from, handle_to, 10)
	_shot(shots_dir + "/03_rotated.png")
	ok = ok and _assert(placements[0].rot == target.rot, "rotated to %d (got %d)" % [target.rot, placements[0].rot])
	# 3. Undo / redo round trip.
	_undo()
	ok = ok and _assert(placements[0].rot != target.rot, "undo reverted rotation")
	_redo()
	ok = ok and _assert(placements[0].rot == target.rot, "redo restored rotation")
	# 4. Play and wait.
	_start_run()
	ok = ok and _assert(sim.running, "simulation running after PLAY")
	await get_tree().create_timer(1.0).timeout
	_shot(shots_dir + "/04_running.png")
	var outcome: Dictionary = await sim.finished
	await get_tree().create_timer(0.5).timeout
	_shot(shots_dir + "/05_result.png")
	ok = ok and _assert(outcome["result"] == "goal", "level solved through the UI (result=%s)" % outcome["result"])
	ok = ok and _assert(result_panel.visible, "result panel shown")
	# 5. Stop rewinds.
	_stop_run()
	await get_tree().process_frame
	ok = ok and _assert(not sim.running and not run_ended, "stop rewound")
	_shot(shots_dir + "/06_rewound.png")
	print("SMOKE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _assert(cond: bool, what: String) -> bool:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	return cond


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)


## Positions are viewport (design) coordinates; Input.parse_input_event wants window coordinates,
## so apply the stretch transform the way the OS layer would have.
func _synthetic_drag(index: int, from_vp: Vector2, to_vp: Vector2, steps: int) -> void:
	var xf := get_viewport().get_final_transform()
	var from := xf * from_vp
	var to := xf * to_vp
	var down := InputEventScreenTouch.new()
	down.index = index
	down.position = from
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	for i in range(1, steps + 1):
		var mv := InputEventScreenDrag.new()
		mv.index = index
		mv.position = from.lerp(to, float(i) / steps)
		mv.relative = (to - from) / steps
		Input.parse_input_event(mv)
		await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = index
	up.position = to
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame
