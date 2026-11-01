class_name WorkshopBg
extends Control
## Light pegboard backdrop for menu screens (world select, board, settings). Drawn, no textures.

const WALL := Color("ecdfc4")
const HOLE := Color("d8c39c")
const STEP := 56.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WALL)
	var y := STEP * 0.5
	var row := 0
	while y < size.y:
		var x := STEP * (0.5 if row % 2 == 0 else 1.0)
		while x < size.x:
			draw_circle(Vector2(x, y), 6.0, HOLE)
			draw_circle(Vector2(x + 1.5, y + 2.0), 4.0, HOLE.darkened(0.12))
			x += STEP
		y += STEP
		row += 1
