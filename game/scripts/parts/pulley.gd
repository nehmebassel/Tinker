extends StaticBody2D
## Pulley — a fixed wheel. Ropes that end on it continue through it as one line, so a downward
## pull on one side lifts the other. A MOTOR on the same cell turns it into a winch.

var def: Dictionary
var fill: Color = Color.WHITE
var radius: float = 30.0
var winch: Node2D = null
var _spin: float = 0.0  # visual only
var _rope_ref: float = -1.0
const RopeScript := preload("res://scripts/parts/rope.gd")


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


func _process(_delta: float) -> void:
	# The wheel turns with the rope: angle = rope travelled / radius. Read-only.
	var sim := get_parent()
	if sim == null or sim.get("running") != true:
		return
	for rl in sim.rope_lines:
		var i: int = rl.chain.find(self)
		if i > 0:
			var d: float = global_position.distance_to(rl.chain[0].global_position)
			if _rope_ref < 0.0:
				_rope_ref = d
			var a := (d - _rope_ref) / radius
			if absf(a - _spin) > 0.001:
				_spin = a
				queue_redraw()
			return


func _draw() -> void:
	# Bracket.
	Art.rect(self, Rect2(-9, -radius - 28, 18, 32), Color("8d8aa8"))
	Art.circle(self, Vector2.ZERO, radius, fill)
	Art.wheel(self, Vector2.ZERO, radius - 7.0, _spin, fill.lightened(0.15), 4)
	draw_arc(Vector2.ZERO, radius - 3.0, 0, TAU, 32, Color(Art.INK, 0.4), 2.0)
	_draw_rope_wrap()


## The rope runs OVER the wheel: from the tangent point facing one end, across the top, to the
## tangent point facing the other end (drawn here because the wheel is under it).
func _draw_rope_wrap() -> void:
	var sim := get_parent()
	if sim == null or sim.get("rope_lines") == null:
		return
	for rl in sim.rope_lines:
		var i: int = rl.chain.find(self)
		if i <= 0 or i >= rl.chain.size() - 1:
			continue
		var c := global_position
		var t1 := RopeScript.pulley_tangent(c, radius, rl.pt(i - 1)) - c
		var t2 := RopeScript.pulley_tangent(c, radius, rl.pt(i + 1)) - c
		var a1 := t1.angle()
		var a2 := t2.angle()
		# Of the two ways round, take the one over the top (its midpoint has the smaller y).
		var d := wrapf(a2 - a1, -PI, PI)
		var mid := a1 + d / 2.0
		if sin(mid) > 0.0:
			d = d - TAU if d > 0.0 else d + TAU
		var col: Color = rl.ropes[0].color if not rl.ropes.is_empty() else Color("d9a066")
		var pts := PackedVector2Array()
		for k in 17:
			pts.append(Vector2.from_angle(a1 + d * k / 16.0) * radius)
		draw_polyline(pts, Art.INK, 9.0)
		draw_polyline(pts, col, 5.0)
