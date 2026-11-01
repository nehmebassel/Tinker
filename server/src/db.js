import { Firestore } from "@google-cloud/firestore";
import { config } from "./config.js";

// Collections:
//   daily/{date}                 level JSON (with reference_solution; stripped before serving) + curated flag
//   scores/{date}_{deviceId}     one accepted entry per device per day
//   levels/{shortId}             sandbox levels (with the author's verified solution)
//   devices/{deviceId}           display name, country, FCM token + push_enabled
//   push/{date}                  one record per daily notification sent (idempotency)
// A NAMED database (FIRESTORE_DATABASE, default "tinker") so Tinker never touches a shared
// project's (default) database.
const opts = {};
if (config.project) opts.projectId = config.project;
if (config.database) opts.databaseId = config.database;
export const db = new Firestore(opts);

export const col = {
  daily: () => db.collection("daily"),
  scores: () => db.collection("scores"),
  levels: () => db.collection("levels"),
  devices: () => db.collection("devices"),
  push: () => db.collection("push"),
};
