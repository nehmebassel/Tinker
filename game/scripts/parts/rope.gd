extends Node2D
## Rope — ties two SNAP POINTS together (M6 rework).
##
## Snap points ("anchors") are declared per part in game/parts/<id>.json as local pixel offsets:
## the bucket's handle, both ends and the middle of a plank, the balloon's knot, the centre of a
## ball / cheese / mouse / cat / pulley. Parts without anchors cannot be tied.
##
## A rope placement is still just (cell, rot):
##   end A = the snap point nearest the rope's cell (within SNAP_A_CELLS)
##   end B = the first snap point of another part along the rope's facing, inside a narrow cone,
##           up to max_length_cells away
## The rope starts TAUT: its length is the distance between the two snap points at build time.
## Everything derives from integer cells, so ropes replay identically.
## The editor uses the same static helpers to show snap points, auto-snap end A on drop and
## auto-aim the rope at the nearest target (see level_screen.gd).
## Ropes that meet at a pulley become one line through it (Simulation.RopeLine): pulling one end
## lifts the other. The line is drawn over the top of the wheel (tangent points + arc on the pulley).

const SNAP_A_CELLS := 2.0
const CONE := 0.3  # max sideways offset per unit of distance along the rope (about 17 degrees)
const CONE_MIN_PX := 30.0

var def: Dictionary
var max_length_cells: int = 30
var line = null  # Simulation.RopeLine
var end_a: Node2D = null
var end_b: Node2D = null
var off_a := Vector2.ZERO  # anchor offsets in the end parts' local space
var off_b := Vector2.ZERO
var color: Color = Color.WHITE
var _len := 0.0


func configure(p_def: Dictionary) -> void:
	def = p_def
	max_length_cells = int(def.get("max_length_cells", max_length_cells))
	color = PartFactory.color_of(def)
	z_index = 5


# ---------------------------------------------------------------- snap points (shared with the editor)

## Every snap point of the given parts: [{node, off (local), pos (world)}], in part order.
static func anchors_of(parts: Array, exclude: Node = null) -> Array:
	var out := []
	for p in parts:
		if p == exclude or not is_instance_valid(p) or not p.has_meta("part_id"):
			continue
		var d := PartRegistry.get_def(str(p.get_meta("part_id")))
		for a in d.get("anchors", []):
			var off := Vector2(float(a[0]), float(a[1]))
			out.append({"node": p, "off": off, "pos": p.to_global(off)})
	return out


## Nearest snap point to `point` within `radius_px` ({} when none). Ties: lowest part index.
static func snap_a(parts: Array, point: Vector2, radius_px: float, exclude: Node = null) -> Dictionary:
	var best := {}
	var bd := radius_px
	for a in anchors_of(parts, exclude):
		var d: float = a["pos"].distance_to(point)
		if d < bd - 0.001:
			bd = d
			best = a
	return best


## Target snap point along `dir` from `from` (inside the cone), {} when none. A PULLEY in the cone
## wins over anything nearer (a ball sitting between a bucket and its pulley must not catch the
## rope); otherwise the first snap point along the way.
static func scan_b(parts: Array, from: Dictionary, dir: Vector2, max_px: float) -> Dictionary:
	var pulley := _scan(parts, from, dir, max_px, true)
	return pulley if not pulley.is_empty() else _scan(parts, from, dir, max_px, false)


static func _scan(parts: Array, from: Dictionary, dir: Vector2, max_px: float, pulleys_only: bool) -> Dictionary:
	var best := {}
	var best_along := max_px
	for a in anchors_of(parts, from.get("node")):
		if pulleys_only and a["node"].get_meta("part_id") != "pulley":
			continue
		var v: Vector2 = a["pos"] - from["pos"]
		var along := v.dot(dir)
		if along < Grid.CELL or along > max_px:
			continue
		var side := absf(v.cross(dir))
		if side > maxf(CONE_MIN_PX, along * CONE):
			continue
		if along < best_along - 0.001:
			best_along = along
			best = a
	return best


static func dir_of(rot: int) -> Vector2:
	return Vector2.RIGHT.rotated(Grid.steps_to_radians(rot))


## What a rope at (cell, rot) would tie, using the given parts: {"a": {...}, "b": {...}} (either may be {}).
static func resolve(parts: Array, cell: Vector2i, rot: int, max_cells: int, self_node: Node = null) -> Dictionary:
	var a := snap_a(parts, Grid.cell_to_world(cell), SNAP_A_CELLS * Grid.CELL, self_node)
	var b := {}
	if not a.is_empty():
		b = scan_b(parts, a, dir_of(rot), max_cells * Grid.CELL)
	return {"a": a, "b": b}


## Editor auto-aim: the rotation (0..23) to use, or -1 when nothing is reachable. Pulleys first:
## the current rotation is kept when it already reaches a pulley.
static func best_rot(parts: Array, cell: Vector2i, rot: int, max_cells: int) -> int:
	var cur := resolve(parts, cell, rot, max_cells)
	if cur["a"].is_empty():
		return -1
	if not cur["b"].is_empty() and cur["b"]["node"].get_meta("part_id") == "pulley":
		return rot
	# Nearest PULLEY in any direction wins (that is what a rope is usually for); otherwise the
	# nearest snap point. The part the end is resting on is never an interesting target, so a
	# pulley further away beats it.
	var best := -1
	var bd := INF
	var best_pulley := false
	for r in Grid.ROT_STEPS:
		var res := resolve(parts, cell, r, max_cells)
		if res["b"].is_empty():
			continue
		var is_pulley: bool = res["b"]["node"].get_meta("part_id") == "pulley"
		var d: float = res["b"]["pos"].distance_to(res["a"]["pos"])
		if (is_pulley and not best_pulley) or (is_pulley == best_pulley and d < bd):
			bd = d
			best = r
			best_pulley = is_pulley
	return best


