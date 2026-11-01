extends StaticBody2D
## Pulley — a fixed wheel. Ropes that end on it continue through it as one line, so a downward
## pull on one side lifts the other. A MOTOR on the same cell turns it into a winch.

var def: Dictionary
var fill: Color = Color.WHITE
var radius: float = 30.0
var winch: Node2D = null


func configure(p_def: Dictionary) -> void:
	def = p_def
	fill = PartFactory.color_of(def)
	radius = float(def["shape"]["radius"])
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func on_attach(sim: Node) -> void:
	var m: Node2D = sim.part_at_cell(get_meta("cell"), self, 0, func(p): return p.get_meta("part_id") == "motor")
	if m != null:
		winch = m
		m.attached = self


func set_motor_on(_on: bool) -> void:
	pass  # the rope line reads winch.on every tick


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	return "%s p=%s" % [name, PartFactory.fmt_pos(global_position)]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	# Bracket.
	draw_rect(Rect2(-8, -radius - 26, 16, 30), PartFactory.OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, radius, PartFactory.OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, radius - PartFactory.OUTLINE_W, fill)
	draw_circle(Vector2.ZERO, radius * 0.25, PartFactory.OUTLINE_COLOR)
	for i in 4:
		var a := i * PI / 4.0
		draw_line(Vector2(radius * 0.3, 0).rotated(a), Vector2(radius * 0.75, 0).rotated(a), PartFactory.OUTLINE_COLOR, 3.0)
		draw_line(Vector2(-radius * 0.3, 0).rotated(a), Vector2(-radius * 0.75, 0).rotated(a), PartFactory.OUTLINE_COLOR, 3.0)
