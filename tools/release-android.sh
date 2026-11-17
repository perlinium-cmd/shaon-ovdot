#!/bin/bash
# Publishes a new version of the employee Android app. The phones see it by themselves ("יש גרסה חדשה").
#
#   1. bump versionCode (+1) and versionName in android/app/build.gradle.kts
#   2. tools/release-android.sh
#   3. commit public/android/ with the change, open a PR, merge -> the Deploy workflow puts it on
#      https://shaon-ovdot-2c10.web.app/android/ and every phone offers the update the next time the app opens.
#
# The same address is also the link for a first install: https://shaon-ovdot-2c10.web.app/android/shaon.apk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/app/build.gradle.kts"
OUT="$ROOT/public/android"
KEEP="$HOME/.shaon"
CERT="50aa5fb63125f6a2ab20919012eef88f63d7798a3e7fdd666b23290b4625ab37"   # the release key (never replace it)
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner | sort -V | tail -1)"

code="$(sed -nE 's/^ *versionCode = ([0-9]+).*/\1/p' "$GRADLE")"
name="$(sed -nE 's/^ *versionName = "([^"]+)".*/\1/p' "$GRADLE")"
[ -n "$code" ] && [ -n "$name" ] || { echo "versionCode/versionName not found in $GRADLE"; exit 1; }

published=0
if [ -f "$OUT/latest.json" ]; then
  published="$(sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' "$OUT/latest.json")"
fi
if [ "$code" -le "$published" ]; then
  echo "versionCode $code is not higher than the published $published: bump it in $GRADLE first."
  exit 1
fi

echo "== Building $name (versionCode $code) with the release key"
cd "$ROOT/android"
./gradlew :app:testDebugUnitTest :app:assembleRelease --console=plain -q
APK="$ROOT/android/app/build/outputs/apk/release/app-release.apk"

echo "== Checking the signature"
"$APKSIGNER" verify --print-certs "$APK" | grep -q "SHA-256 digest: $CERT" \
  || { echo "NOT signed with the release key – stopping (phones would refuse this update)."; exit 1; }

mkdir -p "$OUT" "$KEEP"
cp "$APK" "$OUT/shaon.apk"
cp "$APK" "$KEEP/שעון-עובדות-$name.apk"
sha="$(shasum -a 256 "$OUT/shaon.apk" | cut -d' ' -f1)"
size="$(stat -f%z "$OUT/shaon.apk")"
cat > "$OUT/latest.json" <<EOF
{
  "versionCode": $code,
  "versionName": "$name",
  "url": "shaon.apk",
  "sha256": "$sha",
  "size": $size
}
EOF

echo
echo "Ready: public/android/shaon.apk ($name, $size bytes) + latest.json, copy kept in $KEEP."
echo "Next: commit public/android/ and android/app/build.gradle.kts, open a PR, merge. Phones update from there."
