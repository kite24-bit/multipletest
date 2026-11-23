#!/usr/bin/env bash
#
# Jalankan flow Maestro (.maestro/flows/*) secara PARALEL dan HEADLESS.
#
# Cara kerja:
#   1. (opsional) Nyalakan N emulator Android tanpa jendela (-no-window).
#   2. Siapkan emulator untuk test: matikan dialog crash sistem & animasi.
#   3. Build APK debug sekali, lalu install ke semua device.
#   4. Warm-up driver Maestro di tiap device (hasil diabaikan).
#   5. `maestro test --shard-split N`: flow dibagi ke N device dan dijalankan
#      bersamaan. Tiap flow hanya jalan sekali, di salah satu device.
#   6. Laporan JUnit + screenshot/log disimpan di build/maestro/.
#
# Pemakaian:
#   ./scripts/run_maestro_parallel.sh                   # pakai device yang sudah terhubung
#   EMULATORS=2 ./scripts/run_maestro_parallel.sh       # nyalakan 2 emulator headless dulu
#   EMULATORS=3 AVD=Pixel_8 ./scripts/run_maestro_parallel.sh
#   SKIP_BUILD=1 ./scripts/run_maestro_parallel.sh      # pakai APK hasil build sebelumnya
#   TAGS=smoke ./scripts/run_maestro_parallel.sh        # hanya flow dengan tag tertentu
#   KEEP_EMULATORS=1 ...                                # jangan matikan emulator di akhir
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_APK="build/app/outputs/flutter-apk/app-debug.apk"
OUT_DIR="build/maestro"
EMULATORS="${EMULATORS:-0}"
AVD="${AVD:-Medium_Phone}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

export PATH="$PATH:$HOME/.maestro/bin:$SDK/emulator:$SDK/platform-tools"
export MAESTRO_CLI_NO_ANALYTICS=1

mkdir -p "$OUT_DIR"

connected_devices() {
  adb devices | awk 'NR>1 && $2=="device" {print $1}'
}

# --- 1. Emulator headless ----------------------------------------------------
# Catatan: bash 3.2 (bawaan macOS) + `set -u` menganggap array kosong "unbound",
# jadi array selalu diekspansi dengan pola ${arr[@]+"${arr[@]}"}.
STARTED=()
cleanup() {
  if [[ -n "${STARTED[*]:-}" && -z "${KEEP_EMULATORS:-}" ]]; then
    echo "▶ Mematikan emulator: ${STARTED[*]}"
    for serial in "${STARTED[@]}"; do adb -s "$serial" emu kill >/dev/null 2>&1 || true; done
    # `emu kill` asinkron: tunggu sampai benar-benar hilang dari adb.
    for serial in "${STARTED[@]}"; do
      for _ in $(seq 1 30); do connected_devices | grep -qx "$serial" || break; sleep 1; done
    done
  fi
}
trap cleanup EXIT

if [[ "$EMULATORS" -gt 0 ]]; then
  for ((i = 0; i < EMULATORS; i++)); do
    port=$((5554 + i * 2))
    serial="emulator-$port"
    if connected_devices | grep -qx "$serial"; then
      echo "• $serial sudah jalan, dipakai ulang"
      continue
    fi
    echo "▶ Menyalakan $serial (headless, AVD=$AVD)"
    # -read-only: boleh menjalankan beberapa instance dari AVD yang sama.
    emulator -avd "$AVD" -port "$port" -read-only -no-window -no-audio \
      -no-boot-anim -no-snapshot-save \
      >"$OUT_DIR/emulator-$port.log" 2>&1 &
    STARTED+=("$serial")
  done
  for serial in ${STARTED[@]+"${STARTED[@]}"}; do
    adb -s "$serial" wait-for-device
    until [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
      sleep 2
    done
    echo "✓ $serial siap"
  done
fi

DEVICES=()
while IFS= read -r serial; do DEVICES+=("$serial"); done < <(connected_devices)
if [[ ${#DEVICES[@]} -eq 0 ]]; then
  echo "Tidak ada device Android. Jalankan dengan EMULATORS=2 untuk menyalakan emulator headless." >&2
  exit 1
fi
SHARDS=${#DEVICES[@]}
echo "▶ ${SHARDS} device: ${DEVICES[*]}"

# --- 2. Siapkan emulator -----------------------------------------------------
# Emulator yang baru boot sering memunculkan dialog "<app> keeps stopping"
# (mis. Google Play Store) yang menutupi aplikasi dan membuat flow gagal palsu.
# Hanya diterapkan ke emulator, bukan ke HP fisik.
for serial in "${DEVICES[@]}"; do
  [[ "$serial" == emulator-* ]] || continue
  adb -s "$serial" shell settings put global hide_error_dialogs 1
  for key in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb -s "$serial" shell settings put global "$key" 0
  done
done

# --- 3. Build & install ------------------------------------------------------
if [[ -z "${SKIP_BUILD:-}" ]]; then
  flutter build apk --debug
fi
# Tunggu PID install saja; `wait` polos juga akan menunggu proses emulator.
INSTALL_PIDS=()
for serial in "${DEVICES[@]}"; do
  adb -s "$serial" install -r -t "$APP_APK" >/dev/null &
  INSTALL_PIDS+=("$!")
done
for pid in "${INSTALL_PIDS[@]}"; do wait "$pid"; done
echo "✓ APK terpasang di semua device"

# --- 4. Warm-up --------------------------------------------------------------
# Sesi Maestro pertama di emulator yang baru boot bisa lambat (install driver,
# start app pertama kali). Jalankan satu flow warm-up per device secara
# paralel dan abaikan hasilnya.
echo "▶ Warm-up driver Maestro di semua device"
WARM_PIDS=()
for serial in "${DEVICES[@]}"; do
  maestro --device "$serial" test .maestro/setup/warmup.yaml \
    >"$OUT_DIR/warmup-$serial.log" 2>&1 &
  WARM_PIDS+=("$!")
done
for pid in "${WARM_PIDS[@]}"; do wait "$pid" || true; done

# --- 5. Jalankan Maestro secara paralel -------------------------------------
rm -rf "$OUT_DIR/results" && mkdir -p "$OUT_DIR/results"

ARGS=(test .maestro
  --shard-split "$SHARDS"
  --format junit --output "$OUT_DIR/report.xml"
  --test-output-dir "$OUT_DIR/results")
if [[ -n "${TAGS:-}" ]]; then ARGS+=(--include-tags "$TAGS"); fi

DEVICE_LIST=$(IFS=,; echo "${DEVICES[*]}")
maestro --device "$DEVICE_LIST" "${ARGS[@]}"
