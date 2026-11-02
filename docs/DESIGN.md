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
| A brand-new `World2D` (physics space) for every build | `Simulation.rebuild()` |
| Links (motor→plank, switch→target, rope ends) resolved in creation order from integer cells | `Simulation._attach_pass()` |
| Bodies that leave the stage (+3 tiles) are frozen where they crossed | `Simulation._freeze_escapees()` |
| Whenever a part iterates bodies in an Area2D, the list is sorted by part index | `PartFactory.sorted_bodies()` |

### Two Godot physics findings (M2) — do not undo
1. **Fresh physics space per build.** Godot's 2D broadphase hands out ids from a free list. Rebuilding
   parts inside the same space reuses ids in a different order, which changes pair/constraint order and
   with it the last bits of the solver's float sums: replay 2 differed from replay 1 by 0.001 px on a ball
   crossing plank seams. `get_viewport().world_2d = World2D.new()` in `rebuild()` fixed it; 3,200 replays
   across 32 levels are now bit-identical, in-process and across processes.
2. **`StaticBody2D.constant_linear_velocity` is ignored for an already-resting contact.** A conveyor switched
   on mid-run would not move the ball on it. The belt is therefore driven by the conveyor itself (an Area2D
   strip accelerates bodies toward belt speed each tick). Same for motorised paddles: `PinJoint2D`'s motor is
   far too weak, so a powered plank sets its angular velocity directly.

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
Stage is 45×60 cells. Keep fixed parts out of the PLAY corner (x>35 and y>48). Switches go one cell above the floor they sit on (`y = floor_y - 1`).
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

## Parts (M2) — the 15 from the brief plus cheese

Every part is `game/parts/<id>.json` + `game/scripts/parts/<id>.gd`. Links are decided by **what shares a cell**
(so a solution stays `(part, x, y, rot)` integers) or by **nearest part**:

| Part | Behaviour | Links |
| --- | --- | --- |
| Ball | heavy rigid body, CCD on | — |
| Plank | static ramp; **pivot** when a motor shares its cell (motor on = spinning paddle, off = free see-saw); **dynamic** when a rope ties to it | motor, rope |
| Basket | three static walls + sensor; counts rigid bodies inside (ball, mouse, cheese) | — |
| Fan | force cone along +X, strength × `wind_factor` of the target part × falloff, sampled at several points so a see-saw tips | switch |
| Conveyor | belt strip accelerates resting bodies along +X; powered unless a motor on its cell is off | motor, switch |
| Spring | pad above the body; replaces the incoming normal speed with `gain·v_in + kick` once per landing | — |
| Motor | powered pivot; rot steps 0–11 clockwise, 12–23 counter-clockwise; drives plank / conveyor / pulley (winch) on its cell | switch |
| Rope | ties two **snap points** (see *Ropes and pulleys* below): end A = snap point nearest its cell, end B = target along its facing (pulleys first); starts taut; one-sided distance constraint pulling AT the snap points (`Simulation.RopeLine`) | parts with `anchors` |
| Pulley | fixed wheel; ropes that end on it join into one line (total length conserved); motor on its cell = winch | rope, motor |
| Switch | pressure plate; toggles the **nearest** fan/motor/conveyor (lowest index on ties; a motor-powered conveyor is controlled via its motor); re-arms when empty; link drawn as a dashed line | — |
| Balloon | negative gravity scale, damped; lifts light things on a rope; pops in a lit flame | fan, candle, rope |
| Bucket | rigid U, rotation locked; gets heavier with contents; hangs on a rope | rope |
| Candle | `lit` state; flame pops balloons, scares the cat, lights an unlit candle whose wick it overlaps | — |
| Cheese | light rigid body; eaten when the mouse touches it | — |
| Mouse | runs toward the nearest cheese, flees an awake cat within `fear_range`, hops low steps | — |
| Cat | sleeps until a mouse is within `wake_range`, chases it, catches on contact; flees a lit candle | — |

Initial state for fixed parts comes from the level: `{"part":"motor","x":..,"y":..,"rot":0,"state":{"on":false}}`
(also `candle.lit`, `fan.on`, `conveyor.on`, `cat.awake`). Player-placed parts always use the definition default.

Goal types: `basket {count}`, `candle` (every initially-unlit candle lit), `cheese`, `state {index,key,value}`,
`displaced {index,min_dx,min_dy}`, `rotated {index,min_abs_rad}`. Levels may set `"expect": "stalled"` for
negative demonstrations.

Interaction test levels: `levels/tests/*.json`, generated by `python3 levels/tests/make_tests.py` (one per row of
the interaction table; all fixed parts, empty solution; the harness replays each 100×). Gallery:
`docs/screenshots/m2_parts_gallery.png`.

