extends SceneTree
## Level design harness (World 4+, not shipped in builds: tests/ is excluded from exports).
##
##   godot --headless --fixed-fps 60 --path game -s res://tests/design_levels.gd -- --designs=/tmp/designs.json
##
## designs.json: [{"name": "...", "level": {level JSON}, "search": {"part": "plank", "step": 2,
##                 "region": [x0, y0, x1, y1], "rots": [..], "with": [placements held fixed]}}]
## For each design: is it solved with no parts placed (must not be), how many placements of the
## searched part solve it, and the "robust" ones (>= 3 of 4 neighbouring cells also solve). A rope
## is aimed the way the editor does (Rope.best_rot), so searched ropes behave like a player's.
## Prints one JSON line per design: {"name", "empty", "hits", "tries", "robust": [placement...]}.

const Rope := preload("res://scripts/parts/rope.gd")


func _initialize() -> void:
	_go()


func _run(sim: Simulation, level: LevelData, placements: Array) -> String:
	sim.load_level(level)
	sim.set_player_parts(placements)
	sim.start()
	var o: Dictionary = await sim.finished
	await process_frame
	return str(o["result"])


func _go() -> void:
	await process_frame
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--designs="):
			path = a.trim_prefix("--designs=")
	var designs: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var sim := Simulation.new()
	root.add_child(sim)
	for d in designs:
		var level := LevelData.from_dict(d["level"])
		var s: Dictionary = d["search"]
		var held: Array = []
		for w in s.get("with", []):
			held.append(Placement.from_dict(w))
		var empty := await _run(sim, level, [])
		var r: Array = s.get("region", [0, 0, Grid.STAGE_CELLS.x - 1, Grid.STAGE_CELLS.y - 1])
		var step := int(s.get("step", 2))
		var rots: Array = s.get("rots", range(Grid.ROT_STEPS))
		var part := str(s["part"])
		var ok := {}
		var tries := 0
		for y in range(int(r[1]), int(r[3]) + 1, step):
			for x in range(int(r[0]), int(r[2]) + 1, step):
				var cell := Vector2i(x, y)
				var rot_list: Array = rots
				if part == "pulley" and s.has("rope_cell"):
					# Player places the pulley AND a rope from rope_cell, auto-aimed like the editor.
					var rc := Vector2i(int(s["rope_cell"][0]), int(s["rope_cell"][1]))
					var pul := Placement.new("pulley", cell, 0)
					sim.load_level(level)
					sim.set_player_parts(held + [pul])
					var brr := Rope.best_rot(sim.parts, rc, 0, 30)
					if brr < 0:
						continue
					tries += 1
					if await _run(sim, level, held + [pul, Placement.new("rope", rc, brr)]) == "goal":
						ok[Vector3i(x, y, brr)] = true
					continue
				if part == "rope":
					sim.load_level(level)
					sim.set_player_parts(held)
					var br := Rope.best_rot(sim.parts, cell, 0, 30)
					if br < 0:
						continue
					rot_list = [br]
				for rot in rot_list:
					var pl := held.duplicate()
					pl.append(Placement.new(part, cell, int(rot)))
					tries += 1
					if await _run(sim, level, pl) == "goal":
						ok[Vector3i(x, y, int(rot))] = true
		var robust := []
		for k in ok:
			var n := 0
			for dd in [Vector2i(step, 0), Vector2i(-step, 0), Vector2i(0, step), Vector2i(0, -step)]:
				if ok.has(Vector3i(k.x + dd.x, k.y + dd.y, k.z)):
					n += 1
			if n >= 3:
				robust.append({"part": part, "x": k.x, "y": k.y, "rot": k.z})
		var line := JSON.stringify({"name": d["name"], "empty": empty, "hits": ok.size(), "tries": tries, "robust": robust.slice(0, 12)})
		print(line)
		var f := FileAccess.open(path + ".out", FileAccess.READ_WRITE if FileAccess.file_exists(path + ".out") else FileAccess.WRITE)
		f.seek_end()
		f.store_line(line)
		f.close()
	quit()
