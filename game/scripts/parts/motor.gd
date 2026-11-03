extends StaticBody2D
## Motor — a powered pivot. Whatever part sits on the same cell is "attached":
##   plank    -> pinned at its centre; on = spinning paddle, off = free see-saw
##   conveyor -> runs only while the motor is on
##   pulley   -> winch: shortens the rope line while on
## Facing decides the spin direction: rot steps 0..11 clockwise, 12..23 counter-clockwise.
## Toggleable by a switch.

var def: Dictionary
var fill: Color = Color.WHITE
var on: bool = true
var speed: float = 3.5  # rad/s for paddles
var winch_speed: float = 120.0  # px/s of rope pulled in
var direction: int = 1
var attached: Node2D = null
var radius: float = 20.0
var _spin: float = 0.0  # visual only


func configure(p_def: Dictionary) -> void:
	def = p_def
	fill = PartFactory.color_of(def)
	radius = float(def["shape"]["radius"])
	speed = float(def.get("speed", speed))
	winch_speed = float(def.get("winch_speed", winch_speed))
	on = bool(PartFactory.state_of(self, "on", true))
	direction = 1 if int(get_meta("rot")) < 12 else -1
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func toggle() -> void:
	on = not on
	if attached != null and attached.has_method("set_motor_on"):
		attached.set_motor_on(on)
	queue_redraw()


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	return "%s p=%s on=%s" % [name, PartFactory.fmt_pos(global_position), on]


func set_ghost(p_on: bool) -> void:
	modulate.a = 0.45 if p_on else 1.0


func _process(delta: float) -> void:
	if running_visual() and on:
		_spin += delta * speed * float(direction)
		if FramePacer.anim():
			queue_redraw()


## Motors have no running flag of their own: they turn while their simulation runs.
func running_visual() -> bool:
	var p := get_parent()
	return p != null and p.get("running") == true


func _draw() -> void:
	Art.circle(self, Vector2.ZERO, radius + 6.0, Color("8d8aa8"))
	Art.wheel(self, Vector2.ZERO, radius, _spin, fill if on else fill.darkened(0.45), 3, 8)
	# Direction arrow around the hub.
	var c := Art.INK
	var pts := PackedVector2Array()
	for i in range(9):
		var a := -2.4 + i * 0.4 * direction
		pts.append(Vector2(radius + 14.0, 0).rotated(a))
	draw_polyline(pts, Color(c, 0.55), 3.0)
	var tip := pts[-1]
	var tang := (pts[-1] - pts[-2]).normalized()
	draw_line(tip, tip - tang.rotated(0.6) * 8.0, Color(c, 0.55), 3.0)
	draw_line(tip, tip - tang.rotated(-0.6) * 8.0, Color(c, 0.55), 3.0)
