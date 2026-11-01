# tinker-api — runbook

Node 22 + Express on Cloud Run, Firestore (named database `tinker`), FCM for the daily reminder, and
the game's own headless Godot for server-side replay. Scores are never trusted from the client: an
entry exists only if the server's replay of the submitted integer solution reaches the goal.

## Endpoints
| Method | Path | Does |
| --- | --- | --- |
| GET | `/health` | liveness + server's UTC day |
| GET | `/daily/{date}` | the day's level (no reference solution) + `day` number; `404` until generated; future dates (beyond tomorrow) hidden |
| POST | `/score` | `{device_id, date, solution, elapsed_ms, country, name}` → server replay → `201 {parts, ms, rank}`; `409` second submission; `422` doesn't reach the goal; only today or yesterday (UTC) open |
| GET | `/board/{date}?scope=global\|country&device_id=&country=` | top `BOARD_SIZE` (parts asc, ms asc) + the caller's row |
| POST | `/push/register` | `{device_id, token, enabled}` stores the FCM token, (un)subscribes it to `PUSH_TOPIC` |
| POST | `/level`, GET `/level/{id}` | sandbox share/fetch (author solution replayed before accept) — used from M5 |
| POST | `/admin/generate?days=7` | pre-generate missing days (idempotent) — Cloud Scheduler, nightly |
| POST | `/admin/notify[?dry_run=1]` | send "today's puzzle is ready" once per day (idempotent) — Cloud Scheduler |
| GET | `/admin/queue` | curation queue: the coming days |
| PUT | `/admin/daily/{date}` | swap a day's level `{level}`; its `reference_solution` must replay to goal |
| GET | `/admin/daily/{date}/full` | a day including its solution |

`/admin/*` needs header `x-admin-token` = secret `tinker-admin-token`; admin routes are disabled (404) when `ADMIN_TOKEN` is empty.

## Configuration (Cloud Run → tinker-api → Edit → Variables & secrets — no code change needed)
| Env | Default | Meaning |
| --- | --- | --- |
| `GOOGLE_CLOUD_PROJECT` | — | project |
| `FIRESTORE_DATABASE` | `tinker` | named database (never the shared `(default)`) |
| `ADMIN_TOKEN` | secret | from Secret Manager `tinker-admin-token` |
| `BOARD_SIZE` | 100 | rows per board |
| `RATE_LIMIT_PER_MIN` | 20 | per device per route |
| `DAILY_DAYS_AHEAD` | 7 | generate horizon |
| `DAILY_EPOCH` | 2026-11-01 | "Day 1" |
| `PUSH_ENABLED` / `PUSH_TOPIC` / `PUSH_TITLE` / `PUSH_BODY` | true / tinker-daily / … | daily reminder (`{day}` placeholder) |
| `REPLAY_TIMEOUT_MS` / `GENERATE_TIMEOUT_MS` | 60000 / 600000 | Godot process limits |

## Deploy
`PROJECT=<id> bash server/deploy.sh` from the repo root — idempotent (APIs, named DB + indexes,
runtime SA with `datastore.user` + `firebasecloudmessaging.admin` only, admin secret, image via
Cloud Build, Cloud Run, two scheduler jobs). Re-run to ship a new version.

## Curation (Bassel)
```
TOKEN=$(gcloud secrets versions access latest --secret=tinker-admin-token --project=<id>)
curl -H "x-admin-token: $TOKEN" $URL/admin/queue                        # what's coming
curl -H "x-admin-token: $TOKEN" $URL/admin/daily/2026-11-09/full         # inspect one
curl -X PUT -H "x-admin-token: $TOKEN" -H "content-type: application/json" \
     --data '{"level": {...}}' $URL/admin/daily/2026-11-09                # swap (must replay)
```
A level from `levels/campaign/*.json` can be swapped in as-is. A web curation page is a later task.

## Test locally
`bash tools/ci_daily.sh` — Firestore emulator, the 11 API tests (real Godot replay), then a full day:
real generator → seed → the game client plays it through the touch path → submit → board.
