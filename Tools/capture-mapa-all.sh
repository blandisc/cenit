#!/usr/bin/env bash
# capture-mapa-all.sh — Captura el mapa 100% COMPLETO de forma resiliente (FER-392).
#
# El simulador se degrada tras ~50 relanzamientos de app seguidos (una corrida monolítica pierde todo
# lo que viene después del crash). Este orquestador compila UNA vez y luego captura en TROZOS de ~30
# nodos, reiniciando el simulador entre cada trozo (el contador de lanzamientos vuelve a cero). Usa el
# rango `NOOP_MAPA_OFFSET`/`NOOP_MAPA_LIMIT` del harness (test_mapa_<familia>) y `test-without-building`
# para no recompilar por trozo.
#
#   Tools/capture-mapa-all.sh            # todo el mapa
#   CHUNK=25 Tools/capture-mapa-all.sh   # trozos más chicos
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
CHUNK="${CHUNK:-30}"
STAGING="scratch-appmap-staging"
DD="$HOME/Library/Developer/Xcode/DerivedData"

# (familia, total_de_nodos_capturables). El total se usa solo para calcular cuántos trozos; si sobra
# rango, el harness captura lo que haya y ya. Deben coincidir con test_mapa_<familia>.
FAMILIES=("ajustes:19" "componentes:26" "entrenar:42" "hoy:35" "onboarding:19" "tendencias:119")

echo "▸ Regenerando proyecto + build-for-testing (una sola vez)…"
GIT_CONFIG=/dev/null xcodegen generate >/dev/null
BUILDLOG="$(mktemp -t mapa-build).log"
GIT_CONFIG=/dev/null xcodebuild build-for-testing \
  -project Cenit.xcodeproj -scheme Cenit \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -allowProvisioningUpdates -jobs 4 > "$BUILDLOG" 2>&1 || { echo "✗ build-for-testing falló → $BUILDLOG"; tail -20 "$BUILDLOG"; exit 1; }
echo "  build OK."

rm -rf "$STAGING"; mkdir -p "$STAGING"
TOTAL=0

run_chunk() {   # $1=metodo  $2=offset  $3=limit
  local method="$1" off="$2" lim="$3"
  echo "  · $method  [$off..$((off+lim))]  (sim fresco)"
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  xcrun simctl boot "$SIM_NAME" >/dev/null 2>&1 || true
  xcrun simctl spawn "$SIM_NAME" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true >/dev/null 2>&1 || true
  xcrun simctl status_bar "$SIM_NAME" override --time "9:41" \
    --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi >/dev/null 2>&1 || true
  local log; log="$(mktemp -t mapa-$method-$off).log"
  TEST_RUNNER_NOOP_MAPA_OFFSET="$off" TEST_RUNNER_NOOP_MAPA_LIMIT="$lim" \
  GIT_CONFIG=/dev/null xcodebuild test-without-building \
    -project Cenit.xcodeproj -scheme Cenit \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -test-timeouts-enabled NO -allowProvisioningUpdates \
    -only-testing "CenitUITests/CenitScreenshotTests/$method" > "$log" 2>&1 || true
  local n=0
  while IFS= read -r src; do [ -f "$src" ] && { cp -f "$src" "$STAGING/"; n=$((n+1)); }; done \
    < <(grep -o 'FIXTURE_WRITTEN: .*\.png' "$log" | sed 's/^FIXTURE_WRITTEN: //')
  echo "      → $n PNG"
  TOTAL=$((TOTAL+n))
}

echo "▸ Capturando por familia en trozos de $CHUNK (sim fresco entre trozos)…"
for entry in "${FAMILIES[@]}"; do
  fam="${entry%%:*}"; count="${entry##*:}"; method="test_mapa_$fam"
  off=0
  while [ "$off" -lt "$count" ]; do
    run_chunk "$method" "$off" "$CHUNK"
    off=$((off+CHUNK))
  done
done

echo "▸ Recolectados $TOTAL PNG. Reescalando a shots/ + reconstruyendo canvas…"
python3 -c "import sys; sys.path.insert(0,'Tools'); import importlib.util as u; \
s=u.spec_from_file_location('ba','Tools/build-appmap.py'); m=u.module_from_spec(s); s.loader.exec_module(m); \
m.sync_shots('$STAGING'); m.build_served()"

echo "▸ Guardia check-shots…"
set +e; python3 Tools/check-shots.py; CHECK_RC=$?; set -e
xcrun simctl shutdown all >/dev/null 2>&1 || true
echo "CHECK_RC=$CHECK_RC · $TOTAL PNG recolectados"
[ "$CHECK_RC" -eq 0 ] && echo "✓ mapa completo y verde." || echo "△ mapa con huecos (ver arriba) — publica lo que hay y re-corre lo que falte."
