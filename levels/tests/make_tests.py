#!/usr/bin/env python3
"""Generates levels/tests/*.json — one level per interaction in the parts table (docs/DESIGN.md).

Every level has no tray: all parts are fixed, the reference solution is empty, and the
determinism harness (game/tests/run_tests.gd) replays it 100 times and checks the goal.
Coordinates are integer cells (24 px). Stage is 45 x 60 cells, y grows downward.
Part indices in goals refer to the order of the `fixed` list (0-based).

Run:  python3 levels/tests/make_tests.py   then   godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd
"""
import json
import os

OUT = os.path.dirname(os.path.abspath(__file__))
levels = []


def P(part, x, y, rot=0, **state):
    d = {"part": part, "x": x, "y": y, "rot": rot}
    if state:
        d["state"] = state
    return d


def level(id, title, fixed, goal, expect="goal", note=""):
    levels.append({
        "id": id, "title": title, "hint": note, "test": True,
        "goal": goal, "fixed": fixed, "tray": [], "slots": 0,
        "reference_solution": [], "expect": expect,
    })


def floor(x0, y, n):
    """n planks laid end to end (10 cells each) with top surface at y - 0.5 cells."""
    return [P("plank", x0 + 5 + 10 * i, y) for i in range(n)]


# ---------------------------------------------------------------- fan
level("t_fan_ball", "Fan pushes ball (weakly)",
      floor(4, 40, 3) + [P("ball", 14, 38), P("fan", 6, 37, 0)],
      {"type": "displaced", "index": 3, "min_dx": 120}, note="fan -> ball")
level("t_fan_balloon", "Fan drifts balloon",
      [P("balloon", 10, 30), P("fan", 4, 28, 0)],
      {"type": "displaced", "index": 0, "min_dx": 300}, note="fan -> balloon")
level("t_fan_mouse", "Fan pushes mouse",
      floor(4, 40, 3) + [P("mouse", 14, 38), P("fan", 6, 37, 0)],
      {"type": "displaced", "index": 3, "min_dx": 120}, note="fan -> mouse (idle, no cheese)")
level("t_fan_paddle", "Fan turns a see-saw",
      [P("motor", 22, 30, 0, on=False), P("plank", 22, 30, 0), P("fan", 26, 24, 6)],
      {"type": "rotated", "index": 1, "min_abs_rad": 0.5}, note="fan -> plank on pivot")

# ---------------------------------------------------------------- conveyor
level("t_conveyor_ball", "Conveyor carries ball into basket",
      [P("conveyor", 14, 30, 0), P("ball", 10, 27), P("basket", 28, 36)],
      {"type": "basket", "count": 1}, note="conveyor -> ball")
level("t_conveyor_bucket", "Conveyor carries bucket",
      [P("conveyor", 14, 30, 0), P("bucket", 10, 27)],
      {"type": "displaced", "index": 1, "min_dx": 150}, note="conveyor -> bucket")
level("t_conveyor_mouse", "Conveyor carries idle mouse",
      [P("conveyor", 14, 30, 0), P("mouse", 10, 28)],
      {"type": "displaced", "index": 1, "min_dx": 150}, note="conveyor -> mouse")
level("t_conveyor_cat", "Conveyor carries sleeping cat",
      [P("conveyor", 14, 30, 0), P("cat", 10, 28)],
      {"type": "displaced", "index": 1, "min_dx": 150}, note="conveyor -> cat")

# ---------------------------------------------------------------- spring
level("t_spring_ball", "Spring launches ball",
      [P("spring", 20, 40, 0), P("ball", 20, 28)],
      {"type": "displaced", "index": 1, "min_dy": -300}, note="spring -> ball")
level("t_spring_mouse", "Spring launches mouse",
      [P("spring", 20, 40, 0), P("mouse", 20, 30)],
      {"type": "displaced", "index": 1, "min_dy": -200}, note="spring -> mouse")
level("t_spring_bucket", "Spring launches bucket",
      [P("spring", 20, 40, 0), P("bucket", 20, 28)],
      {"type": "displaced", "index": 1, "min_dy": -120}, note="spring -> bucket")

# ---------------------------------------------------------------- motor
level("t_motor_paddle", "Motor spins a paddle that hits the ball",
      floor(14, 40, 2) + [P("motor", 20, 34, 0), P("plank", 20, 34, 6), P("ball", 24, 38)],
      {"type": "displaced", "index": 4, "min_dx": 80}, note="motor -> plank (paddle) -> ball")
level("t_motor_winch", "Motor on pulley winches a bucket up",
      [P("pulley", 20, 10), P("motor", 20, 10, 0), P("bucket", 20, 22), P("rope", 20, 22, 18)],
      {"type": "displaced", "index": 2, "min_dy": -100}, note="motor -> pulley (winch) -> rope -> bucket")
level("t_motor_conveyor_off", "Motor off keeps conveyor still",
      [P("conveyor", 14, 30, 0), P("motor", 14, 30, 0, on=False), P("ball", 14, 28), P("basket", 28, 36)],
      {"type": "basket", "count": 1}, expect="stalled", note="motor (off) -> conveyor")

# ---------------------------------------------------------------- switch
level("t_switch_ball_motor_conveyor", "Ball on switch starts the conveyor",
      [P("conveyor", 14, 30, 0), P("motor", 14, 30, 0, on=False), P("ball", 14, 28), P("basket", 28, 36),
       P("switch", 8, 44, 0), P("ball", 8, 36)],
      {"type": "basket", "count": 1}, note="ball -> switch -> motor -> conveyor -> ball -> basket")
