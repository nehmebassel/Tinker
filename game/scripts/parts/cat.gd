extends ActorBase
## Cat — sleeps until a mouse comes within `wake_range`, then chases it. A lit candle within
## `fear_range` (or touching its flame) scares it: it runs away from the candle for a while.
## Touching the mouse catches it.

var awake: bool = false
var wake_range: float = 420.0
var fear_range: float = 160.0
var scared_ticks: int = 0
var _scared_by: Node2D = null


func configure(p_def: Dictionary) -> void:
	super.configure(p_def)
	wake_range = float(def.get("wake_range", wake_range))
	fear_range = float(def.get("fear_range", fear_range))
	awake = bool(PartFactory.state_of(self, "awake", false))
	body_entered.connect(_on_body_entered)


func scared() -> bool:
	return scared_ticks > 0


## Called by a lit candle's flame.
func scare(candle: Node2D) -> void:
	scared_ticks = 90
	_scared_by = candle
	awake = true


func decide() -> int:
	var candle := nearest("candle", fear_range, func(c): return c.lit)
	if candle != null:
		scare(candle)
	if scared_ticks > 0:
		scared_ticks -= 1
		if _scared_by != null:
			var s := sign_toward(global_position, _scared_by.global_position, 0.0)
			return -s if s != 0 else 1
	var mouse := nearest("mouse", wake_range if not awake else 4000.0, func(m): return not m.caught)
	if mouse == null:
		return 0
	awake = true
	return sign_toward(global_position, mouse.global_position, 4.0)


func _on_body_entered(body: Node) -> void:
	# A scared cat is running away, not hunting: it never catches.
	# ...and it cannot catch what is standing on its head (a mouse crossing a pit over it).
	if running and not scared() and body.has_method("catch") and body.global_position.y > global_position.y - size.y * 0.45:
		body.catch()
		awake = true


func snapshot() -> String:
	return "%s p=%s v=%s awake=%s scared=%d" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_pos(linear_velocity), awake, scared_ticks]


func _draw() -> void:
	var o := PartFactory.OUTLINE_COLOR
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var f := float(facing)
	var r := Rect2(-hx, -hy, size.x, size.y)
	# Body.
	draw_rect(r, o)
	draw_rect(r.grow(-5), fill)
	# Head.
	var head := Vector2(f * hx * 0.7, -hy * 0.8)
	draw_circle(head, hy * 0.75, o)
	draw_circle(head, hy * 0.75 - 5, fill)
	for s in [-1, 1]:
		var ear := head + Vector2(s * hy * 0.45, -hy * 0.55)
		draw_colored_polygon(PackedVector2Array([ear + Vector2(-10, 10), ear + Vector2(10, 10), ear + Vector2(0, -14)]), o)
	# Eyes: closed when asleep.
	if awake:
		draw_circle(head + Vector2(f * 8, -4), 4.0, o)
		draw_circle(head + Vector2(-f * 6, -4), 4.0, o)
	else:
		draw_line(head + Vector2(-12, -2), head + Vector2(-4, -2), o, 3.0)
		draw_line(head + Vector2(4, -2), head + Vector2(12, -2), o, 3.0)
	# Tail.
	draw_arc(Vector2(-f * hx * 1.1, -hy * 0.6), hy * 0.7, 0.0, PI, 12, o, 4.0)
