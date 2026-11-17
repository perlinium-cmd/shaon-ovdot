#!/bin/zsh
# The Mac's real write path (ShaonTests/EmulatorRulesTests) against the local Firestore + Auth emulators with a rules
# file: every delete the Mac makes must be accepted, each with an exact copy in the recycle bin.
# Nothing here touches the real data: the tests use their own "demo-" project, served only by the local emulators.
#
#   tools/emulator-test.sh [rules file]      default: firestore.rules at the repo root
#   SHAON_SEED_FILE=~/Library/Application\ Support/ShaonMac/backups/<file>.json tools/emulator-test.sh
#       also copies that backup into the emulator and deletes every employee, shift and payment in it (emulator only).
# Ports: SHAON_FIRESTORE_PORT (default 8181; 8080 is often taken by another project's dev server), SHAON_AUTH_PORT (9099).
set -euo pipefail
cd "${0:A:h}/.."
RULES="${1:-../firestore.rules}"; RULES="${RULES:A}"
FS_PORT="${SHAON_FIRESTORE_PORT:-8181}"; AUTH_PORT="${SHAON_AUTH_PORT:-9099}"
DERIVED="$HOME/Library/Caches/ShaonMacBuild"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$RULES" "$TMP/firestore.rules"
cat > "$TMP/firebase.json" <<JSON
{ "firestore": { "rules": "firestore.rules" },
  "emulators": { "firestore": { "port": $FS_PORT }, "auth": { "port": $AUTH_PORT }, "ui": { "enabled": false } } }
JSON

xcodegen generate --spec tools/project-local.yml --project-root "$PWD" --project "$PWD" --quiet
xcodebuild -project ShaonMacLocal.xcodeproj -scheme ShaonMac -derivedDataPath "$DERIVED" -resolvePackageDependencies -quiet
python3 tools/patch-deps.py "$DERIVED/SourcePackages/checkouts"   # Firebase Auth keychain without a profile

export TEST_RUNNER_SHAON_EMULATOR=1 TEST_RUNNER_SHAON_FIRESTORE_PORT=$FS_PORT TEST_RUNNER_SHAON_AUTH_PORT=$AUTH_PORT
[[ -n "${SHAON_SEED_FILE:-}" ]] && export TEST_RUNNER_SHAON_SEED="$(<"$SHAON_SEED_FILE")"
cat > "$TMP/run.sh" <<RUN
xcodebuild test -project "$PWD/ShaonMacLocal.xcodeproj" -scheme ShaonMac -derivedDataPath "$DERIVED" \
  -destination platform=macOS -only-testing:ShaonTests/EmulatorRulesTests
RUN
echo "rules: $RULES"
npx -y firebase-tools@15 emulators:exec --config "$TMP/firebase.json" --only firestore,auth --project demo-shaon "sh '$TMP/run.sh'"
