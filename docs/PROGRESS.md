# Tinker — progress

Source of truth for what is done. Tick at every commit. Requirements are headings; tasks are checkboxes.
Session log at the bottom tells the next agent exactly where things stand.

## Requirements (from the development instructions, 2026-11-01)

### R1 Determinism — same setup, same result, every device
- [x] Fixed 60 Hz physics step, jitter fix off, interpolation render-only (`game/project.godot`)
- [x] Integer-only placements: quarter-tile cells + 15° steps (`scripts/core/grid.gd`, `placement.gd`)
- [x] No randomness in simulation; parts created in a fixed order; run counted in ticks (`simulation.gd`)
- [x] Run ends on goal, 30 s, or 2 s of no motion
- [x] Determinism harness: 100 in-process replays identical (`tests/run_tests.gd`)
- [x] Hash identical across separate processes and across frame pacings (real time, 30 fps, 144 fps)
- [x] CI compares the hash against `levels/hashes.txt`
- [ ] Hash identical on two real phones (needs devices — see "Open for Bassel")
- [ ] Decide Godot physics vs Box2D extension after phone test (ARM/x86 float drift risk)

### R2 Nothing ships unless run end to end
- [x] Headless tests run locally and in CI
- [x] UI smoke test drives real touch events under Xvfb and screenshots every step
- [x] Debug APK exported and signed locally (`build/tinker-debug.apk`, 56 MB, arm64 + x86_64)
- [ ] APK installed and played on a real device or emulator (no device in this environment)

### R3 Process
- [x] `docs/PROGRESS.md` created first commit, ticked per commit
- [x] One PR per milestone (M0+M1 land together in the first PR)
- [x] Tooling installed and verified: Godot 4.5.1, export templates, Android SDK 35, Node 22, gcloud (no credentials yet)

### R4 Product rules
- [x] No gambling vocabulary anywhere in code or copy (grep'd)
- [ ] `ads_enabled` remote flag, default off (M6/M7)
- [ ] Single paid unlock, price in store consoles (M7)

## Milestones

### M0 Repo and tooling — DONE locally, PR pending repo creation
- [x] Working title: **Tinker** (store + trademark check done, see Decisions)
- [ ] GitHub repo `nehmebassel/tinker` created — BLOCKED: session credential cannot create repos; Bassel creates it, then `git push`
- [x] Godot project with fixed 60 Hz step and determinism test scene
- [x] CI workflow: headless tests, hash check, UI smoke, Android debug APK artifact (`.github/workflows/ci.yml`)
- [ ] Green workflow run (needs the repo)

### M1 Feel — code complete, awaiting phone review (kill gate)
- [x] Ball, plank, basket parts with JSON definitions (`game/parts/*.json`)
- [x] Tray with part previews and counts; collapses to a tab
- [x] Drag from tray: part floats above the finger, ghost at the snapped landing spot, red when invalid (overlap/off-stage)
- [x] Tap placed part → rotation ring; drag handle in 15° steps; double-tap ring = 90°; "Turn" and "90°" buttons do the same
- [x] Drag placed part to move; drag onto tray to remove
- [x] Pinch zoom, two-finger pan, double-tap empty = fit, "Fit" button
- [x] Play / Stop (instant rewind by rebuild), Undo / Redo always visible
- [x] Solved overlay with parts + time from first touch
- [x] Level 1 "First drop" with a solver-found reference solution (`tests/find_solution.gd`)
- [x] 100 replays identical; UI smoke test solves level 1 through synthetic touches
- [ ] Bassel places a plank on a phone and says it feels good → go / no-go

### M2 Parts (not started)
- [ ] Remaining 12 parts: fan, conveyor, spring, motor, rope, pulley, switch, balloon, bucket, candle, mouse, cat
- [ ] Plank see-saw mode (pin point)
- [ ] One test level per interaction in the parts table

### M3 Campaign (not started)
- [ ] Levels 2–30, world select, progress save
### M4 Daily (not started)
- [ ] Generator, `server/` Cloud Run (GET /daily, POST /score, GET /board), headless replay verifier
### M5 Sandbox · M6 Polish · M7 Store (not started)

## Decisions

- 2026-11-01 **Title = Tinker.** No live App Store / Play game named exactly "Tinker" (a "Tinker: Gear Puzzles" was removed from the US store). US marks: TINKER reg. 8033567 (Glocal Development — vehicle repair app, unrelated) and TINKER serial 99107334 (Thinking Machines Lab — AI software, class 9/41/42, published for opposition 2026-03). Class 9 "downloadable software" overlaps in words, not in goods; have a trademark lawyer glance at it before the store listing. "Rube" is taken (Rube Works — official Rube Goldberg game; Rube's Lab). "Gizmo" is taken (Gizmo: Make Gizmos, live).
- 2026-11-01 Godot **4.5.1-stable** (latest stable at time of setup).
- 2026-11-01 `levels/` lives at repo root (per spec) and is reachable in the Godot project through the symlink `game/levels -> ../levels`. Verified: the export packs the JSON through the symlink. Windows checkouts must enable `core.symlinks` or build via CI.
- 2026-11-01 Headless replays use `--fixed-fps 60`: each frame advances exactly one physics tick, so 100 replays of level 1 take ~1.4 s with the exact step size a phone uses. Verified the hash does not change with frame pacing.
- 2026-11-01 Stage is 45×60 cells (1080×1440 px). HUD: 160 px top bar, 320 px tray. The lower-right corner (cells x>35, y>48) is the PLAY button zone — **level design rule: keep it free of fixed parts**.
- 2026-11-01 Rewind = rebuild from integer data, never "restore state". Same code path as a replay, so no state can leak between runs.
- 2026-11-01 Node is 22 in this environment (spec says 20). Cloud Run supports both; backend will target Node 22 LTS unless Bassel objects.

## Open for Bassel

1. Create the private repo `nehmebassel/tinker` and grant this session access, then say "push".
2. Install `build/tinker-debug.apk` (from the CI artifact once the workflow runs, or ask me to send it) on your phone. Place a plank. Feel review → go / no-go for M2.
3. Confirm Node 22 for the backend.
4. gcloud has no credentials in this environment; needed from M4.

## Session log

- **2026-11-01 (session 1, autonomous)** Tooling installed; title checked; Godot project, 3 parts, simulation, determinism harness, M1 touch screen, UI smoke test, Android export, CI workflow, docs. Repo creation blocked on credentials. Everything committed locally on `main`.
