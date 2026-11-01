#!/usr/bin/env bash
# Deploys tinker-api to Cloud Run with its own Firestore database, secret, service account and
# scheduler jobs. Idempotent: safe to re-run; each step skips what already exists.
#
#   PROJECT=my-project REGION=europe-west1 bash server/deploy.sh          (from the repo root)
#
# Every name below can be overridden by env. Runtime settings (push text, board size, rate limits,
# epoch...) are Cloud Run env vars, editable in the Cloud Run console without redeploying code.
set -euo pipefail
PROJECT=${PROJECT:?set PROJECT}
REGION=${REGION:-europe-west1}
SERVICE=${SERVICE:-tinker-api}
DB=${DB:-tinker}
REPO=${REPO:-tinker}
RUNTIME_SA_NAME=${RUNTIME_SA_NAME:-tinker-api}
SCHED_TZ=${SCHED_TZ:-Etc/UTC}
GENERATE_CRON=${GENERATE_CRON:-"10 22 * * *"}   # pre-generate the coming week, nightly
NOTIFY_CRON=${NOTIFY_CRON:-"5 7 * * *"}         # "today's puzzle is ready" (07:05 UTC = 09:05 Beirut)
G="gcloud --project=$PROJECT --quiet"
RUNTIME_SA="$RUNTIME_SA_NAME@$PROJECT.iam.gserviceaccount.com"
IMAGE="$REGION-docker.pkg.dev/$PROJECT/$REPO/$SERVICE:$(git rev-parse --short HEAD)"
step() { echo; echo "== $*"; }

step "APIs"
$G services enable run.googleapis.com firestore.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com cloudscheduler.googleapis.com secretmanager.googleapis.com fcm.googleapis.com

step "Firestore database '$DB' ($REGION)"
if ! $G firestore databases describe --database="$DB" >/dev/null 2>&1; then
  $G firestore databases create --database="$DB" --location="$REGION" --type=firestore-native
fi
# Composite indexes for the boards (from server/firestore.indexes.json).
python3 - "$PROJECT" "$DB" <<'PY' | while read -r args; do eval "$G firestore indexes composite create --database=$DB $args" 2>&1 | grep -vE "already exists|ALREADY_EXISTS" || true; done
import json, sys
for ix in json.load(open("server/firestore.indexes.json"))["indexes"]:
    fields = " ".join("--field-config=field-path=%s,order=%s" % (f["fieldPath"], f["order"].lower()) for f in ix["fields"])
    print("--collection-group=%s --query-scope=%s %s --async" % (ix["collectionGroup"], ix["queryScope"].lower(), fields))
PY

step "Runtime service account $RUNTIME_SA"
$G iam service-accounts describe "$RUNTIME_SA" >/dev/null 2>&1 || \
  $G iam service-accounts create "$RUNTIME_SA_NAME" --display-name="Tinker API runtime"
for role in roles/datastore.user roles/firebasecloudmessaging.admin; do
  $G projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$RUNTIME_SA" --role="$role" --condition=None >/dev/null
done

step "Admin token secret"
if ! $G secrets describe tinker-admin-token >/dev/null 2>&1; then
  head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 40 | $G secrets create tinker-admin-token --data-file=- --replication-policy=automatic
fi
$G secrets add-iam-policy-binding tinker-admin-token --member="serviceAccount:$RUNTIME_SA" --role=roles/secretmanager.secretAccessor >/dev/null

step "Client builds (web PWA + Android APK)"
bash tools/build_clients.sh

step "Artifact Registry + image $IMAGE"
$G artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 || \
  $G artifacts repositories create "$REPO" --location="$REGION" --repository-format=docker
$G builds submit --region="$REGION" --config server/cloudbuild.yaml --substitutions=_IMAGE="$IMAGE" .

step "Cloud Run $SERVICE"
$G run deploy "$SERVICE" --region="$REGION" --image="$IMAGE" --service-account="$RUNTIME_SA" \
  --allow-unauthenticated --execution-environment=gen2 --cpu=2 --memory=2Gi --concurrency=4 --timeout=3600 --min-instances=0 --max-instances=5 \
  --set-env-vars="GOOGLE_CLOUD_PROJECT=$PROJECT,FIRESTORE_DATABASE=$DB" \
  --update-secrets="ADMIN_TOKEN=tinker-admin-token:latest"
URL=$($G run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')
echo "URL: $URL"

step "Scheduler jobs"
TOKEN=$($G secrets versions access latest --secret=tinker-admin-token)
for job in "tinker-generate|$GENERATE_CRON|/admin/generate?days=7|1800s" "tinker-notify|$NOTIFY_CRON|/admin/notify|60s"; do
  IFS='|' read -r name cron path deadline <<<"$job"
  verb=create; hdr=--headers
  if $G scheduler jobs describe "$name" --location="$REGION" >/dev/null 2>&1; then verb=update; hdr=--update-headers; fi
  $G scheduler jobs $verb http "$name" --location="$REGION" --schedule="$cron" --time-zone="$SCHED_TZ" \
    --uri="$URL$path" --http-method=POST $hdr="x-admin-token=$TOKEN" --attempt-deadline="$deadline" >/dev/null
  echo "  $name: $cron -> $path"
done

step "Smoke"
curl -fsS "$URL/health"; echo
echo "Done. Generate now:  curl -X POST -H \"x-admin-token: \$(gcloud secrets versions access latest --secret=tinker-admin-token --project=$PROJECT)\" \"$URL/admin/generate?days=7\""
