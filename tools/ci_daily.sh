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

echo "== sandbox: phone A builds + publishes, phone B (separate install) plays the link and remixes"
A=$(mktemp -d); B=$(mktemp -d)
XDG_DATA_HOME=$A timeout 300 xvfb-run -a -s "-screen 0 1200x2100x24" godot --path game --rendering-driver opengl3 --resolution 540x960 \
  --quit-after 12000 -- --server=http://127.0.0.1:8090 --sandbox-publish=/tmp/sandbox_code.txt 2>&1 | tee /tmp/sbA.log | grep -E "ok  |FAIL|SANDBOX"
grep -q "SANDBOX PASS" /tmp/sbA.log
CODE=$(cat /tmp/sandbox_code.txt)
[ "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://127.0.0.1:8090/l/$CODE)" = "302 http://127.0.0.1:8090/play/?level=$CODE" ]
XDG_DATA_HOME=$B timeout 300 xvfb-run -a -s "-screen 0 1200x2100x24" godot --path game --rendering-driver opengl3 --resolution 540x960 \
  --quit-after 12000 -- --server=http://127.0.0.1:8090 --sandbox-play=$CODE 2>&1 | tee /tmp/sbB.log | grep -E "ok  |FAIL|SANDBOX"
grep -q "SANDBOX PASS" /tmp/sbB.log
rm -rf "$A" "$B"

echo "== economy: daily bonus, board drawer with test users, TEST purchase, rewarded ad -> try, try for coins, hint"
curl -fsS -X POST -H "x-admin-token: ci-admin" http://127.0.0.1:8090/admin/test-users >/dev/null
E=$(mktemp -d)
XDG_DATA_HOME=$E timeout 300 xvfb-run -a -s "-screen 0 1200x2100x24" godot --path game --rendering-driver opengl3 --resolution 540x960 \
  --quit-after 12000 -- --server=http://127.0.0.1:8090 --economy-flow 2>&1 | tee /tmp/econ.log | grep -E "ok  |FAIL|ECON|SCRIPT ERROR"
grep -q "ECON PASS" /tmp/econ.log
# The ledger saw the TEST purchase and the house ad, and the admin console page is served.
curl -fsS -H "x-admin-token: ci-admin" "http://127.0.0.1:8090/admin/ledger?days=1" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['totals']['test']>=0.99, d['totals']; print('ledger ok', d['totals'])"
curl -fsS http://127.0.0.1:8090/admin/ui | grep -q "Tinker admin"
rm -rf "$E"
