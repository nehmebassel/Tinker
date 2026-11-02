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
const TOP_BAR_H := 236.0  # 72 title row + 132 buttons + margins
const TRAY_H := 320.0
const TRAY_TAB_H := 72.0
const BTN := 132.0  # touch target in px at design width
const LIFT := Vector2(0, -Grid.TILE * 1.25)  # part floats above the finger
const TAP_SLOP := 14.0  # px of movement before a touch counts as a drag
const RING_R := 150.0
const RING_HANDLE_R := 34.0
const RING_GRAB := 70.0

const C_BG := Color("fbf6ea")
const C_STAGE := Color("fdfaf1")
const C_GRID := Color("e2ebf3")
const C_GRID_MAJOR := Color("bfd3e6")
const C_WALL := Color("cfb48a")
const C_WALL_HOLE := Color("a88d64")
const C_WOOD := Color("b07a45")
const C_INK := Color("1f1a2e")
const C_ACCENT := Color("ff5d73")
const C_GO := Color("7bd389")
const C_PANEL := Color("2d2a4a")
const C_PANEL_TXT := Color("fbf6ea")
const C_BAD := Color("ff3b3b")

@export var level_path: String = LEVEL_PATH_DEFAULT
var level_number: int = 0  # campaign number when opened from the world select, else 0
var next_btn: Button
var levels_btn: Button
var back_btn: Button
var submit_btn: Button
var daily: Dictionary = {}  # set when playing the Daily (see App.daily)
var _solve_ms := 0  # Daily: time from first touch to THIS solve, frozen when the run reached the goal

var level: LevelData
var sim: Simulation
var sounds: SoundWatcher
var info_card: PartInfoCard = null
var tutorial: Tutorial = null
## "campaign" | "daily" | "edit" (sandbox: build the layout) | "verify" (sandbox: author solves it to
## publish) | "shared" (a published level opened from a code or link). See App.sandbox.
var mode: String = "campaign"
var sandbox_index: int = -1
var setup_btn: Button  # editor: opens the level setup (goal, player parts, slots, title)
var publish_btn: Button
var remix_btn: Button
var copy_btn: Button
var edit_btn: Button
var _published_code := ""
var last_result: String = ""  # result of the last finished run ("" while editing / running)
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
var result_face: Control  # sad face, failure only
var again_btn: Button
var tries_badge: Control  # hearts in the top bar
var tries_lbl: Label  # refill countdown next to the hearts
var _out_of_tries := false
var _rope_preview: Dictionary = {}  # while dragging a rope: {"a": snap point, "b": target} (see rope.gd)
const RopeScript := preload("res://scripts/parts/rope.gd")
const ROPE_MAGNET_CELLS := 3.0  # a dragged rope end jumps to a snap point this close

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
var _shot_cards_dir: String = ""  # --shot-cards=dir: one PNG per part info card (docs / review)
var shot_path: String = ""  # --shot=path: render the level, save a PNG, quit (for docs/CI)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level_path = a.trim_prefix("--level=")
		elif a == "--smoke":
			smoke_mode = true
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-cards="):
			_shot_cards_dir = a.trim_prefix("--shot-cards=")
	_build_scene()
	level_number = App.level_number if has_node("/root/App") else 0
	daily = App.daily if has_node("/root/App") else {}
	var sb: Dictionary = App.sandbox if has_node("/root/App") else {}
	if not sb.is_empty():
		mode = str(sb["mode"])
		sandbox_index = int(sb.get("index", -1))
		_load_sandbox(sb)
	elif not daily.is_empty():
		mode = "daily"
		_load_level_data(LevelData.from_dict(daily["level"]))
	else:
		if level_number > 0:
			level_path = Campaign.path_for(level_number)
		_load_level(level_path)
	get_viewport().size_changed.connect(_on_resized)
	_fit_camera()
	_music("build")
	if level_number == 1 and daily.is_empty() and has_node("/root/App") and not App.settings.tutorial_done and not smoke_mode and shot_path == "":
		tutorial = Tutorial.start(hud, self)
		tutorial.top_offset = TOP_BAR_H
		tutorial.bottom_offset = TRAY_H
	if smoke_mode:
		_run_smoke()
	elif shot_path != "":
		_run_shot()
	elif _shot_cards_dir != "":
		_run_shot_cards()


# ------------------------------------------------------------------ scene construction

