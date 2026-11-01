class_name Simulation
extends Node2D
## Simulation — builds a level from data, runs it, and reports a deterministic outcome.
##
## Life cycle:  load_level() -> set_player_parts() -> start() -> [running] -> finished(outcome)
##              stop() rewinds by REBUILDING every part from its integer placement. There is no
##              "restore state" path: a rewind and a fresh replay are the same code, so a run can
##              never carry state over from the previous one.
##
## DETERMINISM RULES enforced here:
##  * parts are created in a fixed order (fixed parts first, then player parts, in list order)
##  * the run is counted in physics ticks, never in seconds
##  * end conditions: goal reached, TIMEOUT_TICKS elapsed, or no body moved for STALL_TICKS
##  * no randomness, no reads of wall-clock time

signal finished(outcome: Dictionary)
signal tick(ticks: int)

const TIMEOUT_TICKS := 30 * 60  # 30 s at 60 Hz
const STALL_TICKS := 2 * 60  # 2 s with nothing moving
const STALL_SPEED := 4.0  # px/s below which a body counts as still
const MIN_RUN_TICKS := 30  # never declare a stall before half a second

var level: LevelData
var player_parts: Array[Placement] = []
var parts: Array[Node2D] = []
var running: bool = false
var ticks: int = 0
var outcome: Dictionary = {}

var _still_ticks: int = 0
var _goal_hit_tick: int = -1
var _baskets: Array = []


func load_level(p_level: LevelData) -> void:
	level = p_level
	player_parts = []
	rebuild()


func set_player_parts(placements: Array) -> void:
	player_parts = []
	for p in placements:
		player_parts.append(p.duplicate_placement())
	rebuild()


## Tear everything down and recreate from integer data. Used for load, edit, and rewind.
func rebuild() -> void:
	running = false
	ticks = 0
	_still_ticks = 0
	_goal_hit_tick = -1
	outcome = {}
	for p in parts:
		remove_child(p)
		p.free()
	parts.clear()
	_baskets.clear()
	if level == null:
		return
	var index := 0
	for pl in level.fixed:
		_spawn(pl, index, true)
		index += 1
	for pl in player_parts:
		_spawn(pl, index, false)
		index += 1


func _spawn(pl: Placement, index: int, is_fixed: bool) -> void:
	var node := PartFactory.create(pl, index, is_fixed)
	if node == null:
		return
	add_child(node)
	parts.append(node)
	if node.has_signal("caught"):
		_baskets.append(node)


func start() -> void:
	if running or level == null:
		return
	# Always start from a clean rebuild so a Play after a Stop is identical to the first Play.
	rebuild()
	running = true
	for p in parts:
		p.set_running(true)


func stop() -> void:
	if not running:
		return
	rebuild()


func _physics_process(_delta: float) -> void:
	if not running:
		return
	ticks += 1
	tick.emit(ticks)
	# Goal check.
	if _goal_hit_tick < 0 and _goal_reached():
		_goal_hit_tick = ticks
	# Count the goal only once it has held for 15 ticks (a ball that bounces straight out does not count).
	if _goal_hit_tick >= 0:
		if _goal_reached():
			if ticks - _goal_hit_tick >= 15:
				_end("goal")
				return
		else:
			_goal_hit_tick = -1
	if ticks >= TIMEOUT_TICKS:
		_end("timeout")
		return
	if ticks > MIN_RUN_TICKS:
		if _anything_moving():
			_still_ticks = 0
		else:
			_still_ticks += 1
			if _still_ticks >= STALL_TICKS:
				_end("stalled")
				return


func _goal_reached() -> bool:
	match str(level.goal.get("type", "basket")):
		"basket":
			var need := int(level.goal.get("count", 1))
			var got := 0
			for b in _baskets:
				got += b.caught_count
			return got >= need
	return false


func _anything_moving() -> bool:
	for p in parts:
		if p is RigidBody2D:
			if p.linear_velocity.length() > STALL_SPEED or absf(p.angular_velocity) > 0.05:
				return true
	return false


func _end(result: String) -> void:
	running = false
	for p in parts:
		p.set_running(false)
	outcome = {
		"result": result,
		"ticks": ticks,
		"parts_used": player_parts.size(),
		"hash": state_hash(result),
	}
	# Deferred so listeners may rebuild/free parts without touching bodies mid-physics-step.
	call_deferred("emit_signal", "finished", outcome)


## Digest of the final state. Two runs are "identical" when this matches.
func state_hash(result: String = "") -> String:
	var lines := PackedStringArray()
	lines.append("level=%s result=%s ticks=%d" % [level.id if level else "", result, ticks])
	for p in parts:
		lines.append(p.snapshot())
	return "\n".join(lines).md5_text()


## Full snapshot text, for debugging a mismatch.
func state_text() -> String:
	var lines := PackedStringArray()
	for p in parts:
		lines.append(p.snapshot())
	return "\n".join(lines)
