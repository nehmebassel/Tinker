class_name FailArt
extends RefCounted
## Drawn icons for the run result (M6): hearts for tries, a sad face, a circular "try again" arrow.
## Drawn rather than font glyphs: the web font has no emoji or arrow symbols.

const INK := Color("1f1a2e")
const HEART := Color("ff5d73")
const EMPTY := Color("6d68a0")


static func heart(ci: CanvasItem, c: Vector2, s: float, full: bool) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var t := i * TAU / 40.0
		# Classic heart curve, scaled to roughly s x s, point down.
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * (s / 34.0))
	ci.draw_colored_polygon(pts, INK)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.78)
	ci.draw_colored_polygon(inner, HEART if full else EMPTY)
	if full:
		ci.draw_circle(c + Vector2(-s * 0.2, -s * 0.18), s * 0.09, Color(1, 1, 1, 0.6))


static func hearts(ci: CanvasItem, origin: Vector2, left: int, total: int, s: float) -> void:
	for i in total:
		heart(ci, origin + Vector2(s * 0.5 + i * s * 1.15, s * 0.5), s, i < left)


static func sad_face(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(4, 6), r, Color(0, 0, 0, 0.2))
	ci.draw_circle(c, r, INK)
	ci.draw_circle(c, r - 6.0, Color("ffd43b"))
	ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.18, Color(1, 1, 1, 0.35))
	for sx in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(sx * r * 0.33, -r * 0.18), r * 0.1, INK)
		# Worried eyebrows.
		ci.draw_line(c + Vector2(sx * r * 0.18, -r * 0.42), c + Vector2(sx * r * 0.48, -r * 0.34), INK, maxf(3.0, r * 0.07))
	# Frown.
	ci.draw_arc(c + Vector2(0, r * 0.55), r * 0.38, PI + 0.5, TAU - 0.5, 16, INK, maxf(4.0, r * 0.09))
	# A tear.
	var tc := c + Vector2(r * 0.36, r * 0.02)
	ci.draw_colored_polygon(PackedVector2Array([tc + Vector2(0, -r * 0.12), tc + Vector2(r * 0.07, r * 0.04), tc + Vector2(-r * 0.07, r * 0.04)]), Color("6ec6ff"))
	ci.draw_circle(tc + Vector2(0, r * 0.05), r * 0.07, Color("6ec6ff"))


## Circular arrow (about 300 degrees, arrowhead at the end), like a "replay" icon.
static func retry(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(4.0, r * 0.22)
	var a0 := -PI * 0.35
	var a1 := a0 + PI * 1.65
	ci.draw_arc(c, r, a0, a1, 32, col, w)
	var tip := c + Vector2(cos(a1), sin(a1)) * r
	var tang := Vector2(-sin(a1), cos(a1))
	var norm := Vector2(cos(a1), sin(a1))
	ci.draw_colored_polygon(PackedVector2Array([tip + tang * r * 0.55, tip + norm * r * 0.42, tip - norm * r * 0.42]), col)
