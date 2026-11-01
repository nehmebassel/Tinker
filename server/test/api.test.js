// End-to-end API tests against the Firestore emulator and the REAL Godot verifier.
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 GOOGLE_CLOUD_PROJECT=tinker-test ADMIN_TOKEN=t npm test
// A fake generator is injected (real generation takes up to minutes); the replay is real.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createApp, db, publicId } from "../src/app.js";
import { todayUtc } from "../src/config.js";

// SAFETY: these tests delete whole collections. They must never touch a real Firestore. Refuse to run
// unless the emulator is configured, before the app (and its Firestore client) is even used.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set. These tests wipe collections and must only run against the Firestore emulator.");
}
process.env.ADMIN_TOKEN = process.env.ADMIN_TOKEN || "test-admin";
const ADMIN = process.env.ADMIN_TOKEN;
const campaign = new URL("../../levels/campaign/001.json", import.meta.url).pathname;

let server, base, level1;
const fcmCalls = [];
const fakeFcm = {
  async subscribe(token, topic) { fcmCalls.push(["sub", token, topic]); return { ok: true }; },
  async unsubscribe(token, topic) { fcmCalls.push(["unsub", token, topic]); return { ok: true }; },
  async sendTopic(topic, msg, dry) { fcmCalls.push(["send", topic, msg, dry]); return { ok: true, id: "projects/x/messages/1" }; },
};
const fakeGenerate = async (date) => ({ ok: true, level: { ...level1, id: "d-" + date, title: "Daily " + date }, info: { template: "fake" } });

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "emulator required");
  level1 = JSON.parse(await readFile(campaign, "utf8"));
  // Wipe emulator state for the collections we touch.
  for (const c of ["daily", "scores", "levels", "devices", "push"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  const app = createApp({ generateFn: fakeGenerate, fcm: fakeFcm });
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const j = async (method, path, body, headers = {}) => {
  const r = await fetch(base + path, { method, headers: { "content-type": "application/json", ...headers }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => null) };
};
const today = todayUtc();
const DEV_A = "device-aaaa-0001", DEV_B = "device-bbbb-0002";

test("health", async () => {
  const r = await j("GET", "/health");
  assert.equal(r.status, 200);
  assert.equal(r.body.ok, true);
});

test("daily 404 before generation, admin needs token, generate fills the week", async () => {
  assert.equal((await j("GET", `/daily/${today}`)).status, 404);
  assert.equal((await j("POST", "/admin/generate?days=2")).status, 401);
  const g = await j("POST", "/admin/generate?days=2", null, { "x-admin-token": ADMIN });
  assert.equal(g.status, 200);
  assert.equal(g.body.made.length, 2);
  const again = await j("POST", "/admin/generate?days=2", null, { "x-admin-token": ADMIN });
  assert.equal(again.body.skipped.length, 2, "idempotent");
});

test("daily is served without the reference solution", async () => {
  const r = await j("GET", `/daily/${today}`);
  assert.equal(r.status, 200);
  assert.equal(r.body.level.id, "d-" + today);
  assert.equal(r.body.level.reference_solution, undefined);
  assert.equal(r.body.level.generator, undefined);
  assert.equal((await j("GET", "/daily/2099-01-01")).status, 404);
  assert.equal((await j("GET", "/daily/not-a-date")).status, 400);
});

test("score: rejects bad input before touching Godot", async () => {
  assert.equal((await j("POST", "/score", { device_id: "x", date: today, solution: [], elapsed_ms: 1 })).status, 400);
  assert.equal((await j("POST", "/score", { device_id: DEV_A, date: today, solution: [{ part: "plank", x: 1.5, y: 2, rot: 0 }], elapsed_ms: 1 })).status, 400);
  assert.equal((await j("POST", "/score", { device_id: DEV_A, date: today, solution: [{ part: "fan", x: 1, y: 2, rot: 0 }], elapsed_ms: 1 })).status, 400, "fan is not in level 1's tray");
  assert.equal((await j("POST", "/score", { device_id: DEV_A, date: "2000-01-01", solution: [], elapsed_ms: 1 })).status, 400, "date not open");
});

test("score: a wrong solution is replayed and refused (422)", async () => {
  const r = await j("POST", "/score", { device_id: DEV_A, date: today, solution: [{ part: "plank", x: 2, y: 2, rot: 0 }], elapsed_ms: 5000, country: "LB" });
  assert.equal(r.status, 422);
  assert.notEqual(r.body.result, "goal");
});

test("score: the real solution is accepted once per device per day, then boards rank it", async () => {
  const sol = level1.reference_solution;
  const a = await j("POST", "/score", { device_id: DEV_A, date: today, solution: sol, elapsed_ms: 12000, country: "LB", name: "Bassel" });
  assert.equal(a.status, 201, JSON.stringify(a.body));
  assert.equal(a.body.parts, 1);
  assert.equal(a.body.rank, 1);
  const dup = await j("POST", "/score", { device_id: DEV_A, date: today, solution: sol, elapsed_ms: 1000, country: "LB" });
  assert.equal(dup.status, 409);
  const b = await j("POST", "/score", { device_id: DEV_B, date: today, solution: sol, elapsed_ms: 8000, country: "FR" });
  assert.equal(b.status, 201);
  assert.equal(b.body.rank, 1, "same parts, faster => rank 1");
  const board = await j("GET", `/board/${today}?device_id=${DEV_A}`);
  assert.equal(board.status, 200);
  assert.deepEqual(board.body.rows.map((r) => r.is_me), [false, true]);
  assert.ok(!JSON.stringify(board.body).includes(DEV_A) && !JSON.stringify(board.body).includes(DEV_B), "device ids (credentials) never appear on a board");
  assert.notEqual(board.body.rows[0].player, board.body.rows[1].player);
  assert.equal(board.body.me.rank, 2);
  const country = await j("GET", `/board/${today}?scope=country&device_id=${DEV_A}`);
  assert.equal(country.body.country, "LB");
  assert.equal(country.body.rows.length, 1);
  assert.equal(country.body.me.rank, 1);
});

test("shared levels: author solution must replay; fetch strips it", async () => {
  const bad = await j("POST", "/level", { device_id: DEV_A, level: { ...level1, reference_solution: [{ part: "plank", x: 2, y: 2, rot: 0 }] } });
  assert.equal(bad.status, 422);
  const good = await j("POST", "/level", { device_id: DEV_A, level: level1 });
  assert.equal(good.status, 201, JSON.stringify(good.body));
  assert.match(good.body.id, /^[a-z0-9]{8}$/);
  const got = await j("GET", `/level/${good.body.id}`);
  assert.equal(got.status, 200);
  assert.equal(got.body.level.reference_solution, undefined);
  assert.equal(got.body.author_parts, 1);
  assert.equal((await j("GET", "/level/nope")).status, 400);
  assert.equal((await j("GET", "/level/zzzzzzzz")).status, 404);
});

test("admin: queue lists upcoming days; curated swap replaces a day", async () => {
  const q = await j("GET", "/admin/queue", null, { "x-admin-token": ADMIN });
  assert.equal(q.status, 200);
  assert.ok(q.body.days.length >= 2);
  const swap = await j("PUT", `/admin/daily/${today}`, { level: { ...level1, title: "Curated one" } }, { "x-admin-token": ADMIN });
  assert.equal(swap.status, 200, JSON.stringify(swap.body));
  const r = await j("GET", `/daily/${today}`);
  assert.equal(r.body.level.title, "Curated one");
  const badSwap = await j("PUT", `/admin/daily/${today}`, { level: { ...level1, reference_solution: [{ part: "plank", x: 2, y: 2, rot: 0 }] } }, { "x-admin-token": ADMIN });
  assert.equal(badSwap.status, 422);
});

test("push: register subscribes to the topic, a new token replaces the old, disable unsubscribes", async () => {
  const T1 = "tok1:" + "a".repeat(40), T2 = "tok2:" + "b".repeat(40);
  assert.equal((await j("POST", "/push/register", { device_id: DEV_A, token: "short" })).status, 400);
  const r1 = await j("POST", "/push/register", { device_id: DEV_A, token: T1 });
  assert.equal(r1.status, 200);
  assert.equal(r1.body.topic, "tinker-daily");
  const r2 = await j("POST", "/push/register", { device_id: DEV_A, token: T2 });
  assert.equal(r2.status, 200);
  assert.deepEqual(fcmCalls.filter((c) => c[0] !== "send").slice(-3).map((c) => c.slice(0, 2)), [["sub", T1], ["unsub", T1], ["sub", T2]]);
  const off = await j("POST", "/push/register", { device_id: DEV_A, token: T2, enabled: false });
  assert.equal(off.body.enabled, false);
  assert.deepEqual(fcmCalls.at(-1).slice(0, 2), ["unsub", T2]);
  const dev = (await db.collection("devices").doc(DEV_A).get()).data();
  assert.equal(dev.fcm_token, T2);
  assert.equal(dev.push_enabled, false);
});

test("push: daily notify needs a level, sends once per day, dry run does not record", async () => {
  assert.equal((await j("POST", "/admin/notify")).status, 401);
  assert.equal((await j("POST", "/admin/notify?date=2099-01-01", null, { "x-admin-token": ADMIN })).status, 409);
  const dry = await j("POST", "/admin/notify?dry_run=1", null, { "x-admin-token": ADMIN });
  assert.equal(dry.status, 200);
  assert.equal(dry.body.dry_run, true);
  assert.equal(fcmCalls.at(-1)[3], true);
  const sent = await j("POST", "/admin/notify", null, { "x-admin-token": ADMIN });
  assert.equal(sent.status, 200);
  assert.equal(sent.body.id, "projects/x/messages/1");
  const msg = fcmCalls.at(-1)[2];
  assert.match(msg.body, /^Day \d+:/);
  assert.equal(msg.data.date, today);
  const again = await j("POST", "/admin/notify", null, { "x-admin-token": ADMIN });
  assert.equal(again.body.skipped, "already sent");
  assert.equal(fcmCalls.filter((c) => c[0] === "send" && c[3] === false).length, 1, "exactly one real send");
});

test("daily carries the day number", async () => {
  const r = await j("GET", `/daily/${today}`);
  assert.ok(Number.isInteger(r.body.day) && r.body.day >= 1);
});

test("score: two concurrent submissions for one device and day -> exactly one 201, one 409", async () => {
  const DEV_C = "device-cccc-0003";
  const sol = level1.reference_solution;
  const body = { device_id: DEV_C, date: today, solution: sol, elapsed_ms: 9000, country: "LB" };
  const [r1, r2] = await Promise.all([j("POST", "/score", body), j("POST", "/score", { ...body, elapsed_ms: 1 })]);
  assert.deepEqual([r1.status, r2.status].sort(), [201, 409]);
  const stored = (await db.collection("scores").doc(`${today}_${DEV_C}`).get()).data();
  const winner = r1.status === 201 ? 9000 : 1;
  assert.equal(stored.ms, winner, "the first accepted entry is not overwritten");
});

test("errors in async handlers return JSON 500 and the server keeps serving", async () => {
  const boom = createApp({ replayFn: async () => { throw new Error("replay exploded"); }, fcm: fakeFcm });
  const s2 = boom.listen(0);
  const b2 = `http://127.0.0.1:${s2.address().port}`;
  try {
    const r = await fetch(b2 + "/score", { method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ device_id: "device-dddd-0004", date: today, solution: level1.reference_solution, elapsed_ms: 1 }) });
    assert.equal(r.status, 500);
    assert.deepEqual(await r.json(), { error: "internal" });
    assert.equal((await fetch(b2 + "/health")).status, 200, "still alive after the failure");
  } finally {
    s2.close();
  }
});

