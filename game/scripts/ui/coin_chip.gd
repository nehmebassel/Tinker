class_name CoinChip
extends Button
## CoinChip — the coin balance in a top bar; tap opens the shop. Hidden while coins are off (admin).

var _shown := -1


static func make(h: float = 100.0) -> CoinChip:
	var c := CoinChip.new()
	c.name = "CoinChip"
	c.custom_minimum_size = Vector2(190, h)
	c.focus_mode = Control.FOCUS_NONE
	c.flat = true
	return c


func _ready() -> void:
	draw.connect(_draw_chip)
	pressed.connect(func() -> void: ShopPanel.open(get_tree().current_scene))
	if has_node("/root/App"):
		App.wallet.changed.connect(_refresh)
		App.economy_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = has_node("/root/App") and App.economy.on("coins")
	if visible and _shown >= 0 and App.wallet.coins != _shown:
		# A little bounce when the balance changes.
		pivot_offset = size / 2.0
		var t := create_tween()
		t.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12)
		t.tween_property(self, "scale", Vector2.ONE, 0.18)
	_shown = App.wallet.coins if has_node("/root/App") else 0
	queue_redraw()


func _draw_chip() -> void:
	var r := Rect2(Vector2(0, size.y * 0.14), Vector2(size.x, size.y * 0.72))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3b375e")
	sb.set_corner_radius_all(int(r.size.y / 2))
	sb.border_color = Color("ffd43b")
	sb.set_border_width_all(4)
	draw_style_box(sb, r)
	var c := Vector2(r.position.x + r.size.y / 2.0 + 4, r.get_center().y)
	CoinChip.draw_coin(self, c, r.size.y * 0.36)
	var f := ThemeDB.fallback_font
	var s := str(_shown if _shown >= 0 else 0)
	draw_string(f, Vector2(c.x + r.size.y * 0.5, r.get_center().y + 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiKit.PANEL_TXT)
	# "+" hint: tap to get more.
	var px := r.end.x - 26
	draw_line(Vector2(px - 9, r.get_center().y), Vector2(px + 9, r.get_center().y), Color("ffd43b"), 4)
	draw_line(Vector2(px, r.get_center().y - 9), Vector2(px, r.get_center().y + 9), Color("ffd43b"), 4)


static func draw_coin(n: CanvasItem, c: Vector2, r: float) -> void:
	n.draw_circle(c, r + 3, UiKit.INK)
	n.draw_circle(c, r, Color("ffd43b"))
	n.draw_circle(c, r * 0.68, Color("f2a93b"))
	n.draw_arc(c, r * 0.68, -2.2, -0.6, 10, Color(1, 1, 1, 0.7), 2.5)
	# A little gear tooth ring: it's Tinker money.
	for i in 8:
		var a := TAU * i / 8.0
		n.draw_line(c + Vector2.from_angle(a) * r * 0.28, c + Vector2.from_angle(a) * r * 0.5, UiKit.INK, 2.0)
