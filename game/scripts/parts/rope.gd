extends Node2D
## Rope — ties the part at its cell (end A) to the part `length` cells away along its facing
## (end B). It is not a body; the Simulation enforces it as a one-sided distance constraint
## (see Simulation.RopeLine). A rope whose end lands on a pulley joins the line on the other
## side of that pulley, so pulling one end lifts the other.

var def: Dictionary
var length_cells: int = 12
var line = null  # Simulation.RopeLine
var end_a: Node2D = null
var end_b: Node2D = null
var color: Color = Color.WHITE


func configure(p_def: Dictionary) -> void:
	def = p_def
	length_cells = int(def.get("length_cells", length_cells))
	color = PartFactory.color_of(def)
	z_index = 5


func cell_b() -> Vector2i:
	var dir := Vector2.RIGHT.rotated(Grid.steps_to_radians(int(get_meta("rot"))))
	var cb := Vector2(get_meta("cell")) + dir * length_cells
	return Vector2i(roundi(cb.x), roundi(cb.y))


func rope_length_px() -> float:
	return float(length_cells * Grid.CELL)


func on_attach(sim: Node) -> void:
	# Ropes never tie to another rope or to a motor: a motor is a power source that shares a cell
	# with the pulley/plank it drives, so it must not shadow that part whatever the creation order.
	var tieable := func(p): return not (p.get_meta("part_id") in ["rope", "motor"])
	end_a = sim.part_at_cell(get_meta("cell"), self, 2, tieable)
	end_b = sim.part_at_cell(cell_b(), self, 2, tieable)
	if end_a == end_b:
		end_b = null
	for e in [end_a, end_b]:
		if e != null and e.has_method("make_dynamic"):
			e.make_dynamic()
	sim.register_rope(self, end_a, end_b)


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	var la: String = end_a.name if end_a else "-"
	var lb: String = end_b.name if end_b else "-"
	var d := -1
	if end_a and end_b:
		d = roundi(end_a.global_position.distance_to(end_b.global_position) * 1000.0)
	return "%s a=%s b=%s d=%d" % [name, la, lb, d]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if line != null and line.is_slack():
		modulate.a = 0.35  # an end is gone: show the rope hanging limp
	var pa := Vector2.ZERO
	var pb := to_local(end_b.global_position) if end_b else Vector2(rope_length_px(), 0)
	if end_a:
		pa = to_local(end_a.global_position)
	# Slack rope sags a little; taut rope is straight. Purely visual.
	var d := pa.distance_to(pb)
	var slack := maxf(0.0, rope_length_px() - d)
	var mid := (pa + pb) / 2.0 + Vector2(0, slack * 0.25).rotated(-global_rotation)
	var pts := PackedVector2Array()
	for i in range(13):
		var t := i / 12.0
		pts.append(pa.lerp(mid, t).lerp(mid.lerp(pb, t), t))
	draw_polyline(pts, PartFactory.OUTLINE_COLOR, 8.0)
	draw_polyline(pts, color, 4.0)
	for p in [pa, pb]:
		draw_circle(p, 7.0, PartFactory.OUTLINE_COLOR)
		draw_circle(p, 4.0, color)
