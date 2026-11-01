class_name Grid
extends RefCounted
## Grid — the single source of truth for snapping.
##
## DETERMINISM: every placement the player makes is stored as integers
## (cell x, cell y, rotation step). World coordinates are derived from those
## integers with the constants below, so a solution file replays identically
## on every device. Never store a float position in a solution.

## One tile in pixels. The stage is 45 x 60 cells (1080 x 1440 px) at design size.
const TILE: int = 96
## Parts snap to a quarter tile.
const CELL: int = TILE / 4  # 24 px
## Rotation snaps to 15 degree steps; 24 steps per turn.
const ROT_STEP_DEG: int = 15
const ROT_STEPS: int = 360 / ROT_STEP_DEG  # 24

## Stage size in cells (portrait). The HUD lives below the stage.
const STAGE_CELLS := Vector2i(45, 60)
const STAGE_PX := Vector2i(STAGE_CELLS.x * CELL, STAGE_CELLS.y * CELL)  # 1080 x 1440


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL, cell.y * CELL)


static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(roundi(p.x / CELL)), int(roundi(p.y / CELL)))


static func snap_world(p: Vector2) -> Vector2:
	return cell_to_world(world_to_cell(p))


static func steps_to_radians(steps: int) -> float:
	return deg_to_rad(float(wrap_steps(steps) * ROT_STEP_DEG))


static func radians_to_steps(rad: float) -> int:
	return wrap_steps(int(roundi(rad_to_deg(rad) / ROT_STEP_DEG)))


static func wrap_steps(steps: int) -> int:
	return posmod(steps, ROT_STEPS)


static func clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, 0, STAGE_CELLS.x), clampi(cell.y, 0, STAGE_CELLS.y))


static func in_stage(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x <= STAGE_CELLS.x and cell.y <= STAGE_CELLS.y