func _build_scene() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100  # below the board (z -10) and the parts' back layers (z -1)
	add_child(bg)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	stage_bg = Node2D.new()
	stage_bg.name = "StageBackground"
	stage_bg.draw.connect(_draw_stage)
	stage_bg.z_index = -10  # behind parts' own back layers (e.g. the inside of the basket, z -1)
	world.add_child(stage_bg)
	sim = Simulation.new()
	sim.name = "Simulation"
	sim.finished.connect(_on_run_finished)
	world.add_child(sim)
	sounds = SoundWatcher.new()
	sounds.name = "SoundWatcher"
	sounds.watch(sim)
	add_child(sounds)
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
	# Top bar: two rows. Row 1: back, title, counter. Row 2: Undo Redo Turn 90 Fit (132 px targets).
	# Two rows because a one-row bar leaves ~200 px for the title at 1080 wide, which is not a title.
	var top := PanelContainer.new()
	top.name = "TopBar"
	top.add_theme_stylebox_override("panel", _panel_style(C_PANEL, 0))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_BAR_H
	hud.add_child(top)
	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 8)
	top.add_child(top_v)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 16)
	top_v.add_child(row1)
	back_btn = _button("<", 96)
	back_btn.custom_minimum_size = Vector2(96, 72)
	back_btn.pressed.connect(_go_back)
	row1.add_child(back_btn)
	title_lbl = _label("", 40, C_PANEL_TXT)
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(title_lbl)
	tries_badge = Control.new()
	tries_badge.name = "TriesBadge"
	tries_badge.custom_minimum_size = Vector2(130, 72)
	tries_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tries_badge.draw.connect(func() -> void:
		if _has_app():
			FailArt.hearts(tries_badge, Vector2(0, 20), App.tries.left(_now()), App.tries.limit, 34.0))
	row1.add_child(tries_badge)
	tries_lbl = _label("", 24, Color(C_PANEL_TXT, 0.75))
	tries_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(tries_lbl)
	counter_lbl = _label("", 30, Color(C_PANEL_TXT, 0.8))
	counter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(counter_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	row2.alignment = BoxContainer.ALIGNMENT_END
	top_v.add_child(row2)
	undo_btn = _button("Undo", BTN)
	undo_btn.pressed.connect(_undo)
	row2.add_child(undo_btn)
	redo_btn = _button("Redo", BTN)
	redo_btn.pressed.connect(_redo)
	row2.add_child(redo_btn)
	rot_btn = _button("Turn", BTN)
	rot_btn.pressed.connect(func() -> void: _rotate_selected(1))
	row2.add_child(rot_btn)
	rot90_btn = _button("90°", BTN)
	rot90_btn.pressed.connect(func() -> void: _rotate_selected(6))
	row2.add_child(rot90_btn)
	fit_btn = _button("Fit", BTN)
	fit_btn.pressed.connect(_fit_camera)
	row2.add_child(fit_btn)
	setup_btn = _button("Next", BTN)
	setup_btn.name = "SetupButton"
	setup_btn.add_theme_stylebox_override("normal", _round_style(C_GO))
	setup_btn.add_theme_stylebox_override("hover", _round_style(C_GO))
	setup_btn.add_theme_color_override("font_color", C_INK)
	setup_btn.pressed.connect(_open_setup)
	setup_btn.visible = false
	row2.add_child(setup_btn)

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
	play_btn = _button("RUN", BTN * 1.5)
	play_btn.name = "RunButton"
	play_btn.add_theme_font_size_override("font_size", 40)
	play_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Drawn icon (play triangle / stop square) above the label, and a glossy highlight.
	var run_icon := Control.new()
	run_icon.name = "RunIcon"
	run_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_icon.draw.connect(func() -> void: _draw_run_icon(run_icon))
	play_btn.add_child(run_icon)
	play_btn.add_theme_stylebox_override("normal", _run_style(C_GO))
	play_btn.add_theme_stylebox_override("pressed", _run_style(C_GO.darkened(0.2)))
	play_btn.add_theme_stylebox_override("hover", _run_style(C_GO))
	play_btn.add_theme_color_override("font_color", C_INK)
	play_btn.pressed.connect(_toggle_play)
	play_btn.set_meta("no_tap", true)  # has its own start / rewind sound
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
	result_face = Control.new()
	result_face.name = "SadFace"
	result_face.custom_minimum_size = Vector2(160, 150)
	result_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_face.draw.connect(func() -> void: FailArt.sad_face(result_face, result_face.size / 2.0, 66.0))
	result_face.visible = false
	rv2.add_child(result_face)
	result_lbl = _label("", 44, C_PANEL_TXT)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv2.add_child(result_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	rv2.add_child(row)
	var again := _button("      Try again", BTN)
	again.name = "TryAgain"
	again.custom_minimum_size.x = 300
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(22, 34)
	icon.size = Vector2(64, 64)
	icon.draw.connect(func() -> void: FailArt.retry(icon, Vector2(32, 32), 22.0, C_PANEL_TXT if not again.disabled else Color(C_PANEL_TXT, 0.35)))
	again.add_child(icon)
	again.pressed.connect(func() -> void:
		result_panel.visible = false
		_stop_run())
	row.add_child(again)
	again_btn = again
	levels_btn = _button("Levels", BTN)
	levels_btn.pressed.connect(func() -> void: App.open_world_select())
	row.add_child(levels_btn)
	next_btn = _button("Next", BTN)
	next_btn.add_theme_stylebox_override("normal", _round_style(C_GO))
	next_btn.add_theme_stylebox_override("hover", _round_style(C_GO))
	next_btn.add_theme_color_override("font_color", C_INK)
	next_btn.pressed.connect(func() -> void: App.open_level(level_number + 1))
	row.add_child(next_btn)
	submit_btn = _button("Submit", BTN)
	submit_btn.add_theme_stylebox_override("normal", _round_style(C_GO))
	submit_btn.add_theme_stylebox_override("hover", _round_style(C_GO))
	submit_btn.add_theme_color_override("font_color", C_INK)
	submit_btn.pressed.connect(_submit_daily)
	submit_btn.visible = false
	row.add_child(submit_btn)
	publish_btn = _go_button("Publish", _publish)
	publish_btn.name = "PublishButton"
	row.add_child(publish_btn)
	copy_btn = _go_button("Copy link", _copy_link)
	copy_btn.name = "CopyLinkButton"
	row.add_child(copy_btn)
	remix_btn = _button("Remix", BTN)
	remix_btn.name = "RemixButton"
	remix_btn.pressed.connect(_remix)
	row.add_child(remix_btn)
	edit_btn = _button("Edit", BTN)
	edit_btn.name = "EditButton"
	edit_btn.pressed.connect(func() -> void: _save_draft_layout(); App.open_sandbox_level("edit", sandbox_index))
	row.add_child(edit_btn)
	for b in [publish_btn, copy_btn, remix_btn, edit_btn]:
		b.visible = false


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
	UiKit.key_shadow(s)
	return s


## RUN / STOP: label sits low (the icon is drawn above it), thicker ink border, deeper shadow.
func _run_style(c: Color) -> StyleBoxFlat:
	var st := _round_style(c)
	st.content_margin_top = 84
	st.content_margin_bottom = 8
	st.set_border_width_all(6)
	st.shadow_size = 4
	st.shadow_offset = Vector2(0, 9)
	st.set_corner_radius_all(36)
	return st


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
	var l := LevelData.load_from_file(path)
	if l == null:
		title_lbl.text = "Level failed to load"
		return
	_load_level_data(l)


func _load_level_data(l: LevelData) -> void:
	level = l
	placements = []
	history = []
	future = []
	selected = -1
	first_touch_msec = -1
	run_ended = false
	sim.load_level(level)
	if not daily.is_empty():
		title_lbl.text = "Daily · Day %d" % int(daily.get("day", 0))
	else:
		title_lbl.text = ("%d · " % level_number if level_number > 0 else "") + level.title
	back_btn.visible = level_number > 0 or not daily.is_empty() or mode in ["edit", "verify", "shared"]
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
	holder.position = Vector2(110, 78)
	item.add_child(holder)
	var preview := PartFactory.create(Placement.new(part, Vector2i.ZERO, 0), 9000, false)
	if preview:
		_disable_collisions(preview)
		var def := PartRegistry.get_def(part)
		var s: Dictionary = def["shape"]
		var w: float = float(s.get("w", s.get("radius", 40) * 2.0))
		var h: float = float(s.get("h", s.get("radius", 40) * 2.0))
		var k: float = minf(170.0 / maxf(w, 1.0), 90.0 / maxf(h, 1.0))
		preview.scale = Vector2(k, k)
		holder.add_child(preview)
	# "i" badge: what does this part do? (opens the info card with a live demo)
	var info := PanelContainer.new()
	info.name = "Info"
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color("6ec6ff")
	ist.set_corner_radius_all(28)
	ist.border_color = C_INK
	ist.set_border_width_all(4)
	info.add_theme_stylebox_override("panel", ist)
	info.custom_minimum_size = Vector2(56, 56)
	info.size = Vector2(56, 56)
	info.position = Vector2(220 - 56 - 8, 8)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var il := _label("i", 34, C_INK)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(il)
	var badge_holder := Control.new()  # PanelContainer stretches direct children; this keeps the corner spot
	badge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_holder.add_child(info)
	item.add_child(badge_holder)
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
		item.get_node("Count").text = ("%s  ∞" % def.get("name", part)) if mode == "edit" else ("%s  ×%d" % [def.get("name", part), left])
		item.modulate.a = 1.0 if left > 0 else 0.4


func _tray_left(part: String) -> int:
	var used := 0
	for p in placements:
		if p.part == part:
			used += 1
	return int(level.tray.get(part, 0)) - used


func _refresh_hud() -> void:
	var editing := not sim.running and not run_ended
	counter_lbl.text = ("%d parts" % placements.size() if mode == "edit" else "%d / %d parts" % [placements.size(), level.slots]) if level else ""
	undo_btn.disabled = history.is_empty() or not editing
	redo_btn.disabled = future.is_empty() or not editing
	rot_btn.disabled = selected < 0 or not editing
	rot90_btn.disabled = rot_btn.disabled
	setup_btn.visible = mode == "edit" and editing
	tries_badge.visible = mode in ["campaign", "daily"]
	tries_lbl.visible = tries_badge.visible
	play_btn.text = "STOP" if (sim.running or run_ended) else ("TEST" if mode == "edit" else "RUN")
	play_btn.get_node("RunIcon").queue_redraw()
	play_btn.add_theme_stylebox_override("normal", _run_style(C_ACCENT if (sim.running or run_ended) else C_GO))
	play_btn.add_theme_stylebox_override("hover", _run_style(C_ACCENT if (sim.running or run_ended) else C_GO))
	play_btn.add_theme_stylebox_override("pressed", _run_style((C_ACCENT if (sim.running or run_ended) else C_GO).darkened(0.2)))
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
	if (info_card != null and is_instance_valid(info_card)) or hud.has_node("SandboxSetup"):
		return  # modal overlays (part card, sandbox setup) get the touches
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
	var item := tray_items.get_node_or_null("Tray_" + part)
	if item and item.find_child("Info", true, false).get_global_rect().grow(18).has_point(pos):
		open_info(part)
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
	# A fixed part: show what it does.
	var fixed_id := _fixed_part_at(wp)
	if fixed_id != "" and not double_tap:
		open_info(fixed_id)
		return
	# Empty stage: double tap fits, single tap deselects.
	if double_tap:
		_fit_camera()
	selected = -1
	_refresh_hud()


func _begin_tray_drag(part: String, index: int, pos: Vector2) -> void:
	drag = {"kind": "tray", "index": index, "start": pos, "part": part}
	_spawn_floating(Placement.new(part, Vector2i.ZERO, 0))
	_snd("pick")
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
				_snd("pick")
			if drag["moved"]:
				_move_floating(pos)
		"rotate":
			var wp := _screen_to_world(pos)
			var ang := (wp - ring_pos).angle()
			var steps := Grid.radians_to_steps(ang)
			if steps != placements[selected].rot:
				placements[selected].rot = steps
				sim.set_player_parts(placements)
				_snd("rotate", -6.0)
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


func _fixed_part_at(wp: Vector2) -> String:
	var space := world.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = wp
	q.collide_with_areas = false
	q.collide_with_bodies = true
	for h in space.intersect_point(q, 8):
		var node: Node = h["collider"]
		if node.has_meta("is_fixed") and node.get_meta("is_fixed"):
			return str(node.get_meta("part_id"))
	return ""


func open_info(part: String) -> void:
	if info_card != null and is_instance_valid(info_card):
		return
	touches.clear()
	_cancel_drag()
	info_card = PartInfoCard.open(hud, part)


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
	_rope_preview = {}
	if ghost.get_meta("part_id") == "rope":
		cell = _snap_rope(wp, cell)
	ghost_valid = Grid.in_stage(cell) and not over_tray and not _overlaps(cell, drag["rot"])
	ghost.visible = not over_tray
	ghost.position = Grid.cell_to_world(cell)
	ghost.rotation = floating.rotation
	ghost.modulate = Color(1, 1, 1, 0.45) if ghost_valid else Color(1, 0.3, 0.3, 0.45)
	overlay.queue_redraw()


func _drop_floating(pos: Vector2, part: String, lifted: Placement) -> void:
	var wp := _screen_to_world(pos) + LIFT / camera.zoom.x * fit_zoom
	var cell := Grid.world_to_cell(wp)
	if part == "rope":
		cell = _snap_rope(wp, cell)
		var will := _rope_preview.duplicate()
		_rope_preview = {}
		if will.get("a", {}).is_empty():
			_toast("Drop the rope's end on a snap point (the rings)")
		elif will.get("b", {}).is_empty():
			_toast("Nothing to tie to in reach: point it at another snap point")
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
	_snd("place")
	_refresh_hud()


## Rope auto-snap: the end jumps to the nearest snap point and the rope aims at the nearest target
## (pulleys first). Returns the snapped cell; updates drag["rot"] and the preview drawn in the overlay.
func _snap_rope(wp: Vector2, cell: Vector2i) -> Vector2i:
	var maxc := int(PartRegistry.get_def("rope").get("max_length_cells", 30))
	var a := RopeScript.snap_a(sim.parts, wp, ROPE_MAGNET_CELLS * Grid.CELL)
	if not a.is_empty():
		cell = Grid.world_to_cell(a["pos"])
		var r := RopeScript.best_rot(sim.parts, cell, int(drag.get("rot", 0)), maxc)
		if r >= 0:
			drag["rot"] = r
			if floating:
				floating.rotation = Grid.steps_to_radians(r)
	_rope_preview = RopeScript.resolve(sim.parts, cell, int(drag.get("rot", 0)), maxc)
	return cell


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
	var part_id: String = ghost.get_meta("part_id")
	for h in hits:
		var node: Node = h["collider"]
		if not node.has_meta("part_index") or int(node.get_meta("part_index")) >= 9000:
			continue
		if _attaches(part_id, cell, node):
			continue  # same-cell attachment (plank/conveyor/pulley on a motor), not an overlap
		return true
	return false


## A motor and a plank/conveyor/pulley on the SAME cell are an attachment, which the editor must
## allow even though their shapes intersect (see docs/DESIGN.md "Parts").
const ATTACHES_TO_MOTOR := ["plank", "conveyor", "pulley"]


func _attaches(part_id: String, cell: Vector2i, other: Node) -> bool:
	if Vector2i(other.get_meta("cell")) != cell:
		return false
	var other_id: String = other.get_meta("part_id")
	return (part_id == "motor" and other_id in ATTACHES_TO_MOTOR) or (other_id == "motor" and part_id in ATTACHES_TO_MOTOR)


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
	_snd("rotate")
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
	if not daily.is_empty():
		App.daily_store.start_clock(daily["date"])  # persists: closing the app does not reset it


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
	if _has_app() and App.tries.left(_now()) <= 0:
		_show_out_of_tries()
		return
	_cancel_drag()
	selected = -1
	run_ended = false
	result_panel.visible = false
	sim.set_player_parts(placements)
	sounds.reset()
	last_result = ""
	sim.start()
	_snd("play")
	_music("run")
	_refresh_hud()


func _stop_run() -> void:
	run_ended = false
	result_panel.visible = false
	var was_live := sim.running or run_ended
	sim.stop()
	sim.rebuild()
	sounds.reset()
	if was_live:
		_snd("rewind")
	_music("build")
	_refresh_hud()


func _on_run_finished(outcome: Dictionary) -> void:
	run_ended = true
	last_result = str(outcome["result"])
	sounds.reset()
	_snd("goal" if outcome["result"] == "goal" else "fail")
	if outcome["result"] == "goal":
		_confetti()
	if mode == "edit":
		_toast("Test run: goal reached!" if outcome["result"] == "goal" else "Test run: the machine stopped. Press STOP to edit.")
		_refresh_hud()
		return
	for b in [publish_btn, copy_btn, remix_btn, edit_btn]:
		b.visible = false
	match outcome["result"]:
		"goal":
			result_face.visible = false
			again_btn.disabled = false
			_out_of_tries = false
			solved_msec = Time.get_ticks_msec()
			var secs := (solved_msec - first_touch_msec) / 1000.0 if first_touch_msec >= 0 else 0.0
			result_lbl.text = "Solved!\n%d part%s · %.1f s" % [outcome["parts_used"], "" if outcome["parts_used"] == 1 else "s", secs]
			if level_number > 0:
				var new_best := App.save.record_solve(level_number, int(outcome["parts_used"]), int(secs * 1000.0), placements)
				if new_best:
					result_lbl.text += "\nNew best!"
			next_btn.visible = level_number > 0 and App.has_next(level_number)
			levels_btn.visible = level_number > 0
			if not daily.is_empty():
				_solve_ms = App.daily_store.elapsed_ms(daily["date"])
				var ms: int = _solve_ms
				result_lbl.text = "Solved!\n%d part%s · %s\nSubmit is final: one entry per day." % [outcome["parts_used"], "" if outcome["parts_used"] == 1 else "s", _fmt_ms(ms)]
			submit_btn.visible = not daily.is_empty()
			if mode == "verify":
				result_lbl.text = "You solved your level with %d part%s.\nPublish it to get a link." % [outcome["parts_used"], "" if outcome["parts_used"] == 1 else "s"]
				publish_btn.visible = true
				edit_btn.visible = true
			elif mode == "shared":
				var ap := int(App.sandbox.get("author_parts", 0))
				result_lbl.text = "Solved!\n%d part%s (the author used %d)" % [outcome["parts_used"], "" if outcome["parts_used"] == 1 else "s", ap]
				remix_btn.visible = true
			result_panel.visible = true
		"stalled", "timeout":
			_show_failure(str(outcome["result"]))
	_refresh_hud()


## The machine stopped (or ran out of time) without reaching the goal: say so, cost one try.
func _show_failure(why: String) -> void:
	var left := 99
	if _has_app():
		left = App.tries.use(_now())
	result_face.visible = true
	next_btn.visible = false
	submit_btn.visible = false
	levels_btn.visible = level_number > 0
	var head := "Everything stopped." if why == "stalled" else "Time's up."
	remix_btn.visible = mode == "shared"
	edit_btn.visible = mode == "verify"
	if not _has_app():
		result_lbl.text = "%s\nThe goal wasn't reached." % head
		_out_of_tries = false
		result_panel.visible = true
		again_btn.queue_redraw()
		return
	if left > 0:
		result_lbl.text = "%s\nThe goal wasn't reached.\n%d tr%s left" % [head, left, "y" if left == 1 else "ies"]
		_out_of_tries = false
		again_btn.disabled = false
	else:
		_out_of_tries = true
		again_btn.disabled = false
		_update_out_of_tries_text(head + "\nThe goal wasn't reached.")
	result_panel.visible = true
	again_btn.queue_redraw()
	tries_badge.queue_redraw()


func _show_out_of_tries() -> void:
	result_face.visible = true
	next_btn.visible = false
	submit_btn.visible = false
	levels_btn.visible = level_number > 0
	_out_of_tries = true
	again_btn.disabled = false
	_update_out_of_tries_text("Out of tries.")
	result_panel.visible = true


func _update_out_of_tries_text(head: String) -> void:
	var wait := App.tries.seconds_to_refill(_now()) if _has_app() else 0
	result_lbl.set_meta("head", head)
	result_lbl.text = "%s\nNew tries in %s\nYou can keep building meanwhile." % [head, Tries.fmt_wait(wait)]


## Tries count in the campaign and the Daily only: the editor, the author's test and shared
## (community) levels are free to retry.
func _has_app() -> bool:
	return has_node("/root/App") and App.tries != null and mode in ["campaign", "daily"]


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


# ------------------------------------------------------------------ drawing

## Workbench look: pegboard wall, a wooden frame, and a blueprint-ruled sheet (minor line every
## tile, major every 4 tiles) so the snap grid reads as engineering paper. Drawn once per level.
func _draw_stage() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(Grid.STAGE_PX))
	# Pegboard wall around the stage (visible when zoomed out / at the edges).
	var wall := r.grow(1400)
	stage_bg.draw_rect(wall, C_WALL)
	var step := Grid.TILE
	var y := wall.position.y
	while y < wall.end.y:
		var x := wall.position.x
		while x < wall.end.x:
			if not r.grow(40).has_point(Vector2(x, y)):
				stage_bg.draw_circle(Vector2(x, y), 7.0, C_WALL_HOLE)
			x += step
		y += step
	# Frame: shadow, wood, ink edges, highlight, corner screws.
	stage_bg.draw_rect(Rect2(r.position + Vector2(14, 18), r.size).grow(30), Color(0, 0, 0, 0.18))
	stage_bg.draw_rect(r.grow(34), C_INK)
	stage_bg.draw_rect(r.grow(28), C_WOOD)
	stage_bg.draw_rect(Rect2(r.position - Vector2(24, 24), Vector2(r.size.x + 48, 8)), C_WOOD.lightened(0.25))
	for i in 6:
		var gy := -20.0 + i * (r.size.y + 40.0) / 5.0
		stage_bg.draw_line(Vector2(-26, gy), Vector2(-4, gy + 30), C_WOOD.darkened(0.2), 2.0)
		stage_bg.draw_line(Vector2(r.size.x + 4, gy), Vector2(r.size.x + 26, gy + 30), C_WOOD.darkened(0.2), 2.0)
	stage_bg.draw_rect(r.grow(6), C_INK)
	for c in [r.position + Vector2(-17, -17), Vector2(r.end.x + 17, r.position.y - 17), Vector2(r.position.x - 17, r.end.y + 17), r.end + Vector2(17, 17)]:
		stage_bg.draw_circle(c, 8.0, C_INK)
		stage_bg.draw_circle(c, 5.0, Color("c9c2b6"))
		stage_bg.draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), C_INK, 2.0)
	# Sheet.
	stage_bg.draw_rect(r, C_STAGE)
	var cells := Grid.STAGE_CELLS
	for gx in range(0, cells.x + 1, 4):
		var px := Grid.cell_to_world(Vector2i(gx, 0)).x
		var major := gx % 16 == 0
		stage_bg.draw_line(Vector2(px, 0), Vector2(px, r.size.y), C_GRID_MAJOR if major else C_GRID, 2.5 if major else 1.5)
	for gy in range(0, cells.y + 1, 4):
		var py := Grid.cell_to_world(Vector2i(0, gy)).y
		var major := gy % 16 == 0
		stage_bg.draw_line(Vector2(0, py), Vector2(r.size.x, py), C_GRID_MAJOR if major else C_GRID, 2.5 if major else 1.5)
	# Title-block corner, like a drawing sheet.
	var tb := Rect2(r.end - Vector2(300, 64), Vector2(300, 64))
	stage_bg.draw_rect(tb, Color(C_GRID_MAJOR, 0.35))
	stage_bg.draw_rect(tb, C_GRID_MAJOR, false, 2.0)


