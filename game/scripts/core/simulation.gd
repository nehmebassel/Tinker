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
##  * links between parts (motor->plank, switch->target, rope->bodies) are resolved in that same
##    order by an attach pass that runs after every rebuild, from integer cells only
##  * the run is counted in physics ticks, never in seconds
##  * end conditions: goal reached, TIMEOUT_TICKS elapsed, or no body moved for STALL_TICKS
##  * no randomness, no reads of wall-clock time
##  * whenever several parts are iterated, it is this node's `parts` array (creation order)

signal finished(outcome: Dictionary)
signal tick(ticks: int)

const TIMEOUT_TICKS := 30 * 60  # 30 s at 60 Hz
const STALL_TICKS := 2 * 60  # 2 s with nothing moving
const STALL_SPEED := 4.0  # px/s below which a body counts as still
const MIN_RUN_TICKS := 30  # never declare a stall before half a second
const GOAL_HOLD_TICKS := 15  # goal must hold this long (a ball bouncing straight out does not count)

var level: LevelData
var player_parts: Array[Placement] = []
var parts: Array[Node2D] = []
var running: bool = false
var ticks: int = 0
var outcome: Dictionary = {}
var rope_lines: Array = []  # Array[RopeLine]
## Sandbox editor only: player placements keep their initial state (lit / on), see PartFactory.create.
var keep_player_state: bool = false

var _still_ticks: int = 0
var _goal_hit_tick: int = -1
var _start_positions: Array[Vector2] = []
var _start_rotations: Array[float] = []
var _links: Node2D  # joints and other helper nodes created by the attach pass


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
	rope_lines.clear()
	for p in parts:
		remove_child(p)
		p.free()
	parts.clear()
	if _links:
		remove_child(_links)
		_links.free()
	_links = Node2D.new()
	_links.name = "Links"
	add_child(_links)
	# DETERMINISM: a brand-new physics space for every build. The broadphase hands out ids from a
	# free list, so re-using a space after frees changes pair ordering and with it the last bits
	# of the solver's float sums. A fresh World2D makes build N identical to build 1.
	if is_inside_tree():
		get_viewport().world_2d = World2D.new()
	if level == null:
		return
	var index := 0
	for pl in level.fixed:
		_spawn(pl, index, true)
		index += 1
	for pl in player_parts:
		_spawn(pl, index, false)
		index += 1
	_attach_pass()


func _spawn(pl: Placement, index: int, is_fixed: bool) -> void:
	var node := PartFactory.create(pl, index, is_fixed, keep_player_state and not is_fixed)
	if node == null:
		return
	add_child(node)
	parts.append(node)


## Resolve every link in creation order. Parts implement on_attach(sim) and use the finders below.
func _attach_pass() -> void:
	for p in parts:
		if p.has_method("on_attach"):
			p.on_attach(self)
	_build_rope_lines()


func start() -> void:
	if running or level == null:
		return
	# Always start from a clean rebuild so a Play after a Stop is identical to the first Play.
	rebuild()
	running = true
	_start_positions = []
	_start_rotations = []
	for p in parts:
		_start_positions.append(p.global_position)
		_start_rotations.append(p.global_rotation)
	for p in parts:
		p.set_running(true)
	for rl in rope_lines:
		rl.on_start()


func stop() -> void:
	if not running:
		return
	rebuild()


func _physics_process(_delta: float) -> void:
	if not running:
		return
	FramePacer.busy(250)  # a running machine animates at full rate
	ticks += 1
	tick.emit(ticks)
	_freeze_escapees()
	for rl in rope_lines:
		rl.enforce()
	# Goal check.
	if _goal_hit_tick < 0 and _goal_reached():
		_goal_hit_tick = ticks
	if _goal_hit_tick >= 0:
		if _goal_reached():
			if ticks - _goal_hit_tick >= GOAL_HOLD_TICKS:
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


# ---------------------------------------------------------------- goals

