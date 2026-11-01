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

# ================================================================ World 2 — fewer slots
level(11, "Pick one", "Three parts in the tray, one slot. Choose well.",
      [P("plank", 6, 14, 1), P("ball", 6, 12), P("basket", 30, 50)],
      [("plank", 1), ("fan", 1), ("spring", 1)], [S("plank", 18, 36, 3)], slots=1, teaches="slots < tray")

level(12, "Two of three", "Two slots. The ball must travel a long way right.",
      [P("ball", 8, 10), P("plank", 8, 30, 1), P("basket", 32, 46)],
      [("conveyor", 1), ("fan", 1), ("plank", 1)], [S("conveyor", 19, 32, 0)], slots=2, teaches="choose movers")

level(13, "Headwind", "The fan blows the mouse back. Switch it off on the way.",
      floor(0, 40, 4) + [P("mouse", 2, 38), P("fan", 29, 34, 12), P("cheese", 33, 38)],
      [("switch", 1), ("plank", 1), ("bucket", 1)], [S("switch", 8, 39, 0)], slots=1,
      goal={"type": "cheese"}, teaches="switch off")

level(14, "Bridge", "The mouse can't jump. Close the gap.",
      [P("plank", 5, 40), P("plank", 25, 40), P("mouse", 3, 38), P("cheese", 28, 38)],
      [("plank", 1), ("conveyor", 1), ("spring", 1)], [S("plank", 15, 40, 0)], slots=1,
      goal={"type": "cheese"}, teaches="bridging for actors")

level(15, "Two for one", "Both balls into the basket. One part.",
      [P("ball", 5, 12), P("ball", 5, 30), P("basket", 24, 50)],
      [("plank", 2)], [S("plank", 8, 32, 2)], slots=1, goal={"type": "basket", "count": 2}, teaches="one part, two jobs")

level(16, "Seesaw", "A plank on a motor that is off is just a seesaw. Drop something on the other end.",
      [P("motor", 20, 36, 0, on=False), P("plank", 20, 36, 0), P("cheese", 16, 34), P("plank", 11, 37), P("basket", 30, 36)],
      [("ball", 1), ("plank", 1)], [S("ball", 22, 10, 0)], slots=1, goal={"type": "caught", "index": 2}, teaches="see-saw launch")

level(17, "Guard cat", "The cat sleeps by the cheese. Scare it off before the mouse arrives.",
      [P("plank", 5, 44), P("plank", 12, 44), P("plank", 17, 46), P("basket", 27, 46), P("cheese", 27, 44),
       P("mouse", 3, 42), P("cat", 12, 42)],
      [("candle", 1), ("fan", 1), ("switch", 1)], [S("candle", 12, 38, 0)], slots=1,
      goal={"type": "cheese"}, teaches="actors + slots")

level(18, "Pop and drop", "The cheese hangs from a balloon stuck under the ceiling. Pop it.",
      [P("plank", 10, 12), P("balloon", 10, 30), P("cheese", 10, 42), P("rope", 10, 42, 18), P("basket", 10, 50)],
      [("candle", 1), ("fan", 1)], [S("candle", 10, 20, 12)], slots=1, goal={"type": "basket", "count": 1},
      teaches="rope goes slack")

level(19, "Chain reaction", "Ball A must start the motor before ball B reaches the paddle.",
      [P("plank", 6, 30, 1), P("ball", 6, 28), P("motor", 15, 36, 0, on=False), P("plank", 15, 36, 6),
       P("ball", 3, 8), P("basket", 28, 50)],
      [("switch", 1), ("plank", 1)], [S("switch", 3, 26, 0)], slots=2, teaches="sequences with slots")

level(20, "Dinner", "The belt pushes the mouse back. Stop it, then let the mouse walk.",
      [P("plank", 5, 40), P("mouse", 2, 38), P("conveyor", 16, 40, 12), P("motor", 16, 40, 0),
       P("plank", 27, 40), P("cheese", 30, 38), P("plank", 30, 14, 1), P("ball", 28, 12)],
      [("switch", 1), ("plank", 1), ("fan", 1)], [S("switch", 31, 39, 0)], slots=2,
      goal={"type": "cheese"}, teaches="world 2 finale")

# ================================================================ World 3 — combinations
level(21, "Double ramp", "Two balls, one basket, two slots.",
      [P("ball", 4, 12), P("ball", 41, 18), P("basket", 22, 52)],
      [("plank", 2), ("fan", 1)], [S("plank", 6, 32, 3), S("plank", 38, 36, 22)], slots=2,
      goal={"type": "basket", "count": 2}, teaches="two chains")

