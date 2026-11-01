// Input validation. Mirrors the game's Placement.is_valid_dict / LevelData.validate rules so that
// obviously bad input is rejected before a Godot process is spawned.
import { DATE_RE } from "./config.js";

export const PARTS = new Set(["ball", "plank", "basket", "fan", "conveyor", "spring", "motor", "rope",
  "pulley", "switch", "balloon", "bucket", "candle", "cheese", "mouse", "cat"]);
const STAGE = { x: 45, y: 60 };
const ROT_STEPS = 24;
const DEVICE_RE = /^[A-Za-z0-9_-]{8,64}$/;
const COUNTRY_RE = /^[A-Z]{2}$/;
const SHORT_ID_RE = /^[a-z0-9]{6,12}$/;

export function isDate(s) {
  return typeof s === "string" && DATE_RE.test(s) && !Number.isNaN(Date.parse(s + "T00:00:00Z"));
}

export function isDeviceId(s) {
  return typeof s === "string" && DEVICE_RE.test(s);
}

export function isCountry(s) {
  return typeof s === "string" && COUNTRY_RE.test(s);
}

export function isShortId(s) {
  return typeof s === "string" && SHORT_ID_RE.test(s);
}

function isInt(v) {
  return typeof v === "number" && Number.isInteger(v);
}

export function validPlacement(p, allowState = false) {
  if (!p || typeof p !== "object") return "placement must be an object";
  if (!PARTS.has(p.part)) return `unknown part ${p.part}`;
  if (!isInt(p.x) || !isInt(p.y) || !isInt(p.rot)) return "x, y, rot must be integers";
  if (p.x < 0 || p.y < 0 || p.x > STAGE.x || p.y > STAGE.y) return "placement off stage";
  if (p.rot < 0 || p.rot >= ROT_STEPS) return "rot out of range";
  if ("state" in p) {
    if (!allowState) return "player placements cannot carry state";
    if (!p.state || typeof p.state !== "object" || Array.isArray(p.state)) return "state must be an object";
  }
  const extra = Object.keys(p).filter((k) => !["part", "x", "y", "rot", "state"].includes(k));
  if (extra.length) return `unexpected keys ${extra.join(",")}`;
  return "";
}

export function validSolution(sol, maxParts = 32) {
  if (!Array.isArray(sol)) return "solution must be an array";
  if (sol.length > maxParts) return "too many parts";
  for (const p of sol) {
    const e = validPlacement(p, false);
    if (e) return e;
  }
  return "";
}

const GOALS = new Set(["basket", "candle", "cheese", "pop", "state", "displaced", "rotated", "caught"]);

export function validLevel(l) {
  if (!l || typeof l !== "object") return "level must be an object";
  if (typeof l.title !== "string" || l.title.length > 60) return "title missing or too long";
  if (!l.goal || typeof l.goal !== "object" || !GOALS.has(l.goal.type)) return "bad goal";
  if (!Array.isArray(l.fixed) || l.fixed.length > 64) return "fixed must be an array (<= 64)";
  for (const p of l.fixed) {
    const e = validPlacement(p, true);
    if (e) return `fixed: ${e}`;
  }
  if (!Array.isArray(l.tray) || l.tray.length > 16) return "tray must be an array (<= 16)";
  let total = 0;
  for (const t of l.tray) {
    if (!t || !PARTS.has(t.part) || !isInt(t.count) || t.count < 1 || t.count > 10) return "bad tray entry";
    total += t.count;
  }
  if (!isInt(l.slots) || l.slots < 1 || l.slots > total) return "slots must be 1..sum(tray)";
  const e = validSolution(l.reference_solution, l.slots);
  if (e) return `reference_solution: ${e}`;
  if (l.reference_solution.length === 0) return "reference_solution required";
  return "";
}

// Does the solution use only tray parts within their counts and the slot limit?
export function solutionFits(level, sol) {
  if (sol.length > level.slots) return false;
  const used = {};
  for (const p of sol) used[p.part] = (used[p.part] || 0) + 1;
  const tray = {};
  for (const t of level.tray) tray[t.part] = (tray[t.part] || 0) + t.count;
  return Object.entries(used).every(([k, n]) => n <= (tray[k] || 0));
}

// What the client may see: never the reference solution or generator internals.
export function publicLevel(level) {
  const { reference_solution, generator, expect, ...rest } = level;
  return rest;
}
