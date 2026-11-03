// Economy + monetization (2026-11-03): coins, tries, hints, skips, ads, no-ads passes, invites, store
// purchases, the earnings ledger and the admin console. Everything a business decision can change lives
// in Firestore settings/economy and is edited from /admin/ui. The DEFAULTS below are only what a fresh
// install starts with. Secrets (Stripe) live in settings/secrets and are never returned unmasked.
//
// Collections (named database "tinker"):
//   settings/economy   runtime config (features, prices, rewards, ads, products, payments)
//   settings/secrets   { stripe_secret_key, stripe_webhook_secret }
//   wallets/{device}   coins, no-ads expiry, invite code, streak, ad counters, rewarded levels
//   ledger/{id}        every money event (ads, purchases, refunds) and every coin movement
//   referrals/{code}   invite code -> device
//   progress/{device}  campaign progress for the campaign leaderboard
//
// Trust model: coins are server-side (a client can't mint them). Ad rewards are client-reported and
// capped per day; real ad revenue comes from the ad network's report, the ledger holds ESTIMATES
// (eCPM set in the console) and says so. Store purchases are verified with the store before credit.
import express from "express";
import { createHmac, timingSafeEqual, randomBytes } from "node:crypto";
import { db } from "./db.js";
import { config, todayUtc, addDays } from "./config.js";
import { isDeviceId, isCountry, isDate } from "./validate.js";

export const DEFAULTS = {
  features: {
    coins: true,                 // master switch for the economy
    daily_bonus: true,           // coins for opening the game each day (+ streak)
    refill_tries_on_new_level: true,
    extra_tries: true,           // spend coins on a try / a full refill
    hints: true,                 // spend coins: show where one part goes (campaign only)
    skip: true,                  // spend coins: mark a campaign level solved
    rewarded_ads: true,          // watch an ad -> a try or coins
    interstitial_ads: false,     // an ad between levels every N levels (off: they hurt retention early on)
    purchases: true,             // the shop (coin packs, no-ads passes)
    referrals: true,             // invite a friend -> both get coins
  },
  economy: {
    start_coins: 50,
    level_reward: 10,            // first solve of a campaign level
    daily_reward: 20,            // solving the Daily (server-verified score)
    daily_bonus: 10,             // opening the game, once per UTC day
    streak_step: 5,              // + per consecutive day, up to streak_max days
    streak_max: 7,
    extra_try_cost: 20,
    refill_cost: 50,
    hint_cost: 30,
    skip_cost: 100,
    ad_reward_coins: 15,
    ad_reward_tries: 1,
    ads_per_day_cap: 6,          // rewarded ads per device per UTC day
    referral_inviter: 100,       // paid when the invited friend solves their first level
    referral_invitee: 50,        // paid when the code is claimed
  },
  ads: {
    provider: "house",           // house (placeholder, works everywhere) | h5 (web: Google H5 Games Ads) | admob (Android)
    h5_client_id: "",            // ca-pub-... (AdSense, H5 Games Ads approved)
    h5_test_mode: true,
    admob_app_id: "",
    admob_rewarded_unit: "",
    admob_interstitial_unit: "",
    interstitial_every_levels: 4,
    est_ecpm_rewarded_usd: 8,    // estimate only, for the ledger; the ad network's report is the truth
    est_ecpm_interstitial_usd: 4,
  },
  payments: {
    mode: "test",                // test: purchases are granted free and marked TEST | live: real stores only
    google_play: true,
    stripe: false,               // web (PWA) checkout
    apple: false,                // App Store (needs the Apple account)
    stripe_publishable_key: "",
    currency: "USD",
  },
  legal: {
    company: "OTONOMY",          // shown on /privacy and in the store listing
    contact_email: "",           // privacy / support contact (required by Google Play); set in the console
    website: "https://otono.my",
    updated: "2026-11-03",
  },
  products: [
    { id: "coins_200", title: "Handful of coins", coins: 200, no_ads_days: 0, price_usd: 0.99, active: true },
    { id: "coins_1200", title: "Bag of coins", coins: 1200, no_ads_days: 0, price_usd: 4.99, active: true, badge: "Popular" },
    { id: "coins_2600", title: "Chest of coins", coins: 2600, no_ads_days: 0, price_usd: 9.99, active: true, badge: "Best value" },
    { id: "noads_7d", title: "No ads for 7 days", coins: 0, no_ads_days: 7, price_usd: 1.99, active: true },
    { id: "noads_30d", title: "No ads for 30 days", coins: 0, no_ads_days: 30, price_usd: 3.99, active: true },
    { id: "noads_forever", title: "No ads, forever", coins: 0, no_ads_days: 36500, price_usd: 7.99, active: true },
    { id: "starter_pack", title: "Starter pack: 500 coins + 7 days no ads", coins: 500, no_ads_days: 7, price_usd: 2.99, active: true, once: true },
  ],
};

