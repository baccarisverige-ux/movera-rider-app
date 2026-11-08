#!/usr/bin/env bash
# PROOF ONLY (owner-approved, not for merge): install the staging APKs on a Google APIs
# emulator, open the app, and keep the Android system log. The Maps key is never printed.
set -uo pipefail
PKG=com.movera.rider
OUT=probe-out
mkdir -p "$OUT"
mask() { perl -pe 'BEGIN{$k=$ENV{MAPS_API_KEY}//""} s/\Q$k\E/[REDACTED]/g if length $k; s/AIza[0-9A-Za-z_\-]{20,}/[REDACTED]/g'; }
PATTERN='Google Maps|Google Android Maps SDK|Maps SDK|Authorization|API key|API_KEY|Google Maps Android API|Ensure that the following|SHA1|SHA-1|MapsInitializer|Failed to load map|API key not found|This API project is not authorized|ApiNotActivated|MapsApiSettings|DynamiteModule|com.google.android.gms.maps|GoogleMap|maps_flutter|zzca|Renderer|PERMISSION_DENIED|FATAL'

adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb emu geo fix 18.0686 59.3293 || true
echo "== Google Play services on emulator =="
adb shell dumpsys package com.google.android.gms | grep -m3 -E 'versionName|versionCode' || echo "no Play services package"

run_one() {
  name="$1"; apk="$2"
  echo "=================== $name ==================="
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  adb install -r "$apk" || { echo "install failed for $name"; return; }
  adb shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION || true
  adb shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION || true
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true
  adb logcat -c
  adb shell am start -W -n "$PKG/.MainActivity"
  sleep 30
  adb shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION || true
  adb exec-out screencap -p > "$OUT/$name-30s.png" || true
  sleep 30
  adb exec-out screencap -p > "$OUT/$name-60s.png" || true
  adb logcat -d -v threadtime | mask > "$OUT/$name-logcat-full.txt"
  { grep -E -i "$PATTERN" "$OUT/$name-logcat-full.txt"; echo "---- E-level lines ----"; grep -E '^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ E ' "$OUT/$name-logcat-full.txt"; } \
    | mask > "$OUT/$name-logcat-filtered.txt"
  echo "---- $name: filtered Maps/auth lines (key masked) ----"
  grep -E -i "$PATTERN" "$OUT/$name-logcat-full.txt" | mask | head -300
  echo "---- $name: E-level lines (first 200, key masked) ----"
  grep -E '^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ E ' "$OUT/$name-logcat-full.txt" | mask | head -200
  echo "---- $name: app process alive? ----"
  adb shell pidof "$PKG" || echo "app not running"
}

# A: the exact staging test APK (sign-in required, so the map may not be created before sign-in).
run_one A-staging-exact out/A-staging-exact.apk
# B: same build, same key and signing, but MOVERA_AUTH_REQUIRED=false so Home (with the map) opens without sign-in.
run_one B-staging-no-signin out/B-staging-no-signin.apk
exit 0
