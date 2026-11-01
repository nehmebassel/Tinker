class_name LevelData
extends RefCounted
## A level: goal, fixed parts already on stage, tray of placeable parts, slot limit,
## and a reference solution used by the determinism test.
##
## JSON shape (levels/campaign/001.json):
## {
##   "id": "c001", "title": "...", "hint": "...",
##   "goal": {"type": "basket", "count": 1},
##   "fixed": [{"part": "ball", "x": 6, "y": 8, "rot": 0}, ...],
##   "tray": [{"part": "plank", "count": 1}],
##   "slots": 1,
##   "reference_solution": [{"part": "plank", "x": 12, "y": 20, "rot": 3}]
## }

var id: String = ""
var title: String = ""
var hint: String = ""
var goal: Dictionary = {"type": "basket", "count": 1}
var fixed: Array[Placement] = []
var tray: Dictionary = {}  # part id -> count
var slots: int = 0  # max parts the player may place (0 = sum of tray)
var reference_solution: Array[Placement] = []


static func from_dict(d: Dictionary) -> LevelData:
	var l := LevelData.new()
	l.id = str(d.get("id", ""))
	l.title = str(d.get("title", ""))
	l.hint = str(d.get("hint", ""))
	l.goal = d.get("goal", {"type": "basket", "count": 1})
	for p in d.get("fixed", []):
		l.fixed.append(Placement.from_dict(p))
	for t in d.get("tray", []):
		l.tray[str(t["part"])] = int(t.get("count", 1))
	l.slots = int(d.get("slots", 0))
	if l.slots <= 0:
		var total := 0
		for c in l.tray.values():
			total += int(c)
		l.slots = total
	for p in d.get("reference_solution", []):
		l.reference_solution.append(Placement.from_dict(p))
	return l


static func load_from_file(path: String) -> LevelData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Level not found: %s" % path)
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_error("Level JSON error %s line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	var err := validate(j.data)
	if err != "":
		push_error("Level %s invalid: %s" % [path, err])
		return null
	return from_dict(j.data)


## "" when valid.
static func validate(d: Variant) -> String:
	if not (d is Dictionary):
		return "root must be an object"
	if not d.has("id"):
		return "missing id"
	if not (d.has("goal") and d["goal"] is Dictionary and d["goal"].has("type")):
		return "missing goal.type"
	for p in d.get("fixed", []):
		if not Placement.is_valid_dict(p):
			return "invalid fixed placement %s" % str(p)
	for p in d.get("reference_solution", []):
		if not Placement.is_valid_dict(p):
			return "invalid reference placement %s" % str(p)
	for t in d.get("tray", []):
		if not (t is Dictionary and t.has("part")):
			return "invalid tray entry %s" % str(t)
	return ""


## True when `placements` only uses parts from the tray within their counts and the slot limit.
func solution_fits(placements: Array) -> bool:
	if placements.size() > slots:
		return false
	var used: Dictionary = {}
	for p in placements:
		used[p.part] = used.get(p.part, 0) + 1
	for part in used:
		if used[part] > tray.get(part, 0):
			return false
	return true
