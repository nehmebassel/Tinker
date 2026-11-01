extends SceneTree
## Brute-force solution finder for single-plank levels (level design aid, not shipped).
##
##   godot --headless --fixed-fps 60 --path game -s res://tests/find_solution.gd -- --level=res://levels/campaign/001.json [--part=plank] [--step=2]
##        [--region=x0,y0,x1,y1] [--rots=0,3,6] [--with=part:x:y:rot,part:x:y:rot]
##
## Scans every cell (stride --step) and every rotation for one placed part and prints
## the placements that reach the goal, fastest first. Paste one into reference_solution.
## --with holds other player parts fixed, so multi-part solutions are searched one part at a time.

var level_path := ""
var part := "plank"
var step := 2
var region := Rect2i(0, 0, Grid.STAGE_CELLS.x, Grid.STAGE_CELLS.y)
var rots: Array = range(Grid.ROT_STEPS)
var with_parts: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level_path = a.trim_prefix("--level=")
		elif a.begins_with("--part="):
			part = a.trim_prefix("--part=")
		elif a.begins_with("--step="):
			step = int(a.trim_prefix("--step="))
		elif a.begins_with("--region="):
			var v := a.trim_prefix("--region=").split(",")
			region = Rect2i(int(v[0]), int(v[1]), int(v[2]) - int(v[0]), int(v[3]) - int(v[1]))
		elif a.begins_with("--rots="):
			rots = []
			for r in a.trim_prefix("--rots=").split(","):
				rots.append(int(r))
		elif a.begins_with("--with="):
			for w in a.trim_prefix("--with=").split(","):
				var f := w.split(":")
				with_parts.append(Placement.new(f[0], Vector2i(int(f[1]), int(f[2])), int(f[3])))
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
	for y in range(region.position.y, region.end.y + 1, step):
		for x in range(region.position.x, region.end.x + 1, step):
			for r in rots:
				var pl := Placement.new(part, Vector2i(x, y), r)
				var all := with_parts.duplicate()
				all.append(pl)
				sim.set_player_parts(all)
				sim.start()
				var o: Dictionary = await sim.finished
				await process_frame
				tried += 1
				if o["result"] == "goal":
					hits.append({"x": x, "y": y, "rot": r, "ticks": o["ticks"]})
		print("row y=%d done, %d tried, %d hits so far" % [y, tried, hits.size()])
	hits.sort_custom(func(a, b): return a["ticks"] < b["ticks"])
	print("=== %d solutions out of %d tries ===" % [hits.size(), tried])
	for h in hits.slice(0, 40):
		print('{"part": "%s", "x": %d, "y": %d, "rot": %d}   // %d ticks' % [part, h["x"], h["y"], h["rot"], h["ticks"]])
	quit(0)
