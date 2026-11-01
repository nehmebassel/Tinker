#!/usr/bin/env python3
"""Demo scenes for the part info cards (tap the "i" on a tray part, or tap a fixed part).

Each part gets the smallest verified scene that shows what it does, copied from levels/tests
(those scenes replay to their goal in CI, so a demo can never show a broken mechanism).
Run from the repo root:  python3 levels/demos/make_demos.py
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.join(HERE, "..", "tests")

# part -> (test scene, seconds before the demo restarts)
DEMOS = {
    "ball": ("t_conveyor_ball", 5),
    "plank": ("t_motor_paddle", 5),
    "basket": ("t_conveyor_ball", 5),
    "fan": ("t_fan_balloon", 5),
    "conveyor": ("t_conveyor_ball", 5),
    "spring": ("t_spring_ball", 4),
    "motor": ("t_motor_paddle", 5),
    "rope": ("t_rope_balloon_cheese", 5),
    "pulley": ("t_rope_pulley_buckets", 5),
    "switch": ("t_switch_ball_motor_conveyor", 6),
    "balloon": ("t_balloon_candle_pop", 5),
    "bucket": ("t_rope_pulley_buckets", 5),
    "candle": ("t_candle_lights_candle", 4),
    "cheese": ("t_mouse_cheese", 6),
    "mouse": ("t_mouse_cheese", 6),
    "cat": ("t_cat_catches_mouse", 7),
}

for part, (src, secs) in DEMOS.items():
    with open(os.path.join(TESTS, src + ".json")) as f:
        level = json.load(f)
    level["id"] = "demo-" + part
    level["demo_seconds"] = secs
    level["source"] = src
    with open(os.path.join(HERE, part + ".json"), "w") as f:
        json.dump(level, f, indent=2)
        f.write("\n")
print("wrote %d demos" % len(DEMOS))
