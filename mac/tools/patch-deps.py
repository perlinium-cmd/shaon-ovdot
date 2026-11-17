#!/usr/bin/env python3
"""Patch SwiftPM checkouts so Firebase Auth and GoogleSignIn use the file-based (legacy)
macOS keychain instead of the data protection keychain.

Why: the data protection keychain needs a restricted entitlement (keychain-access-groups),
which only a provisioning profile can grant. A free Apple account's profile expires after
7 days and the app then refuses to launch. With these patches the app needs no profile and
is signed with a permanent local certificate, so it never expires.

Each patch is an exact-text replacement. If a library update changes the text, this script
exits non-zero and the build stops - the installed app is never replaced with an unpatched one.
Usage: patch-deps.py <SourcePackages/checkouts dir>
"""
import sys
from pathlib import Path

MARK = "SHAON-PATCH"

FIREBASE_FILE = "firebase-ios-sdk/FirebaseAuth/Sources/Swift/Storage/AuthKeychainStorageReal.swift"
FIREBASE_EDITS = [
    ("return SecItemCopyMatching(query as CFDictionary, &result)",
     "return SecItemCopyMatching(shaonFileKeychain(query) as CFDictionary, &result)"),
    ("return SecItemAdd(query as CFDictionary, nil)",
     "return SecItemAdd(shaonFileKeychain(query) as CFDictionary, nil)"),
    ("SecItemUpdate(query as CFDictionary, attributes as CFDictionary)",
     "SecItemUpdate(shaonFileKeychain(query) as CFDictionary,\n"
     "                  shaonFileKeychain(attributes) as CFDictionary)"),
    ("return SecItemDelete(query as CFDictionary)",
     "return SecItemDelete(shaonFileKeychain(query) as CFDictionary)"),
]
FIREBASE_APPEND = f"""
// {MARK}: on macOS use the file-based keychain, which needs no provisioning profile.
// kSecAttrAccessible is only valid with the data protection keychain, so drop it too.
private func shaonFileKeychain(_ query: [String: Any]) -> [String: Any] {{
  #if os(macOS)
    var q = query
    q.removeValue(forKey: kSecUseDataProtectionKeychain as String)
    q.removeValue(forKey: kSecAttrAccessible as String)
    return q
  #else
    return query
  #endif
}}
"""

GTM_FILE = "GTMAppAuth/GTMAppAuth/Sources/KeychainStore/KeychainStore.swift"
GTM_OLD = "    self.init(itemName: itemName, keychainHelper: KeychainWrapper())\n"
# The file-based keychain is shared by all apps, and GoogleSignIn's item name is the generic
# "auth" - another app on this Mac already owns an "auth"/"OAuth" item, so prefix the bundle id.
GTM_NEW = f"""    // {MARK} v2: on macOS use the library's own file-based keychain mode (no profile needed),
    // under an app-specific item name (the file-based keychain is shared by all apps).
    #if os(macOS)
    self.init(itemName: "\\(Bundle.main.bundleIdentifier ?? "app").\\(itemName)",
              keychainAttributes: [KeychainAttribute.useFileBasedKeychain])
    #else
    self.init(itemName: itemName, keychainHelper: KeychainWrapper())
    #endif
"""
# Earlier patch versions that may still be in a cached checkout; upgraded in place.
GTM_PREVIOUS = [f"""    // {MARK}: on macOS use the library's own file-based keychain mode (no profile needed).
    #if os(macOS)
    self.init(itemName: itemName, keychainAttributes: [KeychainAttribute.useFileBasedKeychain])
    #else
    self.init(itemName: itemName, keychainHelper: KeychainWrapper())
    #endif
"""]


def fail(msg):
    print(f"patch-deps: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def write(p, text):
    # Xcode leaves package checkouts read-only.
    p.chmod(p.stat().st_mode | 0o200)
    p.write_text(text)


def patch_firebase(root):
    p = root / FIREBASE_FILE
    if not p.exists():
        fail(f"missing {p}")
    s = p.read_text()
    if MARK in s:
        print("patch-deps: Firebase Auth already patched")
        return
    for old, new in FIREBASE_EDITS:
        if s.count(old) != 1:
            fail(f"Firebase Auth changed - expected exactly one '{old}' in {p.name}")
        s = s.replace(old, new)
    write(p, s + FIREBASE_APPEND)
    print("patch-deps: Firebase Auth patched")


def patch_gtm(root):
    p = root / GTM_FILE
    if not p.exists():
        fail(f"missing {p}")
    s = p.read_text()
    if GTM_NEW in s:
        print("patch-deps: GTMAppAuth already patched")
        return
    for prev in GTM_PREVIOUS:
        if prev in s:
            s = s.replace(prev, GTM_OLD)
    if s.count(GTM_OLD) != 1:
        fail(f"GTMAppAuth changed - expected the default initializer in {p.name}")
    write(p, s.replace(GTM_OLD, GTM_NEW))
    print("patch-deps: GTMAppAuth patched")


def verify(root):
    if MARK not in (root / FIREBASE_FILE).read_text():
        fail(f"patch missing after build in {FIREBASE_FILE}")
    if GTM_NEW not in (root / GTM_FILE).read_text():
        fail(f"patch missing after build in {GTM_FILE}")
    print("patch-deps: patches verified")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        fail("usage: patch-deps.py <checkouts dir> [--verify]")
    root = Path(sys.argv[1])
    if "--verify" in sys.argv:
        verify(root)
    else:
        patch_firebase(root)
        patch_gtm(root)
