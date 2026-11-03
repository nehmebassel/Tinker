// Player operations for the admin console (2026-11-03, Bassel): who is online, who played when, on what
// platform / OS; give coins to selected players; push campaigns to selected players, a filter or
// everyone, with per-recipient sent / received / opened tracking.
//
// Collections:
//   devices/{device}            + platform, os, model, browser, app_version, first_seen, last_seen (presence)
//   activity/{date}_{device}    one doc per device per UTC day it was used (pings, first, last)
//   campaigns/{id}              title, body, target, created_at, counts {targeted, sent, failed, received, opened}
//   push_rcpt/{rcpt}            campaign, device_id, sent, error, received_at, opened_at
//
// Honesty about "received": web push reports it from the service worker; on Android the system shows
// the notification without running the game, so receipt is only known when the player opens it.
import { randomBytes } from "node:crypto";
import { FieldValue } from "@google-cloud/firestore";
import { db } from "./db.js";
import { todayUtc, addDays } from "./config.js";
import { isDeviceId, isCountry, isDate } from "./validate.js";

const ONLINE_S = 150;  // a device is "online" if it pinged in the last 2.5 minutes (it pings every 60 s)
const D = () => db.collection("devices");
const A = () => db.collection("activity");
const C = () => db.collection("campaigns");
const R = () => db.collection("push_rcpt");
const str = (v, n) => (typeof v === "string" ? v.slice(0, n) : "");

function osFamily(d) {
  const p = d.platform || "";
  const ua = d.browser || "";
  if (p === "android") return "Android";
  if (p === "ios") return "iOS";
  if (p === "web") {
    if (/iPhone|iPad|iPod/.test(ua)) return "iOS (web)";
    if (/Android/.test(ua)) return "Android (web)";
    if (/Mac OS X/.test(ua)) return "macOS (web)";
    if (/Windows/.test(ua)) return "Windows (web)";
    if (/Linux/.test(ua)) return "Linux (web)";
    return "Web";
  }
  return p || "unknown";
}

