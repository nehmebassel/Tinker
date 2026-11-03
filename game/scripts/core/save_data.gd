class_name SaveData
extends RefCounted
## SaveData — campaign progress in user://save.json. Device-local, no account.
##
## {"version": 1, "levels": {"7": {"solved": true, "best_parts": 2, "best_ms": 14230, "solution": [...]}}}
## Best = fewest parts, then fastest time (the game's scoring order). The best solution is kept so a
## later "replay my best" and the server-side replay verifier (M4) have the exact integers.

const PATH := "user://save.json"
const VERSION := 1

var levels: Dictionary = {}  # String(number) -> Dictionary
var _path: String = PATH


static func load_or_new(path: String = PATH) -> SaveData:
	var s := SaveData.new()
	s._path = path
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK and j.data is Dictionary:
				var d: Dictionary = j.data
				if d.get("levels") is Dictionary:
					s.levels = d["levels"]
	return s


func save() -> bool:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save file %s" % _path)
		return false
	f.store_string(JSON.stringify({"version": VERSION, "levels": levels}, "  "))
	return true


func is_solved(number: int) -> bool:
	return bool(levels.get(str(number), {}).get("solved", false))


func solved_count() -> int:
	var n := 0
	for k in levels:
		if levels[k].get("solved", false):
			n += 1
	return n


func best(number: int) -> Dictionary:
	return levels.get(str(number), {})


## Records a solve. Returns true when it is a new best (fewer parts, or same parts and faster).
func record_solve(number: int, parts_used: int, elapsed_ms: int, solution: Array) -> bool:
	var key := str(number)
	var cur: Dictionary = levels.get(key, {})
	# A skipped level (bought with coins) has no real score: the first real solve always replaces it.
	var better: bool = not cur.get("solved", false) or cur.get("skipped", false) \
		or parts_used < int(cur.get("best_parts", 1 << 30)) \
		or (parts_used == int(cur.get("best_parts", 1 << 30)) and elapsed_ms < int(cur.get("best_ms", 1 << 30)))
	if better:
		var sol := []
		for p in solution:
			sol.append(p.to_dict() if p is Placement else p)
		levels[key] = {"solved": true, "best_parts": parts_used, "best_ms": elapsed_ms, "solution": sol}
	else:
		cur["solved"] = true
		levels[key] = cur
	save()
	return better


## Skipped with coins (economy "skip"): counts as solved so the next level unlocks; no best score.
func record_skip(number: int) -> void:
	var key := str(number)
	if not levels.get(key, {}).get("solved", false):
		levels[key] = {"solved": true, "skipped": true, "best_parts": 0, "best_ms": 0, "solution": []}
		save()


## Campaign leaderboard numbers: levels solved (skips excluded) and the sum of best part counts.
func board_progress() -> Dictionary:
	var solved := 0
	var parts := 0
	for k in levels:
		var e: Dictionary = levels[k]
		if e.get("solved", false) and not e.get("skipped", false):
			solved += 1
			parts += int(e.get("best_parts", 0))
	return {"solved": solved, "parts": parts}


func reset() -> void:
	levels = {}
	save()
