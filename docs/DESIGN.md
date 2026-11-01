# Tinker — design and architecture

Working copy of the development instructions plus the decisions that shaped the code.
Read this before touching `game/`.

## Vision

Every day the whole world gets the same goal and the same parts; build the machine that solves it in the fewest pieces.
Spiritual successor to The Incredible Machine, designed for touch. Three modes: Campaign, Daily, Sandbox.
No gambling, no dark patterns, one paid unlock.

## Repo layout

```
game/        Godot 4.5 project (GDScript, 2D, GL Compatibility renderer)
  parts/     one JSON per part + index.json
  scripts/core/   grid, placement, level_data, part_registry, simulation
  scripts/parts/  one script per part + part_factory
  scripts/ui/     level_screen (the play screen)
  tests/     run_tests.gd (headless suite), find_solution.gd (level design aid)
  levels -> ../levels   (symlink so res://levels/ works in editor and export)
levels/      campaign JSON + hashes.txt (recorded determinism hashes)
server/      Node backend for Cloud Run (M4)
docs/        PROGRESS.md, DESIGN.md, STORE.md, screenshots/
.github/workflows/ci.yml
tools/       local tool installs (gitignored)
build/       outputs (gitignored)
```

## Determinism — the first requirement

| Rule | Where |
| --- | --- |
| 60 Hz fixed step, `physics_jitter_fix = 0`, 16 solver iterations | `game/project.godot` |
| Positions are integer quarter-tile cells (24 px), rotations are 15° steps (0..23) | `Grid`, `Placement` |
| Solution file = level id + list of `{part, x, y, rot}` integers | `Placement.to_dict()` |
| Parts are created in fixed order: level `fixed[]` then player placements | `Simulation.rebuild()` |
| Runs are counted in ticks; end on goal (held 15 ticks), 1800 ticks, or 120 still ticks | `Simulation._physics_process` |
| Rewind = full rebuild from data | `Simulation.stop()` |
| Outcome hash = md5 of level id, result, ticks and every part's quantised position/rotation/velocity | `Simulation.state_hash()` |
| Nothing in the simulation reads wall-clock time or RNG | code review rule |

Verified so far: 100 in-process replays identical; separate processes identical; `--fixed-fps 30/60/144` and real time identical.
Not yet verified: two real phones (ARM) vs CI (x86). If they diverge, the plan is a Box2D v3 GDExtension or fixed-point, not tweaking.

### Why `--fixed-fps`
Godot steps physics from wall-clock time. In headless runs that would make 100 replays take 100 × 3 s. `--fixed-fps 60` makes every frame advance exactly one tick with the same 1/60 s step the phone uses; `Engine.time_scale` was rejected because it changes the step size.

## Level JSON

```json
{
  "id": "c001", "world": 1, "number": 1, "title": "First drop", "hint": "...",
  "goal": {"type": "basket", "count": 1},
  "fixed": [{"part": "plank", "x": 8, "y": 14, "rot": 1}, {"part": "ball", "x": 8, "y": 12, "rot": 0}, {"part": "basket", "x": 27, "y": 52, "rot": 0}],
  "tray": [{"part": "plank", "count": 1}],
  "slots": 1,
  "reference_solution": [{"part": "plank", "x": 18, "y": 39, "rot": 4}]
}
```
Stage is 45×60 cells. Keep fixed parts out of the PLAY corner (x>35 and y>48).
Find a reference solution with `tests/find_solution.gd` (brute force over one part) and record the hash with
`godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd` → copy `build/determinism-hashes.txt` to `levels/hashes.txt`.

## Part JSON

```json
{"id": "ball", "name": "Bowling ball", "group": "body", "body": "rigid",
 "shape": {"type": "circle", "radius": 36}, "mass": 10, "friction": 0.8, "bounce": 0.1,
 "color": "#ff5d73", "script": "res://scripts/parts/ball.gd", "interacts_with": ["plank", "basket"]}
```
Every part script implements `configure(def)`, `set_running(bool)`, `snapshot() -> String`, `set_ghost(bool)` and draws itself in `_draw()` (flat fill, thick ink outline — art direction: clean flat, thick outlines, bright colours).
New parts: add the JSON, the script, and the id to `parts/index.json`.

## Touch controls (M1)

- Drag from the tray: the part floats 1.25 tiles above the finger; a translucent ghost sits on the snapped landing cell with a crosshair; ghost turns red when the drop is invalid (off-stage or overlapping another part, checked with a physics shape query).
- Tap a placed part: rotation ring (radius 150 px) with a handle; drag the handle for 15° steps; double-tap the ring for 90°. Buttons "Turn" (+15°) and "90°" do the same.
- Drag a placed part to move it; drop it on the tray to remove it.
- Pinch to zoom (fit..3×fit), two-finger drag to pan, double-tap empty space or "Fit" to refit.
- PLAY is the big corner button; during a run everything is locked and it reads STOP; STOP rewinds instantly.
- Undo/Redo always visible in the top bar. History stores full placement snapshots.
- All touch handling is in `LevelScreen._input` on `InputEventScreenTouch/Drag`; mouse is emulated as touch so desktop testing uses the same path. Buttons are real Controls; a touch that starts on one is left to the GUI.
- Touch targets are 132 px at 1080 design width (~48 pt on a 6" phone). Portrait only.

## Testing

```
godot --headless --path game --import                                            # once after clone
godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd -- --replays=100
xvfb-run -a -s "-screen 0 1200x2100x24" godot --path game --rendering-driver opengl3 --resolution 540x960 -- --smoke
```
The smoke test synthesises touch events (converted to window coordinates with `get_final_transform()`), drags the plank to the reference cell, rotates it with the ring, undoes/redoes, presses PLAY, and asserts the level is solved. Screenshots in `build/shots/`.

## Android export

`game/export_presets.cfg` has the "Android" preset (arm64-v8a + x86_64, debug signing). Godot reads the SDK/JDK paths from `~/.config/godot/editor_settings-4.5.tres` and the debug keystore from `GODOT_ANDROID_KEYSTORE_DEBUG_PATH/USER/PASSWORD`. See `tools/setup.sh` for the full local setup and `.github/workflows/ci.yml` for the CI version.

## Backend (M4, not built)

Node 22 on Cloud Run + Firestore. `GET /daily/{date}`, `POST /score` (headless Godot replays the solution), `GET /board/{date}?scope=`, `POST/GET /level`. Scores are never trusted from the client. Device id only; no tracking SDKs. All configuration from environment / remote config, never hard-coded.
