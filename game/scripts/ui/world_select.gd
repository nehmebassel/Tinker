extends Control
## WorldSelect — the campaign MAP (M5 polish request): a blueprint sheet with a marble-run track
## winding through every level, like a Mario world map but built from engineering parts.
##
##   * Levels are gears on the track (green = solved, yellow pulse = next to play, world colour =
##     unlocked, grey bolt = locked). Each is a Button named "Level<n>" (the flow test taps them).
##   * The track is BUILT (brass rails on wooden sleepers) up to the current level and only drawn as
##     dashed blueprint lines beyond it: progress literally constructs the track.
##   * A marble sits on the current level. After a solve it rolls along the rails to the next gear
##     while the new section of track gets built behind it.
##   * Each world has its own animated physics decor: pendulum, meshing gears, Newton's cradle,
##     pulley with a bobbing counterweight.
##   * Top: title, solved count, Settings; below it Daily and Sandbox. Music: "map" (soothing).

const C_SHEET := Color("1f3b63")
const C_SHEET_GRID := Color(1, 1, 1, 0.07)
const C_SHEET_GRID_MAJOR := Color(1, 1, 1, 0.13)
const C_INK := Color("1f1a2e")
const C_RAIL := Color("e0b44c")
const C_SLEEPER := Color("8a5a2f")
const C_PLAN := Color(0.85, 0.92, 1.0, 0.45)
const C_SOLVED := Color("7bd389")
const C_CURRENT := Color("ffd43b")
const C_LOCK := Color("8d8aa8")
const WORLD_COLORS := [Color("4f8fd8"), Color("e8833a"), Color("b35fd1"), Color("2fa39a"), Color("d8505c")]
const TOP_H := 160.0
const ACTIONS_H := 160.0
const STEP_Y := 210.0
const WORLD_GAP := 220.0
const NODE_R := 64.0

var _scroll: ScrollContainer
var _canvas: Control
var _curve := Curve2D.new()
var _nodes: Dictionary = {}  # level number -> Vector2 (canvas coords)
var _offsets: Dictionary = {}  # level number -> curve offset
var _world_bands: Array = []  # [{number, name, y0, y1}]
var _current := 1
var _marble_off := 0.0  # curve offset of the marble
var _built_off := 0.0  # track is built up to here
var _t := 0.0
var _anim: Tween
var _cum: PackedFloat32Array = []  # distance along the track at each baked point
var _marble_layer: Control


func _ready() -> void:
	App.audio.play_music("map")
	var bg := ColorRect.new()
	bg.color = C_SHEET
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_top()
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = TOP_H + ACTIONS_H
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_canvas = Control.new()
	_canvas.name = "MapCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_draw_map)
	_scroll.add_child(_canvas)
	_layout()
	_current = _current_level()
	# Arriving from a solve: the marble starts on the gear it left and rolls to the new one.
	var prev: int = App.map_last_node
	_marble_off = _offsets.get(_current, 0.0)
	_built_off = _marble_off
	if prev > 0 and prev < _current and _offsets.has(prev):
		_marble_off = _offsets[prev]
		_built_off = _marble_off
		_roll_to(_current)
	App.map_last_node = _current
	_scroll_to(_marble_off, false)