## Campaign (M3)

`levels/campaign/make_campaign.py` is the source: edit it, run it, then `run_tests.gd` (which also asserts every
campaign level is NOT solved with an empty tray). `index.json` lists worlds → levels; the game never lists the
directory. Finding a reference solution:

```
godot --headless --fixed-fps 60 --path game -s res://tests/find_solution.gd -- --level=res://levels/campaign/012.json \
  --part=conveyor --step=2 --region=2,26,20,46 --rots=0,1,23 [--with=fan:1:28:0]
```
`--with` holds other player parts so multi-part solutions are searched one part at a time. The solver does not
check the editor's overlap rule, so prefer placements that do not intersect fixed parts (e.g. a switch goes at
`floor_y - 1`, never on the floor plank's own row).

Unlock: level N+1 opens when N is solved (`Campaign.is_unlocked`). Worlds 1–2 free, 3+ paid (M7, not gated yet).
Save: `user://save.json` — per level solved / best_parts / best_ms / best solution (integers), via `SaveData`.
Navigation: `App` autoload (`open_level`, `open_world_select`, deferred scene changes). Main scene is the world
select; the level scene is run directly for tests: `godot --path game res://scenes/level.tscn -- --smoke --level=…`.
Flow test: `godot --path game -- --flow` drives world select → level 1 → solve → Next → back through synthetic touches.

