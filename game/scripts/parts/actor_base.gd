class_name ActorBase
extends RigidBody2D
## Shared body for the mouse and the cat: an upright rigid body steered by rules.
## Rules only read positions of other parts (through the Simulation, in creation order) and
## cast rays through the physics server, so they are as deterministic as the physics itself.

var def: Dictionary
var size: Vector2 = Vector2(48, 36)
var fill: Color = Color.WHITE
var speed: float = 200.0
var accel: float = 1400.0  # px/s^2 of horizontal steering while grounded
var hop: float = 260.0  # upward speed when blocked by a low obstacle
var running: bool = false
var sim: Node = null
var dir: int = 0  # -1 left, 0 idle, +1 right (what the rules decided this tick)
var facing: int = 1
var _hop_cooldown: int = 0


func configure(p_def: Dictionary) -> void:
	def = p_def
	size = Vector2(float(def["shape"]["w"]), float(def["shape"]["h"]))
	fill = PartFactory.color_of(def)
	mass = float(def.get("mass", 1.0))
	speed = float(def.get("speed", speed))
	hop = float(def.get("hop", hop))
	lock_rotation = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 0.9))
	pm.bounce = 0.0
	physics_material_override = pm
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	var cs := CollisionShape2D.new()
	cs.shape = PartFactory.make_shape(def)
	add_child(cs)
	queue_redraw()


func on_attach(p_sim: Node) -> void:
	sim = p_sim


func set_running(p_running: bool) -> void:
	running = p_running
	freeze = not p_running or not alive()


func alive() -> bool:
	return true


func _physics_process(_delta: float) -> void:
	if not running or freeze or not alive():
		return
	dir = decide()
	if dir != 0:
		facing = dir
	if _hop_cooldown > 0:
		_hop_cooldown -= 1
	var grounded := _grounded()
	if dir != 0 and grounded:
		var target := dir * speed
		var dv := clampf(target - linear_velocity.x, -accel / 60.0, accel / 60.0)
		linear_velocity.x += dv
		if _blocked_ahead() and _hop_cooldown == 0:
			linear_velocity.y = -hop
			_hop_cooldown = 30
	queue_redraw()


## Override: return -1, 0 or +1.
func decide() -> int:
	return 0


## Three rays (left foot, centre, right foot): a body hanging over a ledge edge is still supported
## by that edge and must keep steering, otherwise it stalls there forever.
func _grounded() -> bool:
	var space := get_world_2d().direct_space_state
	for fx in [-size.x * 0.4, 0.0, size.x * 0.4]:
		var from := global_position + Vector2(fx, 0)
		var to := from + Vector2(0, size.y / 2.0 + 6.0)
		var q := PhysicsRayQueryParameters2D.create(from, to)
		q.exclude = [get_rid()]
		q.collide_with_areas = false
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func _blocked_ahead() -> bool:
	var space := get_world_2d().direct_space_state
	# Cast at foot level so a low step (a switch plate, a plank edge) triggers a hop.
	var from := global_position + Vector2(0, size.y / 2.0 - 5.0)
	var to := from + Vector2(dir * (size.x / 2.0 + 10.0), 0)
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Node = hit["collider"]
	# Don't hop at the thing we are chasing.
	return not (n.has_meta("part_id") and n.get_meta("part_id") in ["mouse", "cheese"])


## Nearest part with `id` by horizontal distance, in creation order for ties.
func nearest(id: String, max_dist: float, filter: Callable = Callable()) -> Node2D:
	if sim == null:
		return null
	var best: Node2D = null
	var best_d := max_dist
	for p in sim.parts:
		if p == self or p.get_meta("part_id") != id:
			continue
		if filter.is_valid() and not filter.call(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


static func sign_toward(from: Vector2, to: Vector2, deadzone: float = 6.0) -> int:
	var dx := to.x - from.x
	if absf(dx) < deadzone:
		return 0
	return 1 if dx > 0.0 else -1


func set_ghost(on: bool) -> void:
	modulate.a = 0.45 if on else 1.0