const SPEND_ITEMS = { extra_try: "extra_try_cost", refill: "refill_cost", hint: "hint_cost", skip: "skip_cost" };
const SPEND_FEATURE = { extra_try: "extra_tries", refill: "extra_tries", hint: "hints", skip: "skip" };
const PRODUCT_ID_RE = /^[a-z0-9_.]{2,64}$/;
const CODE_RE = /^[A-Z0-9]{6,8}$/;
const TEST_PREFIX = "test-user-";

const S = () => db.collection("settings");
const W = () => db.collection("wallets");
const L = () => db.collection("ledger");
const R = () => db.collection("referrals");
const P = () => db.collection("progress");

function merge(def, over) {
  if (Array.isArray(def)) return Array.isArray(over) ? over : def;
  if (def && typeof def === "object") {
    const o = { ...def };
    for (const k of Object.keys(def)) if (over && over[k] !== undefined) o[k] = merge(def[k], over[k]);
    return o;
  }
  return over === undefined || over === null || typeof over !== typeof def ? def : over;
}

let cache = { at: 0, cfg: null };
export async function getEconomy(force = false) {
  if (!force && cache.cfg && Date.now() - cache.at < 15000) return cache.cfg;
  const snap = await S().doc("economy").get();
  const cfg = merge(DEFAULTS, snap.exists ? snap.data() : {});
  cache = { at: Date.now(), cfg };
  return cfg;
}

async function getSecrets() {
  const s = await S().doc("secrets").get();
  return s.exists ? s.data() : {};
}

function mask(v) {
  return v ? "••••" + String(v).slice(-4) : "";
}

// What a client may see: no secrets, nothing about the ledger.
export function publicEconomy(cfg) {
  return {
    features: cfg.features,
    economy: cfg.economy,
    ads: {
      provider: cfg.ads.provider, h5_client_id: cfg.ads.h5_client_id, h5_test_mode: cfg.ads.h5_test_mode,
      admob_app_id: cfg.ads.admob_app_id, admob_rewarded_unit: cfg.ads.admob_rewarded_unit,
      admob_interstitial_unit: cfg.ads.admob_interstitial_unit, interstitial_every_levels: cfg.ads.interstitial_every_levels,
    },
    payments: { mode: cfg.payments.mode, google_play: cfg.payments.google_play, stripe: cfg.payments.stripe, apple: cfg.payments.apple, currency: cfg.payments.currency },
    legal: { company: cfg.legal.company, contact_email: cfg.legal.contact_email, website: cfg.legal.website },
    products: cfg.products.filter((p) => p.active).map(({ id, title, coins, no_ads_days, price_usd, badge, once }) => ({ id, title, coins, no_ads_days, price_usd, badge: badge || "", once: Boolean(once) })),
  };
}

function newCode() {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (const b of randomBytes(6)) s += a[b % a.length];
  return s;
}

function walletView(w, cfg) {
  const now = new Date().toISOString();
  return {
    coins: w.coins || 0,
    no_ads: Boolean(w.no_ads_until && w.no_ads_until > now),
    no_ads_until: w.no_ads_until || "",
    ref_code: w.ref_code || "",
    referred_by: w.referred_by ? true : false,
    streak: w.streak || 0,
    bonus_today: w.last_bonus_date === todayUtc(),
    ads_left_today: Math.max(0, cfg.economy.ads_per_day_cap - (w.ads_date === todayUtc() ? w.ads_count || 0 : 0)),
    bought: w.bought || [],
  };
}

async function ensureWallet(deviceId, cfg) {
  const ref = W().doc(deviceId);
  const snap = await ref.get();
  if (snap.exists) return snap.data();
  // Reserve a unique invite code, then create the wallet (create() fails if a parallel call won).
  let code = newCode();
  for (let i = 0; i < 5; i++) {
    try { await R().doc(code).create({ device_id: deviceId, created_at: new Date().toISOString() }); break; } catch (e) {
      if (e?.code !== 6) throw e;
      code = newCode();
    }
  }
  const w = { device_id: deviceId, coins: cfg.features.coins ? cfg.economy.start_coins : 0, no_ads_until: "", ref_code: code,
    referred_by: "", streak: 0, last_bonus_date: "", ads_date: "", ads_count: 0, rewarded: [], bought: [],
    test: deviceId.startsWith(TEST_PREFIX), created_at: new Date().toISOString() };
  try {
    await ref.create(w);
    if (w.coins) await ledger({ kind: "coins", type: "start", device_id: deviceId, coins: w.coins });
    return w;
  } catch (e) {
    if (e?.code === 6) { await R().doc(code).delete().catch(() => {}); return (await ref.get()).data(); }
    throw e;
  }
}