level("t_switch_mouse_fan", "Mouse trips switch, fan turns off",
      floor(4, 40, 3) + [P("mouse", 8, 38), P("switch", 16, 39, 0), P("cheese", 28, 38), P("fan", 20, 20, 0)],
      {"type": "state", "index": 6, "key": "on", "value": False}, note="mouse -> switch -> fan")
level("t_switch_cat_motor", "Cat chasing mouse trips switch, motor turns off",
      floor(4, 40, 3) + [P("cat", 8, 38), P("switch", 16, 39, 0), P("mouse", 24, 38), P("motor", 20, 20, 0)],
      {"type": "state", "index": 6, "key": "on", "value": False}, note="cat -> switch -> motor")
level("t_switch_bucket_conveyor", "Bucket lands on switch, conveyor turns off",
      [P("switch", 16, 40, 0), P("bucket", 16, 30), P("conveyor", 30, 40, 0)],
      {"type": "state", "index": 2, "key": "on", "value": False}, note="bucket -> switch -> conveyor")
level("t_switch_balloon_fan", "Balloon rises into an upside-down switch",
      [P("switch", 16, 10, 12), P("balloon", 16, 30), P("fan", 30, 30, 0)],
      {"type": "state", "index": 2, "key": "on", "value": False}, note="balloon -> switch -> fan")

# ---------------------------------------------------------------- rope / pulley / bucket
level("t_rope_pulley_buckets", "Ball into bucket lifts the other bucket",
      [P("pulley", 20, 8), P("bucket", 20, 20), P("bucket", 26, 18),
       P("rope", 20, 20, 18), P("rope", 26, 18, 16), P("ball", 20, 12)],
      {"type": "displaced", "index": 2, "min_dy": -100}, note="ball -> bucket -> rope -> pulley -> bucket")
level("t_rope_plank_hangs", "Plank hangs from a rope and drops until taut",
      [P("pulley", 20, 8), P("plank", 20, 16), P("rope", 20, 16, 18)],
      {"type": "displaced", "index": 1, "min_dy": 60}, note="rope -> plank, pulley as anchor")
level("t_rope_balloon_cheese", "Balloon lifts cheese on a rope",
      [P("balloon", 20, 30), P("cheese", 20, 42), P("rope", 20, 42, 18)],
      {"type": "displaced", "index": 1, "min_dy": -100}, note="balloon -> rope -> cheese")
level("t_pulley_plank_bucket", "Ball into bucket raises a hanging plank",
      [P("pulley", 20, 8), P("plank", 28, 16), P("bucket", 20, 20),
       P("rope", 28, 16, 15), P("rope", 20, 20, 18), P("ball", 20, 12)],
      {"type": "displaced", "index": 1, "min_dy": -60}, note="pulley -> plank")

# ---------------------------------------------------------------- balloon / candle
level("t_balloon_candle_pop", "Balloon rises into a flame and pops",
      [P("candle", 16, 12, 12), P("balloon", 16, 30)],
      {"type": "state", "index": 1, "key": "popped", "value": True}, note="candle -> balloon")
level("t_candle_lights_candle", "Lit candle lights its neighbour",
      [P("candle", 16, 30), P("candle", 17, 30, 0, lit=False)],
      {"type": "candle"}, note="candle -> candle")
level("t_candle_scares_cat", "Awake cat flees a candle",
      floor(4, 40, 3) + [P("cat", 14, 38, 0, awake=True), P("candle", 10, 38)],
      {"type": "displaced", "index": 3, "min_dx": 150}, note="candle -> cat")

# ---------------------------------------------------------------- actors / basket
level("t_mouse_cheese", "Mouse runs to the cheese",
      floor(4, 40, 3) + [P("mouse", 8, 38), P("cheese", 28, 38)],
      {"type": "cheese"}, note="mouse -> cheese")
level("t_cat_catches_mouse", "Cat catches the mouse",
      floor(4, 40, 3) + [P("mouse", 18, 38), P("cat", 8, 38), P("cheese", 32, 38), P("plank", 34, 35, 6)],
      {"type": "state", "index": 3, "key": "caught", "value": True}, note="cat -> mouse")
level("t_basket_mouse", "Mouse falls into a basket on the way to the cheese",
      floor(4, 36, 1) + [P("mouse", 6, 34), P("basket", 18, 46), P("cheese", 30, 36)],
      {"type": "basket", "count": 1}, note="basket <- mouse")
level("t_basket_cheese", "Cheese drops into the basket",
      [P("cheese", 20, 20), P("basket", 20, 36)],
      {"type": "basket", "count": 1}, note="basket <- cheese")
level("t_bucket_ball_switch", "Ball lands in a bucket that sits on a switch",
      [P("switch", 16, 40, 0), P("bucket", 16, 34), P("ball", 16, 20), P("fan", 30, 40, 0)],
      {"type": "state", "index": 3, "key": "on", "value": False}, note="ball -> bucket -> switch -> fan")

# ---------------------------------------------------------------- regressions (PR #1 review)
level("t_reg_plank_not_caught", "A plank poking into the basket does not count",
      [P("basket", 20, 36), P("plank", 20, 34, 6)],
      {"type": "basket", "count": 1}, expect="stalled", note="basket must ignore planks")
level("t_reg_switch_before_conveyor", "Switch created before the motor-powered conveyor still targets the motor",
      [P("switch", 8, 44, 0), P("ball", 8, 36), P("conveyor", 14, 30, 0), P("motor", 14, 30, 0, on=False), P("ball", 14, 28), P("basket", 28, 36)],
      {"type": "basket", "count": 1}, note="switch -> motor regardless of creation order")

for l in levels:
    with open(os.path.join(OUT, l["id"] + ".json"), "w") as f:
        json.dump(l, f, indent=2)
        f.write("\n")
print(f"{len(levels)} test levels written to {OUT}")
