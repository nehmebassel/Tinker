extends RigidBody2D
## Bucket — a rigid U that catches bodies (and so gets heavier) and hangs on a rope.
## Rotation is locked so it stays upright while swinging; that is the friendly, predictable
## behaviour a player expects from a bucket on a string.

var def: Dictionary
var size: Vector2 = Vector2(144, 120)
var wall: float = 16.0
var fill: Color = Color.WHITE
var held: bool = false  # a rope is tied to it


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	mass = float(def.get("mass", 3.0))
	lock_rotation = true
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 0.8))
	pm.bounce = 0.0
	physics_material_override = pm
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	_add_wall(Vector2(0, size.y / 2.0 - wall / 2.0), Vector2(size.x, wall))
	_add_wall(Vector2(-size.x / 2.0 + wall / 2.0, 0), Vector2(wall, size.y))
	_add_wall(Vector2(size.x / 2.0 - wall / 2.0, 0), Vector2(wall, size.y))
	queue_redraw()


func _add_wall(pos: Vector2, sz: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = sz
	cs.shape = r
	cs.position = pos
	add_child(cs)


func make_dynamic() -> void:
	held = true


func set_running(running: bool) -> void:
	freeze = not running


func snapshot() -> String:
	return "%s p=%s v=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_pos(linear_velocity)]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	var o := PartFactory.OUTLINE_COLOR
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var k := PartFactory.OUTLINE_W
	# Handle arc.
	draw_arc(Vector2(0, -hy), hx * 0.8, PI, TAU, 24, o, 6.0)
	# Body: slightly tapered bucket.
	var poly := PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx * 0.85, hy), Vector2(-hx * 0.85, hy)])
	Art.shadow_poly(self, poly)
	draw_colored_polygon(poly, o)
	var inner := PackedVector2Array([Vector2(-hx + k, -hy + k), Vector2(hx - k, -hy + k), Vector2(hx * 0.85 - k, hy - k), Vector2(-hx * 0.85 + k, hy - k)])
	draw_colored_polygon(inner, fill)
	draw_line(inner[0] + Vector2(4, 4), inner[3] + Vector2(4, -4), Color(fill.lightened(0.5), 0.7), 4.0)
	# Hollow interior.
	var hollow := PackedVector2Array([Vector2(-hx + wall, -hy - 1), Vector2(hx - wall, -hy - 1), Vector2(hx * 0.85 - wall, hy - wall), Vector2(-hx * 0.85 + wall, hy - wall)])
	draw_colored_polygon(hollow, Color("fbf6ea"))
	draw_polyline(PackedVector2Array([hollow[0], hollow[3], hollow[2], hollow[1]]), o, 3.0)
	draw_rect(Rect2(-hx, -hy - 6, size.x, 12), o)
	draw_rect(Rect2(-hx + 3, -hy - 3, size.x - 6, 6), fill)
