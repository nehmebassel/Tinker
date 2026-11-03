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

let server, base, appInst;
const verified = [];
const fakePlay = async (pkg, product, token) => {
  verified.push([pkg, product, token]);
  if (token === "bad-token-123") return { ok: false, error: "purchase not completed" };
  return { ok: true, orderId: "GPA." + token, test: false, consume: async () => { consumed.push(token); } };
};
const consumed = [];
const sentPush = [];
const earlyEvents = [];
const fakeFcm = {
  async subscribe() { return { ok: true }; },
  async unsubscribe() { return { ok: true }; },
  async sendTopic() { return { ok: true, id: "x" }; },
  async sendEach(msgs) {
    sentPush.push(...msgs);
    // A fast phone: reports "received" before sendEach returns (the record must already exist).
    for (const m of msgs) if (!m.token.endsWith("dead")) earlyEvents.push(await fetch(base + "/push/event", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ rcpt: m.data.rcpt, event: "received" }) }).then((r) => r.json()));
    return msgs.map((m) => (m.token.endsWith("dead") ? { ok: false, error: "messaging/registration-token-not-registered" } : { ok: true }));
  },
};
const stripeCalls = [];
const fakeFetch = async (url, opts) => { stripeCalls.push([url, String(opts.body)]); return { ok: true, json: async () => ({ url: "https://checkout.stripe.test/s1" }) }; };

