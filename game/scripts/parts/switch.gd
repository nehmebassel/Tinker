extends StaticBody2D
## Switch — a pressure plate. When a body lands on it, it toggles its target: the NEAREST
## fan, motor or conveyor (cell distance; ties go to the lowest part index). Re-arms when the
## plate is empty again. The link is drawn as a dashed line while building.

const TOGGLEABLE := ["fan", "motor", "conveyor"]

var def: Dictionary
var size: Vector2 = Vector2(96, 24)
var fill: Color = Color.WHITE
var target: Node2D = null
var pressed: bool = false
var toggles: int = 0
var running: bool = false
var _plate: Area2D
var _empty_ticks: int = 0
const REARM_TICKS := 20


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	# The solid part is a thin slab at the bottom of the 24 px rect, so a switch placed one cell
	# above a floor sits flush on it and a mouse can step onto it. The plate sensor fills the rest.
	var cs := CollisionShape2D.new()
	var slab := RectangleShape2D.new()
	slab.size = Vector2(size.x, 10.0)
	cs.shape = slab
	cs.position = Vector2(0, size.y / 2.0 - 5.0)
	add_child(cs)
	_plate = Area2D.new()
	_plate.name = "Plate"
	_plate.monitorable = false
	var pcs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(size.x - 8.0, 22.0)
	pcs.shape = r
	pcs.position = Vector2(0, size.y / 2.0 - 10.0 - 11.0)
	_plate.add_child(pcs)
	add_child(_plate)
	queue_redraw()


func on_attach(sim: Node) -> void:
	target = sim.nearest_part(self, func(p): return p.get_meta("part_id") in TOGGLEABLE)
	# A conveyor (or pulley/plank) with a motor on its cell is controlled through that motor.
	# Looked up directly, not via target.motor: the conveyor's own on_attach may not have run yet.
	if target != null and target.get_meta("part_id") != "motor":
		var m: Node2D = sim.part_at_cell(target.get_meta("cell"), target, 0, func(p): return p.get_meta("part_id") == "motor")
		if m != null:
			target = m


func get_link_target() -> Node2D:
	return target


func set_running(p_running: bool) -> void:
	running = p_running
	pressed = false
	_empty_ticks = 0


func _physics_process(_delta: float) -> void:
	if not running:
		return
	var occupied := false
	for body in PartFactory.sorted_bodies(_plate):
		if body is RigidBody2D and not body.freeze:
			occupied = true
			break
	if occupied:
		_empty_ticks = 0
		if not pressed:
			pressed = true
			toggles += 1
			if target != null and target.has_method("toggle"):
				target.toggle()
			queue_redraw()
	elif pressed:
		# Re-arm only after the plate has been empty for a moment: a hopping mouse or a bouncing
		# ball must not toggle twice.
		_empty_ticks += 1
		if _empty_ticks >= REARM_TICKS:
			pressed = false
			queue_redraw()


func snapshot() -> String:
	return "%s p=%s pressed=%s toggles=%d" % [name, PartFactory.fmt_pos(global_position), pressed, toggles]


func set_ghost(p_on: bool) -> void:
	modulate.a = 0.45 if p_on else 1.0


func _draw() -> void:
	var base := Rect2(-size.x / 2.0, size.y / 2.0 - 10.0, size.x, 10.0)
	Art.rect(self, base, Color("4a4670"), true, 3.0)
	var h := 5.0 if pressed else 12.0
	var plate := Rect2(-size.x / 2.0 + 10.0, size.y / 2.0 - 10.0 - h, size.x - 20.0, h)
	Art.rect(self, plate, fill if not pressed else fill.darkened(0.2), false, 3.0)
	# Indicator light: green when pressed.
	draw_circle(Vector2(size.x / 2.0 - 6.0, size.y / 2.0 - 5.0), 3.0, Color("7bd389") if pressed else Color("ff5d73"))
