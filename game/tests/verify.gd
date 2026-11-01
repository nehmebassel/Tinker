extends SceneTree
## Replay verifier — what the server runs for every submitted score and every shared level.
##
##   godot --headless --fixed-fps 60 --path game -s res://tests/verify.gd -- --level-json=/tmp/level.json --solution-json=/tmp/solution.json
##
## Reads the level and the solution (array of {part,x,y,rot}), validates the solution against the
## level's tray/slots, replays it once with the exact same simulation the phone runs, and prints ONE
## line of JSON on stdout:
##   {"ok":true,"result":"goal","ticks":182,"parts":1,"hash":"..."}
##   {"ok":false,"error":"solution does not fit tray/slots"}
## Exit code 0 when the replay ran (whatever the result), 2 on input errors.

var level_path := ""
var solution_path := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level-json="):
			level_path = a.trim_prefix("--level-json=")
		elif a.begins_with("--solution-json="):
			solution_path = a.trim_prefix("--solution-json=")
	_run()


func _fail(msg: String) -> void:
	print(JSON.stringify({"ok": false, "error": msg}))
	quit(2)


func _run() -> void:
	await process_frame
	var level_v: Variant = _read(level_path)
	var sol_v: Variant = _read(solution_path)
	if level_v == null or sol_v == null:
		_fail("cannot read input files")
		return
	var err := LevelData.validate(level_v)
	if err != "":
		_fail("invalid level: " + err)
		return
	if not (sol_v is Array):
		_fail("solution must be an array")
		return
	var placements: Array = []
	for p in sol_v:
		if not Placement.is_valid_dict(p):
			_fail("invalid placement: " + JSON.stringify(p))
			return
		if p.has("state"):
			_fail("player placements cannot carry state")
			return
		var pl := Placement.from_dict(p)
		if not PartRegistry.has(pl.part):
			_fail("unknown part " + pl.part)
			return
		placements.append(pl)
	var level := LevelData.from_dict(level_v)
	if not level.solution_fits(placements):
		_fail("solution does not fit tray/slots")
		return
	var sim := Simulation.new()
	root.add_child(sim)
	sim.load_level(level)
	sim.set_player_parts(placements)
	sim.start()
	var o: Dictionary = await sim.finished
	await process_frame
	print(JSON.stringify({"ok": true, "result": o["result"], "ticks": o["ticks"], "parts": placements.size(), "hash": o["hash"]}))
	quit(0)


static func _read(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return null
	return j.data
