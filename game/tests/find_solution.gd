extends SceneTree
## Brute-force solution finder for single-plank levels (level design aid, not shipped).
##
##   godot --headless --fixed-fps 60 --path game -s res://tests/find_solution.gd -- --level=res://levels/campaign/001.json [--part=plank] [--step=2]
##
## Scans every cell (stride --step) and every rotation for one placed part and prints
## the placements that reach the goal, fastest first. Paste one into reference_solution.

var level_path := ""
var part := "plank"
var step := 2


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level_path = a.trim_prefix("--level=")
		elif a.begins_with("--part="):
			part = a.trim_prefix("--part=")
		elif a.begins_with("--step="):
			step = int(a.trim_prefix("--step="))
	_run()


func _run() -> void:
	await process_frame
	var level := LevelData.load_from_file(level_path)
	if level == null:
		quit(1)
		return
	var sim := Simulation.new()
	root.add_child(sim)
	sim.load_level(level)
	var hits: Array = []
	var tried := 0
	for y in range(0, Grid.STAGE_CELLS.y + 1, step):
		for x in range(0, Grid.STAGE_CELLS.x + 1, step):
			for r in range(Grid.ROT_STEPS):
				var pl := Placement.new(part, Vector2i(x, y), r)
				sim.set_player_parts([pl])
				sim.start()
				var o: Dictionary = await sim.finished
				tried += 1
				if o["result"] == "goal":
					hits.append({"x": x, "y": y, "rot": r, "ticks": o["ticks"]})
		print("row y=%d done, %d tried, %d hits so far" % [y, tried, hits.size()])
	hits.sort_custom(func(a, b): return a["ticks"] < b["ticks"])
	print("=== %d solutions out of %d tries ===" % [hits.size(), tried])
	for h in hits.slice(0, 40):
		print('{"part": "%s", "x": %d, "y": %d, "rot": %d}   // %d ticks' % [part, h["x"], h["y"], h["rot"], h["ticks"]])
	quit(0)