test("public player id is stable and does not reveal the device id", () => {
  assert.equal(publicId(DEV_A), publicId(DEV_A));
  assert.notEqual(publicId(DEV_A), publicId(DEV_B));
  assert.ok(!publicId(DEV_A).includes("aaaa"));
});

test("ties share a rank on the board and in the submission response (1, 1, 3)", async () => {
  const D = "2026-10-31"; // yesterday-style isolated date written directly, then read through the API
  const docs = [["tie-dev-0001", 1, 5000], ["tie-dev-0002", 1, 5000], ["tie-dev-0003", 2, 1000]];
  for (const [id, parts, ms] of docs) {
    await db.collection("scores").doc(`${D}_${id}`).set({ date: D, device_id: id, country: "LB", parts, ms, name: "" });
  }
  const b = await j("GET", `/board/${D}?device_id=tie-dev-0002`);
  assert.deepEqual(b.body.rows.map((r) => r.rank), [1, 1, 3]);
  assert.equal(b.body.me.rank, 1);
  assert.equal(b.body.rows.find((r) => r.is_me).rank, b.body.me.rank, "my row and me agree");
});

test("notify: two overlapping calls send exactly once", async () => {
  const D = "2026-12-01";
  await db.collection("daily").doc(D).set({ date: D, level: { ...level1, id: "d-" + D } });
  const before = fcmCalls.filter((c) => c[0] === "send" && c[3] === false).length;
  const [a, b] = await Promise.all([
    j("POST", `/admin/notify?date=${D}`, null, { "x-admin-token": ADMIN }),
    j("POST", `/admin/notify?date=${D}`, null, { "x-admin-token": ADMIN }),
  ]);
  assert.equal(a.status, 200); assert.equal(b.status, 200);
  assert.equal(fcmCalls.filter((c) => c[0] === "send" && c[3] === false).length - before, 1);
  assert.equal([a.body, b.body].filter((x) => x.skipped === "already sent").length, 1);
});

