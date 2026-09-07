#!/usr/bin/env bash
# capture-appmap.sh — El "un comando" para regenerar el mapa de estados (docs/appmap):
# corre el harness en el simulador → captura los PNG REALES del código → los reescala a
# shots/ → valida con check-shots → reconstruye el canvas HTML.
#
#   Tools/capture-appmap.sh                          # TODO el mapa (test_mapa recorre los manifiestos)
#   NOOP_MAPA_FAMILIA=hoy,entrenar Tools/capture-appmap.sh   # solo esas familias (una lane)
#   Tools/capture-appmap.sh test_today_primed …      # tests específicos (compat viejo)
#   SIM_NAME="iPhone 16" Tools/capture-appmap.sh     # otro simulador
#
# El mapa se guía por manifiesto (FER-381): `test_mapa` lee `docs/appmap/mapa/<familia>.json`
# (empacados en el bundle de CenitUITests) y captura un PNG por nodo×frame. El sim UI-test corre
# HEADLESS (iOS 26.x) — no necesita terminal real.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
STAGING="scratch-appmap-staging"
LOG="$(mktemp -t capture-appmap).log"

# Tests a correr:
#   · con argumentos → esos (compat con test_today_*/test_components);
#   · con NOOP_MAPA_FAMILIA → `test_mapa` (un método, filtrado por esa env al runner);
#   · por defecto → los 6 métodos POR FAMILIA. Cada familia es su propio método, así un crash del app
#     en un nodo aborta solo ESE método y XCUITest reinicia en el siguiente (no se pierde el resto).
if [ "$#" -gt 0 ]; then
  TESTS=("$@")
elif [ -n "${NOOP_MAPA_FAMILIA:-}" ]; then
  TESTS=(test_mapa); export TEST_RUNNER_NOOP_MAPA_FAMILIA="$NOOP_MAPA_FAMILIA"
else
  TESTS=(test_mapa_ajustes test_mapa_componentes test_mapa_entrenar test_mapa_hoy test_mapa_onboarding test_mapa_tendencias)
fi
ONLY=(); for t in "${TESTS[@]}"; do ONLY+=(-only-testing "CenitUITests/CenitScreenshotTests/$t"); done

echo "▸ Regenerando proyecto…"
GIT_CONFIG=/dev/null xcodegen generate >/dev/null

# FER-924: capturas deterministas — Reduce Motion del SISTEMA (congela el movimiento repeatForever) +
# status bar canónico (9:41, batería llena, wifi).
xcrun simctl boot "$SIM_NAME" >/dev/null 2>&1 || true
xcrun simctl spawn "$SIM_NAME" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true >/dev/null 2>&1 || true
xcrun simctl status_bar "$SIM_NAME" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi \
  >/dev/null 2>&1 || echo "  (aviso: no se pudo fijar el status bar — sigue con el reloj real)"

echo "▸ Corriendo harness en '$SIM_NAME' (${TESTS[*]}${NOOP_MAPA_FAMILIA:+ · familias=$NOOP_MAPA_FAMILIA}; el mapa completo tarda ~30-45 min)…"
set +e
# FIRMADO (`-allowProvisioningUpdates`): una app SIN firma no trae el entitlement del App Group y el
# canario `AppGroup.warnIfGroupUnprovisioned()` la aborta antes del primer frame (FER-49).
# `-test-timeouts-enabled NO`: test_mapa hace cientos de relanzamientos en UN método; el tope de 600 s
# por test lo mataría a media corrida.
GIT_CONFIG=/dev/null xcodebuild test \
  -project Cenit.xcodeproj -scheme Cenit \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -test-timeouts-enabled NO \
  -allowProvisioningUpdates -jobs 4 "${ONLY[@]}" > "$LOG" 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && grep -q "FIXTURE_WRITTEN" "$LOG" || true

echo "▸ Recolectando PNG crudos → $STAGING/"
mkdir -p "$STAGING"; N=0
while IFS= read -r src; do
  [ -f "$src" ] || continue
  cp -f "$src" "$STAGING/"; N=$((N+1))
done < <(grep -o 'FIXTURE_WRITTEN: .*\.png' "$LOG" | sed 's/^FIXTURE_WRITTEN: //')
echo "  $N PNG recolectados (RC del test = $RC)."
[ "$N" -eq 0 ] && { echo "✗ Ningún PNG. Log: $LOG"; exit 1; }

echo "▸ Reescalando a shots/ y reconstruyendo el canvas…"
python3 -c "import sys; sys.path.insert(0,'Tools'); import importlib.util as u; \
s=u.spec_from_file_location('ba','Tools/build-appmap.py'); m=u.module_from_spec(s); s.loader.exec_module(m); \
m.sync_shots('$STAGING'); m.build_served()"

echo "▸ Guardia anti-falso-verde (check-shots)…"
CHECK_ARGS=(); [ -n "${NOOP_MAPA_FAMILIA:-}" ] && CHECK_ARGS=(--familia "$NOOP_MAPA_FAMILIA")
set +e
python3 Tools/check-shots.py ${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"}
CHECK_RC=$?
set -e

echo "▸ Apagando el simulador…"
xcrun simctl shutdown "$SIM_NAME" >/dev/null 2>&1 || true

if [ "$CHECK_RC" -ne 0 ]; then
  echo "✗ check-shots reprobó (marcos en blanco/repetidos/faltantes). Log del test: $LOG"
  exit "$CHECK_RC"
fi
echo "✓ Listo → docs/appmap/index.html · check-shots verde."
