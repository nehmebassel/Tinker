extends RigidBody2D
## Plank — three modes, all decided by what else sits on its cell at attach time:
##   static  : a ramp (frozen rigid body = static body). Default.
##   pivot   : a MOTOR sits on the same cell -> plank is pinned at its centre.
##             motor on  = spinning paddle; motor off = free see-saw.
##   dynamic : a ROPE is tied to it (and no motor) -> it hangs / falls as a rigid body.

enum Mode { STATIC, PIVOT, DYNAMIC }

var def: Dictionary
var size: Vector2 = Vector2(240, 24)
var fill: Color = Color.WHITE
var mode: Mode = Mode.STATIC
var motor: Node2D = null
var _joint: PinJoint2D = null
var _sim: Node = null


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	mass = float(def.get("mass", 4.0))
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 0.6))
	pm.bounce = float(def.get("bounce", 0.0))
	physics_material_override = pm
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	can_sleep = false
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func on_attach(sim: Node) -> void:
	_sim = sim
	var m: Node2D = sim.part_at_cell(get_meta("cell"), self, 0, func(p): return p.get_meta("part_id") == "motor")
	if m != null:
		mode = Mode.PIVOT
		motor = m
		motor.attached = self


## Called by a rope that ties itself to this plank.
func make_dynamic() -> void:
	if mode == Mode.STATIC:
		mode = Mode.DYNAMIC


func set_running(running: bool) -> void:
	match mode:
		Mode.STATIC:
			freeze = true
		Mode.DYNAMIC:
			freeze = not running
		Mode.PIVOT:
			freeze = not running
			if running and _joint == null and motor != null:
				_joint = PinJoint2D.new()
				_joint.global_position = motor.global_position
				_joint.node_a = motor.get_path()
				_joint.node_b = get_path()
				_joint.disable_collision = true
				_joint.softness = 0.0
				_sim.add_link_node(_joint)
			elif not running and _joint != null:
				_joint.queue_free()
				_joint = null


## Motor toggled while running: nothing to do, _physics_process reads motor.on every tick.
func set_motor_on(_on: bool) -> void:
	pass


## A powered paddle is driven kinematically: the pin joint's own motor is far too weak (it
## accelerates at ~0.1 rad/s per second), so we set the angular velocity directly. The plank
## still collides as a rigid body, so a ball it hits gets a proper impulse.
func _physics_process(_delta: float) -> void:
	if mode == Mode.PIVOT and not freeze and motor != null and motor.on:
		angular_velocity = motor.speed * motor.direction


## Points along the plank where wind is sampled (local offsets), so a fan can turn a paddle.
func wind_sample_points() -> Array:
	var hw := size.x / 2.0
	return [Vector2(-hw * 0.8, 0), Vector2(-hw * 0.4, 0), Vector2.ZERO, Vector2(hw * 0.4, 0), Vector2(hw * 0.8, 0)]


func snapshot() -> String:
	return "%s p=%s r=%s mode=%d" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_rot(global_rotation), mode]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	var r := Rect2(-size / 2.0, size)
	draw_rect(r, PartFactory.OUTLINE_COLOR)
	draw_rect(r.grow(-PartFactory.OUTLINE_W), fill)
	draw_line(Vector2(-size.x * 0.4, 0), Vector2(size.x * 0.4, 0), Color(fill.r * 0.7, fill.g * 0.7, fill.b * 0.7), 3.0)
	if mode == Mode.PIVOT:
		draw_circle(Vector2.ZERO, 9.0, PartFactory.OUTLINE_COLOR)