var _tick_acc := 0.0


func _process(delta: float) -> void:
	overlay.queue_redraw()
	# RUN breathes gently once there is something to run, so the next step is obvious.
	var ready := not sim.running and not run_ended and not placements.is_empty()
	play_btn.pivot_offset = play_btn.size / 2.0
	var k := 1.0 + (0.045 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)) if ready else 0.0)
	play_btn.scale = Vector2(k, k)
	_tick_acc += delta
	if _tick_acc < 0.5 or not _has_app():
		return
	_tick_acc = 0.0
	var now := _now()
	var wait := App.tries.seconds_to_refill(now)
	tries_lbl.text = Tries.fmt_wait(wait) if wait > 0 else ""
	tries_badge.queue_redraw()
	if _out_of_tries and result_panel.visible:
		if App.tries.left(now) > 0:
			_out_of_tries = false
			again_btn.disabled = false
			result_lbl.text = "Tries refilled!"
			again_btn.queue_redraw()
		else:
			_update_out_of_tries_text(str(result_lbl.get_meta("head", "Out of tries.")))


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
	if not sim.running:
		for p in sim.parts:
			if p.has_method("get_link_target") and p.get_link_target() != null:
				_draw_dashed(overlay, p.global_position + Vector2(0, -14), p.get_link_target().global_position, Color(C_INK, 0.45))
	_draw_rope_hints()
	if ghost and ghost.visible:
		# Landing crosshair.
		var p := ghost.position
		var c := Color(C_INK, 0.5) if ghost_valid else C_BAD
		overlay.draw_line(p + Vector2(-20, 0), p + Vector2(20, 0), c, 3.0)
		overlay.draw_line(p + Vector2(0, -20), p + Vector2(0, 20), c, 3.0)


