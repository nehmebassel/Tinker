extends SceneTree
## Daily level generator — deterministic from the UTC date.
##
##   godot --headless --fixed-fps 60 --path game -s res://tests/gen_daily.gd -- --date=2026-11-08 --out=/tmp/daily.json [--seed-salt=0]
##
## Seed = hash(date + salt). A template is picked and randomised, then the key part is brute-forced
## (same search as find_solution.gd). A candidate is accepted only when it has a solution, is not solved
## by an empty tray, and is neither trivial (too many placements work) nor needle-in-haystack (too few).
## Same date + same build => same level, so the server and the curation tooling agree.
## Output: level JSON with reference_solution and a "generator" block (template, attempt, hit ratio).

var date := ""
var out_path := ""
var salt := 0
var rng := RandomNumberGenerator.new()
var sim: Simulation

const MAX_ATTEMPTS := 24
const MIN_HITS := 4
const MAX_RATIO := 0.45


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--date="):
			date = a.trim_prefix("--date=")
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a.begins_with("--seed-salt="):
			salt = int(a.trim_prefix("--seed-salt="))
	_run()


func _run() -> void:
	await process_frame
	if date == "" or out_path == "":
		print(JSON.stringify({"ok": false, "error": "need --date and --out"}))
		quit(2)
		return
	rng.seed = (date + "#" + str(salt)).hash()
	sim = Simulation.new()
	root.add_child(sim)
	for attempt in MAX_ATTEMPTS:
		var t := rng.randi_range(0, 5)
		var cand: Dictionary = _template(t)
		var res: Dictionary = await _evaluate(cand)
		if res["ok"]:
			var level: Dictionary = cand["level"]
			level["id"] = "d-" + date
			level["title"] = "Daily " + date
			level["reference_solution"] = res["solution"]
			level["generator"] = {"template": cand["name"], "attempt": attempt, "hits": res["hits"], "tries": res["tries"], "salt": salt}
			var f := FileAccess.open(out_path, FileAccess.WRITE)
			f.store_string(JSON.stringify(level, "  "))
			print(JSON.stringify({"ok": true, "template": cand["name"], "attempt": attempt, "hits": res["hits"], "tries": res["tries"]}))
			quit(0)
			return
		print("attempt %d (%s) rejected: %s" % [attempt, cand["name"], res["why"]])
	print(JSON.stringify({"ok": false, "error": "no acceptable level in %d attempts" % MAX_ATTEMPTS}))
	quit(1)


# ---------------------------------------------------------------- helpers

func P(part: String, x: int, y: int, rot: int = 0, state: Dictionary = {}) -> Dictionary:
	var d := {"part": part, "x": x, "y": y, "rot": rot}
	if not state.is_empty():
		d["state"] = state
	return d


func floor_planks(x0: int, y: int, n: int) -> Array:
	var out := []
	for i in n:
		out.append(P("plank", x0 + 5 + 10 * i, y))
	return out


