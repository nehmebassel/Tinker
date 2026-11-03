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

const LEVEL_DIRS := ["res://levels/campaign/", "res://levels/tests/"]

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
	_test_bus_layout()
	_test_tries()
	_test_skip_then_solve()
	await _test_rope_snap()
	await _test_editor_state()
	await _test_levels()
	await _test_sound_watcher()

	_check("every level produced a determinism hash", hashes.size() == _levels_expected)
	_log("")
	_log("%d passed, %d failed" % [passes, failures.size()])
	for f in failures:
		_log("FAIL: " + f)
	_write_files()
	quit(0 if failures.is_empty() else 1)


## A level skipped with coins, then solved for real: the real score replaces the skip (Codex PR #9).
func _test_skip_then_solve() -> void:
	var path := "user://save_skip_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := SaveData.load_or_new(path)
	s.record_skip(5)
	_check("skip: counts as solved (unlocks the next level)", s.is_solved(5))
	_check("skip: not on the campaign board", s.board_progress()["solved"] == 0)
	_check("skip then real solve: recorded as a new best", s.record_solve(5, 2, 4200, []))
	_check("skip then real solve: skip flag gone, real score kept", not s.best(5).get("skipped", false) and int(s.best(5)["best_parts"]) == 2)
	_check("skip then real solve: on the campaign board", s.board_progress()["solved"] == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Sandbox editor: the layout is loaded as player placements, but must keep its start states (Codex PR #8):
## an unlit candle / stopped motor must stay so in TEST, and a candle goal needs an unlit candle.
func _test_editor_state() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	sim.load_level(LevelData.from_dict({"id": "t-editor", "title": "t", "goal": {"type": "candle"}, "fixed": [], "tray": [], "slots": 0, "reference_solution": []}))
	var c := Placement.new("candle", Vector2i(10, 10), 0)
	c.state = {"lit": false}
	var m := Placement.new("motor", Vector2i(20, 10), 0)
	m.state = {"on": false}
	sim.set_player_parts([c, m])
	_check("editor off: player candle ignores state (campaign rule)", sim.parts[0].lit_at_start == true)
	sim.keep_player_state = true
	sim.set_player_parts([c, m])
	_check("editor on: unlit candle stays unlit", sim.parts[0].lit_at_start == false)
	_check("editor on: stopped motor stays stopped", bool(PartFactory.state_of(sim.parts[1], "on", true)) == false)
	sim.queue_free()
	await process_frame
	var d := SandboxStore.new_draft()
	d["goal"] = {"type": "candle"}
	d["tray"] = [{"part": "candle", "count": 1}]
	d["fixed"] = [{"part": "candle", "x": 10, "y": 10, "rot": 0}]
	_check("setup: candle goal without an unlit candle is refused", SandboxStore.problem(d).contains("unlit"))
	d["fixed"] = [{"part": "candle", "x": 10, "y": 10, "rot": 0, "state": {"lit": false}}]
	_check("setup: candle goal with an unlit candle is accepted", SandboxStore.problem(d) == "")
	var many := []
	for i in SandboxStore.MAX_LAYOUT_PARTS + 1:
		many.append({"part": "ball", "x": 2 + (i % 20) * 2, "y": 2 + (i / 20) * 4, "rot": 0})
	d["fixed"] = many + [{"part": "candle", "x": 10, "y": 50, "rot": 0, "state": {"lit": false}}]
	_check("setup: more than %d layout parts is refused (server limit)" % SandboxStore.MAX_LAYOUT_PARTS, SandboxStore.problem(d).begins_with("Too many parts"))


## Rope snap points + auto-aim (the editor and the simulation share these helpers).
func _test_rope_snap() -> void:
	var Rope: GDScript = load("res://scripts/parts/rope.gd")
	var level := LevelData.load_from_file("res://levels/campaign/007.json")
	var sim := Simulation.new()
	root.add_child(sim)
	sim.load_level(level)
	sim.set_player_parts([Placement.new("pulley", Vector2i(22, 16), 0)])
	var near := Grid.cell_to_world(Vector2i(13, 29)) + Vector2(5, -3)
	var a: Dictionary = Rope.snap_a(sim.parts, near, 3.0 * Grid.CELL)
	_check("rope: end snaps to the ball's snap point", not a.is_empty() and a["node"].get_meta("part_id") == "ball")
	var r: int = Rope.best_rot(sim.parts, Vector2i(12, 30), 0, 30)
	var res: Dictionary = Rope.resolve(sim.parts, Vector2i(12, 30), r, 30)
	_check("rope: auto-aim finds the pulley (rot %d)" % r, r >= 0 and not res["b"].is_empty() and res["b"]["node"].get_meta("part_id") == "pulley")
	sim.set_player_parts([Placement.new("pulley", Vector2i(22, 16), 0), Placement.new("rope", Vector2i(12, 30), r)])
	sim.start()
	var o: Dictionary = await sim.finished
	await process_frame
	_check("rope: the auto-aimed rope solves Wrecking ball", o["result"] == "goal")
	var lv2 := LevelData.load_from_file("res://levels/tests/t_rope_pulley_buckets.json")
	sim.load_level(lv2)
	var line_ok := false
	for rl in sim.rope_lines:
		if rl.chain.size() == 3 and rl.chain[1].get_meta("part_id") == "pulley":
			line_ok = rl.chain[0].get_meta("part_id") == "bucket" and rl.chain[2].get_meta("part_id") == "bucket"
	_check("rope: a pulley beats a nearer ball as the target (bucket-pulley-bucket line)", line_ok)
	var bucket_off := Vector2.ZERO
	for rl in sim.rope_lines:
		bucket_off = rl.offs[0]
	_check("rope: bucket is tied at its handle, not its centre", bucket_off.y < -100.0)
	sim.free()


func _test_tries() -> void:
	var path := "user://tries_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var t := Tries.load_or_new(path)
	t.set_rules(3, 6.0)
	var t0 := 1_800_000_000
	_check("tries: full at start", t.left(t0) == 3 and t.seconds_to_refill(t0) == 0)
	t.use(t0)
	_check("tries: a failure costs one", t.left(t0 + 10) == 2)
	t.use(t0 + 3600)
	t.use(t0 + 7200)
	_check("tries: none left after three", t.left(t0 + 7300) == 0)
	_check("tries: window counts from the FIRST failure", t.seconds_to_refill(t0 + 7300) == 6 * 3600 - 7300)
	_check("tries: still none 1 s before the window ends", t.left(t0 + 6 * 3600 - 1) == 0)
	_check("tries: all refilled when the window ends", t.left(t0 + 6 * 3600) == 3)
	var t2 := Tries.load_or_new(path)
	_check("tries: state persists", t2.limit == 3 and t2.left(t0 + 6 * 3600) == 3)
	t2.use(t0 + 7 * 3600)
	_check("tries: a new window starts at the next failure", t2.seconds_to_refill(t0 + 7 * 3600) == 6 * 3600)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The web build only routes buses that exist at startup (see audio.gd): they must come from the layout.
func _test_bus_layout() -> void:
	var layout: Resource = load("res://default_bus_layout.tres")
	_check("default_bus_layout.tres exists", layout is AudioBusLayout)
	for bus in ["Music", "SFX"]:
		_check("bus '%s' declared in default_bus_layout.tres" % bus, layout != null and ("&\"%s\"" % bus) in FileAccess.get_file_as_string("res://default_bus_layout.tres"))
		_check("bus '%s' exists at startup" % bus, AudioServer.get_bus_index(bus) >= 0)


# ---------------------------------------------------------------- sound must never change a replay

## Runs levels with and without a SoundWatcher: the outcome hash must be identical (the watcher only
## reads), and the events each level is built around must make their sound.
const SOUND_CASES := {
	"t_spring_ball": ["spring"],
	"t_balloon_candle_pop": ["pop"],
	"t_conveyor_ball": ["basket"],
	"t_candle_lights_candle": ["candle"],
	"t_rope_pulley_buckets": ["pulley"],
	"t_mouse_cheese": ["mouse"],
}


func _test_sound_watcher() -> void:
	var app: Node = root.get_node_or_null("App")
	if app == null:
		_check("sound watcher: App autoload present", false)
		return
	for id in SOUND_CASES:
		var level := LevelData.load_from_file("res://levels/tests/%s.json" % id)
		var sim := Simulation.new()
		root.add_child(sim)
		sim.load_level(level)
		sim.set_player_parts(level.reference_solution)
		sim.start()
		var plain: Dictionary = await sim.finished
		await process_frame
		var w := SoundWatcher.new()
		w.watch(sim)
		root.add_child(w)
		app.audio.history.clear()
		sim.start()
		var heard: Dictionary = await sim.finished
		await process_frame
		_check("sound: %s replay identical with the watcher" % id, heard["hash"] == plain["hash"])
		for snd in SOUND_CASES[id]:
			_check("sound: %s plays '%s'" % [id, snd], snd in app.audio.history)
		w.free()
		sim.free()
	app.audio.stop_loops()
	# Leaving mid-run must silence the machine loops (the watcher is freed with the level).
	var lv := LevelData.load_from_file("res://levels/tests/t_fan_balloon.json")
	var s2 := Simulation.new()
	root.add_child(s2)
	s2.load_level(lv)
	var w2 := SoundWatcher.new()
	w2.watch(s2)
	root.add_child(w2)
	s2.start()
	for i in 10:
		await physics_frame
	var loop_on: bool = app.audio._loops["fan"].playing
	w2.queue_free()
	s2.queue_free()
	await process_frame
	_check("sound: fan loop plays while a fan runs", loop_on)
	_check("sound: loops stop when the level is left mid-run", not app.audio._loops["fan"].playing)


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
		if level.reference_solution.is_empty() and level.slots > 0:
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
	# A campaign level must not be solved by doing nothing.
	if level.slots > 0 and level.expect == "goal":
		sim.set_player_parts([])
		sim.start()
		var empty: Dictionary = await sim.finished
		await process_frame
		_check("%s: not solved with an empty tray (got %s)" % [level.id, empty["result"]], empty["result"] != "goal")
	root.remove_child(sim)
	sim.free()
	_log("%s: result=%s ticks=%d (%.2fs) hash=%s" % [level.id, result, ticks, ticks / 60.0, first_hash])
	if result != level.expect:
		_log("  final state:\n" + first_text)
	_check("%s: reference solution ends with '%s'" % [level.id, level.expect], result == level.expect)
	_check("%s: %d replays identical" % [level.id, replays], identical)
	hashes.append("%s %s %s %d" % [level.id, first_hash, result, ticks])


# ---------------------------------------------------------------- helpers

func _list_levels() -> PackedStringArray:
	var out := PackedStringArray()
	for d in LEVEL_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		var names := PackedStringArray()
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".json") and f != "index.json":
				names.append(f)
			f = dir.get_next()
		names.sort()
		for n in names:
			out.append(d + n)
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
