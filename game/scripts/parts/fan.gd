extends StaticBody2D
## Fan — pushes bodies in its facing direction (+X local) inside a cone. Strength falls off
## with distance and is scaled by each part's `wind_factor` (balloon 1.0 ... ball 0.12).
## Toggleable by a switch. Wind is applied at sample points so a paddle on a pivot turns.

var def: Dictionary
var fill: Color = Color.WHITE
var on: bool = true
var strength: float = 2600.0  # force at the mouth for wind_factor 1
var reach: float = 480.0  # px
var half_angle_tan: float = 0.45
var running: bool = false
var _cone: Area2D


func configure(p_def: Dictionary) -> void:
	def = p_def
	fill = PartFactory.color_of(def)
	strength = float(def.get("strength", strength))
	reach = float(def.get("reach", reach))
	half_angle_tan = tan(deg_to_rad(float(def.get("half_angle_deg", 24.0))))
	on = bool(PartFactory.state_of(self, "on", true))
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	_cone = Area2D.new()
	_cone.name = "Cone"
	_cone.monitorable = false
	var poly := CollisionPolygon2D.new()
	var hw := float(def["shape"]["w"]) / 2.0
	var mouth := float(def["shape"]["h"]) / 2.0
	poly.polygon = PackedVector2Array([
		Vector2(hw, -mouth), Vector2(hw + reach, -(mouth + reach * half_angle_tan)),
		Vector2(hw + reach, mouth + reach * half_angle_tan), Vector2(hw, mouth)])
	_cone.add_child(poly)
	add_child(_cone)
	queue_redraw()


func toggle() -> void:
	on = not on
	queue_redraw()


func set_running(p_running: bool) -> void:
	running = p_running


func _physics_process(_delta: float) -> void:
	if not running or not on:
		return
	var hw := float(def["shape"]["w"]) / 2.0
	var mouth := float(def["shape"]["h"]) / 2.0
	for body in PartFactory.sorted_bodies(_cone):
		if not (body is RigidBody2D) or body.freeze:
			continue
		var bdef: Dictionary = PartRegistry.get_def(body.get_meta("part_id"))
		var factor := float(bdef.get("wind_factor", 0.4))
		if factor <= 0.0:
			continue
		var samples: Array = body.wind_sample_points() if body.has_method("wind_sample_points") else [Vector2.ZERO]
		var dir := Vector2.RIGHT.rotated(global_rotation)
		var n := samples.size()
		for s in samples:
			var world_pt: Vector2 = body.to_global(s)
			var local := to_local(world_pt)
			var x := local.x - hw
			if x < 0.0 or x > reach or absf(local.y) > mouth + x * half_angle_tan:
				continue
			var falloff := 1.0 - x / reach
			var f := strength * factor * falloff / n
			body.apply_force(dir * f, world_pt - body.global_position)


func snapshot() -> String:
	return "%s p=%s r=%s on=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_rot(global_rotation), on]


func set_ghost(p_on: bool) -> void:
	modulate.a = 0.45 if p_on else 1.0


func _draw() -> void:
	var w := float(def["shape"]["w"])
	var h := float(def["shape"]["h"])
	var r := Rect2(-w / 2.0, -h / 2.0, w, h)
	draw_rect(r, PartFactory.OUTLINE_COLOR)
	draw_rect(r.grow(-PartFactory.OUTLINE_W), fill if on else fill.darkened(0.45))
	# Blades: a circle with three vanes.
	draw_circle(Vector2.ZERO, h * 0.32, PartFactory.OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, h * 0.32 - 4.0, Color("fbf6ea"))
	for i in 3:
		var a := i * TAU / 3.0
		draw_line(Vector2.ZERO, Vector2(h * 0.26, 0).rotated(a), PartFactory.OUTLINE_COLOR, 4.0)
	# Wind lines when on.
	if on:
		for i in 3:
			var y := (i - 1) * h * 0.3
			draw_line(Vector2(w / 2.0 + 8, y), Vector2(w / 2.0 + 40 + 10 * absf(i - 1), y), Color(PartFactory.OUTLINE_COLOR, 0.35), 3.0)
