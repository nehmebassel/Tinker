extends StaticBody2D
## Plank — a static ramp at launch (M1). See-saw mode (pinned at a point) lands in M2.

var def: Dictionary
var size: Vector2 = Vector2(192, 24)
var fill: Color = Color.WHITE


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 0.6))
	pm.bounce = float(def.get("bounce", 0.0))
	physics_material_override = pm
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	return "%s p=%d,%d r=%d" % [name, roundi(global_position.x * 1000.0), roundi(global_position.y * 1000.0), roundi(global_rotation * 10000.0)]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	var r := Rect2(-size / 2.0, size)
	draw_rect(r, PartFactory.OUTLINE_COLOR)
	draw_rect(r.grow(-PartFactory.OUTLINE_W), fill)
	# Wood grain line so the direction reads at a glance.
	draw_line(Vector2(-size.x * 0.4, 0), Vector2(size.x * 0.4, 0), Color(fill.r * 0.7, fill.g * 0.7, fill.b * 0.7), 3.0)
