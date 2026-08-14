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

person() {  # id, name, ticketType, country
  curl -s -X PATCH "$FS/participants/$1" "${OWNER[@]}" -d "{\"fields\":{
    \"source\":{\"stringValue\":\"sheet\"},\"ticketRef\":{\"stringValue\":\"$1\"},
    \"name\":{\"stringValue\":\"$2\"},\"nameLower\":{\"stringValue\":\"$(echo "$2" | tr '[:upper:]' '[:lower:]')\"},
    \"ticketType\":{\"stringValue\":\"$3\"},\"country\":{\"stringValue\":\"$4\"},
    \"searchTokens\":{\"arrayValue\":{\"values\":[]}},
    \"braceletId\":{\"nullValue\":null},\"checkedInAt\":{\"nullValue\":null},
    \"balance\":{\"integerValue\":\"0\"},\"lastTxId\":{\"nullValue\":null},
    \"isBlocked\":{\"booleanValue\":false},\"blockReason\":{\"nullValue\":null}}}" >/dev/null
  echo "  $2 ($3, $4)"
}

drink() {  # id, name, cents, order
  curl -s -X PATCH "$FS/drinks/$1" "${OWNER[@]}" -d "{\"fields\":{
    \"name\":{\"stringValue\":\"$2\"},\"price\":{\"integerValue\":\"$3\"},
    \"sortOrder\":{\"integerValue\":\"$4\"},\"isActive\":{\"booleanValue\":true}}}" >/dev/null
}

echo "staff:";        staff reception@example.test reception; staff bar@example.test bar
echo "participants:"; person 1041 "Amélie Roux" "Full Pass" France
                      person 1042 "Tomás Herrera" "Party Pass" Spain
                      person 1043 "Nina Kowalski" "Full Pass Gold" Poland
echo "drinks:";       drink beer "Draught beer" 400 0; drink gt "Gin & tonic" 800 1
                      echo "  2 drinks"
echo "done."
