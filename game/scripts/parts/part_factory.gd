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
	node.add_to_group("parts")
	if node.has_method("configure"):
		node.configure(def)
	return node


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
	return null


static func color_of(def: Dictionary) -> Color:
	return Color(str(def.get("color", "#ffffff")))
