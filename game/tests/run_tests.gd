extends SceneTree
## Headless test runner.
##
##   godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd [-- --replays=100] [-- --level=c001]
##
## --fixed-fps 60 makes every rendered frame advance exactly one 60 Hz physics tick
## regardless of wall clock, so replays run far faster than real time with the
## exact same step size the phone uses.
##
## Exit code 0 = all passed. Writes build/test-report.txt and build/determinism-hashes.txt
## (hashes are compared across machines by CI).

const LEVELS_DIR := "res://levels/campaign/"

var replays: int = 100
var only_level: String = ""
var failures: PackedStringArray = []
var passes: int = 0
var report: PackedStringArray = []
var hashes: PackedStringArray = []
var _levels_expected: int = 0


func _initialize() -> void:
	_parse_args()
	_run_all()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--replays="):
			replays = int(a.trim_prefix("--replays="))
		elif a.begins_with("--level="):
			only_level = a.trim_prefix("--level=")


func _run_all() -> void:
	# Let autoloads finish _ready.
	await process_frame
	_log("Tinker headless tests — Godot %s — replays=%d" % [Engine.get_version_info()["string"], replays])
	_log("physics_ticks_per_second=%d jitter_fix=%s" % [Engine.physics_ticks_per_second, str(ProjectSettings.get_setting("physics/common/physics_jitter_fix"))])
	_check("physics step is 60 Hz", Engine.physics_ticks_per_second == 60)
	_check("jitter fix is off", float(ProjectSettings.get_setting("physics/common/physics_jitter_fix")) == 0.0)

	_test_grid()
	_test_placement()
	_test_registry()
	await _test_levels()

	_check("every level produced a determinism hash", hashes.size() == _levels_expected)
	_log("")
	_log("%d passed, %d failed" % [passes, failures.size()])
	for f in failures:
		_log("FAIL: " + f)
	_write_files()
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- unit tests

func _test_grid() -> void:
	_check("cell_to_world(1,2)", Grid.cell_to_world(Vector2i(1, 2)) == Vector2(24, 48))
	_check("world_to_cell rounds", Grid.world_to_cell(Vector2(35, 13)) == Vector2i(1, 1))
	_check("snap roundtrip", Grid.world_to_cell(Grid.cell_to_world(Vector2i(17, 33))) == Vector2i(17, 33))
	_check("rotation wraps", Grid.wrap_steps(25) == 1 and Grid.wrap_steps(-1) == 23)
	_check("steps<->radians", Grid.radians_to_steps(Grid.steps_to_radians(7)) == 7)
	_check("15 deg step", is_equal_approx(Grid.steps_to_radians(6), PI / 2.0))


func _test_placement() -> void:
	var p := Placement.new("plank", Vector2i(10, 20), 27)
	_check("placement wraps rot", p.rot == 3)
	var d := p.to_dict()
	var p2 := Placement.from_dict(d)
	_check("placement roundtrip", p.equals(p2))
	_check("rejects float cell", not Placement.is_valid_dict({"part": "plank", "x": 1.5, "y": 2, "rot": 0}))
	_check("rejects rot out of range", not Placement.is_valid_dict({"part": "plank", "x": 1, "y": 2, "rot": 24}))
	_check("rejects off-stage", not Placement.is_valid_dict({"part": "plank", "x": 999, "y": 2, "rot": 0}))
	_check("accepts json ints as floats", Placement.is_valid_dict({"part": "plank", "x": 1.0, "y": 2.0, "rot": 3.0}))


func _test_registry() -> void:
	PartRegistry.ensure_loaded()
	_check("registry has no load errors: " + ", ".join(PartRegistry.load_errors), PartRegistry.load_errors.is_empty())
	for id in ["ball", "plank", "basket"]:
		_check("registry has " + id, PartRegistry.has(id))
	_check("validate catches missing shape", PartRegistry.validate({"id": "x", "name": "x", "body": "rigid", "script": "res://scripts/parts/ball.gd", "color": "#fff"}) != "")


# ---------------------------------------------------------------- determinism

func _test_levels() -> void:
	var files := _list_levels()
	_check("found campaign levels", files.size() > 0)
	for path in files:
		var level := LevelData.load_from_file(path)
		if level == null:
			_check("load " + path, false)
			continue
		if only_level != "" and level.id != only_level:
			continue
		_levels_expected += 1
		_check("%s: reference solution fits tray/slots" % level.id, level.solution_fits(level.reference_solution))
		if level.reference_solution.is_empty():
			_check("%s has a reference solution" % level.id, false)
			continue
		await _replay_level(level)


func _replay_level(level: LevelData) -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	sim.load_level(level)
	sim.set_player_parts(level.reference_solution)
	var first_hash := ""
	var first_text := ""
	var identical := true
	var result := ""
	var ticks := 0
	for i in range(replays):
		sim.start()
		var o: Dictionary = await sim.finished
		await process_frame
		if i == 0:
			first_hash = o["hash"]
			first_text = sim.state_text()
			result = o["result"]
			ticks = o["ticks"]
		elif o["hash"] != first_hash:
			identical = false
			_log("  replay %d differs from replay 0:\n--- first\n%s\n--- this\n%s" % [i, first_text, sim.state_text()])
			break
	root.remove_child(sim)
	sim.free()
	_log("%s: result=%s ticks=%d (%.2fs) hash=%s" % [level.id, result, ticks, ticks / 60.0, first_hash])
	_check("%s: reference solution reaches the goal" % level.id, result == "goal")
	_check("%s: %d replays identical" % [level.id, replays], identical)
	hashes.append("%s %s %s %d" % [level.id, first_hash, result, ticks])


# ---------------------------------------------------------------- helpers

func _list_levels() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			out.append(LEVELS_DIR + f)
		f = dir.get_next()
	out.sort()
	return out


func _check(name: String, ok: bool) -> void:
	if ok:
		passes += 1
		_log("  ok   " + name)
	else:
		failures.append(name)
		_log("  FAIL " + name)


func _log(s: String) -> void:
	print(s)
	report.append(s)


func _write_files() -> void:
	DirAccess.make_dir_recursive_absolute("res://../build")
	var f := FileAccess.open("res://../build/test-report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")
	var h := FileAccess.open("res://../build/determinism-hashes.txt", FileAccess.WRITE)
	if h:
		h.store_string("\n".join(hashes) + "\n")
