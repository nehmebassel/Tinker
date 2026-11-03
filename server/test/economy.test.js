// Economy + admin console against the Firestore emulator (no Godot needed except the Daily reward,
// which only checks that a verified score exists).
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 GOOGLE_CLOUD_PROJECT=tinker-test npm test
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { createApp, db } from "../src/app.js";
import { todayUtc } from "../src/config.js";

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set.");
process.env.ADMIN_TOKEN = process.env.ADMIN_TOKEN || "test-admin";
const ADMIN = { "x-admin-token": process.env.ADMIN_TOKEN };

let server, base;
const verified = [];
const fakePlay = async (pkg, product, token) => {
  verified.push([pkg, product, token]);
  if (token === "bad-token-123") return { ok: false, error: "purchase not completed" };
  return { ok: true, orderId: "GPA." + token, test: false };
};
const sentPush = [];
const fakeFcm = {
  async subscribe() { return { ok: true }; },
  async unsubscribe() { return { ok: true }; },
  async sendTopic() { return { ok: true, id: "x" }; },
  async sendEach(msgs) { sentPush.push(...msgs); return msgs.map((m) => (m.token.endsWith("dead") ? { ok: false, error: "messaging/registration-token-not-registered" } : { ok: true })); },
};
const stripeCalls = [];
const fakeFetch = async (url, opts) => { stripeCalls.push([url, String(opts.body)]); return { ok: true, json: async () => ({ url: "https://checkout.stripe.test/s1" }) }; };