func _build_top() -> void:
	var top := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiKit.PANEL
	st.content_margin_left = 32
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	top.add_theme_stylebox_override("panel", st)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_H
	add_child(top)
	var h := HBoxContainer.new()
	top.add_child(h)
	var title := UiKit.label("Tinker", 64, UiKit.PANEL_TXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var solved := UiKit.label("%d / %d solved" % [App.save.solved_count(), Campaign.level_count()], 32, Color(UiKit.PANEL_TXT, 0.8))
	solved.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(solved)
	var gear := UiKit.button("Settings", UiKit.MUTED, UiKit.PANEL_TXT, 112)
	gear.add_theme_font_size_override("font_size", 28)
	gear.name = "SettingsButton"
	gear.pressed.connect(func() -> void: App.open_settings())
	h.add_child(gear)
	var pad := Control.new()
	pad.custom_minimum_size.x = 16
	h.add_child(pad)

	var actions := HBoxContainer.new()
	actions.set_anchors_preset(Control.PRESET_TOP_WIDE)
	actions.offset_top = TOP_H + 14
	actions.offset_left = 24
	actions.offset_right = -24
	actions.custom_minimum_size.y = ACTIONS_H - 28
	actions.add_theme_constant_override("separation", 20)
	add_child(actions)
	actions.add_child(_daily_button())
	var sb := UiKit.button("Sandbox", Color("6ec6ff"), UiKit.INK, ACTIONS_H - 28)
	sb.name = "SandboxButton"
	sb.custom_minimum_size.x = 300
	sb.pressed.connect(func() -> void: App.open_sandbox())
	actions.add_child(sb)


func _daily_button() -> Button:
	var today := DailyStore.today_utc()
	var done := App.daily_store.is_submitted(today)
	var streak := App.daily_store.streak()
	var label := "Daily · %s" % ("see board" if done else "play today's")
	if streak > 0:
		label += "\nstreak %d" % streak
	var b := UiKit.button(label, UiKit.ACCENT if not done else UiKit.GO, UiKit.INK, ACTIONS_H - 28)
	b.name = "DailyButton"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		b.disabled = true
		b.text = "Loading…"
		var err: String = await App.open_daily()
		if err != "":
			b.disabled = false
			b.text = err)
	return b


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var w := get_viewport_rect().size.x
	var y := 150.0
	var i := 0
	_curve.clear_points()
	_curve.bake_interval = 6.0
	var pts: Array = []
	for wd in Campaign.worlds():
		var band := {"number": int(wd["number"]), "name": str(wd["name"]), "y0": y - 110.0}
		y += WORLD_GAP * (0.0 if i == 0 else 0.35)
		for l in wd["levels"]:
			var n := int(l["number"])
			var x := w * 0.5 + w * 0.27 * sin(i * 0.95)
			var p := Vector2(x, y + 90.0)
			_nodes[n] = p
			pts.append([n, p])
			y += STEP_Y
			i += 1
		band["y1"] = y + 30.0
		_world_bands.append(band)
		y += WORLD_GAP * 0.65
	# Smooth curve: tangent at each node points from the previous to the next node.
	for k in pts.size():
		var p: Vector2 = pts[k][1]
		var prev: Vector2 = pts[k - 1][1] if k > 0 else p - Vector2(0, STEP_Y)
		var next: Vector2 = pts[k + 1][1] if k < pts.size() - 1 else p + Vector2(0, STEP_Y)
		var tan := (next - prev) * 0.28
		_curve.add_point(p, -tan, tan)
	for pair in pts:
		_offsets[pair[0]] = _curve.get_closest_offset(pair[1])
	_canvas.custom_minimum_size = Vector2(w, y + 200.0)
	for pair in pts:
		_canvas.add_child(_level_node(pair[0], pair[1]))
	# Baked points are not exactly bake_interval apart: measure the real distance along the track.
	var baked := _curve.get_baked_points()
	_cum.resize(baked.size())
	var acc := 0.0
	for k in baked.size():
		if k > 0:
			acc += baked[k].distance_to(baked[k - 1])
		_cum[k] = acc
	# The marble rolls above the gears, so it gets its own layer (added last = drawn on top).
	_marble_layer = Control.new()
	_marble_layer.name = "MarbleLayer"
	_marble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marble_layer.size = _canvas.custom_minimum_size
	_marble_layer.draw.connect(func() -> void: _draw_marble(_marble_layer))
	_canvas.add_child(_marble_layer)


func _current_level() -> int:
	var count := Campaign.level_count()
	for n in range(1, count + 1):
		if Campaign.is_unlocked(n, App.save) and not App.save.is_solved(n):
			return n
	return count