# ------------------------------------------------------------------ sandbox (M5)

func _go_button(text: String, cb: Callable) -> Button:
	var b := _button(text, BTN)
	b.add_theme_stylebox_override("normal", _round_style(C_GO))
	b.add_theme_stylebox_override("hover", _round_style(C_GO))
	b.add_theme_color_override("font_color", C_INK)
	b.pressed.connect(cb)
	return b


func _draft() -> Dictionary:
	if sandbox_index < 0 or sandbox_index >= App.sandbox_store.drafts.size():
		return {}
	return App.sandbox_store.drafts[sandbox_index]


func _load_sandbox(sb: Dictionary) -> void:
	match mode:
		"edit":
			# The author builds the LAYOUT with every part, unlimited; these become the level's fixed parts.
			var d := _draft()
			var tray := []
			PartRegistry.ensure_loaded()
			for id in PartRegistry.defs.keys():
				tray.append({"part": id, "count": 99})
			var lv := {"id": "editor", "title": str(d.get("title", "My machine")), "goal": d.get("goal", {"type": "basket"}),
				"fixed": [], "tray": tray, "slots": 99, "reference_solution": []}
			_load_level_data(LevelData.from_dict(lv))
			for f in d.get("fixed", []):
				placements.append(Placement.from_dict(f))
			sim.set_player_parts(placements)
			title_lbl.text = "Editor · " + str(d.get("title", ""))
			_refresh_hud()
		"verify":
			var d := _draft()
			_load_level_data(LevelData.from_dict(SandboxStore.to_level(d, false)))
			title_lbl.text = "Test · " + str(d.get("title", ""))
			_published_code = str(d.get("published_id", ""))
		"shared":
			_load_level_data(LevelData.from_dict(sb["level"]))
			title_lbl.text = "%s · %s" % [str(sb.get("code", "")), str(sb["level"].get("title", ""))]


