// All configuration comes from the environment (Cloud Run env vars / secrets). Nothing is hard-coded.
const env = process.env;

export const config = {
  port: Number(env.PORT || 8080),
  project: env.GOOGLE_CLOUD_PROJECT || env.GCLOUD_PROJECT || "",
  database: env.FIRESTORE_DATABASE || "tinker",
  adminToken: env.ADMIN_TOKEN || "",              // required for /admin/*; empty disables admin routes
  godotBin: env.GODOT_BIN || "godot",
  gameDir: env.GAME_DIR || new URL("../../game/", import.meta.url).pathname,
  replayTimeoutMs: Number(env.REPLAY_TIMEOUT_MS || 60000),
  generateTimeoutMs: Number(env.GENERATE_TIMEOUT_MS || 600000),
  rateLimitPerMin: Number(env.RATE_LIMIT_PER_MIN || 20),
  boardSize: Number(env.BOARD_SIZE || 100),
  daysAhead: Number(env.DAILY_DAYS_AHEAD || 7),
  maxLevelBytes: Number(env.MAX_LEVEL_BYTES || 32768),
  emulator: Boolean(env.FIRESTORE_EMULATOR_HOST),
  webDir: env.WEB_DIR || "",
  downloadDir: env.DOWNLOAD_DIR || "",
  pushEnabled: (env.PUSH_ENABLED || "true") === "true",
  pushTopic: env.PUSH_TOPIC || "tinker-daily",
  pushTitle: env.PUSH_TITLE || "Today's Tinker is ready",
  pushBody: env.PUSH_BODY || "Day {day}: same parts for everyone. How few do you need?",
  dailyEpoch: env.DAILY_EPOCH || "2026-11-01",       // day 1 of the Daily (for the day number)
};

export function todayUtc(now = new Date()) {
  return now.toISOString().slice(0, 10);
}

export function addDays(dateStr, n) {
  const d = new Date(dateStr + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// Day number shown to players ("Day 12"): days since DAILY_EPOCH, 1-based.
export function dayNumber(dateStr) {
  const a = Date.parse(config.dailyEpoch + "T00:00:00Z");
  const b = Date.parse(dateStr + "T00:00:00Z");
  return Math.floor((b - a) / 86400000) + 1;
}
