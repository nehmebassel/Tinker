import express from "express";
import compression from "compression";
import { existsSync, createReadStream, statSync } from "node:fs";
import { join, resolve, sep, extname } from "node:path";
import { pipeline } from "node:stream/promises";
import { randomBytes, createHash } from "node:crypto";
import { config, todayUtc, addDays, dayNumber } from "./config.js";
import { fcm as realFcm, isFcmToken, dailyMessage } from "./push.js";
import { col, db } from "./db.js";
import { replay, generateDaily } from "./godot.js";
import { isDate, isDeviceId, isCountry, isShortId, validSolution, validLevel, solutionFits, publicLevel } from "./validate.js";

// ------------------------------------------------------------------ rate limit (per device / ip, per minute)
const buckets = new Map();
function rateLimited(key) {
  const now = Date.now();
  const b = buckets.get(key) || { start: now, n: 0 };
  if (now - b.start > 60000) { b.start = now; b.n = 0; }
  b.n += 1;
  buckets.set(key, b);
  if (buckets.size > 50000) buckets.clear();
  return b.n > config.rateLimitPerMin;
}

export function publicId(deviceId) {
  return createHash("sha256").update("tinker-player:" + deviceId).digest("base64url").slice(0, 10);
}

function shortId() {
  // 8 chars, lowercase alphanumerics: 36^8 ids, fine for shared levels.
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = randomBytes(8);
  let s = "";
  for (const b of bytes) s += alphabet[b % alphabet.length];
  return s;
}