level(22, "Belt and braces", "The belt is off. Ball B can switch it on.",
      [P("conveyor", 14, 30, 0), P("motor", 14, 30, 0, on=False), P("ball", 10, 28), P("basket", 30, 44),
       P("plank", 36, 14, 23), P("ball", 38, 12)],
      [("switch", 1), ("plank", 1), ("fan", 1)], [S("switch", 22, 24, 0)], slots=1, teaches="switch via a second ball")

level(23, "Catapult", "Feed the mouse. The seesaw can throw.",
      [P("motor", 20, 36, 0, on=False), P("plank", 20, 36, 0), P("cheese", 16, 34), P("plank", 11, 37),
       P("plank", 31, 22), P("plank", 39, 22), P("mouse", 35, 20), P("plank", 43, 19, 6), P("plank", 26, 19, 6)],
      [("ball", 1), ("fan", 1)], [S("ball", 22, 2, 0)], slots=1, goal={"type": "cheese"}, teaches="see-saw + actor")

level(24, "High switch", "The switch has to be up where only the ball can reach it.",
      floor(0, 44, 4) + [P("mouse", 2, 42), P("fan", 29, 38, 12), P("cheese", 33, 42), P("plank", 14, 24), P("ball", 14, 8)],
      [("switch", 1), ("plank", 1)], [S("switch", 14, 23, 0)], slots=1, goal={"type": "cheese"}, teaches="switch placement")

level(25, "Wrecking ball II", "Same trick, one slot, three parts.",
      [P("plank", 9, 32, 1), P("ball", 12, 30), P("pulley", 20, 20), P("plank", 25, 32), P("ball", 24, 30), P("basket", 33, 47)],
      [("rope", 1), ("plank", 1), ("spring", 1)], [S("rope", 12, 30, 21)], slots=1, teaches="rope with distractors")

level(26, "Conveyor escape", "The belt drags the mouse toward the cat. Stop it in time.",
      [P("conveyor", 14, 40, 12), P("motor", 14, 40, 0), P("mouse", 12, 38), P("cat", 4, 38), P("plank", 4, 40),
       P("plank", 25, 40), P("cheese", 29, 38), P("plank", 30, 14, 1), P("ball", 28, 12)],
      [("switch", 1), ("plank", 1), ("candle", 1)], [S("switch", 30, 38, 0)], slots=1,
      goal={"type": "cheese"}, teaches="timing")

level(27, "Pop the right one", "Two balloons. Only one carries the cheese.",
      [P("plank", 10, 12), P("plank", 22, 12), P("balloon", 10, 30), P("cheese", 10, 42), P("rope", 10, 42, 18),
       P("balloon", 22, 30), P("ball", 22, 42), P("rope", 22, 42, 18), P("basket", 10, 50)],
      [("candle", 1), ("fan", 1)], [S("candle", 10, 20, 12)], slots=1, goal={"type": "basket", "count": 1},
      teaches="read the setup")

level(28, "Spring board", "The cheese is up there. Mice can't climb, but they can be launched.",
      floor(0, 44, 3) + [P("plank", 4, 30), P("mouse", 2, 28), P("plank", 24, 34), P("cheese", 27, 32), P("plank", 29, 31, 6)],
      [("spring", 1), ("plank", 1), ("fan", 1)], [S("spring", 14, 37, 2)], slots=1, goal={"type": "cheese"},
      teaches="spring + actor")

level(29, "Ceiling switch", "Only something that floats can reach that switch.",
      floor(0, 40, 4) + [P("mouse", 2, 38), P("fan", 29, 34, 12), P("cheese", 33, 38), P("switch", 4, 10, 12)],
      [("balloon", 1), ("plank", 1), ("candle", 1)], [S("balloon", 4, 34, 0)], slots=1, goal={"type": "cheese"},
      teaches="balloon + switch")

level(30, "Grand finale", "Everything you know. Two slots.",
      [P("ball", 3, 8), P("plank", 6, 30, 1), P("ball", 6, 28), P("motor", 15, 36, 0, on=False), P("plank", 15, 36, 6),
       P("basket", 28, 50)],
      [("switch", 1), ("plank", 1), ("fan", 1), ("spring", 1), ("rope", 1)], [S("switch", 3, 26, 0)], slots=2,
      teaches="world 3 finale")

for l in levels:
    with open(os.path.join(OUT, "%03d.json" % l["number"]), "w") as f:
        json.dump(l, f, indent=2)
        f.write("\n")
print(f"{len(levels)} campaign levels written")