# ---------------------------------------------------------------- simulation

func rope_length_px() -> float:
	return _len


func on_attach(sim: Node) -> void:
	var res := resolve(sim.parts, get_meta("cell"), int(get_meta("rot")), max_length_cells, self)
	var a: Dictionary = res["a"]
	var b: Dictionary = res["b"]
	if a.is_empty() or b.is_empty():
		end_a = a.get("node")
		end_b = null
		return  # a loose rope ties nothing
	end_a = a["node"]
	end_b = b["node"]
	off_a = a["off"]
	off_b = b["off"]
	_len = a["pos"].distance_to(b["pos"])
	for e in [end_a, end_b]:
		if e.has_method("make_dynamic"):
			e.make_dynamic()
	sim.register_rope(self, end_a, end_b, off_a, off_b)


func set_running(_running: bool) -> void:
	pass


func snapshot() -> String:
	var la: String = end_a.name if end_a else "-"
	var lb: String = end_b.name if end_b else "-"
	var d := -1
	if end_a and end_b:
		d = roundi(end_a.to_global(off_a).distance_to(end_b.to_global(off_b)) * 1000.0)
	return "%s a=%s b=%s d=%d" % [name, la, lb, d]


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0


# ---------------------------------------------------------------- drawing

func _process(_delta: float) -> void:
	queue_redraw()


## Where the rope meets an end: the snap point, or the top tangent point of a pulley wheel as seen
## from `other` (so the rope runs over the wheel, not into its axle).
static func contact(end: Node2D, off: Vector2, other_world: Vector2) -> Vector2:
	if end.get_meta("part_id", "") == "pulley":
		return pulley_tangent(end.global_position, end.radius, other_world)
	return end.to_global(off)


static func pulley_tangent(c: Vector2, r: float, from: Vector2) -> Vector2:
	var v := from - c
	var d := v.length()
	if d <= r + 0.5:
		return c + Vector2(0, -r)
	var phi := v.angle()
	var alpha := acos(r / d)
	var p1 := c + Vector2.from_angle(phi + alpha) * r
	var p2 := c + Vector2.from_angle(phi - alpha) * r
	return p1 if p1.y < p2.y else p2


func _draw() -> void:
	if end_a == null or end_b == null:
		_draw_loose()
		return
	var slack_line: bool = line != null and line.is_slack()
	modulate.a = 0.4 if slack_line else 1.0
	var ga := contact(end_a, off_a, end_b.to_global(off_b))
	var gb := contact(end_b, off_b, end_a.to_global(off_a))
	var pa := to_local(ga)
	var pb := to_local(gb)
	# Sag when the line has slack (an end is gone, or the far side is lower than the length allows).
	var span := pa.distance_to(pb)
	var slack := 0.0
	if line != null:
		slack = maxf(0.0, line.length - line.current_length()) if not slack_line else 60.0
	var sag := minf(slack * 0.35, 80.0)
	var mid := (pa + pb) / 2.0 + (Vector2(0, sag)).rotated(-global_rotation)
	var pts := PackedVector2Array()
	for i in range(17):
		var t := i / 16.0
		pts.append(pa.lerp(mid, t).lerp(mid.lerp(pb, t), t))
	draw_polyline(pts, Art.INK, 9.0)
	draw_polyline(pts, color, 5.0)
	# Twisted-fibre dashes so it reads as rope, not a stick.
	for i in range(1, pts.size() - 1, 1):
		var d := (pts[i + 1] - pts[i - 1]).normalized().orthogonal() * 2.0
		draw_line(pts[i] - d, pts[i] + d, color.darkened(0.35), 1.5)
	# Clips at the snap points (not at pulleys: there the rope runs over the wheel).
	for e in [[end_a, pa], [end_b, pb]]:
		if e[0].get_meta("part_id", "") != "pulley":
			_clip(e[1])
	var _unused := span


func _clip(p: Vector2) -> void:
	draw_circle(p, 9.0, Art.INK)
	draw_circle(p, 6.0, Color("e0b44c"))
	draw_circle(p, 2.5, Art.INK)


## A rope that ties nothing: a short coil with a frayed end, so it is obvious it isn't connected.
func _draw_loose() -> void:
	var dir := Vector2.RIGHT
	var p0 := Vector2.ZERO
	if end_a != null:
		p0 = to_local(end_a.to_global(off_a))
	var p1 := p0 + dir * Grid.CELL * 2.5
	draw_line(p0, p1, Art.INK, 9.0)
	draw_line(p0, p1, color, 5.0)
	for k in [-1.0, 0.0, 1.0]:
		draw_line(p1, p1 + Vector2(10, k * 7), color.darkened(0.3), 2.0)
	_clip(p0)
