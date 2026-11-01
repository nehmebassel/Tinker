class_name PartFactory
extends RefCounted
## Builds a part node from its JSON definition and a Placement.
## Creation is the ONLY place that converts integers to world coordinates.

const OUTLINE_W := 6.0
const OUTLINE_COLOR := Color("1f1a2e")


static func create(placement: Placement, index: int, is_fixed: bool) -> Node2D:
	var def: Dictionary = PartRegistry.get_def(placement.part)
	if def.is_empty():
		push_error("Unknown part '%s'" % placement.part)
		return null
	var script: Script = load(def["script"])
	var node: Node2D = script.new()
	node.name = "%s_%d" % [placement.part, index]
	node.position = Grid.cell_to_world(placement.cell)
	node.rotation = Grid.steps_to_radians(placement.rot)
	node.set_meta("part_id", placement.part)
	node.set_meta("part_index", index)
	node.set_meta("is_fixed", is_fixed)
	node.set_meta("cell", placement.cell)
	node.set_meta("rot", placement.rot)
	node.set_meta("state", placement.state if is_fixed else {})
	node.add_to_group("parts")
	if node.has_method("configure"):
		node.configure(def)
	return node


## Initial state value: level placement state overrides the part definition's "state" block.
static func state_of(node: Node, key: String, default: Variant) -> Variant:
	var st: Dictionary = node.get_meta("state", {})
	if st.has(key):
		return st[key]
	var def: Dictionary = PartRegistry.get_def(node.get_meta("part_id"))
	var ds: Dictionary = def.get("state", {})
	return ds.get(key, default)


## Shared snapshot formatting so every part quantises the same way.
static func fmt_pos(v: Vector2) -> String:
	return "%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0)]


static func fmt_rot(f: float) -> String:
	return str(roundi(f * 10000.0))


## Bodies in an Area2D, in creation order (part_index), so force application order is fixed.
static func sorted_bodies(area: Area2D) -> Array:
	var bodies := area.get_overlapping_bodies()
	bodies.sort_custom(func(x, y): return int(x.get_meta("part_index", 1 << 30)) < int(y.get_meta("part_index", 1 << 30)))
	return bodies


## Collision shape from the JSON "shape" block.
static func make_shape(def: Dictionary) -> Shape2D:
	var s: Dictionary = def["shape"]
	match s["type"]:
		"circle":
			var c := CircleShape2D.new()
			c.radius = float(s["radius"])
			return c
		"rect", "basket":
			var r := RectangleShape2D.new()
			r.size = Vector2(float(s["w"]), float(s["h"]))
			return r
		"none":
			return null
	return null


static func color_of(def: Dictionary) -> Color:
	return Color(str(def.get("color", "#ffffff")))