export async function ledger(e, tx = null) {
  const doc = { ts: new Date().toISOString(), date: todayUtc(), amount_usd: 0, coins: 0, test: false, source: "", product: "", ref: "", ...e };
  const ref = e.id ? L().doc(e.id) : L().doc();
  delete doc.id;
  if (tx) tx.set(ref, doc); else await ref.set(doc);
}

// Coins in and out, atomically. fn(w) returns {coins, set, ledger[]} or throws {status, error}.
async function mutate(deviceId, cfg, fn) {
  await ensureWallet(deviceId, cfg);
  const ref = W().doc(deviceId);
  return db.runTransaction(async (tx) => {
    const w = (await tx.get(ref)).data();
    const r = await fn(w, tx);
    const coins = (w.coins || 0) + (r.coins || 0);
    if (coins < 0) throw { status: 402, error: "not enough coins" };
    tx.update(ref, { coins, ...(r.set || {}) });
    for (const e of r.ledger || []) await ledger({ device_id: deviceId, ...e }, tx);
    return { ...w, coins, ...(r.set || {}) };
  });
}

function grantFor(product) {
  return { coins: product.coins || 0, no_ads_days: product.no_ads_days || 0 };
}

function extendNoAds(current, days) {
  if (!days) return current || "";
  const base = current && current > new Date().toISOString() ? new Date(current) : new Date();
  base.setUTCDate(base.getUTCDate() + days);
  return base.toISOString();
}

// One purchase, once (keyed by the store's order id), credited atomically with its ledger line.
async function creditPurchase(deviceId, cfg, product, { source, orderId, amountUsd, test }) {
  const id = `buy_${source}_${String(orderId).replace(/[^\w.-]/g, "_").slice(0, 120)}`;
  if ((await L().doc(id).get()).exists) return { duplicate: true };
  const g = grantFor(product);
  const w = await mutate(deviceId, cfg, async (w, tx) => {
    if ((await tx.get(L().doc(id))).exists) throw { status: 409, error: "already credited" };
    if (product.once && (w.bought || []).includes(product.id)) throw { status: 409, error: "already bought" };
    return {
      coins: g.coins,
      set: { no_ads_until: extendNoAds(w.no_ads_until, g.no_ads_days), bought: [...new Set([...(w.bought || []), product.id])] },
      ledger: [{ id, kind: "money", type: "purchase", source, product: product.id, ref: String(orderId), amount_usd: amountUsd, coins: g.coins, test: Boolean(test) }],
    };
  });
  return { wallet: w };
}

