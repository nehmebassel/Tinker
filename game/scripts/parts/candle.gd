extends StaticBody2D
## Candle — lit or unlit. A lit flame pops balloons, scares the cat, and lights an unlit candle
## whose wick it overlaps. Level goal "candle" = every candle that started unlit is lit.

var def: Dictionary
var size: Vector2 = Vector2(36, 84)
var fill: Color = Color.WHITE
var lit: bool = true
var lit_at_start: bool = true
var flame_reach: float = 60.0
var _flame: Area2D
var _wick: Area2D


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	flame_reach = float(def.get("flame_reach", flame_reach))
	lit = bool(PartFactory.state_of(self, "lit", true))
	lit_at_start = lit
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	# Flame: detects bodies (balloon, cat) and other candles' wicks.
	_flame = Area2D.new()
	_flame.name = "Flame"
	_flame.monitorable = false
	_flame.monitoring = lit
	var fcs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = flame_reach * 0.5
	fcs.shape = c
	fcs.position = Vector2(0, -size.y / 2.0 - flame_reach * 0.45)
	_flame.add_child(fcs)
	_flame.body_entered.connect(_on_flame_body)
	_flame.area_entered.connect(_on_flame_area)
	add_child(_flame)
	# Wick: a small monitorable area other flames can find.
	_wick = Area2D.new()
	_wick.name = "Wick"
	_wick.monitoring = false
	_wick.monitorable = true
	var wcs := CollisionShape2D.new()
	var w := CircleShape2D.new()
	w.radius = 10.0
	wcs.shape = w
	wcs.position = Vector2(0, -size.y / 2.0 - 6.0)
	_wick.add_child(wcs)
	add_child(_wick)
	queue_redraw()


func light() -> void:
	if lit:
		return
	lit = true
	_flame.set_deferred("monitoring", true)
	queue_redraw()


func _on_flame_body(body: Node) -> void:
	if not lit:
		return
	if body.has_method("pop"):
		body.pop()
	if body.has_method("scare"):
		body.scare(self)


func _on_flame_area(area: Area2D) -> void:
	if not lit:
		return
	var other := area.get_parent()
	if other != self and other.has_method("light"):
		other.light()


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	return "%s p=%s lit=%s" % [name, PartFactory.fmt_pos(global_position), lit]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _draw() -> void:
	var r := Rect2(-size / 2.0, size)
	draw_rect(r, PartFactory.OUTLINE_COLOR)
	draw_rect(r.grow(-PartFactory.OUTLINE_W), fill)
	# Wick.
	draw_line(Vector2(0, -size.y / 2.0), Vector2(0, -size.y / 2.0 - 12.0), PartFactory.OUTLINE_COLOR, 4.0)
	if lit:
		var tip := Vector2(0, -size.y / 2.0 - 14.0)
		var outer := PackedVector2Array([tip + Vector2(-16, 0), tip + Vector2(0, -44), tip + Vector2(16, 0), tip + Vector2(0, 10)])
		draw_colored_polygon(outer, Color("ff9a3c"))
		var inner := PackedVector2Array([tip + Vector2(-8, -2), tip + Vector2(0, -24), tip + Vector2(8, -2), tip + Vector2(0, 6)])
		draw_colored_polygon(inner, Color("ffe066"))
