#!/bin/bash
# Publishes a new version of the employee Android app. The phones see it by themselves ("יש גרסה חדשה").
#
#   1. bump versionCode (+1) and versionName in android/app/build.gradle.kts
#   2. tools/release-android.sh
#   3. commit public/android/latest.json with the change, open a PR, merge -> the Deploy workflow puts it on
#      https://shaon-ovdot-2c10.web.app/android/latest.json and every phone offers the update the next time the app opens.
#
# The APK itself goes to a release on the public repo perlinium-cmd/shaon-android (Firebase's free plan refuses APKs).
# Link for a first install (redirects to the newest release): https://shaon-ovdot-2c10.web.app/android/shaon.apk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/app/build.gradle.kts"
OUT="$ROOT/public/android"
KEEP="$HOME/.shaon"
REPO="perlinium-cmd/shaon-android"
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
cp "$APK" "$KEEP/שעון-עובדות-$name.apk"
STAGE="$(mktemp -d)"
cp "$APK" "$STAGE/shaon.apk"            # the asset name the links rely on
sha="$(shasum -a 256 "$STAGE/shaon.apk" | cut -d' ' -f1)"
size="$(stat -f%z "$STAGE/shaon.apk")"

echo "== Publishing release v$name on $REPO"
gh release create "v$name" "$STAGE/shaon.apk" --repo "$REPO" --title "$name" --notes "Employee app $name (versionCode $code)."
url="https://github.com/$REPO/releases/download/v$name/shaon.apk"
[ "$(curl -sfL "$url" | shasum -a 256 | cut -d' ' -f1)" = "$sha" ] \
  || { echo "The published APK does not match – stopping before latest.json is written."; exit 1; }

cat > "$OUT/latest.json" <<EOF
{
  "versionCode": $code,
  "versionName": "$name",
  "url": "$url",
  "sha256": "$sha",
  "size": $size
}
EOF

echo
echo "Ready: release v$name ($size bytes) is on $REPO, latest.json written, copy kept in $KEEP."
echo "Next: commit public/android/latest.json and android/app/build.gradle.kts, open a PR, merge. Phones update from there."
