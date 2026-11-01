// Runs the game's own headless scripts: verify.gd (replay a solution) and gen_daily.gd (make a level).
// The server never trusts a client's claim: a score exists only if THIS replay reached the goal.
import { spawn } from "node:child_process";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { config } from "./config.js";

// Godot needs a writable user data dir (user://). In a container the user's HOME may not be writable,
// and Godot crashes (SIGSEGV) when it cannot create user://logs — so point every XDG dir at tmp.
const GODOT_HOME = join(tmpdir(), "tinker-godot-home");
const godotEnv = {
  ...process.env,
  HOME: GODOT_HOME,
  XDG_DATA_HOME: join(GODOT_HOME, "data"),
  XDG_CONFIG_HOME: join(GODOT_HOME, "config"),
  XDG_CACHE_HOME: join(GODOT_HOME, "cache"),
};

function run(args, timeoutMs) {
  return new Promise((resolve) => {
    const p = spawn(config.godotBin, ["--headless", "--fixed-fps", "60", "--path", config.gameDir, ...args], {
      stdio: ["ignore", "pipe", "pipe"],
      env: godotEnv,
    });
    let out = "", err = "";
    const t = setTimeout(() => p.kill("SIGKILL"), timeoutMs);
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("close", (code) => {
      clearTimeout(t);
      resolve({ code, out, err });
    });
  });
}

// Godot prints a banner first; the script's answer is the last JSON line.
function lastJson(out) {
  const lines = out.trim().split("\n").reverse();
  for (const l of lines) {
    const s = l.trim();
    if (s.startsWith("{")) {
      try { return JSON.parse(s); } catch { /* keep looking */ }
    }
  }
  return null;
}

export async function replay(level, solution) {
  const dir = await mkdtemp(join(tmpdir(), "tinker-verify-"));
  try {
    const lp = join(dir, "level.json"), sp = join(dir, "solution.json");
    await writeFile(lp, JSON.stringify(level));
    await writeFile(sp, JSON.stringify(solution));
    const r = await run(["-s", "res://tests/verify.gd", "--", `--level-json=${lp}`, `--solution-json=${sp}`], config.replayTimeoutMs);
    const j = lastJson(r.out);
    if (!j) {
      console.error(`verify produced no result (exit ${r.code}): ${(r.err + "\n" + r.out).slice(-1500)}`);
      return { ok: false, error: "verifier produced no result", detail: (r.err || r.out).slice(-500) };
    }
    return j;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

export async function generateDaily(date, salt = 0) {
  const dir = await mkdtemp(join(tmpdir(), "tinker-gen-"));
  try {
    const out = join(dir, "daily.json");
    const r = await run(["-s", "res://tests/gen_daily.gd", "--", `--date=${date}`, `--out=${out}`, `--seed-salt=${salt}`], config.generateTimeoutMs);
    const j = lastJson(r.out);
    if (!j || !j.ok) return { ok: false, error: j?.error || `generator failed (exit ${r.code})`, detail: (r.err + "\n" + r.out).slice(-1500) };
    const level = JSON.parse(await readFile(out, "utf8"));
    return { ok: true, level, info: j };
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
