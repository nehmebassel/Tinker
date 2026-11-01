extends RigidBody2D
## Cheese — what the mouse wants. A light rigid body (it can be carried in a bucket or dropped
## into a basket). When the mouse touches it, it is eaten: goal type "cheese".

var def: Dictionary
var size: Vector2 = Vector2(48, 36)
var fill: Color = Color.WHITE
var eaten: bool = false
var running: bool = false
var _sensor: Area2D


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	mass = float(def.get("mass", 0.5))
	lock_rotation = true
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.0
	physics_material_override = pm
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	_sensor = Area2D.new()
	_sensor.monitorable = false
	var scs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size + Vector2(16, 16)
	scs.shape = r
	_sensor.add_child(scs)
	_sensor.body_entered.connect(_on_body)
	add_child(_sensor)
	queue_redraw()


func _on_body(body: Node) -> void:
	if not running or eaten or body.get_meta("part_id", "") != "mouse" or body.caught:
		return
	eaten = true
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_deferred("linear_velocity", Vector2.ZERO)
	set_deferred("visible", false)


func set_running(p_running: bool) -> void:
	running = p_running
	freeze = (not running) or eaten
	if running:
		for body in PartFactory.sorted_bodies(_sensor):
			_on_body(body)


func snapshot() -> String:
	return "%s p=%s eaten=%s" % [name, PartFactory.fmt_pos(global_position), eaten]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var wedge := PackedVector2Array([Vector2(-hx, hy), Vector2(hx, hy), Vector2(hx, -hy * 0.2), Vector2(-hx, -hy)])
	Art.shadow_poly(self, wedge)
	draw_colored_polygon(wedge, Art.INK)
	var k := Art.OUTLINE_W
	var inner := PackedVector2Array([Vector2(-hx + k, hy - k), Vector2(hx - k, hy - k), Vector2(hx - k, -hy * 0.2 + k * 0.5), Vector2(-hx + k, -hy + k * 1.5)])
	draw_colored_polygon(inner, fill)
	draw_line(Vector2(-hx + k + 2, -hy + k * 1.5 + 2), Vector2(hx - k - 2, -hy * 0.2 + k * 0.5 + 2), Color(fill.lightened(0.5), 0.8), 3.0)
	var hole := fill.darkened(0.3)
	draw_circle(Vector2(-hx * 0.3, hy * 0.2), 5.0, hole)
	draw_circle(Vector2(hx * 0.35, -hy * 0.1), 4.0, hole)
	draw_circle(Vector2(hx * 0.1, hy * 0.5), 3.0, hole)
