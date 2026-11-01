extends RigidBody2D
## Bowling ball — heavy, reliable, rolls. Interacts with everything.
## Frozen until the simulation starts so the build phase has no motion.

var def: Dictionary
var radius: float = 36.0
var fill: Color = Color.WHITE


func configure(p_def: Dictionary) -> void:
	def = p_def
	radius = float(def["shape"]["radius"])
	fill = PartFactory.color_of(def)
	mass = float(def.get("mass", 10.0))
	gravity_scale = float(def.get("gravity_scale", 1.0))
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 0.8))
	pm.bounce = float(def.get("bounce", 0.1))
	physics_material_override = pm
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func set_running(running: bool) -> void:
	freeze = not running


## Deterministic state string for the outcome hash.
func snapshot() -> String:
	return "%s p=%s r=%s v=%s" % [name, _q(global_position), _qf(global_rotation), _q(linear_velocity)]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, PartFactory.OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, radius - PartFactory.OUTLINE_W, fill)
	# Three finger holes so rotation is visible.
	var hole := Color(fill.r * 0.45, fill.g * 0.45, fill.b * 0.45)
	for a in [-0.35, 0.0, 0.35]:
		draw_circle(Vector2(0, -radius * 0.42).rotated(a + 0.6), radius * 0.11, hole)


static func _q(v: Vector2) -> String:
	return "%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0)]


static func _qf(f: float) -> String:
	return str(roundi(f * 10000.0))