test("notify: a failed send releases the claim so a retry can send", async () => {
  const D = "2026-12-02";
  await db.collection("daily").doc(D).set({ date: D, level: { ...level1, id: "d-" + D } });
  let fail = true;
  const flaky = { ...fakeFcm, async sendTopic(...a) { if (fail) throw new Error("fcm down"); return fakeFcm.sendTopic(...a); } };
  const s3 = createApp({ fcm: flaky }).listen(0);
  const b3 = `http://127.0.0.1:${s3.address().port}`;
  try {
    const r1 = await fetch(`${b3}/admin/notify?date=${D}`, { method: "POST", headers: { "x-admin-token": ADMIN } });
    assert.equal(r1.status, 500);
    fail = false;
    const r2 = await fetch(`${b3}/admin/notify?date=${D}`, { method: "POST", headers: { "x-admin-token": ADMIN } });
    assert.equal((await r2.json()).dry_run, false, "retry actually sent");
  } finally { s3.close(); }
});

test("country board never mixes in my entry from another country", async () => {
  const D = "2026-10-30";
  await db.collection("scores").doc(`${D}_cc-dev-0001`).set({ date: D, device_id: "cc-dev-0001", country: "FR", parts: 1, ms: 100, name: "" });
  await db.collection("scores").doc(`${D}_cc-dev-0002`).set({ date: D, device_id: "cc-dev-0002", country: "LB", parts: 1, ms: 200, name: "" });
  const r = await j("GET", `/board/${D}?scope=country&country=LB&device_id=cc-dev-0001`);
  assert.equal(r.body.country, "LB");
  assert.equal(r.body.rows.length, 1);
  assert.equal(r.body.me, null, "my FR entry is not on the LB board");
});