export function createApp({ replayFn = replay, generateFn = generateDaily, fcm = realFcm } = {}) {
  const app = express();
  app.use(express.json({ limit: config.maxLevelBytes }));
  app.disable("x-powered-by");

  app.get("/health", (_req, res) => res.json({ ok: true, today: todayUtc(), emulator: config.emulator }));
  // Game rules for clients (cached by the game; it falls back to its own defaults offline).
  app.get("/config", (_req, res) => {
    res.set("Cache-Control", "public, max-age=300");
    res.json({ tries_limit: config.triesLimit, tries_window_hours: config.triesWindowHours });
  });

  // ---------------------------------------------------------------- the game itself
  // /play/   : the browser (PWA) build — same origin as the API, so no CORS and no setup.
  // /download/tinker.apk : the Android build for side-loading.
  // Both are optional (WEB_DIR / DOWNLOAD_DIR); the API works without them.
  // Push client config for the web page and the Android plugin (both fetch it at runtime).
  app.get("/push/config", (_req, res) => {
    res.set("Cache-Control", "public, max-age=300");
    res.json({ web: config.firebaseWeb, android: config.firebaseAndroid, vapidKey: config.vapidKey || null, topic: config.pushTopic });
  });
  // The web push glue lives with the server (not the Godot export) so it ships with every deploy.
  const staticDir = new URL("../static/", import.meta.url).pathname;
  app.get("/play/push.js", (_req, res) => res.set("Cache-Control", "no-cache").type("application/javascript").sendFile(staticDir + "push.js"));
  app.get("/play/fcm/sw.js", (_req, res) => res.set({ "Cache-Control": "no-cache", "Service-Worker-Allowed": "/play/fcm/" }).type("application/javascript").sendFile(staticDir + "fcm-sw.js"));

  if (config.webDir && existsSync(config.webDir)) {
    // Cloud Run 500s non-streamed responses over 32 MiB. Gzip responses are streamed (chunked) by
    // compression(), but a client that refuses gzip would get index.wasm (~36 MB) with a
    // Content-Length -> stream large files chunked for those clients.
    const webRoot = resolve(config.webDir);
    app.get("/play/*rest", (req, res, next) => {
      if (req.acceptsEncodings("gzip")) return next();
      const file = resolve(webRoot, "." + decodeURIComponent(req.path.slice("/play".length)));
      if (!file.startsWith(webRoot + sep)) return next();
      let st;
      try { st = statSync(file); } catch { return next(); }
      if (!st.isFile() || st.size <= 30 * 1024 * 1024) return next();
      res.type(extname(file)).set("Cache-Control", "public, max-age=3600");
      res.flushHeaders();
      pipeline(createReadStream(file), res).catch(() => {});
    });
    app.use("/play", compression({ threshold: 1024 }), express.static(config.webDir, {
      setHeaders(res, path) {
        // The engine (wasm/js) is versioned by deploy; the service worker and HTML must revalidate.
        res.setHeader("Cache-Control", /\.(html|json)$|service\.worker\.js$/.test(path) ? "no-cache" : "public, max-age=3600");
      },
    }));
    app.get("/", (_req, res) => res.redirect(302, "/play/"));
  }
  if (config.downloadDir && existsSync(config.downloadDir)) {
    // Streamed chunked, never with Content-Length: Cloud Run rejects (500) any non-streamed HTTP/1
    // response over 32 MiB, and the APK is ~60 MB. Chunked responses have no size cap.
    app.get("/download/:file", (req, res) => {
      const name = req.params.file;
      if (!/^[\w.-]+\.apk$/.test(name)) return res.status(404).end();
      const file = join(config.downloadDir, name);
      if (!existsSync(file)) return res.status(404).end();
      res.set({
        "Content-Type": "application/vnd.android.package-archive",
        "Content-Disposition": `attachment; filename="${name}"`,
        "Cache-Control": "no-cache",
      });
      if (req.method === "HEAD") return res.end();
      res.flushHeaders();  // headers go out now, without Content-Length -> Transfer-Encoding: chunked
      // pipeline closes the file when the client aborts (pipe() would leave the fd open).
      pipeline(createReadStream(file), res).catch(() => {});
    });
  }

  // ---------------------------------------------------------------- daily
  // Returns the day's level without its reference solution. Levels are pre-generated by
  // /admin/generate (a Cloud Scheduler job); nothing is generated in the request path.
  app.get("/daily/:date", async (req, res) => {
    const { date } = req.params;
    if (!isDate(date)) return res.status(400).json({ error: "bad date" });
    if (date > addDays(todayUtc(), 1)) return res.status(404).json({ error: "not yet" });
    const snap = await col.daily().doc(date).get();
    if (!snap.exists) return res.status(404).json({ error: "no level for this date" });
    res.set("Cache-Control", "public, max-age=300");
    res.json({ date, day: dayNumber(date), level: publicLevel(snap.data().level) });
  });

  // ---------------------------------------------------------------- score
  app.post("/score", async (req, res) => {
    const { device_id, date, solution, elapsed_ms, country, name } = req.body || {};
    if (!isDeviceId(device_id)) return res.status(400).json({ error: "bad device_id" });
    if (rateLimited("score:" + device_id)) return res.status(429).json({ error: "slow down" });
    if (!isDate(date)) return res.status(400).json({ error: "bad date" });
    const today = todayUtc();
    if (date !== today && date !== addDays(today, -1)) return res.status(400).json({ error: "date not open for submission" });
    const e = validSolution(solution);
    if (e) return res.status(400).json({ error: e });
    // A run can't have lasted longer than the time since its day began (00:00 UTC): up to ~48 h for
    // yesterday's puzzle, which stays open until today ends. +1 h slack for device clock skew.
    const maxMs = Date.now() - Date.parse(date + "T00:00:00Z") + 3600000;
    if (!Number.isInteger(elapsed_ms) || elapsed_ms < 0 || elapsed_ms > maxMs) return res.status(400).json({ error: "bad elapsed_ms" });
    const ctry = isCountry(country) ? country : "ZZ";
    const dailySnap = await col.daily().doc(date).get();
    if (!dailySnap.exists) return res.status(404).json({ error: "no level for this date" });
    const level = dailySnap.data().level;
    if (!solutionFits(level, solution)) return res.status(400).json({ error: "solution does not fit tray/slots" });
    const scoreId = `${date}_${device_id}`;
    const existing = await col.scores().doc(scoreId).get();
    if (existing.exists) return res.status(409).json({ error: "already submitted", entry: existing.data() });
    // The proof: replay on the server with the same simulation.
    const r = await replayFn(level, solution);
    if (!r.ok) return res.status(400).json({ error: "replay failed: " + r.error });
    if (r.result !== "goal") return res.status(422).json({ error: "solution does not reach the goal", result: r.result });
    const entry = {
      date, device_id, country: ctry, parts: r.parts, ms: elapsed_ms, hash: r.hash, ticks: r.ticks,
      name: typeof name === "string" ? name.slice(0, 24) : "",
      solution, created_at: new Date().toISOString(),
    };
    // Atomic: create() fails if another request for this device+day won the race during the replay.
    try {
      await col.scores().doc(scoreId).create(entry);
    } catch (err) {
      if (err?.code === 6 /* ALREADY_EXISTS */) {
        const first = (await col.scores().doc(scoreId).get()).data();
        return res.status(409).json({ error: "already submitted", entry: first });
      }
      throw err;
    }
    await col.devices().doc(device_id).set({ country: ctry, last_seen: entry.created_at, name: entry.name }, { merge: true });
    const rank = await rankOf(date, "global", entry);
    res.status(201).json({ ok: true, parts: entry.parts, ms: entry.ms, rank });
  });

  // ---------------------------------------------------------------- board
  // Rank by parts asc, then ms asc. Top N plus the caller's own row (scope global or country).
  app.get("/board/:date", async (req, res) => {
    const { date } = req.params;
    if (!isDate(date)) return res.status(400).json({ error: "bad date" });
    const scope = req.query.scope === "country" ? "country" : "global";
    const deviceId = isDeviceId(req.query.device_id) ? req.query.device_id : null;
    let country = isCountry(req.query.country) ? req.query.country : null;
    let mine = null;
    if (deviceId) {
      const s = await col.scores().doc(`${date}_${deviceId}`).get();
      if (s.exists) { mine = s.data(); if (!country) country = mine.country; }
    }
    if (scope === "country" && !country) return res.status(400).json({ error: "country required for country scope" });
    // One leaderboard per response: on a country board, my row only appears if my entry is in it.
    if (scope === "country" && mine && mine.country !== country) mine = null;
    let q = col.scores().where("date", "==", date);
    if (scope === "country") q = q.where("country", "==", country);
    q = q.orderBy("parts", "asc").orderBy("ms", "asc").limit(config.boardSize);
    const snap = await q.get();
    // Competition ranking ("1, 1, 3"), the same policy as rankOf: a row's rank is 1 + the number of
    // entries strictly better (fewer parts, or same parts and faster). Ties share a rank.
    const rows = [];
    snap.docs.forEach((d, i) => {
      const e = d.data();
      const prev = rows[i - 1];
      const rank = prev && prev._parts === e.parts && prev._ms === e.ms ? prev.rank : i + 1;
      rows.push({ ...row(e, rank, deviceId), _parts: e.parts, _ms: e.ms });
    });
    for (const r of rows) { delete r._parts; delete r._ms; }
    let own = null;
    if (mine) own = row(mine, await rankOf(date, scope, mine), deviceId);
    res.set("Cache-Control", "public, max-age=30");
    res.json({ date, scope, country: scope === "country" ? country : null, rows, me: own });
  });

  // device_id is the device's private credential (it authorises /score and /push/register), so it is
  // never published. Boards carry a one-way public id and an is_me flag for the caller's own row.
  function row(e, rank, callerId) {
    return { rank, player: publicId(e.device_id), is_me: callerId === e.device_id, name: e.name || "", country: e.country, parts: e.parts, ms: e.ms };
  }

  async function rankOf(date, scope, entry) {
    // rank = 1 + entries strictly better (fewer parts, or same parts and faster).
    let base = col.scores().where("date", "==", date);
    if (scope === "country") base = base.where("country", "==", entry.country);
    const fewer = await base.where("parts", "<", entry.parts).count().get();
    const faster = await base.where("parts", "==", entry.parts).where("ms", "<", entry.ms).count().get();
    return 1 + fewer.data().count + faster.data().count;
  }

  // ---------------------------------------------------------------- push
  // A device registers (or refreshes) its FCM token; we keep it on the device doc and subscribe it to
  // the daily topic. enabled=false unsubscribes (the in-game "Daily reminder" toggle).
  app.post("/push/register", async (req, res) => {
    const { device_id, token, enabled = true } = req.body || {};
    if (!isDeviceId(device_id)) return res.status(400).json({ error: "bad device_id" });
    if (!isFcmToken(token)) return res.status(400).json({ error: "bad token" });
    if (rateLimited("push:" + device_id)) return res.status(429).json({ error: "slow down" });
    const ref = col.devices().doc(device_id);
    const prev = (await ref.get()).data() || {};
    if (prev.fcm_token && prev.fcm_token !== token && prev.push_enabled) {
      await fcm.unsubscribe(prev.fcm_token, config.pushTopic).catch(() => {});
    }
    const r = enabled ? await fcm.subscribe(token, config.pushTopic) : await fcm.unsubscribe(token, config.pushTopic);
    if (!r.ok) return res.status(502).json({ error: "fcm: " + (r.error || "failed") });
    await ref.set({ fcm_token: token, push_enabled: Boolean(enabled), push_updated_at: new Date().toISOString() }, { merge: true });
    res.json({ ok: true, topic: config.pushTopic, enabled: Boolean(enabled) });
  });

  // ---------------------------------------------------------------- shared levels (sandbox)
  app.post("/level", async (req, res) => {
    const { device_id, level } = req.body || {};
    if (!isDeviceId(device_id)) return res.status(400).json({ error: "bad device_id" });
    if (rateLimited("level:" + device_id)) return res.status(429).json({ error: "slow down" });
    const e = validLevel(level);
    if (e) return res.status(400).json({ error: e });
    if (!solutionFits(level, level.reference_solution)) return res.status(400).json({ error: "author solution does not fit tray/slots" });
    const r = await replayFn(level, level.reference_solution);
    if (!r.ok) return res.status(400).json({ error: "replay failed: " + r.error });
    if (r.result !== "goal") return res.status(422).json({ error: "author solution does not reach the goal", result: r.result });
    // A level that finishes itself with no player parts is not a puzzle.
    const empty = await replayFn(level, []);
    if (empty.ok && empty.result === "goal") return res.status(422).json({ error: "the level solves itself with no parts placed" });
    let id = shortId();
    for (let i = 0; i < 5 && (await col.levels().doc(id).get()).exists; i++) id = shortId();
    const doc = {
      id, author: device_id, created_at: new Date().toISOString(), plays: 0, title: level.title, goal_type: level.goal.type,
      level: { ...level, id: "s-" + id, reference_solution: level.reference_solution },
      author_parts: r.parts, hash: r.hash,
    };
    await col.levels().doc(id).set(doc);
    res.status(201).json({ ok: true, id, author_parts: r.parts });
  });

  // Newest shared levels (Sandbox "Community" list). Public data only.
  app.get("/levels/recent", async (req, res) => {
    const limit = Math.min(Math.max(parseInt(req.query.limit || "20", 10) || 20, 1), 50);
    const snap = await col.levels().orderBy("created_at", "desc").limit(limit).get();
    res.set("Cache-Control", "public, max-age=60");
    res.json({ levels: snap.docs.map((d) => {
      const x = d.data();
      return { id: x.id, title: x.title || x.level?.title || "", goal: x.goal_type || x.level?.goal?.type || "", author_parts: x.author_parts, plays: x.plays || 0, created_at: x.created_at };
    }) });
  });

  // Share link: opens the browser build straight into the level (/play/ reads ?level=).
  app.get("/l/:id", (req, res) => {
    const { id } = req.params;
    if (!isShortId(id)) return res.status(404).end();
    res.redirect(302, "/play/?level=" + encodeURIComponent(id));
  });

  app.get("/level/:id", async (req, res) => {
    const { id } = req.params;
    if (!isShortId(id)) return res.status(400).json({ error: "bad id" });
    const snap = await col.levels().doc(id).get();
    if (!snap.exists) return res.status(404).json({ error: "not found" });
    const d = snap.data();
    col.levels().doc(id).update({ plays: (d.plays || 0) + 1 }).catch(() => {});
    res.set("Cache-Control", "public, max-age=300");
    res.json({ id, author_parts: d.author_parts, created_at: d.created_at, level: publicLevel(d.level) });
  });

  // ---------------------------------------------------------------- admin (curation)
  const admin = express.Router();
  admin.use((req, res, next) => {
    if (!config.adminToken) return res.status(404).end();
    if (req.get("x-admin-token") !== config.adminToken) return res.status(401).json({ error: "unauthorized" });
    next();
  });
  // Pre-generate missing dailies for today .. today+daysAhead. Idempotent; safe for Cloud Scheduler.
  admin.post("/generate", async (req, res) => {
    const days = Math.min(Number(req.query.days || config.daysAhead), 30);
    const start = todayUtc();
    const made = [], skipped = [], failed = [];
    for (let i = 0; i < days; i++) {
      const date = addDays(start, i);
      const ref = col.daily().doc(date);
      if ((await ref.get()).exists) { skipped.push(date); continue; }
      const g = await generateFn(date, 0);
      if (!g.ok) {
        console.error(`generate ${date} failed: ${g.error}\n${g.detail || ""}`);
        failed.push({ date, error: g.error, detail: (g.detail || "").slice(-800) });
        continue;
      }
      // create(), not set(): a level curated while this one was generating must win.
      try {
        await ref.create({ date, level: g.level, curated: false, source: "generator", info: g.info, created_at: new Date().toISOString() });
        made.push(date);
      } catch (err) {
        if (err?.code === 6) { skipped.push(date); continue; }
        throw err;
      }
    }
    res.json({ made, skipped, failed });
  });
  // The curation queue: what players will get for the coming days.
  admin.get("/queue", async (_req, res) => {
    const start = todayUtc();
    const snap = await col.daily().where("date", ">=", start).orderBy("date").limit(31).get();
    res.json({ days: snap.docs.map((d) => { const x = d.data(); return { date: x.date, curated: x.curated, source: x.source, template: x.info?.template, title: x.level.title, tray: x.level.tray, slots: x.level.slots }; }) });
  });
  // Swap a day's level (broken or dull). The replacement must carry a verified reference solution.
  admin.put("/daily/:date", async (req, res) => {
    const { date } = req.params;
    if (!isDate(date)) return res.status(400).json({ error: "bad date" });
    const level = req.body?.level;
    const e = validLevel(level);
    if (e) return res.status(400).json({ error: e });
    const r = await replayFn(level, level.reference_solution);
    if (!r.ok || r.result !== "goal") return res.status(422).json({ error: "reference solution does not reach the goal", detail: r });
    await col.daily().doc(date).set({ date, level: { ...level, id: "d-" + date }, curated: true, source: "curated", created_at: new Date().toISOString() });
    res.json({ ok: true, date, parts: r.parts });
  });
  // Send "today's puzzle is ready" to the topic — once per day (idempotent: Cloud Scheduler retries
  // must not double-notify). ?dry_run=1 validates with FCM without delivering.
  admin.post("/notify", async (req, res) => {
    if (!config.pushEnabled) return res.json({ ok: true, skipped: "push disabled" });
    const date = isDate(req.query.date) ? req.query.date : todayUtc();
    const dry = req.query.dry_run === "1";
    const daily = await col.daily().doc(date).get();
    if (!daily.exists) return res.status(409).json({ error: "no level for " + date + " (generate first)" });
    const ref = col.push().doc(date);
    if (dry) {
      const r = await fcm.sendTopic(config.pushTopic, dailyMessage(date, dayNumber(date)), true);
      return res.json({ ok: true, date, dry_run: true, id: r.id });
    }
    // Claim the day atomically BEFORE sending: of two overlapping calls only one creates the claim.
    // If the send fails, the claim is released so the scheduler's retry can try again.
    try {
      await ref.create({ date, topic: config.pushTopic, status: "sending", claimed_at: new Date().toISOString() });
    } catch (err) {
      if (err?.code === 6) return res.json({ ok: true, skipped: "already sent", date });
      throw err;
    }
    let r;
    try {
      r = await fcm.sendTopic(config.pushTopic, dailyMessage(date, dayNumber(date)), false);
    } catch (err) {
      await ref.delete().catch(() => {});
      throw err;
    }
    await ref.update({ status: "sent", id: r.id, sent_at: new Date().toISOString() });
    res.json({ ok: true, date, dry_run: false, id: r.id });
  });
  admin.get("/daily/:date/full", async (req, res) => {
    const snap = await col.daily().doc(req.params.date).get();
    if (!snap.exists) return res.status(404).json({ error: "not found" });
    res.json(snap.data());
  });
  app.use("/admin", admin);

  app.use((err, _req, res, _next) => {
    if (err?.type === "entity.too.large") return res.status(413).json({ error: "payload too large" });
    if (err?.type === "entity.parse.failed") return res.status(400).json({ error: "bad json" });
    console.error(err);
    res.status(500).json({ error: "internal" });
  });
  return app;
}

export { db };
