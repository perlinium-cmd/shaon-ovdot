#!/bin/zsh
# Builds ShaonMac and installs it to /Applications - signed like the Perli app: developer
# certificate, NO provisioning profile, so the installed app never expires.
#  - Firebase Auth / GoogleSignIn are patched to keep the login in the file-based keychain,
#    which needs no restricted entitlement (tools/patch-deps.py).
#  - The widget target is excluded and the app group is off (tools/project-local.yml).
#  - Replaced apps are kept in dated folders in ~/Library/Application Support/ShaonMac/previous
#    (newest 3).
# Every check must pass before /Applications is touched.
# Usage: tools/build-local.sh [--no-install]   (--no-install: build and check only; /Applications is not touched)
set -euo pipefail
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

cd "${0:A:h}/.."
DERIVED="$HOME/Library/Caches/ShaonMacBuild"
CHECKOUTS="$DERIVED/SourcePackages/checkouts"
BACKUP_DIR="$HOME/Library/Application Support/ShaonMac/previous"

xcodegen generate --spec tools/project-local.yml --project-root "$PWD" --project "$PWD" --quiet

# Each step uses "|| return 1": set -e does not apply inside a function called from "if !".
build() {
  xcodebuild -project ShaonMacLocal.xcodeproj -scheme ShaonMac -derivedDataPath "$DERIVED" \
    -resolvePackageDependencies || return 1
  python3 tools/patch-deps.py "$CHECKOUTS" || return 1
  xcodebuild -project ShaonMacLocal.xcodeproj -scheme ShaonMac -configuration Release \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS' clean build || return 1
  python3 tools/patch-deps.py "$CHECKOUTS" --verify || return 1
}
# Package artifacts in the cache can end up half-downloaded (e.g. an interrupted run);
# if the build fails, wipe the cache and retry once from scratch.
if ! build; then
  echo "Build failed - wiping $DERIVED and retrying once"
  rm -rf "$DERIVED"
  build
fi

APP="$DERIVED/Build/Products/Release/ShaonMac.app"
codesign --verify --deep --strict "$APP"
if [[ -e "$APP/Contents/embedded.provisionprofile" ]]; then
  echo "ERROR: build contains a provisioning profile - it would expire"; exit 1
fi
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q -E "keychain-access-groups|application-identifier"; then
  echo "ERROR: build has a restricted entitlement - it would need a provisioning profile"; exit 1
fi

if (( ! INSTALL )); then echo "Built and checked (not installed): $APP"; exit 0; fi

osascript -e 'tell application "ShaonMac" to quit' 2>/dev/null || true
sleep 2
if [[ -d /Applications/ShaonMac.app ]]; then
  # Keep the replaced app in a dated folder; keep only the 3 newest backups.
  STAMP_DIR="$BACKUP_DIR/$(date +%Y-%m-%d_%H%M%S)"
  mkdir -p "$STAMP_DIR"
  BACKUP="$STAMP_DIR/ShaonMac.app"
  mv /Applications/ShaonMac.app "$BACKUP"
  backups=("$BACKUP_DIR"/20*(N/On))   # dated folders, newest first
  for old in "${backups[@]:3}"; do rm -rf "$old"; done
fi
ditto "$APP" /Applications/ShaonMac.app
echo "Installed (no provisioning profile - does not expire). Previous app: ${BACKUP:-none}"
