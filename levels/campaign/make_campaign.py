#!/usr/bin/env python3
"""Generates levels/campaign/NNN.json — the hand-made campaign.

Coordinates are integer cells (24 px); stage 45 x 60; y grows downward. Keep fixed parts out of
the PLAY corner (x > 35 and y > 48). A floor plank is 10 cells wide, top surface at y - 0.5.
Reference solutions are found with game/tests/find_solution.gd and verified by run_tests.gd.

Run:  python3 levels/campaign/make_campaign.py
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


def S(part, x, y, rot=0):
    return {"part": part, "x": x, "y": y, "rot": rot}


def level(n, title, hint, fixed, tray, solution, goal=None, slots=None, teaches=""):
    world = (n - 1) // 10 + 1
    levels.append({
        "id": "c%03d" % n, "world": world, "number": n, "title": title, "hint": hint, "teaches": teaches,
        "goal": goal or {"type": "basket", "count": 1},
        "fixed": fixed,
        "tray": [{"part": p, "count": c} for p, c in tray],
        "slots": slots if slots is not None else sum(c for _, c in tray),
        "reference_solution": solution,
        "expect": "goal",
    })


def floor(x0, y, n):
    return [P("plank", x0 + 5 + 10 * i, y) for i in range(n)]


# ================================================================ World 1 — learn the parts
level(1, "First drop", "Drag the plank under the ball. Tap it to rotate.",
      [P("plank", 8, 14, 1), P("ball", 8, 12), P("basket", 27, 52)],
      [("plank", 1)], [S("plank", 18, 39, 4)], teaches="drag and rotate")

level(2, "Across the gap", "The ball needs a push. Fans blow things away from their face.",
      [P("plank", 6, 30), P("ball", 6, 28), P("basket", 30, 50)],
      [("plank", 1), ("fan", 1)], [S("fan", 1, 28, 0), S("plank", 16, 38, 2)], teaches="movers")

level(3, "Up and over", "A spring throws whatever lands on it. Angle it.",
      [P("ball", 10, 28), P("plank", 10, 44), P("plank", 26, 34), P("basket", 26, 30)],
      [("spring", 1)], [S("spring", 10, 41, 1)], teaches="vertical launch, angle")

level(4, "Wrong way", "Parts have a direction. Place yours pointing the right way.",
      [P("conveyor", 14, 22, 12), P("ball", 14, 20), P("basket", 24, 50)],
      [("conveyor", 1)], [S("conveyor", 8, 28, 0)], teaches="direction")

level(5, "Long way round", "Small errors compound. Chain the fans.",
      [P("plank", 5, 14), P("ball", 5, 12), P("plank", 18, 34), P("basket", 31, 50)],
      [("fan", 2), ("plank", 1)], [S("fan", 0, 12, 0), S("fan", 12, 32, 0), S("plank", 28, 42, 3)], teaches="chains")

level(6, "Pop goes the balloon", "Balloons float. Steer yours into the flame.",
      [P("candle", 30, 6, 12), P("plank", 22, 20, 0)],
      [("balloon", 1), ("fan", 2)], [S("balloon", 10, 50, 0), S("fan", 6, 44, 23)],
      goal={"type": "pop"}, teaches="floating bodies, second goal type")

level(7, "Wrecking ball", "A rope ties two things together. Hang the ball from a pulley and let it swing.",
      [P("plank", 9, 32, 1), P("ball", 12, 30), P("plank", 25, 32), P("ball", 24, 30), P("basket", 33, 47)],
      [("rope", 1), ("pulley", 1)],
      [S("pulley", 20, 20), S("rope", 12, 30, 21)],
      teaches="connectors")

level(8, "Switched off", "That fan is off. Something has to step on the switch.",
      [P("plank", 5, 30, 1), P("ball", 5, 28), P("fan", 10, 46, 0, on=False), P("ball", 15, 44), P("plank", 16, 46),
       P("basket", 30, 50)],
      [("switch", 1), ("plank", 1)], [S("switch", 12, 34, 0), S("plank", 16, 38, 2)], teaches="sequences")

level(9, "Paddle", "A plank on a motor spins. Use it to whack the ball across.",
      [P("plank", 6, 30, 1), P("ball", 6, 28), P("basket", 28, 50)],
      [("plank", 1), ("motor", 1), ("rope", 1)], [S("motor", 15, 36, 0), S("plank", 15, 36, 6)], teaches="combinatorial toolbox")

level(10, "Cat and mouse", "The mouse wants the cheese. The cat wants the mouse. Cats hate candles.",
      [P("plank", 5, 44), P("plank", 12, 44), P("plank", 17, 46), P("basket", 27, 46), P("cheese", 27, 44),
       P("mouse", 3, 42), P("cat", 10, 42)],
      [("plank", 1), ("fan", 1), ("candle", 1)], [S("candle", 10, 38, 0)],
      goal={"type": "cheese"}, teaches="actors")

for l in levels:
    with open(os.path.join(OUT, "%03d.json" % l["number"]), "w") as f:
        json.dump(l, f, indent=2)
        f.write("\n")
print(f"{len(levels)} campaign levels written")
