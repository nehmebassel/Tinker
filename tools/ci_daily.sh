#!/usr/bin/env bash
# Full Daily cycle on a throwaway staging backend: Firestore emulator + tinker-api (real Godot replay)
# + the game client under Xvfb. Used by CI and runnable locally from the repo root:  bash tools/ci_daily.sh
set -euo pipefail
JAR=$(ls ~/.cache/firebase/emulators/cloud-firestore-emulator-*.jar | head -1)
java -jar "$JAR" --host=127.0.0.1 --port=8081 >/tmp/emu.log 2>&1 &
EMU=$!
trap 'kill $EMU $SRV 2>/dev/null || true' EXIT
until curl -s -m 2 http://127.0.0.1:8081/ >/dev/null; do sleep 1; done
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 GOOGLE_CLOUD_PROJECT=tinker-ci ADMIN_TOKEN=ci-admin GODOT_BIN=godot
echo "== server API tests"
(cd server && npm test)
echo "== staging server"
(cd server && PORT=8090 node src/index.js >/tmp/srv.log 2>&1) &
SRV=$!
until curl -s -m 2 http://127.0.0.1:8090/health >/dev/null; do sleep 1; done
echo "== generate today with the REAL generator, keep only if it is a one-part level"
TODAY=$(date -u +%F)
for salt in 0 1 2 3 4 5 6 7; do
  godot --headless --fixed-fps 60 --path game -s res://tests/gen_daily.gd -- --date="$TODAY" --out=/tmp/today.json --seed-salt=$salt | grep '^{' | tail -1
  n=$(python3 -c "import json;print(len(json.load(open('/tmp/today.json'))['reference_solution']))")
  [ "$n" = "1" ] && break
done
python3 - <<'PY'
import json
d = json.load(open('/tmp/today.json'))
json.dump(d['reference_solution'], open('/tmp/daily_sol.json', 'w'))
for k in ('generator', 'expect'):
    d.pop(k, None)
json.dump({'level': d}, open('/tmp/seed.json', 'w'))
PY
curl -fsS -X PUT -H "content-type: application/json" -H "x-admin-token: ci-admin" --data @/tmp/seed.json "http://127.0.0.1:8090/admin/daily/$TODAY"; echo
echo "== game client plays the day"
timeout 300 xvfb-run -a -s "-screen 0 1200x2100x24" godot --path game --rendering-driver opengl3 --resolution 540x960 \
  --quit-after 12000 -- --server=http://127.0.0.1:8090 --daily-flow=/tmp/daily_sol.json 2>&1 | tee /tmp/daily.log | grep -E "ok  |FAIL|DAILY"
grep -q "DAILY PASS" /tmp/daily.log