func _level_node(number: int, at: Vector2) -> Button:
	var unlocked := Campaign.is_unlocked(number, App.save)
	var best := App.save.best(number)
	var solved := bool(best.get("solved", false))
	var b := Button.new()
	b.name = "Level%d" % number
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not unlocked
	b.size = Vector2(NODE_R * 2.4, NODE_R * 2.4)
	b.position = at - b.size / 2.0
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.tooltip_text = str(Campaign.entry(number).get("title", ""))
	var face := Control.new()
	face.name = "Gear"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size = b.size
	face.draw.connect(func() -> void: _draw_gear(face, number, unlocked, solved))
	b.add_child(face)
	if solved:
		var sub := UiKit.label("%d part%s" % [int(best["best_parts"]), "" if int(best["best_parts"]) == 1 else "s"], 24, Color("fdfaf1"))
		sub.name = "Best"
		sub.add_theme_constant_override("outline_size", 8)
		sub.add_theme_color_override("font_outline_color", C_INK)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.position = Vector2(0, b.size.y - 30)
		sub.size = Vector2(b.size.x, 30)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sub)
	b.pressed.connect(func() -> void: App.open_level(number))
	return b


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_t += delta
	if not FramePacer.anim():
		return  # decor is visual only: paced (FramePacer) so an idle map does not heat the phone
	_canvas.queue_redraw()
	if _marble_layer:
		_marble_layer.queue_redraw()
	for c in _canvas.get_children():
		var g := c.get_node_or_null("Gear")
		if g:
			g.queue_redraw()


func _roll_to(number: int) -> void:
	var target: float = _offsets[number]
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_anim.tween_interval(0.5)
	_anim.tween_method(func(v: float) -> void:
		_marble_off = v
		_built_off = maxf(_built_off, v + 30.0)
		_scroll_to(v, false), _marble_off, target, 1.8)
	_anim.tween_callback(func() -> void:
		_built_off = target
		App.audio.sfx("place")
		App.audio.buzz(18))


func _scroll_to(off: float, _smooth: bool) -> void:
	var p := _curve.sample_baked(off)
	var view_h := get_viewport_rect().size.y - TOP_H - ACTIONS_H
	var target := int(clampf(p.y - view_h * 0.55, 0.0, maxf(0.0, _canvas.custom_minimum_size.y - view_h)))
	_scroll.set_deferred("scroll_vertical", target)


# ------------------------------------------------------------------ drawing

func _draw_map() -> void:
	var c := _canvas
	var size := c.custom_minimum_size
	# Blueprint grid.
	var step := 48.0
	var x := 0.0
	var k := 0
	while x < size.x:
		# In 1000 px segments: one very long line gets culled once the view scrolls away from its ends.
		var y0 := 0.0
		while y0 < size.y:
			c.draw_line(Vector2(x, y0), Vector2(x, minf(y0 + 1000.0, size.y)), C_SHEET_GRID_MAJOR if k % 4 == 0 else C_SHEET_GRID, 1.0)
			y0 += 1000.0
		x += step
		k += 1
	var y := 0.0
	k = 0
	while y < size.y:
		c.draw_line(Vector2(0, y), Vector2(size.x, y), C_SHEET_GRID_MAJOR if k % 4 == 0 else C_SHEET_GRID, 1.0)
		y += step
		k += 1
	_draw_track(c)
	for band in _world_bands:  # signs over the rails, so a world's name is never crossed out
		_draw_world_band(c, band)


func _draw_world_band(c: Control, band: Dictionary) -> void:
	var col: Color = WORLD_COLORS[(int(band["number"]) - 1) % WORLD_COLORS.size()]
	var w := c.custom_minimum_size.x
	c.draw_rect(Rect2(0, band["y0"], w, band["y1"] - band["y0"]), Color(col, 0.08))
	# Riveted name plate.
	var font := ThemeDB.fallback_font
	var text := "World %d — %s" % [band["number"], band["name"]]
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	var plate := Rect2(Vector2((w - tw) / 2.0 - 40, band["y0"] + 14), Vector2(tw + 80, 66))
	c.draw_rect(plate.grow(5), C_INK)
	c.draw_rect(plate, col.darkened(0.15))
	c.draw_rect(Rect2(plate.position + Vector2(4, 4), Vector2(plate.size.x - 8, 10)), Color(1, 1, 1, 0.18))
	for p in [plate.position + Vector2(14, 14), Vector2(plate.end.x - 14, plate.position.y + 14), Vector2(plate.position.x + 14, plate.end.y - 14), plate.end - Vector2(14, 14)]:
		c.draw_circle(p, 6.0, C_INK)
		c.draw_circle(p, 4.0, Color("c9c2b6"))
	c.draw_string(font, plate.position + Vector2(40, 46), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color("fdfaf1"))
	# Decor, both sides, animated.
	var mid_y: float = (band["y0"] + band["y1"]) / 2.0
	match (int(band["number"]) - 1) % 4:
		0:
			_decor_pendulum(c, Vector2(w * 0.1, band["y0"] + 170))
			_decor_crates(c, Vector2(w * 0.9, mid_y + 260))
		1:
			_decor_gears(c, Vector2(w * 0.9, band["y0"] + 230))
			_decor_pipes(c, Vector2(w * 0.07, mid_y + 200))
		2:
			_decor_cradle(c, Vector2(w * 0.12, band["y0"] + 190))
			_decor_cheese(c, Vector2(w * 0.9, mid_y + 240))
		_:
			_decor_pulley(c, Vector2(w * 0.9, band["y0"] + 140))
			_decor_gears(c, Vector2(w * 0.1, mid_y + 220))