Design rules learned the hard way (all enforced by tests now):
- Actors steer with impulses, never by writing `linear_velocity` (that discarded the conveyor's impulse).
- A mouse fears only an awake, unscared cat on its own level; a scared cat never catches; a cat cannot catch what
  stands on its head (a mouse crossing a pit over it); actors use three ground rays so a body hanging over a
  ledge edge keeps steering; the mouse stops once the cheese is within its half-width (straight above/below).
- Conveyor belts drive both faces (rot 12 = carries leftward on top). Switch plates re-arm after 20 empty ticks.
- A see-saw needs a stop under one end or it tips at once. Springs cap at 900 px/s (gain 1.2, kick 250).
- Wind has no occlusion: walls do not shield from a fan. Levels must not rely on shelter.

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

## Sandbox (M5)

Brief: build any level from all parts, set a goal, play-test it, publish as a link; others play and remix;
the server replays the author's solution before accepting. Acceptance: built on phone A, played on phone B
from a link.

* **Sandbox home** (`scripts/ui/sandbox_screen.gd`, from the map's Sandbox button): New level; Play a code
  or pasted link; My levels (Edit / Test / Link / Delete); Community = newest published levels
  (`GET /levels/recent`).
* **Editor** = the level screen in mode `edit` (`App.sandbox = {mode, index}`): tray holds every part,
  unlimited (∞); what is placed is the level's FIXED layout; TEST runs it for free (no tries, toast only).
  Saved to `user://sandbox.json` (`SandboxStore`) on leaving. Changing the layout clears the solution.
* **Start states**: selecting a candle / motor / fan / conveyor in the editor shows a Light/Unlit or On/Off
  button; the state is stored on the layout placement. `Simulation.keep_player_state` (editor only) makes TEST
  honour it, since the layout is loaded as player placements. A candle goal needs an unlit candle in the layout.
* **Next** → `SandboxSetup`: name, goal (ball in basket / light the candle / mouse gets cheese / pop a
  balloon), parts the player gets (0-5 each), slots. `SandboxStore.problem()` blocks obvious dead ends
  (no layout, no player parts, goal part missing, cheese without a mouse).
* **Solve it to publish** → mode `verify`: the author plays the level exactly as players will. On a solve,
  **Publish** → `POST /level` with the author's placements as the reference solution. The server validates,
  replays it (must reach the goal) and replays an EMPTY solution (must NOT reach it: "the level solves
  itself"). Returns an 8-character code.
* **Link**: `https://<server>/l/CODE` → 302 `/play/?level=CODE`; the browser build reads `?level=` at start
  (`App._open_link_level`) and opens it. In the app: Sandbox → Play a code (accepts the link too).
* **Shared levels** (mode `shared`): play, see the author's part count after solving, **Remix** = editable
  copy in My levels. Tries apply to the campaign and the Daily only.
* **Test**: `tools/ci_daily.sh` runs two installs with separate data dirs: A builds campaign level 1's
  layout through the editor, sets up, solves, publishes; B opens the code, solves it, remixes it.

## Map screen (2026-11-02)

`scripts/ui/world_select.gd` (scene name unchanged). Blueprint sheet; levels are gears on a marble-run track
(Curve2D through the nodes, sine-snaking, a gap and a riveted name plate per world). The track is BUILT
(brass rails, wooden sleepers) up to the current level and dashed blueprint beyond. A marble perches on the
current gear; `App.map_last_node` remembers where it was, so after a solve it rolls along the rails to the
next gear while the rail is laid. Animated decor per world (pendulum, meshing gears, Newton's cradle,
pulley with counterweight). Music: `music_map.ogg` (Lyria, soothing, seed 411), also on the Sandbox screens.

## World 4 "Rigging" and the level-design harness (2026-11-02)

`game/tests/design_levels.gd` (not exported) takes a JSON list of candidate levels, checks each does NOT
solve with nothing placed, then brute-forces placements of one part over a region (ropes are auto-aimed with
`Rope.best_rot`, exactly like the editor; `rope_cell` mode also places a pulley). A placement is "robust" when
>= 3 of its 4 neighbouring cells also solve; reference solutions are only taken from robust hits, so a level
does not depend on pixel-perfect placement. Results append to `<designs>.out` one JSON line per design.
Levels 31-40: 31/32 rope pendulum (mirrored), 33 place the pulley AND the rope, 34/35 candle pops the balloon
that holds the cheese over a basket, 36/37 same onto a mouse, 38/39 ball hits a switch, motor winches a
bucket, tethered balloon rises into a candle (pop goal), 40 pulley + rope with a spring distractor.

## Ropes and pulleys (M6 rework, 2026-11-02)

Requested by Bassel: clearer, more realistic, visible snap points, auto-snap.
* **Snap points** = `anchors` in `game/parts/<id>.json` (local px): bucket handle top `(0,-116)`, plank ends
  and middle `(±108,0),(0,0)`, balloon knot `(0,49)`, centre of ball / cheese / mouse / cat / pulley.
  Parts without anchors cannot be tied.
* **Placement** is still `(cell, rot)`: end A = nearest snap point within 2 cells of the cell; end B = a
  pulley inside the aim cone (±17°, min 30 px) if any, else the first snap point along the facing, up to
  `max_length_cells` (30). Length = the distance between the two points at build time (**taut**).
  Shared code: `rope.gd` static `snap_a / scan_b / resolve / best_rot`.
* **Physics**: `RopeLine` keeps a snap-point offset per chain node; it measures and pulls at the snap points
  (`apply_impulse` at the offset, spin included in the stretch rate), so a bucket swings from its handle and
  a plank tied by one end hangs and turns.
* **Editor**: while a rope is dragged every snap point shows as a ring; the end magnets to the nearest snap
  point within 3 cells, the rope auto-aims (nearest pulley first) and a live preview shows the rope it will
  make (green) or a red "nothing in reach". A selected rope also shows the rings.
* **Drawing**: brass clips at snap points; on a pulley the rope meets the wheel at the tangent points and the
  pulley draws the arc over the top.
* **Levels changed**: buckets' ropes moved up to the handle (tests); "Wrecking ball" 7/25 re-laid out with a
  search (target ball on the left end of a ledge at 25,36; pulley 22,16 in the middle of a 12-cell robust
  region); `t_rope_plank_hangs` now ties the plank by its end. 11 rope levels got new hashes; all others
  unchanged.

## Runs: failure, tries, RUN (M6)

* A run that stalls or times out ends by itself: fail sound, sad face, "The goal wasn't reached", tries left,
  and a circular-arrow **Try again** (rewinds). No STOP needed.
* **Tries** (`scripts/core/tries.gd`): a failed run costs one; solving is free. `TRIES_LIMIT` (3) per
  `TRIES_WINDOW_HOURS` (6), the window starting at the first failure; all refill when it ends. Rules come from
  the server (`GET /config`, Cloud Run env), cached; project settings are the offline fallback. Hearts and a
  countdown in the top bar; out of tries → RUN shows when new tries come (building is still allowed).
* The button is **RUN** / **STOP** with drawn icons; it breathes once a part is placed.
* Basket: woven wicker with a dark inside (drawn behind parts), rim, ribbon; a bobbing bullseye marks it as the
  goal, a green check with sparkles when the goal is met (latched for the run).
* Balloon pop: "POP!" star, rubber shreds and a falling knot (0.8 s) instead of vanishing.

## Look, sound and part cards (M6)

**Look.** Flat fills + thick ink outlines (brief) with three depth cues from `scripts/parts/art.gd`: a drop
shadow cast down-right in *world* space (it does not turn with the part), a top-left highlight, a darker
lower edge. Stage = blueprint-ruled sheet (minor line per tile, major every 4) in a wooden frame on a
pegboard wall; menus use `WorkshopBg` (pegboard). Animations live in each part's `_process` and only
advance a visual phase + redraw; they never touch bodies, so `levels/hashes.txt` is unchanged.

**Sound.** `App.audio` (`scripts/core/audio.gd`): buses Music and SFX, volumes = Settings sliders.
The buses are declared in `game/default_bus_layout.tres` and must stay there: the web build plays sounds
as Web Audio samples through a bus graph built at boot, and buses added at run time are never connected to
the output (this made the browser build completely silent until 2026-11-02). `tools/web_audio_check.js`
(CI, android job) fails unless real signal reaches the speakers in headless Chromium. On iPhone the page
sets `navigator.audioSession.type = "playback"` (export head include) so the silent switch does not mute it.
Music crossfades between `menu` (menus), `build` (editing) and `run` (machine running).
`SoundWatcher` (`scripts/ui/sound_watcher.gd`) reads the running simulation after each physics tick and
plays effects for state changes (popped, lit, caught_count, spring launches, switch pressed, cat awake,
mouse caught, cheese eaten), impacts (velocity jump > 260 px/s in one tick, volume by strength, pitch by
part, rate-limited) and a creak while a pulley line moves; fan / motor loops while any is on.
Test `sound:` in run_tests: same hash with and without the watcher.

| Asset | Source | Prompt (abridged) |
|---|---|---|
| music_menu.ogg | Lyria lyria-002 (Vertex), seed 101 | calm cozy inventor's workshop, music box + celesta, clockwork ticks, 84 BPM |
| music_build.ogg | Lyria, seed 202 | focused, pizzicato + marimba, light tick-tock, 96 BPM, unobtrusive |
| music_run.ogg | Lyria, seed 303 | upbeat Rube Goldberg in motion, xylophone runs, ratchet percussion, 116 BPM |
| 20 effects | ElevenLabs Sound Effects v2 (flow "Tinker game SFX") | one prompt each, e.g. "cartoon metal spring boing", "ball dropping into a wicker basket" |

Music loops: Lyria's 32.8 s clip minus its 0.8 s fade-out, last 3 s equal-power crossfaded into the head
(seamless), loudness-normalised to -20 LUFS, Vorbis q3. Effects: leading silence trimmed, capped length,
fade-out, mono, per-type loudness. Replacing a sound = drop a same-named .ogg in `game/assets/audio`.

**Part cards.** `PartInfoCard` (`scripts/ui/part_info.gd`) opens from the "i" on a tray part or by tapping a
fixed part. It shows the part JSON's `name`, `description` and `interacts_with`, and runs the part's demo
scene (`levels/demos/<id>.json`, copied from a CI-verified test scene by `levels/demos/make_demos.py`)
in a SubViewport with its own physics world, restarting every `demo_seconds`. The demo camera widens
smoothly to everything that moves. `--shot-cards=dir` renders all cards (`docs/screenshots/m6_info_cards.png`).

**Feedback.** Vibration (`App.audio.buzz`) on pick 10 ms, place 18 ms, rotate 6 ms, solve 60 ms; Settings
toggle. Confetti (`CPUParticles2D`, HUD layer) on solve.

**Tutorial.** `scripts/ui/tutorial.gd`, campaign level 1 only, while `settings.tutorial_done` is false:
bubble inside the tray (never over the board) + bouncing arrow (first tray part, then PLAY); reads the
level screen only; finishes on the first solve or Skip; Settings → "Show tutorial again".

## Backend (M4)

See `server/README.md` (endpoints, configuration table, deploy, curation). Key decisions:
- **Server replay is the proof.** `/score` spawns the same Godot build headless (`verify.gd`) on the
  submitted integers; an entry exists only if that replay reaches the goal. Parts are counted by the
  server. Time is the client's clock (from first touch, persisted per day) — it can be lied about, but
  only as a tie-breaker after parts; rate limits and one submission per device per day bound abuse.
- **Daily generation is offline and deterministic**: nightly scheduler job generates the coming week;
  nothing is generated in a request. Curation = inspect `/admin/queue`, swap with `PUT /admin/daily/{date}`.
- **Named Firestore database** `tinker`, so a shared GCP project's `(default)` DB is never touched.
- **Push via FCM topic** `tinker-daily`: one send reaches everyone; tokens kept on device docs for later
  targeted messages. Idempotent per day so scheduler retries never double-notify.
- **Client config is in Settings** (server URL, name, reminder), persisted in `user://settings.json`;
  the initial server URL comes from the project setting `tinker/server_url`.
