extends RigidBody2D
## Balloon — floats up (negative gravity scale) at a terminal speed set by linear damping,
## drifts in fan wind, pops on a lit candle. Popping removes it from play but keeps the node so
## the snapshot records it.

var def: Dictionary
var radius: float = 40.0
var fill: Color = Color.WHITE
var popped: bool = false
const POP_ANIM_S := 0.8
var _pop_t: float = 99.0  # time since the pop (visual only)


func configure(p_def: Dictionary) -> void:
	def = p_def
	radius = float(def["shape"]["radius"])
	fill = PartFactory.color_of(def)
	mass = float(def.get("mass", 0.25))
	gravity_scale = float(def.get("gravity_scale", -0.35))
	linear_damp = float(def.get("linear_damp", 1.6))
	angular_damp = 4.0
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.2
	physics_material_override = pm
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func set_running(running: bool) -> void:
	freeze = (not running) or popped


## Called by a lit candle's flame. Deferred changes: this arrives from a physics callback.
func pop() -> void:
	if popped:
		return
	popped = true
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_deferred("linear_velocity", Vector2.ZERO)
	set_deferred("angular_velocity", 0.0)
	_pop_t = 0.0  # the burst animation runs in _process; the body is already out of play


func _process(delta: float) -> void:
	if popped and _pop_t < POP_ANIM_S:
		_pop_t += delta
		queue_redraw()


func snapshot() -> String:
	return "%s p=%s v=%s popped=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_pos(linear_velocity), popped]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	if popped:
		_draw_pop()
		return
	# Slightly egg-shaped balloon with a knot and string stub.
	var pts := PackedVector2Array()
	for i in range(32):
		var a := i * TAU / 32.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * 1.12 + radius * 0.1))
	Art.shadow_poly(self, pts)
	draw_colored_polygon(pts, Art.INK)
	var inner := PackedVector2Array()
	var shade := PackedVector2Array()
	for i in range(32):
		var a := i * TAU / 32.0
		var rr := radius - Art.OUTLINE_W
		inner.append(Vector2(cos(a) * rr, sin(a) * rr * 1.12 + radius * 0.1))
		shade.append(Vector2(cos(a) * rr * 0.86 - rr * 0.08, sin(a) * rr * 0.96 + radius * 0.02))
	draw_colored_polygon(inner, fill.darkened(0.18))
	draw_colored_polygon(shade, fill)
	draw_circle(Vector2(-radius * 0.35, -radius * 0.35), radius * 0.17, Color(1, 1, 1, 0.6))
	draw_circle(Vector2(-radius * 0.18, -radius * 0.55), radius * 0.07, Color(1, 1, 1, 0.5))
	var knot := Vector2(0, radius * 1.22)
	draw_colored_polygon(PackedVector2Array([knot + Vector2(-8, 0), knot + Vector2(8, 0), knot + Vector2(0, -10)]), Art.INK)
	draw_line(knot, knot + Vector2(4, 26), Art.INK, 3.0)


## Burst: a jagged "POP!" flash, rubber shreds flying out and a limp knot dropping, fading out.
## Drawn in a non-rotating frame so the effect reads the same whatever the balloon's spin was.
func _draw_pop() -> void:
	if _pop_t >= POP_ANIM_S:
		return
	draw_set_transform(Vector2.ZERO, -global_rotation, Vector2(1.7, 1.7))  # bold enough at full-board zoom
	var t := _pop_t / POP_ANIM_S  # 0..1
	var fade := 1.0 - t
	# Flash star.
	var star := PackedVector2Array()
	var rr := radius * (1.0 + t * 0.9)
	for i in 16:
		var a := i * TAU / 16.0
		var k := rr if i % 2 == 0 else rr * 0.55
		star.append(Vector2(cos(a), sin(a)) * k)
	draw_colored_polygon(star, Color(1.0, 0.93, 0.45, 0.85 * fade))
	draw_polyline(star + PackedVector2Array([star[0]]), Color(Art.INK, 0.8 * fade), 4.0)
	# Shreds of rubber.
	for i in 9:
		var a := i * TAU / 9.0 + 0.3
		var d := radius * (0.4 + t * 1.8)
		var c := Vector2(cos(a), sin(a)) * d + Vector2(0, t * t * 60.0)
		var w := Vector2(cos(a + 1.2), sin(a + 1.2)) * 10.0
		var h := Vector2(cos(a), sin(a)) * 6.0
		draw_colored_polygon(PackedVector2Array([c - w - h, c + w - h * 0.4, c + w * 0.6 + h, c - w * 0.5 + h * 0.8]), Color(fill, fade))
	# Knot and string falling.
	var knot := Vector2(0, radius * 1.1 + t * t * 140.0)
	draw_colored_polygon(PackedVector2Array([knot + Vector2(-8, 0), knot + Vector2(8, 0), knot + Vector2(0, -10)]), Color(Art.INK, fade))
	draw_line(knot, knot + Vector2(6, 26), Color(Art.INK, fade), 3.0)
	if t < 0.6:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-40, -rr - 10), "POP!", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(Art.INK, fade))
		draw_string(font, Vector2(-42, -rr - 12), "POP!", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("ff5d73", fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
