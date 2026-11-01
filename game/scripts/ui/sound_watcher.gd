class_name SoundWatcher
extends Node
## SoundWatcher — turns what happens in a running Simulation into sounds.
##
## READ-ONLY by design: it only reads part state (flags, counters, velocities) after each physics
## tick and never writes to a part or a body, so it cannot change a replay. Everything it uses
## already exists for the simulation's own rules (popped, lit, caught_count, _launched...).
##
## Events:   balloon popped -> pop      candle lit -> candle     basket catch -> basket
##           spring launch  -> spring   switch pressed -> switch  cat wakes / mouse caught -> cat
##           cheese eaten   -> mouse    pulley line moving -> pulley (rate-limited)
##           a body's velocity jumps (it hit something) -> impact_wood / impact_metal, louder for
##           harder hits, pitch varies by part so a busy machine does not sound like one note.
## Loops:    fan whirr while any fan is on; motor hum while any motor or conveyor is on.

const IMPACT_DV := 260.0  # px/s change in one tick that counts as a hit
const IMPACT_GAP_MS := 120  # per part
const GLOBAL_GAP_MS := 45  # between any two impact sounds
const PULLEY_GAP_MS := 900
const METAL := ["bucket", "motor", "conveyor", "switch", "spring", "pulley"]
const PITCH := {"ball": 1.0, "plank": 0.85, "bucket": 1.0, "balloon": 1.4, "cheese": 1.25, "mouse": 1.3, "cat": 0.9}

var sim: Simulation
var _prev: Dictionary = {}  # instance id -> {v, flags...}
var _last_hit: Dictionary = {}  # instance id -> msec
var _last_global := 0
var _last_pulley := 0
var _line_len: Dictionary = {}


func watch(p_sim: Simulation) -> void:
	sim = p_sim
	process_physics_priority = 100  # after the simulation and the parts have stepped


func reset() -> void:
	_prev.clear()
	_last_hit.clear()
	_line_len.clear()
	var a := _audio()
	if a:
		a.stop_loops()


## Leaving the level mid-run (Back, Next) frees this watcher: the fan/motor loops belong to the
## persistent App.audio, so stop them here or they would keep playing over the menus.
func _exit_tree() -> void:
	var a := _audio()
	if a:
		a.stop_loops()


func _physics_process(_delta: float) -> void:
	var a := _audio()
	if sim == null or not sim.running or a == null:
		return
	var now := Time.get_ticks_msec()
	var fan_on := false
	var motor_on := false
	for p in sim.parts:
		if not is_instance_valid(p):
			continue
		var id := p.get_instance_id()
		var kind: String = p.get_meta("part_id")
		var st: Dictionary = _prev.get(id, {})
		var first := st.is_empty()
		match kind:
			"balloon":
				if _rose(st, "popped", p.popped, first):
					a.sfx("pop")
			"candle":
				if _rose(st, "lit", p.lit, first):
					a.sfx("candle", 2.0)
			"basket":
				var c: int = p.caught_count
				if not first and c > int(st.get("caught", 0)):
					a.sfx("basket")
				st["caught"] = c
			"spring":
				var n: int = p._launched.size()
				if not first and n > int(st.get("launched", 0)):
					a.sfx("spring")
				st["launched"] = n
			"switch":
				if _rose(st, "pressed", p.pressed, first):
					a.sfx("switch")
			"cat":
				if _rose(st, "awake", p.awake, first):
					a.sfx("cat")
			"mouse":
				if _rose(st, "caught", p.caught, first):
					a.sfx("cat", 0.0, 1.15)
			"cheese":
				if _rose(st, "eaten", p.eaten, first):
					a.sfx("mouse")
			"fan":
				fan_on = fan_on or p.on
			"motor", "conveyor":
				motor_on = motor_on or p.on
		if p is RigidBody2D and not p.freeze:
			var v: Vector2 = p.linear_velocity
			if not first:
				var dv := (v - Vector2(st.get("v", v))).length()
				if dv > IMPACT_DV and now - int(_last_hit.get(id, 0)) > IMPACT_GAP_MS and now - _last_global > GLOBAL_GAP_MS:
					_last_hit[id] = now
					_last_global = now
					var loud := clampf(remap(dv, IMPACT_DV, 1400.0, -14.0, 0.0), -14.0, 0.0)
					a.sfx("impact_metal" if kind in METAL else "impact_wood", loud, float(PITCH.get(kind, 1.0)))
			st["v"] = v
		_prev[id] = st
	a.set_loop("fan", fan_on)
	a.set_loop("motor", motor_on)
	# Pulley creak while a line through a pulley is actually moving (an end rose or fell).
	for rl in sim.rope_lines:
		if rl.chain.size() < 3:
			continue
		var key: int = rl.get_instance_id()
		var y: float = rl.chain[0].global_position.y
		var before: float = float(_line_len.get(key, y))
		_line_len[key] = y
		if absf(y - before) > 1.5 and now - _last_pulley > PULLEY_GAP_MS:
			_last_pulley = now
			a.sfx("pulley", -6.0)


## App.audio, looked up at run time (headless test scripts have no global App identifier).
func _audio() -> Audio:
	var app := get_node_or_null("/root/App")
	return app.audio if app else null


## True once when a flag goes false -> true (not when it starts true).
static func _rose(st: Dictionary, key: String, value: bool, first: bool) -> bool:
	var was := bool(st.get(key, value))
	st[key] = value
	return not first and value and not was
