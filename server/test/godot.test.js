// The Godot wrapper must turn a spawn failure into a result, never an unhandled 'error' event.
import { test } from "node:test";
import assert from "node:assert/strict";

test("replay with a missing Godot binary returns a failure instead of crashing", async () => {
  process.env.GODOT_BIN = "/nonexistent/godot";
  const { replay } = await import("../src/godot.js?missing-bin");
  const r = await replay({ id: "x" }, []);
  assert.equal(r.ok, false);
});

test("the API tests refuse to run without the emulator", async () => {
  const { spawnSync } = await import("node:child_process");
  const env = { ...process.env };
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.NODE_TEST_CONTEXT;  // else the child reports into this runner and exits 0
  const r = spawnSync(process.execPath, [new URL("./api.test.js", import.meta.url).pathname], { env, encoding: "utf8" });
  assert.notEqual(r.status, 0);
  assert.match(r.stdout + r.stderr, /Refusing to run: FIRESTORE_EMULATOR_HOST is not set/);
});
