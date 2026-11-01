extends StaticBody2D
## Spring — launches whatever lands on its pad along its up axis (local -Y). Launch impulse grows
## with the impact speed ("force by compression") and is applied once per landing.

var def: Dictionary
var size: Vector2 = Vector2(96, 48)
var fill: Color = Color.WHITE
var gain: float = 1.7  # outgoing speed = gain * incoming speed + kick
var kick: float = 420.0  # px/s added on every launch
var max_speed: float = 1500.0
var running: bool = false
var _pad: Area2D
var _launched: Dictionary = {}  # body -> true until it leaves the pad
var _squash: float = 0.0  # visual only
var _seen_launches: int = 0


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	gain = float(def.get("gain", gain))
	kick = float(def.get("kick", kick))
	max_speed = float(def.get("max_speed", max_speed))
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	physics_material_override = pm
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	_pad = Area2D.new()
	_pad.name = "Pad"
	_pad.monitorable = false
	var pcs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(size.x, 28.0)
	pcs.shape = r
	pcs.position = Vector2(0, -size.y / 2.0 - 10.0)
	_pad.add_child(pcs)
	_pad.body_exited.connect(func(b: Node) -> void: _launched.erase(b))
	add_child(_pad)
	queue_redraw()


func set_running(p_running: bool) -> void:
	running = p_running
	_launched.clear()


func _physics_process(_delta: float) -> void:
	if not running:
		return
	var up := Vector2.UP.rotated(global_rotation)
	for body in PartFactory.sorted_bodies(_pad):
		if not (body is RigidBody2D) or body.freeze or _launched.has(body):
			continue
		var v_in: float = -body.linear_velocity.dot(up)  # positive when moving into the pad
		if v_in < 20.0:
			continue
		var v_out := minf(v_in * gain + kick, max_speed)
		# Replace the normal component of the velocity with the launch speed.
		var tangent: Vector2 = body.linear_velocity - body.linear_velocity.dot(up) * up
		body.linear_velocity = tangent + up * v_out
		_launched[body] = true


func snapshot() -> String:
	return "%s p=%s r=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_rot(global_rotation)]


func set_ghost(p_on: bool) -> void:
	modulate.a = 0.45 if p_on else 1.0


func _process(delta: float) -> void:
	var n := _launched.size()
	if n > _seen_launches:
		_squash = 1.0
	_seen_launches = n
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta * 4.0)
		queue_redraw()


func _draw() -> void:
	# Base plate.
	var base := Rect2(-size.x / 2.0, size.y / 2.0 - 14.0, size.x, 14.0)
	Art.rect(self, base, Color("8d8aa8"), true, 3.0)
	# Coil: squashes then springs back after a launch (visual only; the pad does not move).
	var bounce := sin(_squash * PI * 2.0) * _squash
	var top_y := -size.y / 2.0 + 12.0 + bounce * 10.0
	var bottom_y := size.y / 2.0 - 14.0
	var pts := PackedVector2Array()
	var n := 6
	for i in range(n + 1):
		var t := float(i) / n
		var x := (size.x * 0.3) * (1 if i % 2 == 0 else -1)
		pts.append(Vector2(x, bottom_y - t * (bottom_y - top_y)))
	draw_polyline(pts, Art.INK, 8.0)
	draw_polyline(pts, fill, 4.0)
	draw_polyline(pts, Color(fill.lightened(0.5), 0.6), 1.5)
	# Top pad.
	Art.rect(self, Rect2(-size.x / 2.0, top_y - 12.0, size.x, 12.0), fill, false, 3.0)
