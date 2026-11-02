extends SceneTree
## Debug: run a level's reference solution and print dynamic part positions every 30 ticks.
func _initialize():
	_go()
func _go():
	await process_frame
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): path = a.trim_prefix("--level=")
	var level := LevelData.load_from_file(path)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.load_level(level)
	sim.set_player_parts(level.reference_solution)
	for rl in sim.rope_lines:
		print("line chain=", rl.chain.map(func(n): return n.name), " offs=", rl.offs, " len=", snappedf(rl.length,0.1), " cur=", snappedf(rl.current_length(),0.1))
	for p in sim.parts:
		if p.get_meta("part_id") == "rope":
			print(p.name, " a=", p.end_a.name if p.end_a else "-", " b=", p.end_b.name if p.end_b else "-")
	sim.start()
	sim.tick.connect(func(t):
		if t % 30 == 0:
			var s := "t=%d" % t
			for p in sim.parts:
				if p is RigidBody2D and not p.freeze:
					s += " %s(%d,%d)" % [p.name, roundi(p.global_position.x), roundi(p.global_position.y)]
			print(s))
	var o = await sim.finished
	print("RESULT ", o["result"], " ticks ", o["ticks"])
	quit()