func _go_back() -> void:
	if mode == "edit":
		_save_draft_layout()
	if mode in ["edit", "verify", "shared"]:
		App.open_sandbox()
	else:
		App.open_world_select()


## Editor: the parts on the board ARE the level's fixed layout.
func _save_draft_layout() -> void:
	if mode != "edit" or sandbox_index < 0:
		return
	var d := _draft()
	if d.is_empty():
		return
	var fixed := []
	for p in placements:
		fixed.append(p.to_dict())
	if fixed != d.get("fixed", []):
		d["fixed"] = fixed
		d["solution"] = []  # the layout changed: the author must solve it again before publishing
		d["published_id"] = ""
	App.sandbox_store.put(sandbox_index, d)


func _exit_tree() -> void:
	if mode == "edit" and has_node("/root/App"):
		_save_draft_layout()


func _open_setup() -> void:
	_cancel_drag()
	_save_draft_layout()
	SandboxSetup.open(hud, sandbox_index)


func _publish() -> void:
	var d := _draft()
	if d.is_empty():
		return
	var sol := []
	for p in placements:
		sol.append(p.to_dict())
	var lv := SandboxStore.to_level(d, false)
	lv["reference_solution"] = sol
	publish_btn.disabled = true
	publish_btn.text = "Publishing…"
	var r: Dictionary = await App.api.post_json("/level", {"device_id": App.settings.device_id, "level": lv})
	publish_btn.disabled = false
	publish_btn.text = "Publish"
	if not r["ok"]:
		result_lbl.text = "Not published:\n" + str(r["error"])
		return
	_published_code = str(r["body"]["id"])
	d["solution"] = sol
	d["published_id"] = _published_code
	App.sandbox_store.put(sandbox_index, d)
	publish_btn.visible = false
	copy_btn.visible = true
	result_lbl.text = "Published! Code: %s\n%s" % [_published_code, App.share_link(_published_code)]
	_snd("goal")


