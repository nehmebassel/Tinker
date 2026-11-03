extends StaticBody2D
## Conveyor — moves anything resting on it along its facing direction (+X local).
## The belt is driven by us, not by StaticBody2D.constant_linear_velocity: Godot ignores a change
## of that value for an already-resting contact, so a conveyor switched on mid-run would not move
## the ball sitting on it. Instead a thin Area2D over the belt accelerates every body in it toward
## belt speed each tick (bodies sorted by creation order). Powered by default; a MOTOR on the
## same cell makes power follow the motor; a switch toggles.

var def: Dictionary
var size: Vector2 = Vector2(288, 36)
var fill: Color = Color.WHITE
var on: bool = true
var speed: float = 220.0
var accel: float = 2400.0  # px/s^2 toward belt speed
var motor: Node2D = null
var running: bool = false
var _belt: Area2D
var _scroll: float = 0.0  # visual only


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	speed = float(def.get("speed", speed))
	on = bool(PartFactory.state_of(self, "on", true))
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 1.0))
	pm.bounce = 0.0
	physics_material_override = pm
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	# Belt strips on BOTH faces: a conveyor rotated 180 degrees (the only way to point it left
	# with 15-degree steps) must still carry things on its upper face.
	_belt = Area2D.new()
	_belt.name = "Belt"
	_belt.monitorable = false
	for side in [-1.0, 1.0]:
		var bcs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(size.x - 8.0, 14.0)
		bcs.shape = r
		bcs.position = Vector2(0, side * (size.y / 2.0 + 5.0))
		_belt.add_child(bcs)
	add_child(_belt)
	queue_redraw()


func on_attach(sim: Node) -> void:
	var m: Node2D = sim.part_at_cell(get_meta("cell"), self, 0, func(p): return p.get_meta("part_id") == "motor")
	if m != null:
		motor = m
		motor.attached = self
		on = motor.on
		_apply()


func toggle() -> void:
	on = not on
	_apply()
	queue_redraw()


## Motor on the same cell toggled.
func set_motor_on(p_on: bool) -> void:
	on = p_on
	_apply()
	queue_redraw()


func _apply() -> void:
	pass  # kept for call sites; the belt is driven in _physics_process


func set_running(p_running: bool) -> void:
	running = p_running


func _physics_process(_delta: float) -> void:
	if not running or not on:
		return
	var dir := Vector2.RIGHT.rotated(global_rotation)
	for body in PartFactory.sorted_bodies(_belt):
		if not (body is RigidBody2D) or body.freeze:
			continue
		var v_rel: float = speed - body.linear_velocity.dot(dir)
		var dv: float = clampf(v_rel, -accel / 60.0, accel / 60.0)
		body.apply_central_impulse(dir * dv * body.mass)


func snapshot() -> String:
	return "%s p=%s r=%s on=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_rot(global_rotation), on]


func set_ghost(p_on: bool) -> void:
	modulate.a = 0.45 if p_on else 1.0


func _process(delta: float) -> void:
	if running and on:
		_scroll += delta * speed
		if FramePacer.anim():
			queue_redraw()


func _draw() -> void:
	var r := Rect2(-size / 2.0, size)
	Art.rect(self, r, fill if on else fill.darkened(0.45))
	# Tread lines scroll along the belt while it runs; rollers turn with it.
	var inner := r.grow(-Art.OUTLINE_W - 2.0)
	var gap := 22.0
	var off := fmod(_scroll, gap)
	var x := inner.position.x + off
	while x < inner.end.x:
		draw_line(Vector2(x, inner.position.y), Vector2(x - 6.0, inner.end.y), Color(Art.INK, 0.35), 3.0)
		x += gap
	var rr := size.y * 0.34
	var ang := _scroll / maxf(rr, 1.0)
	Art.wheel(self, Vector2(-size.x / 2.0 + size.y / 2.0, 0), rr, ang, Color("c9c2b6"), 3)
	Art.wheel(self, Vector2(size.x / 2.0 - size.y / 2.0, 0), rr, ang, Color("c9c2b6"), 3)