// ------------------------------------------------------------------ store verification
// Google Play: purchases.products.get with the server's service account (granted in Play Console →
// Users and permissions). Injected in tests.
export async function verifyGooglePlay(packageName, productId, token) {
  const { GoogleAuth } = await import("google-auth-library");
  const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] });
  const client = await auth.getClient();
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`;
  let r;
  try { r = await client.request({ url: base }); } catch (e) { return { ok: false, error: "google: " + (e?.response?.data?.error?.message || e.message) }; }
  const d = r.data || {};
  if (d.purchaseState !== 0) return { ok: false, error: "purchase not completed (state " + d.purchaseState + ")" };
  // Consuming makes the product buyable again. It is done by the caller only AFTER the credit is stored
  // (Codex PR #9): consumed-but-not-credited would mean paid and nothing received. An unconsumed purchase
  // is re-sent by the app on its next start (queryPurchasesAsync), and the credit is idempotent per order.
  const consume = async () => {
    if (d.consumptionState === 0) await client.request({ url: base + ":consume", method: "POST" }).catch((e) => console.error("consume failed", e?.message));
  };
  return { ok: true, orderId: d.orderId || token.slice(-24), test: d.purchaseType === 0 /* license tester */, consume };
}

function stripeSigOk(raw, header, secret) {
  if (!raw || !header || !secret) return false;
  const parts = Object.fromEntries(String(header).split(",").map((kv) => kv.split("=")));
  if (!parts.t || !parts.v1) return false;
  if (Math.abs(Date.now() / 1000 - Number(parts.t)) > 600) return false;
  const want = createHmac("sha256", secret).update(`${parts.t}.${raw}`).digest("hex");
  const a = Buffer.from(want), b = Buffer.from(parts.v1);
  return a.length === b.length && timingSafeEqual(a, b);
}

// ------------------------------------------------------------------ test users (leaderboard demo data)
const TEST_NAMES = ["Gizmo Gwen", "Lever Leo", "Pulley Pia", "Cog Carl", "Sprocket Sam", "Ratchet Rae", "Widget Wes",
  "Bolt Bea", "Piston Pat", "Hinge Hana", "Axle Ari", "Spring Sol"];
const TEST_COUNTRIES = ["LB", "US", "GB", "FR", "DE", "CA", "AE", "JP", "BR", "IN", "AU", "ES"];

async function seedTestUsers(publicLevelFor) {
  const made = [];
  for (let i = 0; i < TEST_NAMES.length; i++) {
    const dev = `${TEST_PREFIX}${String(i + 1).padStart(4, "0")}`;
    const name = TEST_NAMES[i], country = TEST_COUNTRIES[i];
    await db.collection("devices").doc(dev).set({ name, country, test: true }, { merge: true });
    const solved = 3 + ((i * 7) % 34), parts = solved + (i % 5) * 2;
    await P().doc(dev).set({ device_id: dev, name, country, solved, parts, score: solved * 100000 - parts, test: true, updated_at: new Date().toISOString() });
    for (const date of [todayUtc(), addDays(todayUtc(), -1)]) {
      if (!(await publicLevelFor(date))) continue;
      await db.collection("scores").doc(`${date}_${dev}`).set({ date, device_id: dev, country, name, parts: 1 + (i % 3), ms: 9000 + i * 3700 + (date === todayUtc() ? 0 : 1500),
        hash: "test", ticks: 0, solution: [], test: true, created_at: new Date().toISOString() });
    }
    made.push(name);
  }
  return made;
}

async function removeTestUsers() {
  let n = 0;
  for (const c of ["scores", "progress", "devices", "wallets"]) {
    const snap = await db.collection(c).where("test", "==", true).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
    n += snap.size;
  }
  return n;
}

// ------------------------------------------------------------------ admin gate
// Every /admin/* call needs the admin token (Secret Manager tinker-admin-token). 10 wrong tokens from
// one address lock it out for 10 minutes.
const fails = new Map();
export function adminGate(req, res, next) {
  if (!config.adminToken) return res.status(404).end();
  const ip = req.ip || "?";
  const f = fails.get(ip) || { n: 0, t: Date.now() };
  if (Date.now() - f.t > 600000) { f.n = 0; f.t = Date.now(); }
  if (f.n >= 10) return res.status(429).json({ error: "too many attempts, wait 10 minutes" });
  const got = Buffer.from(String(req.get("x-admin-token") || "")), want = Buffer.from(config.adminToken);
  if (got.length !== want.length || !timingSafeEqual(got, want)) { f.n++; fails.set(ip, f); return res.status(401).json({ error: "unauthorized" }); }
  next();
}

// ------------------------------------------------------------------ routes
export function mountEconomy(app, { rateLimited, playVerify = verifyGooglePlay, fetchFn = fetch, publicId } = {}) {
  const bad = (res, status, error) => res.status(status).json({ error });
  const guard = (req, res, key) => {
    const d = req.body?.device_id;
    if (!isDeviceId(d)) { bad(res, 400, "bad device_id"); return null; }
    if (rateLimited(key + ":" + d)) { bad(res, 429, "slow down"); return null; }
    return d;
  };
  const fail = (res, e) => (e && e.status ? bad(res, e.status, e.error) : (console.error(e), bad(res, 500, "internal")));

  app.post("/wallet", async (req, res) => {
    const d = guard(req, res, "wallet"); if (!d) return;
    try {
      const cfg = await getEconomy();
      res.json({ wallet: walletView(await ensureWallet(d, cfg), cfg) });
    } catch (e) { fail(res, e); }
  });

  // Daily bonus: once per UTC day; the streak grows on consecutive days.
  app.post("/wallet/bonus", async (req, res) => {
    const d = guard(req, res, "bonus"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.coins || !cfg.features.daily_bonus) return bad(res, 403, "daily bonus is off");
      const today = todayUtc();
      let got = 0;
      const w = await mutate(d, cfg, async (w) => {
        if (w.last_bonus_date === today) throw { status: 409, error: "already claimed today" };
        const streak = w.last_bonus_date === addDays(today, -1) ? Math.min((w.streak || 0) + 1, cfg.economy.streak_max) : 1;
        got = cfg.economy.daily_bonus + (streak - 1) * cfg.economy.streak_step;
        return { coins: got, set: { last_bonus_date: today, streak }, ledger: [{ kind: "coins", type: "daily_bonus", coins: got }] };
      });
      res.json({ coins_added: got, wallet: walletView(w, cfg) });
    } catch (e) { fail(res, e); }
  });

  // Rewards for solving: a campaign level once, the Daily once per date (only with a verified score).
  app.post("/wallet/earn", async (req, res) => {
    const d = guard(req, res, "earn"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.coins) return bad(res, 403, "coins are off");
      const { reason, level, date } = req.body;
      let key, amount;
      if (reason === "campaign" && Number.isInteger(level) && level >= 1 && level <= 1000) {
        key = "c" + level; amount = cfg.economy.level_reward;
      } else if (reason === "daily" && isDate(date)) {
        if (!(await db.collection("scores").doc(`${date}_${d}`).get()).exists) return bad(res, 403, "no verified score for that day");
        key = "d" + date; amount = cfg.economy.daily_reward;
      } else return bad(res, 400, "bad reason");
      let first = false;
      const w = await mutate(d, cfg, async (w) => {
        const done = w.rewarded || [];
        if (done.includes(key)) throw { status: 409, error: "already rewarded" };
        first = done.length === 0;
        return { coins: amount, set: { rewarded: [...done, key].slice(-2000) }, ledger: [{ kind: "coins", type: "earn_" + reason, ref: key, coins: amount }] };
      });
      // An invited friend's first solve pays the inviter.
      if (first && w.referred_by && cfg.features.referrals) {
        await mutate(w.referred_by, cfg, async () => ({ coins: cfg.economy.referral_inviter,
          ledger: [{ kind: "coins", type: "referral_inviter", ref: d.slice(0, 6), coins: cfg.economy.referral_inviter }] })).catch(() => {});
      }
      res.json({ coins_added: amount, wallet: walletView(w, cfg) });
    } catch (e) { fail(res, e); }
  });

  app.post("/wallet/spend", async (req, res) => {
    const d = guard(req, res, "spend"); if (!d) return;
    try {
      const cfg = await getEconomy();
      const item = req.body.item;
      if (!SPEND_ITEMS[item]) return bad(res, 400, "bad item");
      if (!cfg.features.coins || !cfg.features[SPEND_FEATURE[item]]) return bad(res, 403, item + " is off");
      const cost = cfg.economy[SPEND_ITEMS[item]];
      const ref = typeof req.body.ref === "string" ? req.body.ref.slice(0, 40) : "";
      const w = await mutate(d, cfg, async () => ({ coins: -cost, ledger: [{ kind: "coins", type: "spend_" + item, ref, coins: -cost }] }));
      res.json({ ok: true, item, cost, wallet: walletView(w, cfg) });
    } catch (e) { fail(res, e); }
  });

  // A rewarded ad finished on the device. Capped per day; revenue is an eCPM ESTIMATE.
  app.post("/ads/reward", async (req, res) => {
    const d = guard(req, res, "ad"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.rewarded_ads) return bad(res, 403, "rewarded ads are off");
      const reward = req.body.reward === "try" ? "try" : "coins";
      const provider = ["house", "h5", "admob"].includes(req.body.provider) ? req.body.provider : "house";
      const today = todayUtc();
      const coins = reward === "coins" && cfg.features.coins ? cfg.economy.ad_reward_coins : 0;
      const est = provider === "house" ? 0 : cfg.ads.est_ecpm_rewarded_usd / 1000;
      const w = await mutate(d, cfg, async (w) => {
        const n = w.ads_date === today ? w.ads_count || 0 : 0;
        if (n >= cfg.economy.ads_per_day_cap) throw { status: 429, error: "no more rewarded ads today" };
        return { coins, set: { ads_date: today, ads_count: n + 1 },
          ledger: [{ kind: "money", type: "ad_rewarded", source: provider, product: reward, amount_usd: est, coins, estimated: true, test: provider === "house" || cfg.ads.h5_test_mode && provider === "h5" }] };
      });
      res.json({ ok: true, reward, coins_added: coins, tries_added: reward === "try" ? cfg.economy.ad_reward_tries : 0, wallet: walletView(w, cfg) });
    } catch (e) { fail(res, e); }
  });

  app.post("/ads/impression", async (req, res) => {
    const d = guard(req, res, "imp"); if (!d) return;
    try {
      const cfg = await getEconomy();
      const provider = ["house", "h5", "admob"].includes(req.body.provider) ? req.body.provider : "house";
      await ledger({ kind: "money", type: "ad_interstitial", source: provider, device_id: d, estimated: true,
        amount_usd: provider === "house" ? 0 : cfg.ads.est_ecpm_interstitial_usd / 1000, test: provider === "house" || cfg.ads.h5_test_mode && provider === "h5" });
      res.json({ ok: true });
    } catch (e) { fail(res, e); }
  });

  // Invite codes: a NEW player (wallet younger than 7 days, no solves yet) claims a friend's code once.
  app.post("/referral/claim", async (req, res) => {
    const d = guard(req, res, "ref"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.referrals) return bad(res, 403, "invites are off");
      const code = String(req.body.code || "").toUpperCase().trim();
      if (!CODE_RE.test(code)) return bad(res, 400, "bad code");
      const owner = await R().doc(code).get();
      if (!owner.exists) return bad(res, 404, "unknown code");
      const inviter = owner.data().device_id;
      if (inviter === d) return bad(res, 400, "that's your own code");
      const w = await mutate(d, cfg, async (w) => {
        if (w.referred_by) throw { status: 409, error: "already used an invite code" };
        if ((w.rewarded || []).length > 0 || Date.now() - Date.parse(w.created_at) > 7 * 86400000) throw { status: 403, error: "invite codes are for new players" };
        return { coins: cfg.economy.referral_invitee, set: { referred_by: inviter }, ledger: [{ kind: "coins", type: "referral_invitee", coins: cfg.economy.referral_invitee }] };
      });
      res.json({ ok: true, coins_added: cfg.economy.referral_invitee, wallet: walletView(w, cfg) });
    } catch (e) { fail(res, e); }
  });
  // Invite link: opens the web build, which claims the code (?ref=).
  app.get("/i/:code", (req, res) => {
    const code = String(req.params.code).toUpperCase();
    if (!CODE_RE.test(code)) return res.status(404).end();
    res.redirect(302, "/play/?ref=" + code);
  });

  // ---------------------------------------------------------------- purchases
  const findProduct = (cfg, id) => cfg.products.find((p) => p.id === id && p.active);

  // TEST mode (no store account yet): granted free, marked TEST, never counted as revenue.
  app.post("/purchase/test", async (req, res) => {
    const d = guard(req, res, "buy"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.purchases || cfg.payments.mode !== "test") return bad(res, 403, "test purchases are off");
      const p = findProduct(cfg, req.body.product);
      if (!p) return bad(res, 404, "unknown product");
      const r = await creditPurchase(d, cfg, p, { source: "test", orderId: "test-" + Date.now() + "-" + randomBytes(4).toString("hex"), amountUsd: p.price_usd, test: true });
      res.json({ ok: true, test: true, wallet: walletView(r.wallet, cfg) });
    } catch (e) { fail(res, e); }
  });

  // Google Play: the app sends the purchase token; we verify with Google, consume, then credit.
  app.post("/purchase/google", async (req, res) => {
    const d = guard(req, res, "buy"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.purchases || !cfg.payments.google_play) return bad(res, 403, "Google Play purchases are off");
      const { product, token } = req.body;
      const p = findProduct(cfg, product);
      if (!p || !PRODUCT_ID_RE.test(product)) return bad(res, 404, "unknown product");
      if (typeof token !== "string" || token.length < 10 || token.length > 4096) return bad(res, 400, "bad token");
      const v = await playVerify(config.androidPackage, product, token);
      if (!v.ok) return bad(res, 402, v.error);
      const r = await creditPurchase(d, cfg, p, { source: "google_play", orderId: v.orderId, amountUsd: v.test ? 0 : p.price_usd, test: v.test });
      // Credited (now or by an earlier attempt): only now let Google consume it.
      if (v.consume) await v.consume();
      if (r.duplicate) return res.json({ ok: true, duplicate: true, wallet: walletView(await ensureWallet(d, cfg), cfg) });
      res.json({ ok: true, wallet: walletView(r.wallet, cfg) });
    } catch (e) { fail(res, e); }
  });

  // Apple: needs the App Store account (App Store Server API keys). Off until then.
  app.post("/purchase/apple", async (_req, res) => bad(res, 501, "App Store purchases are not set up yet"));

  // Stripe (web/PWA): Checkout session; coins arrive via the signed webhook.
  app.post("/purchase/stripe", async (req, res) => {
    const d = guard(req, res, "buy"); if (!d) return;
    try {
      const cfg = await getEconomy();
      if (!cfg.features.purchases || !cfg.payments.stripe) return bad(res, 403, "card payments are off");
      const p = findProduct(cfg, req.body.product);
      if (!p) return bad(res, 404, "unknown product");
      const sec = await getSecrets();
      if (!sec.stripe_secret_key) return bad(res, 503, "Stripe is not configured");
      const origin = `${req.protocol}://${req.get("host")}`;
      const body = new URLSearchParams({
        mode: "payment", success_url: origin + "/play/?paid=1", cancel_url: origin + "/play/?paid=0",
        "line_items[0][quantity]": "1", "line_items[0][price_data][currency]": cfg.payments.currency.toLowerCase(),
        "line_items[0][price_data][unit_amount]": String(Math.round(p.price_usd * 100)),
        "line_items[0][price_data][product_data][name]": "Tinker: " + p.title,
        "metadata[device_id]": d, "metadata[product]": p.id,
      });
      const r = await fetchFn("https://api.stripe.com/v1/checkout/sessions", { method: "POST", body,
        headers: { Authorization: "Bearer " + sec.stripe_secret_key, "Content-Type": "application/x-www-form-urlencoded" } });
      const j = await r.json();
      if (!r.ok) return bad(res, 502, "stripe: " + (j.error?.message || r.status));
      res.json({ ok: true, url: j.url });
    } catch (e) { fail(res, e); }
  });
  app.post("/stripe/webhook", async (req, res) => {
    try {
      const sec = await getSecrets();
      if (!stripeSigOk(req.rawBody?.toString("utf8"), req.get("stripe-signature"), sec.stripe_webhook_secret)) return bad(res, 400, "bad signature");
      const ev = req.body;
      const cfg = await getEconomy();
      if (ev.type === "checkout.session.completed" && ev.data?.object?.payment_status === "paid") {
        const s = ev.data.object;
        const p = findProduct(cfg, s.metadata?.product);
        if (p && isDeviceId(s.metadata?.device_id)) {
          await creditPurchase(s.metadata.device_id, cfg, p, { source: "stripe", orderId: s.id, amountUsd: (s.amount_total || 0) / 100, test: !ev.livemode });
        }
      } else if (ev.type === "charge.refunded") {
        const c = ev.data?.object || {};
        await ledger({ id: "refund_stripe_" + c.id, kind: "money", type: "refund", source: "stripe", ref: c.id, amount_usd: -(c.amount_refunded || 0) / 100, test: !ev.livemode });
      }
      res.json({ received: true });
    } catch (e) { fail(res, e); }
  });

  // ---------------------------------------------------------------- campaign leaderboard
  app.post("/progress", async (req, res) => {
    const d = guard(req, res, "progress"); if (!d) return;
    const { solved, parts, name, country } = req.body;
    if (!Number.isInteger(solved) || solved < 0 || solved > 1000 || !Number.isInteger(parts) || parts < 0 || parts > 100000) return bad(res, 400, "bad progress");
    await P().doc(d).set({ device_id: d, solved, parts, score: solved * 100000 - parts, name: typeof name === "string" ? name.slice(0, 24) : "",
      country: isCountry(country) ? country : "ZZ", updated_at: new Date().toISOString() }, { merge: true });
    res.json({ ok: true });
  });
  app.get("/board-campaign", async (req, res) => {
    const me = isDeviceId(req.query.device_id) ? req.query.device_id : null;
    const snap = await P().orderBy("score", "desc").limit(config.boardSize).get();
    const rows = [];
    snap.docs.forEach((doc, i) => {
      const e = doc.data();
      const prev = rows[i - 1];
      const rank = prev && prev._s === e.score ? prev.rank : i + 1;
      rows.push({ rank, _s: e.score, player: publicId(e.device_id), is_me: e.device_id === me, name: e.name || "", country: e.country || "ZZ", solved: e.solved, parts: e.parts });
    });
    let own = rows.find((r) => r.is_me) || null;
    if (!own && me) {
      const m = await P().doc(me).get();
      if (m.exists) {
        const e = m.data();
        const better = await P().where("score", ">", e.score).count().get();
        own = { rank: better.data().count + 1, player: publicId(me), is_me: true, name: e.name || "", country: e.country || "ZZ", solved: e.solved, parts: e.parts };
      }
    }
    for (const r of rows) delete r._s;
    res.set("Cache-Control", "public, max-age=30");
    res.json({ rows, me: own });
  });

  // ---------------------------------------------------------------- admin console
  // Used by the admin console (grant to one or many players).
  app.locals.grantCoins = async (deviceId, coins, note = "") => {
    const cfg = await getEconomy();
    const w = await mutate(deviceId, cfg, async () => ({ coins, ledger: [{ kind: "coins", type: "admin_grant", ref: note, coins }] }));
    return { coins: w.coins };
  };
  const admin = express.Router();
  admin.use(adminGate);
  admin.get("/economy", async (_req, res) => {
    const cfg = await getEconomy(true);
    const sec = await getSecrets();
    res.json({ config: cfg, defaults: DEFAULTS, secrets: { stripe_secret_key: mask(sec.stripe_secret_key), stripe_webhook_secret: mask(sec.stripe_webhook_secret) },
      android_package: config.androidPackage, webhook_url: "/stripe/webhook" });
  });
  admin.put("/economy", async (req, res) => {
    const cfg = merge(DEFAULTS, req.body?.config || {});
    if (!["house", "h5", "admob"].includes(cfg.ads.provider)) return bad(res, 400, "bad ad provider");
    if (!["test", "live"].includes(cfg.payments.mode)) return bad(res, 400, "bad payments mode");
    for (const p of cfg.products) {
      if (!PRODUCT_ID_RE.test(p.id || "") || !(p.price_usd >= 0) || !(p.coins >= 0) || !(p.no_ads_days >= 0)) return bad(res, 400, "bad product " + (p.id || "?"));
    }
    for (const [k, v] of Object.entries(cfg.economy)) if (!Number.isFinite(v) || v < 0) return bad(res, 400, "bad number: " + k);
    await S().doc("economy").set({ ...cfg, updated_at: new Date().toISOString() });
    cache = { at: 0, cfg: null };
    res.json({ ok: true, config: await getEconomy(true) });
  });
  admin.put("/secrets", async (req, res) => {
    const upd = {};
    for (const k of ["stripe_secret_key", "stripe_webhook_secret"]) {
      const v = req.body?.[k];
      if (typeof v === "string" && v && !v.startsWith("••••")) upd[k] = v.trim();
      if (v === null) upd[k] = "";
    }
    await S().doc("secrets").set(upd, { merge: true });
    res.json({ ok: true });
  });
  admin.get("/ledger", async (req, res) => {
    const days = Math.min(Math.max(parseInt(req.query.days || "30", 10) || 30, 1), 366);
    const from = addDays(todayUtc(), -days + 1);
    const snap = await L().where("date", ">=", from).orderBy("date", "desc").limit(5000).get();
    const money = [], coins = { earned: 0, spent: 0, by_type: {} };
    const byDay = {}, bySource = {};
    for (const doc of snap.docs) {
      const e = doc.data();
      if (e.kind === "money") {
        money.push({ id: doc.id, ...e, device: e.device_id ? publicId(e.device_id) : "" });
        const k = e.test ? "test" : e.estimated ? "estimated" : "real";
        byDay[e.date] = byDay[e.date] || { real: 0, estimated: 0, test: 0, ads: 0, purchases: 0 };
        byDay[e.date][k] += e.amount_usd || 0;
        if (e.type.startsWith("ad_")) byDay[e.date].ads++; else if (e.type === "purchase") byDay[e.date].purchases++;
        const sk = `${e.source || "?"}:${e.type}`;
        bySource[sk] = bySource[sk] || { count: 0, real: 0, estimated: 0, test: 0 };
        bySource[sk].count++; bySource[sk][k] += e.amount_usd || 0;
      } else if (e.kind === "coins") {
        if (e.coins > 0) coins.earned += e.coins; else coins.spent -= e.coins;
        coins.by_type[e.type] = (coins.by_type[e.type] || 0) + e.coins;
      }
    }
    money.sort((a, b) => (a.ts < b.ts ? 1 : -1));
    const totals = { real: 0, estimated: 0, test: 0 };
    for (const v of Object.values(byDay)) { totals.real += v.real; totals.estimated += v.estimated; totals.test += v.test; }
    res.json({ from, days, totals, by_day: byDay, by_source: bySource, coins, entries: money.slice(0, 300) });
  });
  admin.get("/stats", async (_req, res) => {
    const wallets = await W().count().get();
    const testW = await W().where("test", "==", true).count().get();
    const dev = await db.collection("devices").count().get();
    const since = new Date(Date.now() - 86400000).toISOString();
    const active = await db.collection("devices").where("last_seen", ">=", since).count().get();
    const scoresToday = await db.collection("scores").where("date", "==", todayUtc()).count().get();
    const levels = await db.collection("levels").count().get();
    const testUsers = await P().where("test", "==", true).count().get();
    res.json({ wallets: wallets.data().count, test_wallets: testW.data().count, devices: dev.data().count, active_24h: active.data().count,
      daily_scores_today: scoresToday.data().count, shared_levels: levels.data().count, test_users: testUsers.data().count });
  });
  admin.post("/test-users", async (_req, res) => {
    const made = await seedTestUsers(async (date) => (await db.collection("daily").doc(date).get()).exists);
    res.json({ ok: true, made });
  });
  admin.delete("/test-users", async (_req, res) => res.json({ ok: true, removed: await removeTestUsers() }));
  admin.post("/grant", async (req, res) => {
    const { device_id, coins } = req.body || {};
    if (!isDeviceId(device_id) || !Number.isInteger(coins) || Math.abs(coins) > 100000) return bad(res, 400, "bad grant");
    try {
      const cfg = await getEconomy();
      const w = await mutate(device_id, cfg, async () => ({ coins, ledger: [{ kind: "coins", type: "admin_grant", coins }] }));
      res.json({ ok: true, wallet: walletView(w, cfg) });
    } catch (e) { fail(res, e); }
  });
  return admin;
}
