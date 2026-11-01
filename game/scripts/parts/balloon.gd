extends RigidBody2D
## Balloon — floats up (negative gravity scale) at a terminal speed set by linear damping,
## drifts in fan wind, pops on a lit candle. Popping removes it from play but keeps the node so
## the snapshot records it.

var def: Dictionary
var radius: float = 40.0
var fill: Color = Color.WHITE
var popped: bool = false


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
	set_deferred("visible", false)


func snapshot() -> String:
	return "%s p=%s v=%s popped=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_pos(linear_velocity), popped]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	# Slightly egg-shaped balloon with a knot and string stub.
	var pts := PackedVector2Array()
	for i in range(32):
		var a := i * TAU / 32.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * 1.12 + radius * 0.1))
	draw_colored_polygon(pts, PartFactory.OUTLINE_COLOR)
	var inner := PackedVector2Array()
	for i in range(32):
		var a := i * TAU / 32.0
		inner.append(Vector2(cos(a) * (radius - PartFactory.OUTLINE_W), sin(a) * (radius - PartFactory.OUTLINE_W) * 1.12 + radius * 0.1))
	draw_colored_polygon(inner, fill)
	draw_circle(Vector2(-radius * 0.35, -radius * 0.35), radius * 0.16, Color(1, 1, 1, 0.55))
	var knot := Vector2(0, radius * 1.22)
	draw_colored_polygon(PackedVector2Array([knot + Vector2(-8, 0), knot + Vector2(8, 0), knot + Vector2(0, -10)]), PartFactory.OUTLINE_COLOR)
	draw_line(knot, knot + Vector2(4, 26), PartFactory.OUTLINE_COLOR, 3.0)
