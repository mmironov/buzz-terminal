#!/bin/bash
# Seed the running Firestore + Auth emulators with enough to drive the app.
#
#     firebase emulators:start --only firestore,auth --project swing-buzz
#     ./seed-emulator.sh
#
# `Authorization: Bearer owner` is the emulator's admin credential — it bypasses
# security rules the same way the Admin SDK does, which is what the roster import
# needs and what no client is ever allowed.
set -euo pipefail
PROJECT=${FIREBASE_PROJECT_ID:-swing-buzz}
AUTH=http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1
FS="http://127.0.0.1:8080/v1/projects/$PROJECT/databases/(default)/documents"
OWNER=(-H 'Authorization: Bearer owner' -H 'Content-Type: application/json')

# Wait for BOTH emulators. Checking only Firestore's port races the Auth
# emulator, and the failure looks like a JSON parse error rather than "not ready".
for _ in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8080 >/dev/null 2>&1 \
     && curl -sf "http://127.0.0.1:9099/emulator/v1/projects/$PROJECT/config" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -sf "http://127.0.0.1:9099/emulator/v1/projects/$PROJECT/config" >/dev/null 2>&1 \
  || { echo "Auth emulator not reachable on :9099 — is it running?" >&2; exit 1; }

staff() {  # email, role
  local uid
  uid=$(curl -s -X POST "$AUTH/accounts:signUp?key=fake" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"festival26\",\"returnSecureToken\":true}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('localId',''))")
  [ -z "$uid" ] && { echo "  $1 already exists, skipping"; return 0; }
  curl -s -X POST "$AUTH/projects/$PROJECT/accounts:update" "${OWNER[@]}" \
    -d "{\"localId\":\"$uid\",\"customAttributes\":\"{\\\"role\\\":\\\"$2\\\"}\"}" >/dev/null
  echo "  $1 → role=$2"
}

person() {  # id, name, ticketType, country, level
  curl -s -X PATCH "$FS/participants/$1" "${OWNER[@]}" -d "{\"fields\":{
    \"source\":{\"stringValue\":\"sheet\"},\"ticketRef\":{\"stringValue\":\"$1\"},
    \"name\":{\"stringValue\":\"$2\"},\"nameLower\":{\"stringValue\":\"$(echo "$2" | tr '[:upper:]' '[:lower:]')\"},
    \"ticketType\":{\"stringValue\":\"$3\"},\"country\":{\"stringValue\":\"$4\"},
    \"level\":{\"stringValue\":\"${5:-}\"},
    \"searchTokens\":{\"arrayValue\":{\"values\":[]}},
    \"braceletId\":{\"nullValue\":null},\"checkedInAt\":{\"nullValue\":null},
    \"balance\":{\"integerValue\":\"0\"},\"lastTxId\":{\"nullValue\":null},
    \"isBlocked\":{\"booleanValue\":false},\"blockReason\":{\"nullValue\":null}}}" >/dev/null
  echo "  $2 ($3, $4${5:+, $5})"
}

drink() {  # id, name, cents, order
  curl -s -X PATCH "$FS/drinks/$1" "${OWNER[@]}" -d "{\"fields\":{
    \"name\":{\"stringValue\":\"$2\"},\"price\":{\"integerValue\":\"$3\"},
    \"sortOrder\":{\"integerValue\":\"$4\"},\"isActive\":{\"booleanValue\":true}}}" >/dev/null
}

doorpass() {  # id, name, cents, order, kind
  curl -s -X PATCH "$FS/doorPasses/$1" "${OWNER[@]}" -d "{\"fields\":{
    \"name\":{\"stringValue\":\"$2\"},\"price\":{\"integerValue\":\"$3\"},
    \"sortOrder\":{\"integerValue\":\"$4\"},\"isActive\":{\"booleanValue\":true},
    \"kind\":{\"stringValue\":\"${5:-pass}\"}}}" >/dev/null
}

# admin@example.test is the web-admin panel's account. It has no terminal flow —
# `admin` is not a staff role — and signing into the iOS or Android app with it is
# correctly refused.
echo "staff:";        staff reception@example.test reception; staff bar@example.test bar
                      staff admin@example.test admin
echo "participants:"; person 1041 "Amélie Roux" "Full Pass" France Advanced
                      person 1042 "Tomás Herrera" "Party Pass" Spain Other
                      person 1043 "Nina Kowalski" "Full Pass Gold" Poland Pro
                      person 1044 "Karol Chrząszcz" "Full Pass" Poland Pro
# The real menu, matching DEFAULT_DRINKS in import-roster/firestore.mjs. An
# emulator that sells different drinks at different prices than production is a
# rehearsal for the wrong show.
echo "drinks:";       drink water "Water" 200 0; drink beer "Beer" 400 1
                      drink gt "Gin & Tonic" 600 2
                      echo "  3 drinks"
# The door catalogue. Without it reception cannot sell at the desk at all —
# `isWellFormedDoorPass` reads this collection as the sale is written.
echo "door passes:"
                      doorpass evening-ticket "Evening Ticket" 0 0 evening
                      doorpass party-pass "Party Pass" 12000 1
                      doorpass party-pass-plus "Party Pass Plus" 15500 2
                      doorpass full-pass "Full Pass" 20500 3
                      doorpass full-pass-gold "Full Pass Gold" 25900 4
                      doorpass jazz-performance-track "Jazz Performance Track" 18500 5
                      echo "  6 passes"
echo "done."