test("generate never overwrites a level curated while it was generating", async () => {
  const D = (await import("../src/config.js")).todayUtc();
  await db.collection("daily").doc(D).delete();
  let release;
  const gate = new Promise((r) => (release = r));
  const slowGen = async (date) => { await gate; return { ok: true, level: { ...level1, id: "d-" + date, title: "Generated" }, info: { template: "slow" } }; };
  const s4 = createApp({ generateFn: slowGen, fcm: fakeFcm }).listen(0);
  const b4 = `http://127.0.0.1:${s4.address().port}`;
  try {
    const gen = fetch(`${b4}/admin/generate?days=1`, { method: "POST", headers: { "x-admin-token": ADMIN } });
    await new Promise((r) => setTimeout(r, 300));
    const cur = await j("PUT", `/admin/daily/${D}`, { level: { ...level1, title: "Curated wins" } }, { "x-admin-token": ADMIN });
    assert.equal(cur.status, 200);
    release();
    const g = await (await gen).json();
    assert.deepEqual(g.skipped, [D]);
    assert.equal((await j("GET", `/daily/${D}`)).body.level.title, "Curated wins");
  } finally { s4.close(); }
});

test("push config and the web push glue are served", async () => {
  const c = await j("GET", "/push/config");
  assert.equal(c.status, 200);
  assert.equal(c.body.topic, "tinker-daily");
  assert.ok("web" in c.body && "android" in c.body);
  const js = await fetch(base + "/play/push.js");
  assert.equal(js.status, 200);
  assert.match(js.headers.get("content-type"), /javascript/);
  assert.match(await js.text(), /window\.tinkerPush/);
  const sw = await fetch(base + "/play/fcm/sw.js");
  assert.equal(sw.status, 200);
  assert.equal(sw.headers.get("service-worker-allowed"), "/play/fcm/");
});

