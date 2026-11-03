extends StaticBody2D
## Candle — lit or unlit. A lit flame pops balloons, scares the cat, and lights an unlit candle
## whose wick it overlaps. Level goal "candle" = every candle that started unlit is lit.

var def: Dictionary
var size: Vector2 = Vector2(36, 84)
var fill: Color = Color.WHITE
var lit: bool = true
var lit_at_start: bool = true
var flame_reach: float = 60.0
var running: bool = false
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
	# Flames act only during a run; while building, the stage must show the real initial setup.
	if not lit or not running:
		return
	if body.has_method("pop"):
		body.pop()
	if body.has_method("scare"):
		body.scare(self)


func _on_flame_area(area: Area2D) -> void:
	if not lit or not running:
		return
	var other := area.get_parent()
	if other != self and other.has_method("light"):
		other.light()


func set_running(p_running: bool) -> void:
	running = p_running
	if running and lit:
		# Overlaps that already exist at PLAY would never fire *_entered again: process them now,
		# in creation order.
		for body in PartFactory.sorted_bodies(_flame):
			_on_flame_body(body)
		var areas := _flame.get_overlapping_areas()
		areas.sort_custom(func(x, y): return int(x.get_parent().get_meta("part_index", 1 << 30)) < int(y.get_parent().get_meta("part_index", 1 << 30)))
		for a in areas:
			_on_flame_area(a)


func snapshot() -> String:
	return "%s p=%s lit=%s" % [name, PartFactory.fmt_pos(global_position), lit]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


func _process(_delta: float) -> void:
	if lit:
		if FramePacer.anim():
			queue_redraw()  # flicker (time-based, visual only), paced for battery


func _draw() -> void:
	var r := Rect2(-size / 2.0, size)
	Art.rect(self, r, fill)
	# Wax drip.
	draw_circle(Vector2(size.x * 0.18, -size.y / 2.0 + 14.0), 5.0, fill.lightened(0.3))
	# Wick.
	draw_line(Vector2(0, -size.y / 2.0), Vector2(0, -size.y / 2.0 - 12.0), Art.INK, 4.0)
	if lit:
		var t := Time.get_ticks_msec() / 1000.0 + float(get_meta("part_index", 0))
		var k := 1.0 + 0.09 * sin(t * 13.0) + 0.05 * sin(t * 7.3)
		var sway := 2.5 * sin(t * 5.1)
		var tip := Vector2(0, -size.y / 2.0 - 14.0)
		draw_circle(tip + Vector2(0, -16), 34.0 * k, Color(1.0, 0.75, 0.3, 0.12))
		var outer := PackedVector2Array([tip + Vector2(-16, 0), tip + Vector2(sway, -44 * k), tip + Vector2(16, 0), tip + Vector2(0, 10)])
		draw_colored_polygon(outer, Color("ff9a3c"))
		var inner := PackedVector2Array([tip + Vector2(-8, -2), tip + Vector2(sway * 0.6, -24 * k), tip + Vector2(8, -2), tip + Vector2(0, 6)])
		draw_colored_polygon(inner, Color("ffe066"))
