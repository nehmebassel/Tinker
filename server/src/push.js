// Push notifications via Firebase Cloud Messaging (firebase-admin, Application Default Credentials).
// Devices register their FCM token; the token is stored on devices/{id} and subscribed to one topic.
// The daily "puzzle is ready" message goes to the topic, so sending is one call whatever the audience.
// Everything is configurable by env (Cloud Run console): PUSH_TOPIC, PUSH_TITLE, PUSH_BODY, PUSH_ENABLED.
import { config } from "./config.js";

let _messaging = null;

async function messaging() {
  if (_messaging) return _messaging;
  const { initializeApp, getApps } = await import("firebase-admin/app");
  const { getMessaging } = await import("firebase-admin/messaging");
  const app = getApps()[0] || initializeApp(config.project ? { projectId: config.project } : {});
  _messaging = getMessaging(app);
  return _messaging;
}

// The real sender. Tests inject a fake with the same three methods.
export const fcm = {
  async subscribe(token, topic) {
    const r = await (await messaging()).subscribeToTopic([token], topic);
    return { ok: r.failureCount === 0, error: r.errors?.[0]?.error?.code };
  },
  async unsubscribe(token, topic) {
    const r = await (await messaging()).unsubscribeFromTopic([token], topic);
    return { ok: r.failureCount === 0, error: r.errors?.[0]?.error?.code };
  },
  async sendTopic(topic, { title, body, data }, dryRun = false) {
    const id = await (await messaging()).send({
      topic,
      notification: { title, body },
      data,
      android: { priority: "normal", notification: { channelId: "daily" } },
      apns: { payload: { aps: { sound: "default" } } },
    }, dryRun);
    return { ok: true, id };
  },
};

// FCM registration tokens are long opaque strings: letters, digits, : _ - .
const TOKEN_RE = /^[A-Za-z0-9:_\-.]{20,4096}$/;
export function isFcmToken(s) {
  return typeof s === "string" && TOKEN_RE.test(s);
}

export function dailyMessage(date, dayNumber) {
  return {
    title: config.pushTitle,
    body: config.pushBody.replace("{day}", String(dayNumber)),
    data: { kind: "daily", date },
  };
}