before(async () => {
  for (const c of ["settings", "wallets", "ledger", "referrals", "progress", "scores", "devices", "daily", "activity", "campaigns", "push_rcpt"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  appInst = createApp({ playVerify: fakePlay, fetchFn: fakeFetch, fcm: fakeFcm });
  server = appInst.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  server.close();
  // Leave no economy overrides behind: later suites (ci_daily's staging server) expect the defaults.
  for (const c of ["settings"]) { const s = await db.collection(c).get(); await Promise.all(s.docs.map((d) => d.ref.delete())); }
});

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
  const changed = await j("POST", "/wallet/spend", { device_id: A, item: "hint", expected_cost: 999 });
  assert.equal(changed.status, 409, "a price the player did not see is not charged");
  assert.equal(changed.body.cost, 30);
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

test("referral: a Daily first solve pays the inviter once (then campaign solves don't)", async () => {
  const D = "eco-device-dddd";
  const code = (await j("POST", "/wallet", { device_id: A })).body.wallet.ref_code;
  const before = (await j("POST", "/wallet", { device_id: A })).body.wallet.coins;
  assert.equal((await j("POST", "/referral/claim", { device_id: D, code })).status, 200);
  const r = await appInst.locals.earnDaily(D, todayUtc());
  assert.ok(r.coins_added > 0);
  assert.equal((await appInst.locals.earnDaily(D, todayUtc())).coins_added, 0, "Daily reward is once per date");
  await j("POST", "/wallet/earn", { device_id: D, reason: "campaign", level: 1 });
  await j("POST", "/wallet/earn", { device_id: D, reason: "campaign", level: 2 });
  const after = (await j("POST", "/wallet", { device_id: A })).body.wallet.coins;
  assert.equal(after - before, 100, "inviter paid exactly once");
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
  assert.ok(consumed.includes("tok-abcdef-1"), "consumed only after the credit");
  assert.ok(!consumed.includes("bad-token-123"), "a failed purchase is not consumed");
  assert.equal((await j("POST", "/purchase/apple", { device_id: B })).status, 501);
  // Switched off after the purchase sheet opened: the paid Play purchase is still fulfilled.
  const cfgX = (await j("GET", "/admin/economy", null, ADMIN)).body.config;
  cfgX.products = cfgX.products.map((x) => (x.id === "coins_1200" ? { ...x, active: false } : x));
  await j("PUT", "/admin/economy", { config: cfgX }, ADMIN);
  const late = await j("POST", "/purchase/google", { device_id: B, product: "coins_1200", token: "tok-late-0001" });
  assert.equal(late.status, 200, "inactive product still fulfilled for a paid purchase");
  cfgX.products = cfgX.products.map((x) => (x.id === "coins_1200" ? { ...x, active: true } : x));
  await j("PUT", "/admin/economy", { config: cfgX }, ADMIN);
  // A one-time product paid twice through a real store is fulfilled again (flagged), never lost.
  assert.equal((await j("POST", "/purchase/google", { device_id: B, product: "starter_pack", token: "tok-once-0001" })).status, 200);
  assert.equal((await j("POST", "/purchase/google", { device_id: B, product: "starter_pack", token: "tok-once-0002" })).status, 200);
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
  assert.ok(Math.abs(l.body.totals.real - (0.99 + 4.99 + 2.99 * 2)) < 1e-9, "verified Google Play purchases are real revenue (" + l.body.totals.real + ")");
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
  const ev = { type: "checkout.session.completed", livemode: false, data: { object: { id: "cs_1", payment_status: "paid", amount_total: 99, metadata: { device_id: A, product: "coins_200", coins: "200", no_ads_days: "0", once: "0" } } } };
  assert.ok(stripeCalls.at(-1)[1].includes("metadata%5Bcoins%5D=200"), "checkout carries the entitlement snapshot");
  const raw = JSON.stringify(ev);
  const t = Math.floor(Date.now() / 1000);
  const sig = createHmac("sha256", "whsec_test").update(`${t}.${raw}`).digest("hex");
  const bad = await fetch(base + "/stripe/webhook", { method: "POST", headers: { "content-type": "application/json", "stripe-signature": `t=${t},v1=00` }, body: raw });
  assert.equal(bad.status, 400);
  // The product is switched off after checkout started: the paid session must still be fulfilled.
  const cfg2 = (await j("GET", "/admin/economy", null, ADMIN)).body.config;
  cfg2.products = cfg2.products.map((x) => (x.id === "coins_200" ? { ...x, active: false } : x));
  await j("PUT", "/admin/economy", { config: cfg2 }, ADMIN);
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
  assert.equal(earlyEvents[0].counted, true, "receipt reported before sendEach returned is counted");
  assert.equal((await j("POST", "/push/event", { rcpt: msgA.data.rcpt, event: "received" })).body.counted, false, "counted once");
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

test("privacy policy page uses the publisher set in the console", async () => {
  const cfg = (await j("GET", "/admin/economy", null, ADMIN)).body.config;
  cfg.legal.contact_email = "privacy@example.test";
  await j("PUT", "/admin/economy", { config: cfg }, ADMIN);
  const r = await fetch(base + "/privacy");
  assert.equal(r.status, 200);
  const html = await r.text();
  assert.ok(html.includes("mailto:privacy@example.test"));
  assert.ok(html.includes("OTONOMY"));
  assert.equal(html.includes("{{"), false);
});

test("delete my data: removes the device's records, keeps money lines anonymised", async () => {
  const D = "eco-device-dddd";
  await j("POST", "/presence", { device_id: D, name: "Dee", platform: "android" });
  await j("POST", "/wallet", { device_id: D });
  await j("POST", "/progress", { device_id: D, solved: 2, parts: 3 });
  await j("POST", "/purchase/google", { device_id: D, product: "coins_200", token: "tok-del-00001" });
  const r = await j("POST", "/me/delete", { device_id: D });
  assert.equal(r.status, 200);
  assert.ok(r.body.deleted >= 4);
  assert.equal((await db.collection("wallets").doc(D).get()).exists, false);
  assert.equal((await db.collection("devices").doc(D).get()).exists, false);
  assert.equal((await db.collection("progress").doc(D).get()).exists, false);
  assert.equal((await db.collection("ledger").where("device_id", "==", D).get()).size, 0);
  assert.ok(r.body.anonymised >= 1, "purchase kept for accounting, anonymised");
});
