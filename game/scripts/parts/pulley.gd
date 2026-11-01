extends StaticBody2D
## Pulley — a fixed wheel. Ropes that end on it continue through it as one line, so a downward
## pull on one side lifts the other. A MOTOR on the same cell turns it into a winch.

var def: Dictionary
var fill: Color = Color.WHITE
var radius: float = 30.0
var winch: Node2D = null
var _spin: float = 0.0  # visual only
var _rope_ref: float = -1.0


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
