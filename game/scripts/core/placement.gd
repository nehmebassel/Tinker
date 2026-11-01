class_name Placement
extends RefCounted
## One part on the stage: which part, where (integer cells), which rotation step.
## This is the unit of a solution file. Integers only — see Grid.

var part: String
var cell: Vector2i
var rot: int  # 0..23, multiples of 15 degrees


func _init(p_part: String = "", p_cell: Vector2i = Vector2i.ZERO, p_rot: int = 0) -> void:
	part = p_part
	cell = p_cell
	rot = Grid.wrap_steps(p_rot)


func duplicate_placement() -> Placement:
	return Placement.new(part, cell, rot)


func to_dict() -> Dictionary:
	return {"part": part, "x": cell.x, "y": cell.y, "rot": rot}


static func from_dict(d: Dictionary) -> Placement:
	return Placement.new(str(d.get("part", "")), Vector2i(int(d.get("x", 0)), int(d.get("y", 0))), int(d.get("rot", 0)))


## Strict check used for anything coming over the network or from a file.
static func is_valid_dict(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	if not (d.has("part") and d.has("x") and d.has("y") and d.has("rot")):
		return false
	for k in ["x", "y", "rot"]:
		var v: Variant = d[k]
		# JSON gives floats; accept only whole numbers.
		if not (v is int or v is float):
			return false
		if v is float and v != floor(v):
			return false
	var rot := int(d["rot"])
	if rot < 0 or rot >= Grid.ROT_STEPS:
		return false
	return Grid.in_stage(Vector2i(int(d["x"]), int(d["y"])))


func equals(other: Placement) -> bool:
	return part == other.part and cell == other.cell and rot == other.rot
