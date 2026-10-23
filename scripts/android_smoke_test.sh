#!/usr/bin/env bash
set -euo pipefail

adb_bin=${BASTION_SMOKE_ADB:-adb}
attempts=${BASTION_SMOKE_ATTEMPTS:-30}
package=com.bastionmesh.connect
# The Kotlin namespace stays com.bastionmesh.bastion (from flutter create),
# so the activity is named in full rather than relative to the app ID.
activity="$package/com.bastionmesh.bastion.MainActivity"

# Preserve startup diagnostics even when launch or process checks fail.
collect_diagnostics() {
  "$adb_bin" logcat -d > emulator-log.txt || true
  "$adb_bin" exec-out screencap -p > emulator-screen.png || true
}
trap collect_diagnostics EXIT

"$adb_bin" install -r build/app/outputs/flutter-apk/app-debug.apk
"$adb_bin" shell pm list packages | grep -Fx "package:$package"
"$adb_bin" logcat -c
"$adb_bin" shell am start -W -n "$activity" > emulator-launch.txt || true

# Android's am wait can time out before a cold Flutter app draws its frame.
# Require the actual activity to display, rather than treating that timeout
# as success or repeatedly launching it.
displayed=false
for ((attempt=0; attempt<attempts; attempt++)); do
  "$adb_bin" logcat -d > emulator-log.txt
  if grep -F "Displayed $activity" emulator-log.txt; then
    displayed=true
    break
  fi
  sleep 2
done
if [[ "$displayed" != true ]]; then
  echo 'NOTORYX Connect did not display its first activity within the startup window.' >&2
  exit 1
fi

sleep 5
app_pid=$("$adb_bin" shell pidof "$package" | tr -d '\r')
test -n "$app_pid"
"$adb_bin" logcat --pid="$app_pid" -d > emulator-process-log.txt
if grep -q 'FATAL EXCEPTION' emulator-process-log.txt; then
  echo 'NOTORYX Connect crashed during startup.' >&2
  exit 1
fi
