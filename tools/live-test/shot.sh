#!/bin/zsh
# Screenshot of the emulator + the on-screen texts and tap targets (bounds in real pixels).
# usage: tools/live-test/shot.sh <name> [outdir]   -> <outdir>/<name>.png (1000px high; multiply by 2.4 for taps on 1080x2400)
D=${0:A:h}; OUT=${2:-${TMPDIR:-/tmp}}
adb exec-out screencap -p > $OUT/$1.png && sips -Z 1000 $OUT/$1.png >/dev/null && echo "$OUT/$1.png"
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml | python3 $D/ui.py