func _draw_track(c: Control) -> void:
	var pts := _curve.get_baked_points()
	if pts.size() < 2:
		return
	# Planned section (beyond the built offset): dashed blueprint rails.
	for i in range(pts.size() - 1):
		var off := _cum[i]
		if off <= _built_off:
			continue
		if int(off / 18.0) % 2 == 0:
			var d := (pts[i + 1] - pts[i]).normalized().orthogonal() * 12.0
			c.draw_line(pts[i] + d, pts[i + 1] + d, C_PLAN, 2.0)
			c.draw_line(pts[i] - d, pts[i + 1] - d, C_PLAN, 2.0)
	# Built section: sleepers, then ink-edged brass rails.
	var next_sleeper := 0.0
	for i in range(0, pts.size() - 1):
		if _cum[i] > _built_off:
			break
		if _cum[i] < next_sleeper:
			continue
		next_sleeper = _cum[i] + 28.0
		var d := (pts[i + 1] - pts[i]).normalized()
		var n := d.orthogonal()
		var a := pts[i] + n * 20.0
		var b := pts[i] - n * 20.0
		c.draw_line(a, b, C_INK, 11.0)
		c.draw_line(a, b, C_SLEEPER, 7.0)
	var built := PackedVector2Array()
	for i in pts.size():
		if _cum[i] > _built_off:
			break
		built.append(pts[i])
	if built.size() >= 2:
		for side in [-1.0, 1.0]:
			var rail := PackedVector2Array()
			for i in built.size():
				var j := mini(i + 1, built.size() - 1)
				var h := maxi(i - 1, 0)
				var n := (built[j] - built[h]).normalized().orthogonal()
				rail.append(built[i] + n * 12.0 * side)
			c.draw_polyline(rail, C_INK, 8.0)
			c.draw_polyline(rail, C_RAIL, 4.0)


func _draw_marble(c: Control) -> void:
	var p := _curve.sample_baked(_marble_off)
	var r := 34.0
	var ang := _marble_off / r
	# On the rails between gears; perched on top of a gear when parked at one (like a map token).
	var near := INF
	for n in _nodes:
		near = minf(near, _nodes[n].distance_to(p))
	var perch := clampf(1.0 - near / (NODE_R * 1.6), 0.0, 1.0)
	var lift := Vector2(0, -r - 4.0 - perch * (NODE_R + 4.0))
	c.draw_circle(p + Vector2(5, 8), r, Color(0, 0, 0, 0.3))
	c.draw_circle(p + lift + Vector2.ZERO, r, C_INK)
	c.draw_circle(p + lift, r - 4.0, Color("ff5d73").darkened(0.15))
	c.draw_circle(p + lift + Vector2(-2, -2), r - 7.0, Color("ff5d73"))
	for a in [-0.35, 0.0, 0.35]:
		c.draw_circle(p + lift + Vector2(0, -r * 0.45).rotated(a + ang), 3.5, Color("7a2030"))
	c.draw_circle(p + lift + Vector2(-r * 0.35, -r * 0.4), 5.0, Color(1, 1, 1, 0.6))