before(async () => {
  for (const c of ["settings", "wallets", "ledger", "referrals", "progress", "scores", "devices", "daily", "activity", "campaigns", "push_rcpt"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  server = createApp({ playVerify: fakePlay, fetchFn: fakeFetch, fcm: fakeFcm }).listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const j = async (method, path, body, headers = {}) => {
  const r = await fetch(base + path, { method, headers: { "content-type": "application/json", ...headers }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => null) };
};
const A = "eco-device-aaaa", B = "eco-device-bbbb", C = "eco-device-cccc";

test("config carries the public economy, never secrets", async () => {
  const r = await j("GET", "/config");
  assert.equal(r.status, 200);
  assert.equal(r.body.economy.features.coins, true);
  assert.ok(r.body.economy.products.length >= 5);
  assert.equal(JSON.stringify(r.body).includes("stripe_secret"), false);
});

test("wallet: created with start coins and an invite code", async () => {
  const r = await j("POST", "/wallet", { device_id: A });
  assert.equal(r.status, 200);
  assert.equal(r.body.wallet.coins, 50);
  assert.match(r.body.wallet.ref_code, /^[A-Z0-9]{6}$/);
  assert.equal((await j("POST", "/wallet", { device_id: "x" })).status, 400);
});

test("daily bonus once per day", async () => {
  const r = await j("POST", "/wallet/bonus", { device_id: A });
  assert.equal(r.status, 200);
  assert.equal(r.body.coins_added, 10);
  assert.equal((await j("POST", "/wallet/bonus", { device_id: A })).status, 409);
});

test("earn: a campaign level pays once", async () => {
  const r = await j("POST", "/wallet/earn", { device_id: A, reason: "campaign", level: 1 });
  assert.equal(r.status, 200);
  assert.equal(r.body.wallet.coins, 70);
  assert.equal((await j("POST", "/wallet/earn", { device_id: A, reason: "campaign", level: 1 })).status, 409);
  assert.equal((await j("POST", "/wallet/earn", { device_id: A, reason: "daily", date: todayUtc() })).status, 403, "no verified score");
});

test("spend: prices from config, not enough coins is refused", async () => {
  const r = await j("POST", "/wallet/spend", { device_id: A, item: "hint", ref: "c5" });
  assert.equal(r.status, 200);
  assert.equal(r.body.wallet.coins, 40);
  assert.equal((await j("POST", "/wallet/spend", { device_id: A, item: "skip" })).status, 402);
  assert.equal((await j("POST", "/wallet/spend", { device_id: A, item: "nope" })).status, 400);
});

test("rewarded ads: reward + daily cap", async () => {
  const r = await j("POST", "/ads/reward", { device_id: B, reward: "try", provider: "house" });
  assert.equal(r.status, 200);
  assert.equal(r.body.tries_added, 1);
  for (let i = 0; i < 5; i++) assert.equal((await j("POST", "/ads/reward", { device_id: B, reward: "coins", provider: "house" })).status, 200);
  assert.equal((await j("POST", "/ads/reward", { device_id: B, reward: "coins" })).status, 429);
});

test("referral: invitee paid on claim, inviter on the friend's first solve", async () => {
  const code = (await j("POST", "/wallet", { device_id: A })).body.wallet.ref_code;
  const before = (await j("POST", "/wallet", { device_id: A })).body.wallet.coins;
  assert.equal((await j("POST", "/referral/claim", { device_id: A, code })).status, 400, "own code");
  const r = await j("POST", "/referral/claim", { device_id: C, code });
  assert.equal(r.status, 200);
  assert.equal(r.body.wallet.coins, 100);
  assert.equal((await j("POST", "/referral/claim", { device_id: C, code })).status, 409);
  await j("POST", "/wallet/earn", { device_id: C, reason: "campaign", level: 1 });
  const after = (await j("POST", "/wallet", { device_id: A })).body.wallet.coins;
  assert.equal(after - before, 100);
});

test("purchases: test mode grants and books as TEST; google play verified + idempotent", async () => {
  const t = await j("POST", "/purchase/test", { device_id: B, product: "noads_7d" });
  assert.equal(t.status, 200);
  assert.equal(t.body.wallet.no_ads, true);
  const g = await j("POST", "/purchase/google", { device_id: B, product: "coins_200", token: "tok-abcdef-1" });
  assert.equal(g.status, 200);
  const coins = g.body.wallet.coins;
  const again = await j("POST", "/purchase/google", { device_id: B, product: "coins_200", token: "tok-abcdef-1" });
  assert.equal(again.body.duplicate, true);
  assert.equal(again.body.wallet.coins, coins);
  assert.equal((await j("POST", "/purchase/google", { device_id: B, product: "coins_200", token: "bad-token-123" })).status, 402);
  assert.deepEqual(verified[0], ["my.otono.tinker", "coins_200", "tok-abcdef-1"]);
  assert.equal((await j("POST", "/purchase/apple", { device_id: B })).status, 501);
});

test("admin: token required, toggles change /config, ledger shows real vs test", async () => {
  assert.equal((await j("GET", "/admin/economy")).status, 401);
  const e = await j("GET", "/admin/economy", null, ADMIN);
  assert.equal(e.status, 200);
  const cfg = e.body.config;
  cfg.features.hints = false;
  cfg.economy.hint_cost = 45;
  assert.equal((await j("PUT", "/admin/economy", { config: cfg }, ADMIN)).status, 200);
  const pub = (await j("GET", "/config")).body.economy;
  assert.equal(pub.features.hints, false);
  assert.equal(pub.economy.hint_cost, 45);
  assert.equal((await j("POST", "/wallet/spend", { device_id: A, item: "hint" })).status, 403);
  const l = await j("GET", "/admin/ledger?days=7", null, ADMIN);
  assert.equal(l.status, 200);
  assert.ok(Math.abs(l.body.totals.real - 0.99) < 1e-9, "google play coins_200 is real revenue");
  assert.ok(l.body.totals.test >= 1.99, "test purchase booked as test");
  assert.equal((await j("PUT", "/admin/economy", { config: { ...cfg, payments: { ...cfg.payments, mode: "free" } } }, ADMIN)).status, 400);
});

test("stripe: checkout needs keys; webhook only with a valid signature", async () => {
  const cfg = (await j("GET", "/admin/economy", null, ADMIN)).body.config;
  cfg.payments.stripe = true;
  await j("PUT", "/admin/economy", { config: cfg }, ADMIN);
  assert.equal((await j("POST", "/purchase/stripe", { device_id: A, product: "coins_200" })).status, 503);
  await j("PUT", "/admin/secrets", { stripe_secret_key: "sk_test_x", stripe_webhook_secret: "whsec_test" }, ADMIN);
  const masked = (await j("GET", "/admin/economy", null, ADMIN)).body.secrets.stripe_secret_key;
  assert.equal(masked, "••••st_x");
  const s = await j("POST", "/purchase/stripe", { device_id: A, product: "coins_200" });
  assert.equal(s.status, 200);
  assert.equal(s.body.url, "https://checkout.stripe.test/s1");
  const ev = { type: "checkout.session.completed", livemode: false, data: { object: { id: "cs_1", payment_status: "paid", amount_total: 99, metadata: { device_id: A, product: "coins_200" } } } };
  const raw = JSON.stringify(ev);
  const t = Math.floor(Date.now() / 1000);
  const sig = createHmac("sha256", "whsec_test").update(`${t}.${raw}`).digest("hex");
  const bad = await fetch(base + "/stripe/webhook", { method: "POST", headers: { "content-type": "application/json", "stripe-signature": `t=${t},v1=00` }, body: raw });
  assert.equal(bad.status, 400);
  const coinsBefore = (await j("POST", "/wallet", { device_id: A })).body.wallet.coins;
  const ok = await fetch(base + "/stripe/webhook", { method: "POST", headers: { "content-type": "application/json", "stripe-signature": `t=${t},v1=${sig}` }, body: raw });
  assert.equal(ok.status, 200);
  assert.equal((await j("POST", "/wallet", { device_id: A })).body.wallet.coins - coinsBefore, 200);
});

test("campaign board + test users seed/remove", async () => {
  await j("POST", "/progress", { device_id: A, solved: 12, parts: 20, name: "Me", country: "LB" });
  const seed = await j("POST", "/admin/test-users", null, ADMIN);
  assert.equal(seed.body.made.length, 12);
  const b = await j("GET", "/board-campaign?device_id=" + A);
  assert.equal(b.status, 200);
  assert.ok(b.body.rows.length >= 13);
  assert.equal(b.body.me.solved, 12);
  assert.ok(b.body.rows.every((r, i) => i === 0 || r.rank >= b.body.rows[i - 1].rank));
  const st = await j("GET", "/admin/stats", null, ADMIN);
  assert.equal(st.body.test_users, 12);
  const rm = await j("DELETE", "/admin/test-users", null, ADMIN);
  assert.ok(rm.body.removed >= 24);
  assert.equal((await j("GET", "/board-campaign")).body.rows.length, 1);
});

test("admin ui page is served without the token and holds no secrets", async () => {
  const r = await fetch(base + "/admin/ui");
  assert.equal(r.status, 200);
  const html = await r.text();
  assert.ok(html.includes("Tinker admin"));
  assert.equal(/(sk_live|sk_test|whsec)_[A-Za-z0-9]{8,}/.test(html), false);
});

test("presence -> players list (online, today, OS) and activity", async () => {
  await j("POST", "/presence", { device_id: A, name: "Ann", country: "LB", platform: "web", os: "Web", browser: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)" });
  await j("POST", "/presence", { device_id: B, name: "Bob", country: "US", platform: "android", os: "Android 15", model: "Pixel 8" });
  const on = await j("GET", "/admin/players?filter=online", null, ADMIN);
  assert.equal(on.status, 200);
  assert.equal(on.body.online, 2);
  const ann = on.body.players.find((p) => p.name === "Ann");
  assert.equal(ann.os_family, "iOS (web)");
  assert.equal(on.body.by_os["Android"], 1);
  const today = await j("GET", "/admin/players?filter=today", null, ADMIN);
  assert.equal(today.body.count, 2);
  const act = await j("GET", "/admin/activity", null, ADMIN);
  assert.equal(act.body.days.at(-1).players, 2);
  assert.equal(act.body.online_now, 2);
});

test("grant coins to many players", async () => {
  const before = (await j("POST", "/wallet", { device_id: B })).body.wallet.coins;
  const r = await j("POST", "/admin/grant-many", { device_ids: [A, B], coins: 250, note: "launch gift" }, ADMIN);
  assert.equal(r.status, 200);
  assert.equal(r.body.granted, 2);
  assert.equal((await j("POST", "/wallet", { device_id: B })).body.wallet.coins - before, 250);
  assert.equal((await j("POST", "/admin/grant-many", { device_ids: [A], coins: 0 }, ADMIN)).status, 400);
});

test("push campaign to selected players: sent / received / opened tracked", async () => {
  await j("POST", "/push/register", { device_id: A, token: "tokA-xxxxxxxxxxxxxxxxxxxxxxxxx", enabled: true });
  await j("POST", "/push/register", { device_id: B, token: "tokB-xxxxxxxxxxxxxxxxxxxxxxxdead", enabled: true });
  const r = await j("POST", "/admin/push", { title: "New levels!", body: "World 4 is out", target: "selected", device_ids: [A, B, C] }, ADMIN);
  assert.equal(r.status, 200);
  assert.equal(r.body.targeted, 2, "C never opened the app: no device to target");
  assert.equal(r.body.reachable, 2);
  assert.equal(r.body.sent, 1);
  assert.equal(r.body.failed, 1);
  const msgA = sentPush.find((m) => m.token.startsWith("tokA"));
  assert.match(msgA.data.rcpt, /^[a-f0-9]{24}$/);
  assert.equal((await j("POST", "/push/event", { rcpt: msgA.data.rcpt, event: "received" })).body.counted, true);
  assert.equal((await j("POST", "/push/event", { rcpt: msgA.data.rcpt, event: "opened" })).body.counted, true);
  assert.equal((await j("POST", "/push/event", { rcpt: msgA.data.rcpt, event: "opened" })).body.counted, false, "counted once");
  const list = await j("GET", "/admin/campaigns", null, ADMIN);
  const c = list.body.campaigns.find((x) => x.id === r.body.id);
  assert.deepEqual([c.counts.sent, c.counts.failed, c.counts.received, c.counts.opened], [1, 1, 1, 1]);
  const det = await j("GET", "/admin/campaigns/" + r.body.id, null, ADMIN);
  assert.equal(det.body.recipients.length, 2);
  assert.ok(det.body.recipients.find((x) => x.name === "Ann").opened_at);
  const dead = await db.collection("devices").doc(B).get();
  assert.equal(dead.data().push_enabled, false, "dead token switched off");
  assert.equal((await j("POST", "/admin/push", { title: "", body: "x", target: "all" }, ADMIN)).status, 400);
});
