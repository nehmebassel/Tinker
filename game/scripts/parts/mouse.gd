extends ActorBase
## Mouse — runs toward the nearest cheese, flees an awake cat that is close, trips switches
## (it is a rigid body, so pressure plates and baskets see it). Caught by the cat = out of play.

var caught: bool = false
var fear_range: float = 240.0
var sight: float = 2000.0


func configure(p_def: Dictionary) -> void:
	super.configure(p_def)
	fear_range = float(def.get("fear_range", fear_range))


func alive() -> bool:
	return not caught


func decide() -> int:
	# Fear only cats on the same level: one stuck in a pit below (or on a ledge above) is no threat.
	var cat := nearest("cat", fear_range, func(c): return c.awake and not c.scared() and absf(c.global_position.y - global_position.y) < Grid.TILE * 0.5)
	if cat != null:
		return -sign_toward(global_position, cat.global_position, 0.0) if cat.global_position.x != global_position.x else 1
	var cheese := nearest("cheese", sight, func(c): return not c.eaten)
	if cheese != null:
		# Stop once the cheese is within the mouse's own half-width (it is straight above or below).
		return sign_toward(global_position, cheese.global_position, size.x / 2.0)
	return 0


## Called by the cat on contact. Deferred: arrives from a physics callback.
func catch() -> void:
	if caught:
		return
	caught = true
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_deferred("linear_velocity", Vector2.ZERO)
	set_deferred("visible", false)


func snapshot() -> String:
	return "%s p=%s v=%s caught=%s" % [name, PartFactory.fmt_pos(global_position), PartFactory.fmt_pos(linear_velocity), caught]


func _draw() -> void:
	var o := PartFactory.OUTLINE_COLOR
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var f := float(facing)
	# Body: rounded blob, nose toward facing.
	var pts := PackedVector2Array()
	for i in range(24):
		var a := i * TAU / 24.0
		var rx := hx * (1.0 if cos(a) * f < 0 else 1.15)
		pts.append(Vector2(cos(a) * rx, sin(a) * hy))
	draw_colored_polygon(pts, o)
	var inner := PackedVector2Array()
	for i in range(24):
		var a := i * TAU / 24.0
		var rx := (hx - 5) * (1.0 if cos(a) * f < 0 else 1.15)
		inner.append(Vector2(cos(a) * rx, sin(a) * (hy - 5)))
	draw_colored_polygon(inner, fill)
	# Ear, eye, nose, tail.
	draw_circle(Vector2(-f * hx * 0.2, -hy * 0.9), hy * 0.4, o)
	draw_circle(Vector2(-f * hx * 0.2, -hy * 0.9), hy * 0.4 - 4, Color("ffb3c1"))
	draw_circle(Vector2(f * hx * 0.45, -hy * 0.25), 4.0, o)
	draw_circle(Vector2(f * hx * 1.12, 0), 5.0, Color("ff5d73"))
	draw_line(Vector2(-f * hx, hy * 0.3), Vector2(-f * hx * 1.8, -hy * 0.2), o, 3.0)