func _draw_gear(n: Control, number: int, unlocked: bool, solved: bool) -> void:
	var c := n.size / 2.0
	var world := Campaign.world_of(number)
	var col: Color = WORLD_COLORS[(world - 1) % WORLD_COLORS.size()] if unlocked else C_LOCK
	if solved:
		col = C_SOLVED
	var is_current := number == _current and unlocked and not solved
	if is_current:
		col = C_CURRENT
		var glow := 0.5 + 0.5 * sin(_t * 4.0)
		n.draw_circle(c, NODE_R + 18.0 + glow * 8.0, Color(C_CURRENT, 0.18 + 0.12 * glow))
	var spin := (_t * (0.6 if is_current else 0.15)) if unlocked else 0.0
	var teeth := 12
	n.draw_circle(c + Vector2(5, 8), NODE_R, Color(0, 0, 0, 0.3))
	for i in teeth:
		var a := spin + i * TAU / teeth
		var dir := Vector2.from_angle(a)
		var t := dir.orthogonal() * 11.0
		var base := c + dir * (NODE_R - 6.0)
		var tip := c + dir * (NODE_R + 12.0)
		n.draw_colored_polygon(PackedVector2Array([base - t * 1.2, tip - t * 0.8, tip + t * 0.8, base + t * 1.2]), C_INK)
		n.draw_colored_polygon(PackedVector2Array([base - t * 0.8 + dir * 2, tip - t * 0.45 - dir * 3, tip + t * 0.45 - dir * 3, base + t * 0.8 + dir * 2]), col.darkened(0.1))
	n.draw_circle(c, NODE_R, C_INK)
	n.draw_circle(c, NODE_R - 6.0, col)
	n.draw_circle(c + Vector2(-NODE_R * 0.3, -NODE_R * 0.35), NODE_R * 0.25, Color(1, 1, 1, 0.22))
	n.draw_circle(c, NODE_R * 0.62, Color(col.darkened(0.25), 0.6))
	var font := ThemeDB.fallback_font
	var txt := str(number)
	var fs := 50
	var tsize := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var txt_col := C_INK if (solved or is_current) else (Color("fdfaf1") if unlocked else Color(C_INK, 0.45))
	if unlocked:
		n.draw_string(font, c + Vector2(-tsize.x / 2.0, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
	else:
		# Padlock.
		n.draw_rect(Rect2(c + Vector2(-18, -2), Vector2(36, 28)), C_INK)
		n.draw_rect(Rect2(c + Vector2(-14, 2), Vector2(28, 20)), Color("c9c2b6"))
		n.draw_arc(c + Vector2(0, -4), 12.0, PI, TAU, 12, C_INK, 6.0)
	if solved:
		var ck := c + Vector2(NODE_R * 0.62, -NODE_R * 0.62)
		n.draw_circle(ck, 20.0, C_INK)
		n.draw_circle(ck, 16.0, Color("fdfaf1"))
		n.draw_polyline(PackedVector2Array([ck + Vector2(-8, 0), ck + Vector2(-2, 7), ck + Vector2(9, -7)]), Color("2fbf71"), 5.0)


# ------------------------------------------------------------------ decor (visual only)

func _decor_pendulum(c: Control, p: Vector2) -> void:
	c.draw_rect(Rect2(p + Vector2(-50, -8), Vector2(100, 12)), C_PLAN)
	var a := sin(_t * 1.6) * 0.6
	var bob := p + Vector2(0, 130).rotated(a)
	c.draw_line(p, bob, C_PLAN, 3.0)
	c.draw_circle(bob, 20.0, Color(C_PLAN, 0.9))
	c.draw_arc(p, 130.0, PI / 2.0 - 0.6, PI / 2.0 + 0.6, 24, Color(C_PLAN, 0.3), 2.0)


func _decor_crates(c: Control, p: Vector2) -> void:
	for q in [Vector2(-50, 0), Vector2(20, 0), Vector2(-15, -66)]:
		var r := Rect2(p + q, Vector2(64, 64))
		c.draw_rect(r, C_PLAN, false, 3.0)
		c.draw_line(r.position, r.end, Color(C_PLAN, 0.6), 2.0)
		c.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(C_PLAN, 0.6), 2.0)


func _decor_gear_outline(c: Control, p: Vector2, r: float, teeth: int, a0: float) -> void:
	var pts := PackedVector2Array()
	for i in teeth * 4 + 1:
		var a := a0 + i * TAU / (teeth * 4)
		var rr := r + (8.0 if (i % 4) in [1, 2] else 0.0)
		pts.append(p + Vector2.from_angle(a) * rr)
	c.draw_polyline(pts, C_PLAN, 3.0)
	c.draw_circle(p, r * 0.25, Color(C_PLAN, 0.6))


func _decor_gears(c: Control, p: Vector2) -> void:
	# Two meshing gears turn in opposite directions (speed ratio = teeth ratio).
	_decor_gear_outline(c, p, 54.0, 12, _t * 0.5)
	_decor_gear_outline(c, p + Vector2(-48, 84), 34.0, 8, -_t * 0.75 + 0.2)


func _decor_pipes(c: Control, p: Vector2) -> void:
	var path := PackedVector2Array([p + Vector2(0, -120), p, p + Vector2(60, 0), p + Vector2(60, 110)])
	c.draw_polyline(path, C_PLAN, 14.0)
	c.draw_polyline(path, C_SHEET, 8.0)
	c.draw_circle(p + Vector2(60, -10), 16.0, Color(C_PLAN, 0.8))
	var puff := fmod(_t * 0.8, 1.0)
	c.draw_circle(p + Vector2(60, 110 + puff * 40), 6.0 + puff * 14.0, Color(C_PLAN, 0.4 * (1.0 - puff)))


func _decor_cradle(c: Control, p: Vector2) -> void:
	# Newton's cradle: the end balls swing in turn, the middle ones stay still.
	c.draw_line(p + Vector2(-80, 0), p + Vector2(80, 0), C_PLAN, 4.0)
	var s := sin(_t * 3.0)
	for i in 5:
		var top := p + Vector2(-56 + i * 28, 0)
		var a := 0.0
		if i == 0 and s < 0.0:
			a = s * 0.5
		elif i == 4 and s > 0.0:
			a = s * 0.5
		var ball := top + Vector2(0, 100).rotated(a)
		c.draw_line(top, ball, Color(C_PLAN, 0.7), 2.0)
		c.draw_circle(ball, 13.0, C_PLAN)


func _decor_cheese(c: Control, p: Vector2) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-50, 30), p + Vector2(50, 30), p + Vector2(50, -6), p + Vector2(-50, -30)]), Color(C_PLAN, 0.25))
	c.draw_polyline(PackedVector2Array([p + Vector2(-50, 30), p + Vector2(50, 30), p + Vector2(50, -6), p + Vector2(-50, -30), p + Vector2(-50, 30)]), C_PLAN, 3.0)
	var wob := sin(_t * 5.0) * 4.0
	c.draw_circle(p + Vector2(-110, 18 + wob * 0.2), 18.0, Color(C_PLAN, 0.8))
	c.draw_circle(p + Vector2(-122, 2), 8.0, Color(C_PLAN, 0.8))
	c.draw_line(p + Vector2(-128, 22), p + Vector2(-160, 10 + wob), C_PLAN, 2.0)


func _decor_pulley(c: Control, p: Vector2) -> void:
	# Pulley with a counterweight bobbing on one side and a hook on the other.
	var bob := sin(_t * 1.2) * 30.0
	c.draw_line(p + Vector2(0, -60), p, C_PLAN, 4.0)
	c.draw_circle(p, 26.0, Color(C_PLAN, 0.35))
	c.draw_arc(p, 26.0, 0, TAU, 24, C_PLAN, 3.0)
	c.draw_line(p + Vector2(-26, 0), p + Vector2(-26, 120 + bob), C_PLAN, 2.0)
	c.draw_line(p + Vector2(26, 0), p + Vector2(26, 120 - bob), C_PLAN, 2.0)
	c.draw_rect(Rect2(p + Vector2(-44, 120 + bob), Vector2(36, 40)), C_PLAN, false, 3.0)
	c.draw_arc(p + Vector2(26, 132 - bob), 12.0, 0, PI, 12, C_PLAN, 3.0)