func _goal_reached() -> bool:
	var g := level.goal
	match str(g.get("type", "basket")):
		"basket":
			var need := int(g.get("count", 1))
			var got := 0
			for p in parts:
				if p.get_meta("part_id") == "basket":
					got += p.caught_count
			return got >= need
		"candle":
			# Every candle that started unlit must be lit.
			var any := false
			for p in parts:
				if p.get_meta("part_id") == "candle" and not p.lit_at_start:
					any = true
					if not p.lit:
						return false
			return any
		"cheese":
			for p in parts:
				if p.get_meta("part_id") == "cheese" and p.eaten:
					return true
			return false
		"caught":
			# {"type":"caught","index":i}: that specific part is inside a basket.
			var ci := int(g.get("index", -1))
			if ci < 0 or ci >= parts.size():
				return false
			for p in parts:
				if p.get_meta("part_id") == "basket" and p._inside.has(parts[ci]):
					return true
			return false
		"pop":
			# Any balloon popped (fixed or player-placed).
			for p in parts:
				if p.get_meta("part_id") == "balloon" and p.popped:
					return true
			return false
		"state":
			# {"type":"state","index":i,"key":"popped","value":true}
			var i := int(g.get("index", -1))
			if i < 0 or i >= parts.size():
				return false
			return parts[i].get(str(g.get("key", ""))) == g.get("value")
		"displaced":
			# {"type":"displaced","index":i,"min_dx":200} and/or "min_dy" (signed; negative = up)
			var i := int(g.get("index", -1))
			if i < 0 or i >= parts.size() or i >= _start_positions.size():
				return false
			var d := parts[i].global_position - _start_positions[i]
			if g.has("min_dx"):
				var mdx := float(g["min_dx"])
				if (mdx >= 0.0 and d.x < mdx) or (mdx < 0.0 and d.x > mdx):
					return false
			if g.has("min_dy"):
				var mdy := float(g["min_dy"])
				if (mdy >= 0.0 and d.y < mdy) or (mdy < 0.0 and d.y > mdy):
					return false
			return true
		"rotated":
			# {"type":"rotated","index":i,"min_abs_rad":1.0}
			var i := int(g.get("index", -1))
			if i < 0 or i >= parts.size() or i >= _start_rotations.size():
				return false
			return absf(angle_difference(_start_rotations[i], parts[i].global_rotation)) >= float(g.get("min_abs_rad", 1.0)) \
				or absf(parts[i].global_rotation - _start_rotations[i]) >= float(g.get("min_abs_rad", 1.0))
	return false


## Anything that leaves the stage (plus a margin) is out of play: frozen where it crossed the
## line so the run can stall instead of waiting 30 s for a body falling forever.
const OUT_MARGIN := Grid.TILE * 3.0


func _freeze_escapees() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(Grid.STAGE_PX)).grow(OUT_MARGIN)
	for p in parts:
		if p is RigidBody2D and not p.freeze and not bounds.has_point(p.global_position):
			p.set_meta("out", true)
			p.set_deferred("freeze", true)
			p.set_deferred("linear_velocity", Vector2.ZERO)
			p.set_deferred("angular_velocity", 0.0)


func _anything_moving() -> bool:
	for p in parts:
		if p is RigidBody2D and not p.freeze:
			if p.linear_velocity.length() > STALL_SPEED or absf(p.angular_velocity) > 0.05:
				return true
	for rl in rope_lines:
		if rl.is_winching():
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


# ---------------------------------------------------------------- finders (used by on_attach)

## Part whose cell is exactly `cell` (lowest index wins), else nearest within `radius` cells, else null.
func part_at_cell(cell: Vector2i, exclude: Node = null, radius: int = 1, filter: Callable = Callable()) -> Node2D:
	var best: Node2D = null
	var best_d := radius * radius + 1
	for p in parts:
		if p == exclude:
			continue
		if filter.is_valid() and not filter.call(p):
			continue
		var c: Vector2i = p.get_meta("cell")
		var d := (c - cell).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best


## Nearest part (cell distance) satisfying `filter`; ties go to the lowest index.
func nearest_part(from: Node2D, filter: Callable) -> Node2D:
	var fc: Vector2i = from.get_meta("cell")
	var best: Node2D = null
	var best_d := 1 << 30
	for p in parts:
		if p == from or not filter.call(p):
			continue
		var d := (Vector2i(p.get_meta("cell")) - fc).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best


func parts_of(id: String) -> Array:
	var out := []
	for p in parts:
		if p.get_meta("part_id") == id:
			out.append(p)
	return out


func add_link_node(n: Node) -> void:
	_links.add_child(n)


# ---------------------------------------------------------------- ropes

## Ropes register (rope, end_a, end_b). Ropes that share a pulley are merged into one line so the
## total length is conserved across the pulley: pulling one end lifts the other.
var _rope_regs: Array = []


func register_rope(rope: Node2D, a: Node2D, b: Node2D, oa: Vector2 = Vector2.ZERO, ob: Vector2 = Vector2.ZERO) -> void:
	_rope_regs.append({"rope": rope, "a": a, "b": b, "oa": oa, "ob": ob})


func _build_rope_lines() -> void:
	rope_lines.clear()
	var used := {}
	for i in _rope_regs.size():
		if used.has(i):
			continue
		var reg: Dictionary = _rope_regs[i]
		if reg["a"] == null or reg["b"] == null:
			used[i] = true
			continue
		used[i] = true
		var chain: Array = [reg["a"], reg["b"]]
		var offs: Array = [reg["oa"], reg["ob"]]  # snap-point offset of each chain node (pulleys: centre)
		var ropes: Array = [reg["rope"]]
		var length: float = reg["rope"].rope_length_px()
		# Extend through pulleys at either end.
		for _pass in range(8):
			var grew := false
			for side in [0, 1]:
				var end: Node2D = chain[0] if side == 0 else chain[-1]
				if end.get_meta("part_id") != "pulley":
					continue
				for j in _rope_regs.size():
					if used.has(j):
						continue
					var r2: Dictionary = _rope_regs[j]
					if r2["a"] == null or r2["b"] == null:
						continue
					var other: Node2D = null
					var other_off := Vector2.ZERO
					if r2["a"] == end:
						other = r2["b"]
						other_off = r2["ob"]
					elif r2["b"] == end:
						other = r2["a"]
						other_off = r2["oa"]
					if other == null:
						continue
					used[j] = true
					ropes.append(r2["rope"])
					length += r2["rope"].rope_length_px()
					if side == 0:
						chain.push_front(other)
						offs.push_front(other_off)
					else:
						chain.push_back(other)
						offs.push_back(other_off)
					grew = true
					break
			if not grew:
				break
		var line := RopeLine.new(chain, offs, length, ropes)
		rope_lines.append(line)
		for r in ropes:
			r.line = line
	_rope_regs.clear()


