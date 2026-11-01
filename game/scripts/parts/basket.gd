extends StaticBody2D
## Basket — the classic target. Counts bodies that enter and settle inside.
## Emits `caught` once per body. The Simulation reads `caught_count` to decide the goal.

signal caught(body: Node)

var def: Dictionary
var size: Vector2 = Vector2(192, 144)
var fill: Color = Color.WHITE
var wall: float = 18.0
var caught_count: int = 0
var _inside: Array[Node] = []
var _sensor: Area2D


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	physics_material_override = pm
	# Three static walls: floor, left, right (open top).
	_add_wall(Vector2(0, size.y / 2.0 - wall / 2.0), Vector2(size.x, wall))
	_add_wall(Vector2(-size.x / 2.0 + wall / 2.0, 0), Vector2(wall, size.y))
	_add_wall(Vector2(size.x / 2.0 - wall / 2.0, 0), Vector2(wall, size.y))
	# Sensor inside the basket, slightly below the rim so a ball bouncing on the rim doesn't count.
	_sensor = Area2D.new()
	_sensor.name = "Sensor"
	_sensor.monitoring = true
	_sensor.monitorable = false
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(size.x - wall * 2.0 - 4.0, size.y - wall - 20.0)
	cs.shape = r
	cs.position = Vector2(0, 10.0 - wall / 2.0)
	_sensor.add_child(cs)
	_sensor.body_entered.connect(_on_body_entered)
	_sensor.body_exited.connect(_on_body_exited)
	add_child(_sensor)
	queue_redraw()


func _add_wall(pos: Vector2, sz: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = sz
	cs.shape = r
	cs.position = pos
	add_child(cs)


func _on_body_entered(body: Node) -> void:
	if body is RigidBody2D and not _inside.has(body):
		_inside.append(body)
		caught_count += 1
		caught.emit(body)


func _on_body_exited(body: Node) -> void:
	if _inside.has(body):
		_inside.erase(body)
		caught_count -= 1


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	return "%s p=%d,%d r=%d caught=%d" % [name, roundi(global_position.x * 1000.0), roundi(global_position.y * 1000.0), roundi(global_rotation * 10000.0), caught_count]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	var o := PartFactory.OUTLINE_COLOR
	var w := wall
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	# Outer U in outline colour, inner U in fill colour.
	draw_rect(Rect2(-hx, hy - w, size.x, w), o)
	draw_rect(Rect2(-hx, -hy, w, size.y), o)
	draw_rect(Rect2(hx - w, -hy, w, size.y), o)
	var k := PartFactory.OUTLINE_W
	draw_rect(Rect2(-hx + k, hy - w + k, size.x - 2 * k, w - 2 * k), fill)
	draw_rect(Rect2(-hx + k, -hy + k, w - 2 * k, size.y - 2 * k), fill)
	draw_rect(Rect2(hx - w + k, -hy + k, w - 2 * k, size.y - 2 * k), fill)
	# Weave stripes.
	var stripe := Color(fill.r * 0.75, fill.g * 0.75, fill.b * 0.75)
	for i in range(1, 4):
		var y := -hy + i * size.y / 4.0
		draw_line(Vector2(-hx + w, y), Vector2(hx - w, y), stripe, 2.0)
