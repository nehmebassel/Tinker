class_name PartRegistry
extends RefCounted
## PartRegistry — loads every part definition from res://parts/*.json.
##
## Each part is one JSON file (sprite, collision shape, mass, behaviour script),
## so new parts ship as data without engine changes. `parts/index.json` lists the
## ids; we read an index instead of listing the directory because directory
## listing inside an exported PCK is not something we want to depend on.

const PARTS_DIR := "res://parts/"

static var defs: Dictionary = {}  # id -> Dictionary
static var load_errors: PackedStringArray = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if not _loaded:
		reload()


static func reload() -> void:
	_loaded = true
	defs.clear()
	load_errors.clear()
	var index: Variant = _read_json(PARTS_DIR + "index.json")
	if index == null or not (index is Dictionary) or not index.has("parts"):
		load_errors.append("parts/index.json missing or malformed")
		return
	for id in index["parts"]:
		var d: Variant = _read_json(PARTS_DIR + str(id) + ".json")
		if d == null or not (d is Dictionary):
			load_errors.append("part %s: cannot read json" % id)
			continue
		var err := validate(d)
		if err != "":
			load_errors.append("part %s: %s" % [id, err])
			continue
		defs[d["id"]] = d


static func get_def(id: String) -> Dictionary:
	ensure_loaded()
	return defs.get(id, {})


static func has(id: String) -> bool:
	ensure_loaded()
	return defs.has(id)


## Returns "" when valid, otherwise a message.
static func validate(d: Dictionary) -> String:
	for key in ["id", "name", "body", "shape", "script", "color"]:
		if not d.has(key):
			return "missing field '%s'" % key
	if not (d["body"] in ["rigid", "static", "area", "none"]):
		return "body must be rigid, static, area or none"
	var s: Dictionary = d["shape"]
	if not s.has("type"):
		return "shape.type missing"
	match s["type"]:
		"circle":
			if not s.has("radius"):
				return "circle needs radius"
		"rect":
			if not (s.has("w") and s.has("h")):
				return "rect needs w and h"
		"basket":
			if not (s.has("w") and s.has("h")):
				return "basket needs w and h"
		"none":
			pass
		_:
			return "unknown shape type %s" % s["type"]
	if not ResourceLoader.exists(d["script"]):
		return "script %s not found" % d["script"]
	return ""


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_error("JSON error in %s line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data