func pick(arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


func base_level(fixed: Array, tray: Array, slots: int, goal: Dictionary) -> Dictionary:
	var t := []
	for pair in tray:
		t.append({"part": pair[0], "count": pair[1]})
	return {"id": "d", "title": "", "hint": "", "goal": goal, "fixed": fixed, "tray": t, "slots": slots, "reference_solution": [], "expect": "goal"}


func distractor(exclude: Array) -> String:
	var pool := ["fan", "spring", "conveyor", "plank", "switch", "bucket", "candle", "balloon"]
	var d: String = pick(pool)
	while d in exclude:
		d = pick(pool)
	return d


## Each template returns {name, level, part, region: Rect2i, rots: Array, with: Array}.
func _template(t: int) -> Dictionary:
	match t:
		0:  # Ramp: ball on a tilted ledge, basket below; one plank among distractors.
			var left := rng.randf() < 0.5
			var lx := rng.randi_range(3, 10) if left else rng.randi_range(34, 40)
			var ly := rng.randi_range(8, 22)
			var bx := rng.randi_range(16, 30)
			var by := rng.randi_range(42, 52)
			var fixed := [P("plank", lx, ly + 2, 1 if left else 23), P("ball", lx, ly), P("basket", bx, by)]
			var tray := [["plank", 1], [distractor(["plank"]), 1]]
			return {"name": "ramp", "level": base_level(fixed, tray, 1, {"type": "basket", "count": 1}),
				"part": "plank", "region": Rect2i(4, ly + 6, 36, by - ly - 10), "rots": range(24), "with": []}
		1:  # Nudge: ball at rest on a flat ledge; fan held beside it, plank searched.
			var lx := rng.randi_range(4, 10)
			var ly := rng.randi_range(14, 30)
			var bx := rng.randi_range(22, 32)
			var by := rng.randi_range(44, 52)
			var fixed := [P("plank", lx, ly + 2), P("ball", lx, ly), P("basket", bx, by)]
			var tray := [["plank", 1], ["fan", 1]]
			return {"name": "nudge", "level": base_level(fixed, tray, 2, {"type": "basket", "count": 1}),
				"part": "plank", "region": Rect2i(lx + 4, ly + 4, 26, by - ly - 8), "rots": range(24),
				"with": [{"part": "fan", "x": maxi(1, lx - 5), "y": ly, "rot": 0}]}
		2:  # Spring: ball falls onto a floor; basket on a ledge; spring searched.
			var bx := rng.randi_range(6, 14)
			var by := rng.randi_range(22, 32)
			var fx := by + rng.randi_range(10, 16)
			var kx := rng.randi_range(22, 32)
			var ky := rng.randi_range(22, 36)
			var fixed := [P("ball", bx, by), P("plank", bx, fx), P("plank", kx, ky + 4), P("basket", kx, ky)]
			var tray := [["spring", 1], [distractor(["spring"]), 1]]
			return {"name": "spring", "level": base_level(fixed, tray, 1, {"type": "basket", "count": 1}),
				"part": "spring", "region": Rect2i(bx - 3, fx - 4, 6, 3), "rots": [0, 1, 2, 3, 21, 22, 23], "with": []}
		3:  # Belt: ball drops from a ledge that points the wrong way; conveyor searched.
			var cx := rng.randi_range(10, 16)
			var cy := rng.randi_range(14, 24)
			var bx := rng.randi_range(18, 30)
			var by := rng.randi_range(46, 52)
			var fixed := [P("conveyor", cx, cy, 12), P("ball", cx, cy - 2), P("basket", bx, by)]
			var tray := [["conveyor", 1], [distractor(["conveyor"]), 1]]
			return {"name": "belt", "level": base_level(fixed, tray, 1, {"type": "basket", "count": 1}),
				"part": "conveyor", "region": Rect2i(2, cy + 4, 18, by - cy - 8), "rots": [0, 1, 23], "with": []}
		4:  # Headwind: mouse vs a fan; switch searched along the floor.
			var fy := rng.randi_range(36, 44)
			var fanx := rng.randi_range(24, 31)
			var fixed := floor_planks(0, fy, 4) + [P("mouse", 2, fy - 2), P("fan", fanx, fy - 6, 12), P("cheese", fanx + 4, fy - 2)]
			var tray := [["switch", 1], [distractor(["switch", "balloon"]), 1]]
			return {"name": "headwind", "level": base_level(fixed, tray, 1, {"type": "cheese"}),
				"part": "switch", "region": Rect2i(4, fy - 1, fanx - 12, 0), "rots": [0], "with": []}
		_:  # Pop: candle hanging high; balloon held low; fan searched.
			var cx := rng.randi_range(20, 34)
			var cy := rng.randi_range(4, 10)
			var blx := rng.randi_range(4, 12)
			var fixed := [P("candle", cx, cy, 12)]
			var tray := [["balloon", 1], ["fan", 1]]
			return {"name": "pop", "level": base_level(fixed, tray, 2, {"type": "pop"}),
				"part": "fan", "region": Rect2i(0, 10, 24, 40), "rots": [0, 1, 2, 3, 21, 22, 23],
				"with": [{"part": "balloon", "x": blx, "y": 50, "rot": 0}]}


func _evaluate(cand: Dictionary) -> Dictionary:
	var level := LevelData.from_dict(cand["level"])
	sim.load_level(level)
	# 1. Not solved by doing nothing.
	sim.set_player_parts([])
	sim.start()
	var empty: Dictionary = await sim.finished
	await process_frame
	if empty["result"] == "goal":
		return {"ok": false, "why": "solved with an empty tray"}
	# 2. Brute-force the key part (held parts fixed).
	var held: Array = []
	for w in cand["with"]:
		held.append(Placement.from_dict(w))
	var region: Rect2i = cand["region"]
	var hits: Array = []
	var tries := 0
	for y in range(region.position.y, region.end.y + 1, 2):
		for x in range(region.position.x, region.end.x + 1, 2):
			if not Grid.in_stage(Vector2i(x, y)):
				continue
			for r in cand["rots"]:
				var all := held.duplicate()
				all.append(Placement.new(cand["part"], Vector2i(x, y), r))
				sim.set_player_parts(all)
				sim.start()
				var o: Dictionary = await sim.finished
				await process_frame
				tries += 1
				if o["result"] == "goal":
					hits.append({"x": x, "y": y, "rot": r, "ticks": o["ticks"]})
	if hits.size() < MIN_HITS:
		return {"ok": false, "why": "%d hits of %d (too few)" % [hits.size(), tries]}
	if float(hits.size()) / tries > MAX_RATIO:
		return {"ok": false, "why": "%d hits of %d (too easy)" % [hits.size(), tries]}
	hits.sort_custom(func(a, b): return a["ticks"] < b["ticks"])
	var h: Dictionary = hits[hits.size() / 2]
	var solution: Array = []
	for w in cand["with"]:
		solution.append(w)
	solution.append({"part": cand["part"], "x": h["x"], "y": h["y"], "rot": h["rot"]})
	return {"ok": true, "solution": solution, "hits": hits.size(), "tries": tries}