## One inextensible line through zero or more pulleys. Enforced as a one-sided distance
## constraint with impulses on the dynamic end bodies. Pulleys are fixed waypoints; a motor on a
## pulley winches the line (shortens it while on).
class RopeLine:
	var chain: Array  # [end_a, pulley..., end_b]
	var offs: Array  # snap-point offset (local) for each chain node; pulleys use their centre
	var length: float
	var ropes: Array
	var start_length: float
	var winch: Node2D = null  # motor, if any pulley on the line has one
	const BETA := 12.0  # position correction per second
	const MIN_LENGTH := 24.0

	func _init(p_chain: Array, p_offs: Array, p_length: float, p_ropes: Array) -> void:
		chain = p_chain
		offs = p_offs
		length = p_length
		start_length = p_length
		ropes = p_ropes
		for n in chain:
			if n.get_meta("part_id") == "pulley" and n.winch != null:
				winch = n.winch

	func on_start() -> void:
		length = start_length

	func is_winching() -> bool:
		if winch == null or not winch.on or is_slack():
			return false
		# Still counts as motion only while the length can still change.
		return (winch.direction > 0 and length > MIN_LENGTH) or (winch.direction < 0 and length < start_length * 2.0)

	## World position of chain node i's snap point.
	func pt(i: int) -> Vector2:
		var n: Node2D = chain[i]
		return n.to_global(offs[i]) if offs[i] != Vector2.ZERO else n.global_position

	func current_length() -> float:
		var d := 0.0
		for i in range(chain.size() - 1):
			d += pt(i).distance_to(pt(i + 1))
		return d

	static func _dynamic(n: Node2D) -> bool:
		return n is RigidBody2D and not n.freeze

	## An endpoint that left play (popped balloon, eaten cheese, caught mouse, fell off the stage)
	## no longer holds the rope: the line goes slack instead of acting as an invisible anchor.
	static func _gone(n: Node2D) -> bool:
		if n.get_meta("out", false):
			return true
		for key in ["popped", "eaten", "caught"]:
			if n.get(key) == true:
				return true
		return false

	func is_slack() -> bool:
		return _gone(chain[0]) or _gone(chain[-1])

	func enforce() -> void:
		if is_slack():
			return
		if winch != null and winch.on:
			length = clampf(length - winch.direction * winch.winch_speed / 60.0, MIN_LENGTH, start_length * 2.0)
		var d := current_length()
		var excess := d - length
		if excess <= 0.0:
			return
		var a: Node2D = chain[0]
		var b: Node2D = chain[-1]
		var n := chain.size()
		var pa := pt(0)
		var pb := pt(n - 1)
		var dir_a := (pt(1) - pa).normalized()
		var dir_b := (pt(n - 2) - pb).normalized()
		# Effective inverse mass at each snap point along the rope: linear part plus the rotational
		# part (an off-centre pull also spins the body), so the correction is not overshot.
		var wa: float = _eff_inv_mass(a, pa - a.global_position, dir_a) if _dynamic(a) else 0.0
		var wb: float = _eff_inv_mass(b, pb - b.global_position, dir_b) if _dynamic(b) else 0.0
		var wsum: float = wa + wb
		if wsum <= 0.0:
			return
		# Rate at which the line is stretching (positive = getting longer).
		var v_sep := 0.0
		# Velocity of the snap point itself (includes spin when it is off-centre).
		if wa > 0.0:
			v_sep += -(a.linear_velocity + _spin_vel(a, pa)).dot(dir_a)
		if wb > 0.0:
			v_sep += -(b.linear_velocity + _spin_vel(b, pb)).dot(dir_b)
		var dv: float = excess * BETA + maxf(0.0, v_sep)
		var j: float = dv / wsum
		# Pull at the snap point: an off-centre pull also turns the part (a bucket swings on its handle).
		if wa > 0.0:
			a.apply_impulse(dir_a * j, pa - a.global_position)
		if wb > 0.0:
			b.apply_impulse(dir_b * j, pb - b.global_position)

	static func _eff_inv_mass(body: RigidBody2D, r: Vector2, d: Vector2) -> float:
		var inv_i := 0.0
		var st := PhysicsServer2D.body_get_direct_state(body.get_rid())
		if st:
			inv_i = st.inverse_inertia
		var rc := r.cross(d)
		return 1.0 / body.mass + rc * rc * inv_i

	static func _spin_vel(body: Node2D, p: Vector2) -> Vector2:
		if not (body is RigidBody2D):
			return Vector2.ZERO
		var r := p - body.global_position
		return Vector2(-r.y, r.x) * body.angular_velocity
