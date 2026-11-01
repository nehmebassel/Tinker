class_name Art
extends RefCounted
## Art — the shared drawing style for parts (M6 polish).
##
## Flat fills and thick ink outlines (the brief's art direction) plus three cues that make a part
## read as a physical object on the workbench:
##   * a soft drop shadow, always cast down-right in WORLD space (it does not turn with the part)
##   * a highlight band / spot from a light at the top-left
##   * a darker lower edge
## Everything here only draws. Nothing reads or writes physics state.

const INK := Color("1f1a2e")
const OUTLINE_W := 6.0
const SHADOW := Color(0.12, 0.07, 0.22, 0.20)
const SHADOW_OFF := Vector2(6, 8)


## Shadow offset in the item's local space, so the shadow falls the same way however it is rotated.
static func shadow_off(ci: CanvasItem) -> Vector2:
	if not ci.is_inside_tree():
		return SHADOW_OFF
	var xf := ci.get_global_transform()
	return xf.affine_inverse().basis_xform(SHADOW_OFF)


static func rect(ci: CanvasItem, r: Rect2, fill: Color, shadow: bool = true, outline: float = OUTLINE_W) -> void:
	if shadow:
		ci.draw_rect(Rect2(r.position + shadow_off(ci), r.size), SHADOW)
	ci.draw_rect(r, INK)
	var inner := r.grow(-outline)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	ci.draw_rect(inner, fill.darkened(0.16))
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.74)), fill)
	var hl_h := clampf(inner.size.y * 0.22, 2.0, 7.0)
	ci.draw_rect(Rect2(inner.position + Vector2(3, 2), Vector2(maxf(inner.size.x - 6, 0), hl_h)), Color(fill.lightened(0.45), 0.75))


static func circle(ci: CanvasItem, c: Vector2, r: float, fill: Color, shadow: bool = true) -> void:
	if shadow:
		ci.draw_circle(c + shadow_off(ci), r, SHADOW)
	ci.draw_circle(c, r, INK)
	var ir := r - OUTLINE_W
	if ir <= 0.0:
		return
	ci.draw_circle(c, ir, fill.darkened(0.18))
	ci.draw_circle(c + Vector2(-ir * 0.08, -ir * 0.1), ir * 0.86, fill)
	ci.draw_circle(c + Vector2(-ir * 0.38, -ir * 0.42), ir * 0.2, Color(fill.lightened(0.6), 0.7))


static func shadow_poly(ci: CanvasItem, pts: PackedVector2Array) -> void:
	var off := shadow_off(ci)
	var s := PackedVector2Array()
	for p in pts:
		s.append(p + off)
	ci.draw_colored_polygon(s, SHADOW)


## Spoked wheel / gear face, rotated by `angle`. Used by motor, pulley and conveyor rollers so
## turning is visible.
static func wheel(ci: CanvasItem, c: Vector2, r: float, angle: float, fill: Color, spokes: int = 4, teeth: int = 0) -> void:
	if teeth > 0:
		for i in teeth:
			var a := angle + i * TAU / teeth
			var d := Vector2.RIGHT.rotated(a)
			var t := d.orthogonal() * r * 0.16
			ci.draw_colored_polygon(PackedVector2Array([c + d * r * 0.9 - t, c + d * r * 1.18 - t * 0.7, c + d * r * 1.18 + t * 0.7, c + d * r * 0.9 + t]), INK)
	ci.draw_circle(c, r, INK)
	ci.draw_circle(c, r - 4.0, fill)
	for i in spokes:
		var a := angle + i * TAU / spokes
		ci.draw_line(c + Vector2(r * 0.22, 0).rotated(a), c + Vector2(r * 0.8, 0).rotated(a), INK, maxf(2.0, r * 0.12))
	ci.draw_circle(c, r * 0.24, INK)
	ci.draw_circle(c, r * 0.12, fill.lightened(0.4))