test("APK download is streamed chunked (Cloud Run rejects non-streamed responses over 32 MiB)", async () => {
  const { config } = await import("../src/config.js");
  const { mkdtemp, writeFile, rm } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = await mkdtemp(join(tmpdir(), "tinker-dl-"));
  const prev = config.downloadDir;
  const body = Buffer.alloc(3 * 1024 * 1024, 7);
  await writeFile(join(dir, "tinker.apk"), body);
  config.downloadDir = dir;
  const s5 = createApp({ fcm: fakeFcm }).listen(0);
  const b5 = `http://127.0.0.1:${s5.address().port}`;
  try {
    const r = await fetch(`${b5}/download/tinker.apk`);
    assert.equal(r.status, 200);
    assert.equal(r.headers.get("content-length"), null);
    assert.equal(r.headers.get("transfer-encoding"), "chunked");
    assert.match(r.headers.get("content-type"), /android\.package-archive/);
    assert.equal((await r.arrayBuffer()).byteLength, body.length);
    assert.equal((await fetch(`${b5}/download/..%2Fsecret.apk`)).status, 404);
    assert.equal((await fetch(`${b5}/download/missing.apk`)).status, 404);
  } finally { s5.close(); config.downloadDir = prev; await rm(dir, { recursive: true, force: true }); }
});

test("large web files are streamed chunked to clients that refuse gzip", async () => {
  const { config } = await import("../src/config.js");
  const { mkdtemp, writeFile, rm } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = await mkdtemp(join(tmpdir(), "tinker-web-"));
  const prev = config.webDir;
  const big = Buffer.alloc(31 * 1024 * 1024, 1);
  await writeFile(join(dir, "index.wasm"), big);
  await writeFile(join(dir, "index.html"), "<html>ok</html>");
  config.webDir = dir;
  const s6 = createApp({ fcm: fakeFcm }).listen(0);
  const b6 = `http://127.0.0.1:${s6.address().port}`;
  const http = await import("node:http");
  const raw = (path) => new Promise((ok, bad) => http.get(b6 + path, { headers: { "accept-encoding": "identity" } }, (r) => {
    let n = 0; r.on("data", (d) => (n += d.length)); r.on("end", () => ok({ status: r.statusCode, headers: r.headers, n }));
  }).on("error", bad));
  try {
    const w = await raw("/play/index.wasm");
    assert.equal(w.status, 200);
    assert.equal(w.headers["content-length"], undefined);
    assert.equal(w.headers["transfer-encoding"], "chunked");
    assert.match(w.headers["content-type"], /wasm/);
    assert.equal(w.n, big.length);
    const h = await raw("/play/index.html");  // small files still go through express.static
    assert.equal(h.status, 200);
    assert.equal(h.headers["content-length"], "15");
    assert.equal((await raw("/play/..%2F..%2Fetc%2Fpasswd")).status, 404);
  } finally { s6.close(); config.webDir = prev; await rm(dir, { recursive: true, force: true }); }
});