export function mountOps(app, admin, { fcm, rateLimited, publicId }) {
  // ---------------------------------------------------------------- presence (game heartbeat)
  app.post("/presence", async (req, res) => {
    const b = req.body || {};
    const d = b.device_id;
    if (!isDeviceId(d)) return res.status(400).json({ error: "bad device_id" });
    if (rateLimited("presence:" + d)) return res.status(429).json({ error: "slow down" });
    const now = new Date().toISOString(), date = todayUtc();
    const info = { platform: str(b.platform, 20), os: str(b.os, 60), model: str(b.model, 60), browser: str(b.browser, 300),
      app_version: str(b.app_version, 20), last_seen: now };
    if (typeof b.name === "string" && b.name) info.name = b.name.slice(0, 24);
    if (isCountry(b.country)) info.country = b.country;
    const ref = D().doc(d);
    const prev = await ref.get();
    if (!prev.exists || !prev.data().first_seen) info.first_seen = now;
    await ref.set(info, { merge: true });
    await A().doc(`${date}_${d}`).set({ date, device_id: d, platform: info.platform, last: now, pings: FieldValue.increment(1),
      ...(prev.exists && prev.data().last_seen?.slice(0, 10) === date ? {} : { first: now }) }, { merge: true });
    res.json({ ok: true });
  });

  // ---------------------------------------------------------------- delete my data (Settings button)
  // Google Play's Data safety form asks for a deletion path. The device id is the only credential, so
  // the device that owns the data can delete it. Money ledger lines are kept for accounting but
  // anonymised; everything else about the device goes.
  app.post("/me/delete", async (req, res) => {
    const d = req.body?.device_id;
    if (!isDeviceId(d)) return res.status(400).json({ error: "bad device_id" });
    if (rateLimited("delete:" + d)) return res.status(429).json({ error: "slow down" });
    let n = 0;
    const del = async (q) => { const s = await q.get(); const b = db.batch(); s.docs.forEach((x) => b.delete(x.ref)); if (s.size) await b.commit(); n += s.size; };
    const w = await db.collection("wallets").doc(d).get();
    if (w.exists && w.data().ref_code) await db.collection("referrals").doc(w.data().ref_code).delete().catch(() => {});
    for (const c of ["wallets", "devices", "progress"]) { const r = db.collection(c).doc(d); if ((await r.get()).exists) { await r.delete(); n++; } }
    await del(db.collection("scores").where("device_id", "==", d));
    await del(A().where("device_id", "==", d));
    await del(R().where("device_id", "==", d));
    await del(db.collection("ledger").where("device_id", "==", d).where("kind", "==", "coins"));
    const money = await db.collection("ledger").where("device_id", "==", d).get();
    for (const x of money.docs) await x.ref.update({ device_id: "deleted" });
    console.log(`data deleted for a device: ${n} records, ${money.size} ledger lines anonymised`);
    res.json({ ok: true, deleted: n, anonymised: money.size });
  });

  // ---------------------------------------------------------------- push events (received / opened)
  app.post("/push/event", async (req, res) => {
    const { rcpt, event } = req.body || {};
    if (typeof rcpt !== "string" || !/^[a-f0-9]{16,40}$/.test(rcpt) || !["received", "opened"].includes(event)) return res.status(400).json({ error: "bad event" });
    if (rateLimited("pushev:" + rcpt)) return res.status(429).json({ error: "slow down" });
    const ref = R().doc(rcpt);
    const first = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) return null;
      const r = s.data();
      const upd = {};
      const counts = {};
      if (event === "opened" && !r.opened_at) { upd.opened_at = new Date().toISOString(); counts["counts.opened"] = FieldValue.increment(1); }
      // Opening proves receipt.
      if (!r.received_at) { upd.received_at = new Date().toISOString(); counts["counts.received"] = FieldValue.increment(1); }
      if (!Object.keys(upd).length) return null;
      tx.update(ref, upd);
      tx.update(C().doc(r.campaign), counts);
      return r.campaign;
    });
    res.json({ ok: true, counted: Boolean(first) });
  });

  // ---------------------------------------------------------------- admin: players
  // ?filter=all|online|today|range (&from=&to=) &q=name &limit
  async function selectDevices(q) {
    const limit = Math.min(Math.max(parseInt(q.limit || "300", 10) || 300, 1), 2000);
    let ids = null;
    if (q.filter === "online") {
      const since = new Date(Date.now() - ONLINE_S * 1000).toISOString();
      const s = await D().where("last_seen", ">=", since).limit(limit).get();
      return s.docs.map((x) => ({ id: x.id, ...x.data() }));
    }
    if (q.filter === "today" || q.filter === "range") {
      const from = q.filter === "today" ? todayUtc() : isDate(q.from) ? q.from : addDays(todayUtc(), -6);
      const to = q.filter === "today" ? todayUtc() : isDate(q.to) ? q.to : todayUtc();
      const s = await A().where("date", ">=", from).where("date", "<=", to).limit(20000).get();
      const days = new Map();
      for (const x of s.docs) { const a = x.data(); days.set(a.device_id, (days.get(a.device_id) || 0) + 1); }
      ids = [...days.keys()].slice(0, limit);
      const docs = await Promise.all(ids.map((id) => D().doc(id).get()));
      return docs.filter((x) => x.exists).map((x) => ({ id: x.id, ...x.data(), active_days: days.get(x.id) }));
    }
    const s = await D().orderBy("last_seen", "desc").limit(limit).get();
    return s.docs.map((x) => ({ id: x.id, ...x.data() }));
  }

  admin.get("/players", async (req, res) => {
    let list = await selectDevices(req.query);
    const qn = String(req.query.q || "").toLowerCase().trim();
    if (qn) list = list.filter((p) => (p.name || "").toLowerCase().includes(qn) || p.id.toLowerCase().startsWith(qn));
    if (req.query.test !== "1") list = list.filter((p) => !p.test);
    const wallets = await Promise.all(list.map((p) => db.collection("wallets").doc(p.id).get()));
    const since = new Date(Date.now() - ONLINE_S * 1000).toISOString();
    const rows = list.map((p, i) => {
      const w = wallets[i].exists ? wallets[i].data() : null;
      return { device_id: p.id, player: publicId(p.id), name: p.name || "", country: p.country || "", platform: p.platform || "",
        os_family: osFamily(p), os: p.os || "", model: p.model || "", app_version: p.app_version || "", first_seen: p.first_seen || "",
        last_seen: p.last_seen || "", online: (p.last_seen || "") >= since, push: Boolean(p.fcm_token && p.push_enabled),
        coins: w ? w.coins : null, active_days: p.active_days || undefined };
    });
    const by = (k) => rows.reduce((m, r) => ((m[r[k] || "?"] = (m[r[k] || "?"] || 0) + 1), m), {});
    res.json({ count: rows.length, online: rows.filter((r) => r.online).length, by_os: by("os_family"), by_platform: by("platform"), players: rows });
  });

  // Daily active players for a date range (chart in the console).
  admin.get("/activity", async (req, res) => {
    const from = isDate(req.query.from) ? req.query.from : addDays(todayUtc(), -13);
    const to = isDate(req.query.to) ? req.query.to : todayUtc();
    const s = await A().where("date", ">=", from).where("date", "<=", to).limit(50000).get();
    const days = {};
    for (const x of s.docs) { const a = x.data(); days[a.date] = days[a.date] || { players: 0, android: 0, web: 0, ios: 0, other: 0 }; days[a.date].players++; const k = ["android", "web", "ios"].includes(a.platform) ? a.platform : "other"; days[a.date][k]++; }
    const out = [];
    for (let d = from; d <= to; d = addDays(d, 1)) out.push({ date: d, ...(days[d] || { players: 0, android: 0, web: 0, ios: 0, other: 0 }) });
    const since = new Date(Date.now() - ONLINE_S * 1000).toISOString();
    const online = await D().where("last_seen", ">=", since).count().get();
    res.json({ from, to, online_now: online.data().count, days: out });
  });

  // ---------------------------------------------------------------- admin: coins to many players
  admin.post("/grant-many", async (req, res) => {
    const { device_ids, coins, note } = req.body || {};
    if (!Array.isArray(device_ids) || !device_ids.length || device_ids.length > 2000 || !device_ids.every(isDeviceId)) return res.status(400).json({ error: "bad device_ids" });
    if (!Number.isInteger(coins) || coins === 0 || Math.abs(coins) > 1000000) return res.status(400).json({ error: "bad coins" });
    const results = [];
    for (const id of device_ids) {
      const r = await app.locals.grantCoins(id, coins, str(note, 80)).catch((e) => ({ error: e?.error || "failed" }));
      results.push({ device_id: id, ...r });
    }
    res.json({ ok: true, granted: results.filter((r) => !r.error).length, results });
  });

  // ---------------------------------------------------------------- admin: push campaigns
  // target: "all" | "selected" (device_ids) | "filter" (same filter as /players)
  admin.post("/push", async (req, res) => {
    const { title, body, target, device_ids, filter, from, to, dry_run } = req.body || {};
    if (typeof title !== "string" || !title.trim() || title.length > 80) return res.status(400).json({ error: "title 1-80 chars" });
    if (typeof body !== "string" || !body.trim() || body.length > 240) return res.status(400).json({ error: "body 1-240 chars" });
    let devs;
    if (target === "selected") {
      if (!Array.isArray(device_ids) || !device_ids.length || !device_ids.every(isDeviceId)) return res.status(400).json({ error: "select players" });
      devs = (await Promise.all(device_ids.slice(0, 5000).map((id) => D().doc(id).get()))).filter((x) => x.exists).map((x) => ({ id: x.id, ...x.data() }));
    } else if (target === "filter") {
      devs = await selectDevices({ filter, from, to, limit: "2000" });
    } else if (target === "all") {
      const s = await D().where("push_enabled", "==", true).get();
      devs = s.docs.map((x) => ({ id: x.id, ...x.data() }));
    } else return res.status(400).json({ error: "bad target" });
    const reachable = devs.filter((d) => d.fcm_token && d.push_enabled && !d.test);
    const id = C().doc().id;
    const campaign = { id, title: title.trim(), body: body.trim(), target, filter: target === "filter" ? { filter, from: from || "", to: to || "" } : null,
      created_at: new Date().toISOString(), dry_run: Boolean(dry_run),
      counts: { targeted: devs.length, reachable: reachable.length, sent: 0, failed: 0, received: 0, opened: 0 } };
    await C().doc(id).set(campaign);
    const msgs = reachable.map((d) => ({ d, rcpt: randomBytes(12).toString("hex") }));
    let sent = 0, failed = 0;
    for (let i = 0; i < msgs.length; i += 500) {
      const chunk = msgs.slice(i, i + 500);
      // Reserve the recipient records BEFORE sending: a phone can report "received" (or the player can
      // open it) before sendEach returns, and that event needs a record to land on (Codex PR #9).
      const pre = db.batch();
      chunk.forEach(({ d, rcpt }) => pre.set(R().doc(rcpt), { campaign: id, device_id: d.id, name: d.name || "", sent: null, error: "", sent_at: "" }));
      await pre.commit();
      const results = await fcm.sendEach(chunk.map(({ d, rcpt }) => ({
        token: d.fcm_token, notification: { title: campaign.title, body: campaign.body },
        data: { kind: "campaign", campaign: id, rcpt },
        android: { priority: "high", notification: { channelId: "daily" } },
        webpush: { fcmOptions: { link: "/play/?push=" + rcpt } },
      })), Boolean(dry_run));
      const batch = db.batch();
      chunk.forEach(({ d, rcpt }, k) => {
        const r = results[k] || { ok: false, error: "no result" };
        if (r.ok) sent++; else failed++;
        batch.set(R().doc(rcpt), { sent: r.ok, error: r.ok ? "" : String(r.error || "").slice(0, 120), sent_at: new Date().toISOString() }, { merge: true });
        // A token FCM says is dead will never work again: stop using it.
        if (!r.ok && /registration-token-not-registered|invalid-registration-token/.test(String(r.error))) batch.update(D().doc(d.id), { push_enabled: false });
      });
      await batch.commit();
    }
    await C().doc(id).update({ "counts.sent": sent, "counts.failed": failed });
    res.json({ ok: true, id, targeted: devs.length, reachable: reachable.length, sent, failed, dry_run: Boolean(dry_run) });
  });

  admin.get("/campaigns", async (_req, res) => {
    const s = await C().orderBy("created_at", "desc").limit(50).get();
    res.json({ campaigns: s.docs.map((x) => x.data()) });
  });
  admin.get("/campaigns/:id", async (req, res) => {
    const c = await C().doc(req.params.id).get();
    if (!c.exists) return res.status(404).json({ error: "not found" });
    const s = await R().where("campaign", "==", req.params.id).limit(5000).get();
    res.json({ campaign: c.data(), recipients: s.docs.map((x) => { const r = x.data(); return { player: publicId(r.device_id), device_id: r.device_id, name: r.name, sent: r.sent, error: r.error, received_at: r.received_at || "", opened_at: r.opened_at || "" }; }) });
  });
}