func _copy_link() -> void:
	if _published_code == "":
		return
	var link := App.share_link(_published_code)
	DisplayServer.clipboard_set(link)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.share ? navigator.share({title: 'Tinker level', url: %s}).catch(function(){}) : 0" % JSON.stringify(link), true)
	_toast("Link copied: " + link)


func _remix() -> void:
	var lv: Dictionary = App.sandbox.get("level", {})
	var idx := App.sandbox_store.add(SandboxStore.remix_of(lv, str(App.sandbox.get("code", ""))))
	App.open_sandbox_level("edit", idx)


const HAPTIC_MS := {"pick": 10, "place": 18, "rotate": 6, "goal": 60}


## RUN / STOP icon: a fat play triangle or a stop square, plus a glossy top highlight.
func _draw_run_icon(n: Control) -> void:
	var sz := n.size
	var c := Vector2(sz.x / 2.0, sz.y * 0.36)
	var stopping := sim != null and (sim.running or run_ended)
	# Gloss band.
	var gloss := StyleBoxFlat.new()
	gloss.bg_color = Color(1, 1, 1, 0.22)
	gloss.set_corner_radius_all(20)
	n.draw_style_box(gloss, Rect2(Vector2(12, 9), Vector2(sz.x - 24, sz.y * 0.28)))
	var r := minf(sz.x, sz.y) * 0.2
	if stopping:
		var q := Rect2(c - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6)
		n.draw_rect(q.grow(4.0), C_INK)
		n.draw_rect(q, C_PANEL_TXT)
	else:
		var tri := PackedVector2Array([c + Vector2(-r * 0.75, -r), c + Vector2(r * 1.05, 0), c + Vector2(-r * 0.75, r)])
		var big := PackedVector2Array()
		for p in tri:
			big.append(c + (p - c) * 1.22)
		n.draw_colored_polygon(big, C_INK)
		n.draw_colored_polygon(tri, C_PANEL_TXT)


