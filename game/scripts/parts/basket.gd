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
var _back: Node2D  # inside of the basket, drawn behind every part (z -1)
var _marker: Node2D  # "target" bullseye / solved check, drawn above parts
var _t: float = 0.0  # visual clock
var _won_t: float = -1.0  # seconds since the goal was met (visual)
const WICKER := Color("d49a52")
const WICKER_DARK := Color("9c6530")
const INSIDE := Color("5a3a22")


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
	_back = Node2D.new()
	_back.z_index = -1
	_back.draw.connect(_draw_back)
	add_child(_back)
	_marker = Node2D.new()
	_marker.z_index = 6
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	queue_redraw()


func _add_wall(pos: Vector2, sz: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = sz
	cs.shape = r
	cs.position = pos
	add_child(cs)


## Only things that can "land" count: never a plank (planks are rigid bodies so they can hang on
## ropes, but a frozen ramp poking into the sensor must not satisfy the goal).
func _catchable(body: Node) -> bool:
	if not (body is RigidBody2D) or not body.has_meta("part_id"):
		return false
	return str(body.get_meta("part_id")) in def.get("catches", ["ball", "mouse", "cheese", "bucket", "balloon"])


func _on_body_entered(body: Node) -> void:
	if _catchable(body) and not _inside.has(body):
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


## The level's goal is "get things into the basket" (marker shows only then).
func _is_goal() -> bool:
	var sim := get_parent()
	if sim == null or sim.get("level") == null:
		return false
	return str(sim.level.goal.get("type", "")) == "basket"


func _goal_met() -> bool:
	var sim := get_parent()
	return _is_goal() and caught_count >= int(sim.level.goal.get("count", 1))


func _process(delta: float) -> void:
	_t += delta
	# Latched: once the goal is met this run the check stays (freezing bodies at the end of a run can
	# briefly report them as leaving the sensor). The node is rebuilt on rewind, which clears it.
	if _won_t >= 0.0 or _goal_met():
		_won_t = maxf(_won_t, 0.0) + delta
	_marker.queue_redraw()


func _draw_back() -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var r := Rect2(-hx + wall * 0.6, -hy + 6.0, size.x - wall * 1.2, size.y - wall * 0.6)
	_back.draw_rect(r, INSIDE)
	# Inner weave shadow lines.
	for i in range(1, 6):
		var y := r.position.y + i * r.size.y / 6.0
		_back.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0, 0, 0, 0.18), 3.0)


func _draw() -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var w := wall
	var o := Art.INK
	var so := Art.shadow_off(self)
	# Walls + floor as one woven U (shadow under the U only: the inside is open).
	var parts := [Rect2(-hx, -hy, w, size.y), Rect2(hx - w, -hy, w, size.y), Rect2(-hx, hy - w, size.x, w)]
	for rr in parts:
		draw_rect(Rect2(rr.position + so, rr.size), Art.SHADOW)
	for rr in parts:
		draw_rect(rr, o)
	for rr in parts:
		var inner: Rect2 = rr.grow(-4.0)
		draw_rect(inner, WICKER)
		# Basket weave: short alternating strands.
		var step := 12.0
		var row := 0
		var y := inner.position.y
		while y < inner.end.y - 1.0:
			var x := inner.position.x + (step * 0.5 if row % 2 == 1 else 0.0)
			while x < inner.end.x - 1.0:
				var seg := Rect2(Vector2(x, y + 1.0), Vector2(minf(step - 3.0, inner.end.x - x), minf(step * 0.5 - 1.5, inner.end.y - y - 1.0)))
				draw_rect(seg, WICKER_DARK if (row + int(x / step)) % 2 == 0 else WICKER.lightened(0.15))
				x += step
			y += step * 0.5
			row += 1
	# Rim: rounded lips on both walls and a ribbon in the part colour.
	for sx in [-1.0, 1.0]:
		var c := Vector2(sx * (hx - w / 2.0), -hy)
		draw_circle(c, w * 0.75, o)
		draw_circle(c, w * 0.75 - 4.0, WICKER.lightened(0.1))
		draw_circle(c + Vector2(-3, -3), w * 0.2, Color(1, 1, 1, 0.5))
	var band := Rect2(-hx + 2, hy - w - 10.0, size.x - 4, 8.0)
	draw_rect(band, o)
	draw_rect(band.grow(-2.0), fill)


func _draw_marker() -> void:
	if not _is_goal():
		return
	var top := Vector2(0, -size.y / 2.0 - 96.0)
	_marker.draw_set_transform(top, 0.0, Vector2(1.6, 1.6))  # big enough to read at full-board zoom
	top = Vector2.ZERO
	if _won_t >= 0.0:
		# Solved: green check badge with a pop-in and sparkles.
		var k := minf(1.0, _won_t * 4.0)
		var r := 34.0 * (0.6 + 0.4 * k) + 4.0 * sin(_won_t * 8.0) * (1.0 - minf(1.0, _won_t))
		_marker.draw_circle(top, r + 5.0, Art.INK)
		_marker.draw_circle(top, r, Color("7bd389"))
		_marker.draw_polyline(PackedVector2Array([top + Vector2(-r * 0.45, 0), top + Vector2(-r * 0.1, r * 0.35), top + Vector2(r * 0.5, -r * 0.35)]), Art.INK, 7.0)
		for i in 8:
			var a := i * TAU / 8.0 + _won_t
			var d := r + 14.0 + _won_t * 30.0
			var al := clampf(1.0 - _won_t, 0.0, 1.0)
			_marker.draw_circle(top + Vector2(cos(a), sin(a)) * d, 5.0, Color(1.0, 0.85, 0.3, al))
		return
	# Target: bullseye with a down arrow, gently bobbing so the goal is obvious at a glance.
	var bob := sin(_t * 3.0) * 8.0
	var c := top + Vector2(0, bob)
	_marker.draw_circle(c + Vector2(3, 5), 30.0, Color(0, 0, 0, 0.15))
	var rings := [[30.0, Art.INK], [26.0, Color("ff5d73")], [19.0, Color("fdfaf1")], [12.0, Color("ff5d73")], [5.0, Color("fdfaf1")]]
	for ring in rings:
		_marker.draw_circle(c, ring[0], ring[1])
	var a0 := c + Vector2(0, 36)
	_marker.draw_colored_polygon(PackedVector2Array([a0 + Vector2(-14, 0), a0 + Vector2(14, 0), a0 + Vector2(0, 18)]), Art.INK)
	_marker.draw_colored_polygon(PackedVector2Array([a0 + Vector2(-9, 3), a0 + Vector2(9, 3), a0 + Vector2(0, 13)]), Color("ff5d73"))
