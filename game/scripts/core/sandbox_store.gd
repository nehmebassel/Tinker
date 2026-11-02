class_name SandboxStore
extends RefCounted
## SandboxStore — the player's own levels (M5), in user://sandbox.json.
## A draft: {uid, title, goal: {type, count?}, fixed: [placement dicts], tray: [{part, count}],
##           slots, solution: [placement dicts] (the author's, once solved), published_id}
## The level a draft becomes is to_level(): the same JSON as campaign levels, so the server's
## validator and replay accept it as-is.

const PATH := "user://sandbox.json"
const GOALS := ["basket", "candle", "cheese", "pop"]

var drafts: Array = []
var _path := PATH


static func load_or_new(path: String = PATH) -> SandboxStore:
	var s := SandboxStore.new()
	s._path = path
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.get("drafts") is Array:
			s.drafts = d["drafts"]
	return s


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"drafts": drafts}, "  "))


static func new_draft(title: String = "My machine") -> Dictionary:
	var uid := "%d%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
	return {"uid": uid, "title": title, "goal": {"type": "basket", "count": 1}, "fixed": [],
		"tray": [{"part": "plank", "count": 1}], "slots": 1, "solution": [], "published_id": ""}


## A shared level (as served by GET /level/:id) turned into an editable copy.
static func remix_of(level: Dictionary, code: String) -> Dictionary:
	var d := new_draft(("Remix of " + str(level.get("title", code))).substr(0, 60))
	d["goal"] = level.get("goal", d["goal"]).duplicate(true)
	d["fixed"] = level.get("fixed", []).duplicate(true)
	d["tray"] = level.get("tray", d["tray"]).duplicate(true)
	d["slots"] = int(level.get("slots", 1))
	return d


func add(draft: Dictionary) -> int:
	drafts.append(draft)
	save()
	return drafts.size() - 1


func put(index: int, draft: Dictionary) -> void:
	if index >= 0 and index < drafts.size():
		drafts[index] = draft
		save()


func remove(index: int) -> void:
	if index >= 0 and index < drafts.size():
		drafts.remove_at(index)
		save()


static func to_level(d: Dictionary, with_solution: bool = true) -> Dictionary:
	var lvl := {
		"id": "draft-" + str(d.get("uid", "x")),
		"title": str(d.get("title", "My machine")).substr(0, 60),
		"hint": "",
		"goal": d.get("goal", {"type": "basket", "count": 1}).duplicate(true),
		"fixed": d.get("fixed", []).duplicate(true),
		"tray": d.get("tray", []).duplicate(true),
		"slots": int(d.get("slots", 1)),
		"expect": "goal",
		"reference_solution": d.get("solution", []).duplicate(true) if with_solution else [],
	}
	return lvl


## "" when the draft can be play-tested as a puzzle; otherwise what is missing, in plain words.
static func problem(d: Dictionary) -> String:
	var fixed: Array = d.get("fixed", [])
	var tray: Array = d.get("tray", [])
	var total := 0
	for t in tray:
		total += int(t.get("count", 0))
	if fixed.is_empty():
		return "Build something first: drag parts onto the board."
	if total < 1:
		return "Give the player at least one part."
	if int(d.get("slots", 0)) < 1 or int(d.get("slots", 0)) > total:
		return "Slots must be between 1 and the number of player parts."
	var need := {"basket": "basket", "candle": "candle", "cheese": "cheese", "pop": "balloon"}
	var g := str(d.get("goal", {}).get("type", "basket"))
	var has := false
	for p in fixed:
		if str(p.get("part", "")) == need.get(g, ""):
			has = true
	for t in tray:
		if str(t.get("part", "")) == need.get(g, ""):
			has = true
	if not has:
		return "The goal needs a %s on the board or in the player's parts." % need.get(g, g)
	if g == "candle":
		# Player parts always start in their default state (a lit candle), so the goal needs an UNLIT
		# candle in the layout (select it in the editor and tap Unlit).
		var unlit := false
		for p in fixed:
			if str(p.get("part", "")) == "candle" and p.get("state", {}).get("lit", true) == false:
				unlit = true
		if not unlit:
			return "A candle goal needs an unlit candle on the board: select a candle and tap Unlit."
	if g == "cheese":
		var mouse := false
		for p in fixed:
			mouse = mouse or str(p.get("part", "")) == "mouse"
		if not mouse:
			return "A cheese goal needs a mouse on the board."
	return ""