## Celebration burst from the top of the screen when a run reaches the goal. HUD layer only:
## it cannot touch the simulation. CPUParticles2D so it works in the web (Compatibility) build.
func _confetti() -> void:
	var vs := get_viewport_rect().size
	var colors := [C_ACCENT, C_GO, Color("6ec6ff"), Color("ffd43b"), Color("b35fd1"), Color("e8833a")]
	for i in 2:
		var p := CPUParticles2D.new()
		p.name = "Confetti%d" % i
		p.position = Vector2(vs.x * (0.3 + 0.4 * i), TOP_BAR_H - 20)
		p.amount = 70
		p.one_shot = true
		p.explosiveness = 0.9
		p.lifetime = 2.6
		p.direction = Vector2(0, 1)
		p.spread = 70.0
		p.initial_velocity_min = 380.0
		p.initial_velocity_max = 900.0
		p.gravity = Vector2(0, 900)
		p.angular_velocity_min = -420.0
		p.angular_velocity_max = 420.0
		p.scale_amount_min = 10.0
		p.scale_amount_max = 18.0
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.colors = PackedColorArray(colors)
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		p.color_initial_ramp = g
		hud.add_child(p)
		p.emitting = true
		get_tree().create_timer(3.5).timeout.connect(p.queue_free)


## Sounds go through App.audio; level scenes opened without App (tools, shots) stay silent.
func _snd(sound: String, gain_db: float = 0.0) -> void:
	if has_node("/root/App") and App.audio:
		App.audio.sfx(sound, gain_db)
		var ms: int = HAPTIC_MS.get(sound, 0)
		if ms > 0:
			App.audio.buzz(ms)


func _music(track: String) -> void:
	if has_node("/root/App") and App.audio:
		App.audio.play_music(track)


## Snap points: rings on every part a rope can tie to, shown while a rope is dragged or selected;
## the chosen end and target glow, joined by the rope it will make (green) or a red "no target".
func _draw_rope_hints() -> void:
	if sim.running or run_ended:
		return
	var dragging: bool = ghost != null and ghost.visible and ghost.get_meta("part_id") == "rope"
	var sel_rope: bool = selected >= 0 and selected < placements.size() and placements[selected].part == "rope"
	if not dragging and not sel_rope:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
	for a in RopeScript.anchors_of(sim.parts):
		overlay.draw_arc(a["pos"], 16.0, 0, TAU, 24, Color(C_INK, 0.55), 4.0, true)
		overlay.draw_circle(a["pos"], 5.0, Color(C_INK, 0.55))
	if not dragging:
		return
	var a: Dictionary = _rope_preview.get("a", {})
	var b: Dictionary = _rope_preview.get("b", {})
	if a.is_empty():
		return
	var ok := Color("2fbf71")
	overlay.draw_circle(a["pos"], 14.0 + 4.0 * pulse, Color(ok, 0.45))
	overlay.draw_arc(a["pos"], 18.0, 0, TAU, 24, ok, 5.0, true)
	if b.is_empty():
		var dir := RopeScript.dir_of(int(drag.get("rot", 0)))
		var end: Vector2 = a["pos"] + dir * Grid.CELL * 6.0
		_draw_dashed(overlay, a["pos"], end, C_BAD)
		overlay.draw_line(end + Vector2(-10, -10), end + Vector2(10, 10), C_BAD, 5.0)
		overlay.draw_line(end + Vector2(-10, 10), end + Vector2(10, -10), C_BAD, 5.0)
		return
	var bp: Vector2 = b["pos"]
	if b["node"].get_meta("part_id") == "pulley":
		bp = RopeScript.pulley_tangent(b["node"].global_position, b["node"].radius, a["pos"])
	overlay.draw_line(a["pos"], bp, Color(C_INK, 0.8), 9.0)
	overlay.draw_line(a["pos"], bp, Color("d9a066"), 5.0)
	overlay.draw_circle(b["pos"], 14.0 + 4.0 * pulse, Color(ok, 0.45))
	overlay.draw_arc(b["pos"], 18.0, 0, TAU, 24, ok, 5.0, true)


static func _fmt_ms(ms: int) -> String:
	var t := ms / 1000
	return "%d:%02d" % [t / 60, t % 60] if t >= 60 else "%.1f s" % (ms / 1000.0)


func _submit_daily() -> void:
	submit_btn.disabled = true
	submit_btn.text = "Checking…"
	var r: Dictionary = await App.submit_daily(placements, _solve_ms)
	if r["ok"] or r["status"] == 409:
		App.open_board(daily["date"])
		return
	submit_btn.disabled = false
	submit_btn.text = "Submit"
	_toast(str(r["error"]))


func _draw_dashed(on: CanvasItem, a: Vector2, b: Vector2, c: Color) -> void:
	var d := a.distance_to(b)
	var n := int(d / 18.0)
	for i in range(0, n, 2):
		on.draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(mini(i + 1, n)) / n), c, 3.0)
	on.draw_circle(b, 7.0, c)


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
	var outcome: Dictionary = await run_smoke_steps()
	var ok: bool = _smoke_ok and outcome.get("result", "") == "goal"
	print("SMOKE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


var _smoke_ok := true


## Drives the real input path: drag the first tray part to the reference cell, rotate it with the
## ring, undo/redo, PLAY, wait for the result, screenshot every step. Returns the outcome.
func run_smoke_steps() -> Dictionary:
	_smoke_ok = true
	await get_tree().process_frame
	await get_tree().process_frame
	var shots_dir := "res://../build/shots"
	DirAccess.make_dir_recursive_absolute(shots_dir)
	_shot(shots_dir + "/01_start.png")
	var vw := get_viewport_rect().size.x
	for b in [undo_btn, redo_btn, rot_btn, rot90_btn, fit_btn]:
		_assert(b.get_global_rect().end.x <= vw + 0.5, "%s inside the viewport (right edge %.0f <= %.0f)" % [b.text, b.get_global_rect().end.x, vw])
	var item: Control = tray_items.get_child(0)
	# Info card: tap the "i", the live demo must be running in its own world, then close it.
	await _tap_button(item.find_child("Info", true, false))
	_assert(info_card != null and is_instance_valid(info_card), "tapping i opens the part info card")
	if info_card != null and is_instance_valid(info_card):
		await get_tree().create_timer(1.5).timeout
		var demo: Simulation = info_card._sim
		_assert((demo.running or demo.ticks > 0) and demo.parts.size() > 0, "info card demo started (%d parts, %d ticks)" % [demo.parts.size(), demo.ticks])  # a short demo may already rest on its goal
		_assert(demo.get_viewport() != get_viewport(), "info card demo has its own viewport/world")
		_shot(shots_dir + "/00_info_card.png")
		await _tap_button(info_card.find_child("CloseInfo", true, false))
		await get_tree().process_frame
		_assert(info_card == null or not is_instance_valid(info_card), "Got it closes the card")
		_assert(placements.is_empty(), "opening the card placed nothing")
	var from: Vector2 = item.get_global_rect().get_center()
	var target: Placement = level.reference_solution[0]
	var to: Vector2 = _world_to_screen(Grid.cell_to_world(target.cell) - LIFT)
	await _synthetic_drag(0, from, to, 12)
	_shot(shots_dir + "/02_dropped.png")
	_assert(placements.size() == 1, "one part placed")
	_assert(placements.size() == 1 and placements[0].cell == target.cell, "landed on cell %s (got %s)" % [target.cell, placements[0].cell if placements.size() else "none"])
	_assert(selected == 0, "dropped part is selected")
	if placements.is_empty():
		return {}
	var rot_before: int = placements[0].rot  # a rope is auto-aimed on drop: the drag may be a no-op
	var handle_from: Vector2 = _world_to_screen(ring_pos + Vector2(RING_R, 0).rotated(Grid.steps_to_radians(placements[0].rot)))
	var handle_to: Vector2 = _world_to_screen(ring_pos + Vector2(RING_R, 0).rotated(Grid.steps_to_radians(target.rot)))
	await _synthetic_drag(0, handle_from, handle_to, 10)
	_shot(shots_dir + "/03_rotated.png")
	_assert(placements[0].rot == target.rot, "rotated to %d (got %d)" % [target.rot, placements[0].rot])
	if target.rot != 0 and rot_before != target.rot:
		_undo()
		_assert(placements[0].rot != target.rot, "undo reverted rotation")
		_redo()
		_assert(placements[0].rot == target.rot, "redo restored rotation")
	var outcome_box := {}
	sim.finished.connect(func(o: Dictionary) -> void: outcome_box["o"] = o, CONNECT_ONE_SHOT)
	await _tap_button(play_btn)
	_assert(sim.running, "simulation running after PLAY")
	await get_tree().create_timer(1.0).timeout
	_shot(shots_dir + "/04_running.png")
	while not outcome_box.has("o"):
		await get_tree().process_frame
	var outcome: Dictionary = outcome_box["o"]
	await get_tree().create_timer(0.5).timeout
	_shot(shots_dir + "/05_result.png")
	_assert(outcome["result"] == "goal", "level solved through the UI (result=%s)" % outcome["result"])
	_assert(result_panel.visible, "result panel shown")
	return outcome


func _run_shot() -> void:
	for i in 3:
		await get_tree().process_frame
	_shot(shot_path)
	if level and not level.reference_solution.is_empty():
		placements = []
		for p in level.reference_solution:
			placements.append(p.duplicate_placement())
		sim.set_player_parts(placements)
		_refresh_hud()
	_start_run()
	await get_tree().create_timer(1.0).timeout
	_shot(shot_path.get_basename() + "_run.png")
	get_tree().quit(0)


func _run_shot_cards() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_cards_dir)
	PartRegistry.ensure_loaded()
	for part in PartRegistry.defs.keys():
		open_info(part)
		await get_tree().create_timer(2.2).timeout
		_shot("%s/card_%s.png" % [_shot_cards_dir, part])
		info_card.close()
		info_card = null
		await get_tree().process_frame
	get_tree().quit(0)


func _tap_button(b: Control) -> void:
	var xf := get_viewport().get_final_transform()
	var p := xf * b.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = p
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().process_frame


func _assert(cond: bool, what: String) -> bool:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	_smoke_ok = _smoke_ok and cond
	return cond


func _shot(path: String) -> void:
	# Headless (dummy renderer) has no framebuffer: reading it only logs engine errors.
	if DisplayServer.get_name() == "headless":
		return
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
