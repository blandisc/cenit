#!/usr/bin/env python3
"""Genera docs/appmap/mapa/tendencias.json (FER-384 · Ola 2 del mapa 100%, familia Tendencias/Cuerpo).

DECISIÓN DEL DUEÑO: **matriz completa** — el detalle de métrica no usa una muestra representativa,
sino un nodo por (métrica, rango, estado): las ~36 métricas de `MetricCatalog` (leídas del propio
`Cenit/Data/MetricCatalog.swift`, nunca inventadas) x los 6 rangos de `ExploreRange` x los 4 estados
(full/focus/sin-lecturas/calibrando). Además el landing de Cuerpo x los 6 rangos, y un puñado de
nodos para Explorar/Ciclo.

El JSON es grande a propósito (ver README del mapa) — este script es la fuente; no se edita el JSON
a mano. Re-ejecutar tras cualquier cambio a `MetricCatalog.swift` o a las palancas DEBUG:

    python3 Tools/gen-mapa-tendencias.py
    python3 -c "import json; json.load(open('docs/appmap/mapa/tendencias.json'))"   # valida el JSON
"""
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "Cenit" / "Data" / "MetricCatalog.swift"
OUT_PATH = REPO_ROOT / "docs" / "appmap" / "mapa" / "tendencias.json"

# `metric("key", String(localized: "Title"), …)` — un renglón por métrica en `MetricCatalog.all`.
# Captura SOLO la clave + el título en inglés (documentación del nodo); nunca se inventa una clave
# que el catálogo no declare.
CATALOG_ROW = re.compile(r'metric\("([a-zA-Z0-9_]+)",\s*String\(localized:\s*"([^"]+)"\)')

# Las 7 métricas "ricas" que `CuerpoView.openDebugRoute()` abre directo por `metricSpec`
# (`MetricDetailScreen`, depth `.full`). `heart_rate` NO está en `MetricCatalog` (descriptor sintético
# de `MetricDetailSpec.heartRate`) — se agrega a mano, con su propio título, como hace el catálogo.
RICH_KEYS = {"hrv", "rhr", "resp_rate", "spo2", "heart_rate", "steps", "vo2max"}
HEART_RATE_EXTRA = ("heart_rate", "Heart Rate (intradía)")

# `ExploreRange.label` exacto — el arg `-cenit.range` (`TendenciasFixtures.debugRange()`) solo
# reconoce estos 6 valores.
# Rangos a capturar. Por defecto (versión LIGERA, decisión del dueño 2026-09-06) UN solo rango: la
# misma métrica en semana/mes/3 meses se veía casi igual y no aportaba — no repetimos por rango. Con
# `--full` vuelve la matriz de los 6 rangos de `ExploreRange` (regenerar es trivial).
FULL_RANGES = ["W", "M", "3M", "6M", "1Y", "ALL"]
DEFAULT_RANGE = "M"          # el rango por defecto del app (mes)
RANGES = [DEFAULT_RANGE]     # se sobreescribe a FULL_RANGES con --full en main()

# Estados del detalle de métrica que SÍ tienen palanca en esta familia: con datos, vacío, calibrando.
# `focus` (la profundidad de Hoy/TodayView) NO existe en Cuerpo — `MetricDetailScreen` abre siempre en
# `.full` — así que ya no se emite (antes era un nodo `omitido` por métrica, puro relleno gris).
STATES = ["full"]   # un estado por métrica (los vacío/calibrando no diferenciaban en captura, FER-392); --full-states los restaura


def slug_range(r: str) -> str:
    return r.lower()


def slug_key(key: str) -> str:
    return key.replace("_", "-")


def read_catalog() -> list[tuple[str, str]]:
    """[(key, title), …] en el orden del catálogo, + `heart_rate` al final (no vive ahí)."""
    text = CATALOG_PATH.read_text(encoding="utf-8")
    rows = CATALOG_ROW.findall(text)
    if len(rows) < 30:   # guardia: si el parseo se rompe (el archivo cambió de forma), no generar basura
        print(f"gen-mapa-tendencias: solo {len(rows)} métricas parseadas de {CATALOG_PATH} "
              "— ¿cambió el formato de MetricCatalog.all? Revisa CATALOG_ROW.", flush=True)
        raise SystemExit(2)
    rows.append(HEART_RATE_EXTRA)
    return rows


def landing_nodes() -> list[dict]:
    """Cuerpo × 6 rangos. Reusa el fixture histórico `primed` (recovery/veredicto reales) — el
    fixture propio de esta familia (`tendencias_full`) es deliberadamente simple (no calcula
    Preparedness), y el landing SÍ necesita ese veredicto para verse como el héroe real."""
    nodes = []
    for i, r in enumerate(RANGES):
        nodes.append({
            "id": f"cuerpo-{slug_range(r)}",
            "titulo": f"Cuerpo · landing · rango {r}",
            "condicion": f"Landing de Tendencias con datos (`primed`), selector de rango en {r}.",
            "fixture": "primed",
            "args": ["-cenit.range", r],
            "pasos": [{"nav": "body", "settle": 5}],
            "frames": 2,   # scroll: el landing es una sola pantalla larga (héroe → footer)
            "png": f"tendencias-cuerpo-{slug_range(r)}.png",
            "x": i * 460, "y": 0,
        })
    return nodes


def metric_nodes(catalog: list[tuple[str, str]]) -> list[dict]:
    """(métrica, rango, estado) — la matriz completa. Un nodo por celda, sin muestreo."""
    nodes = []
    for row_i, (key, title) in enumerate(catalog):
        rich = key in RICH_KEYS
        via = ("metricSpec (ruta directa, MetricDetailScreen)" if rich
               else "Explorar → fila empujada (MetricDetailView genérico)")
        for col_i, r in enumerate(RANGES):
            for state in STATES:
                node = {
                    "id": f"detalle-{slug_key(key)}-{slug_range(r)}-{state}",
                    "titulo": f"Detalle · {title} · {r} · {state}",
                    "condicion": f"{via} · estado «{state}» · rango {r}.",
                    "args": ["-cenit.route", f"tendencias/{key}", "-cenit.range", r],
                    "pasos": [{"wait": 2}],   # margen extra: el fixture siembra el store en un Task detached
                    "frames": 1,
                    "png": f"tendencias-detalle-{slug_key(key)}-{slug_range(r)}-{state}.png",
                    "x": col_i * 380, "y": 200 + row_i * 260 + (0 if state == "full" else 60),
                }
                if state == "full":
                    node["fixture"] = "tendencias_full"
                elif state == "calibrando":
                    node["fixture"] = "tendencias_calibrando"
                # "sin-lecturas": SIN fixture — `-cenit.freshStore YES` (que test_mapa añade a todo
                # nodo) ya deja el store vacío; no hace falta sembrar nada.
                nodes.append(node)
    return nodes


def aux_nodes() -> list[dict]:
    """Explorar (la lista, no el detalle de una métrica) — dos estados (con datos / vacía), NO la
    matriz de rango×estado (esa es la del detalle de métrica). Ciclo queda `omitido`:
    `CyclePhaseView` solo se presenta desde `AjustesView.showCyclePhase` (familia Ajustes) —
    tocar ese archivo está fuera de mi alcance."""
    screens = [
        ("explorar",      "explorar",      "Explorar · catálogo de métricas (la lista, sin drill-down)"),
    ]
    nodes = []
    # El «vacío» de explorar capturó idéntico al «con datos» (la pantalla muestra su
    # estado por defecto poblado aunque el store esté vacío) — se marca omitido para no repetir foto
    # (FER-392); afinar el estado vacío es backlog.
    NO_DIFERENCIA_VACIO = {"explorar"}
    for i, (route_key, id_prefix, blurb) in enumerate(screens):
        for state, fixture in (("full", "tendencias_full"), ("vacio", None)):
            node = {
                "id": f"{id_prefix}-{state}",
                "titulo": f"{blurb} · {state}",
                "condicion": f"{blurb}, estado {'con datos' if state == 'full' else 'vacío (sin fixture, freshStore)'}.",
                "args": ["-cenit.route", f"tendencias/{route_key}"],
                "pasos": [{"wait": 2}],
                "frames": 1,
                "png": f"tendencias-{id_prefix}-{state}.png",
                "x": 3200 + i * 380, "y": 0 if state == "full" else 260,
            }
            if fixture:
                node["fixture"] = fixture
            if state == "vacio" and route_key in NO_DIFERENCIA_VACIO:
                node["omitido"] = "el estado vacío capturó idéntico al de con datos (pantalla poblada por defecto) — afinar backlog"
            nodes.append(node)
    nodes.append({
        "id": "ciclo",
        "titulo": "Fase del ciclo (CyclePhaseView)",
        "condicion": "Sin nodo capturable desde esta familia.",
        "omitido": ("CyclePhaseView se presenta SOLO desde AjustesView.showCyclePhase (familia "
                     "Ajustes) — no hay palanca en Cuerpo/Tendencias sin tocar AjustesView.swift, "
                     "fuera del alcance de este lane (FER-384)."),
        "x": 3200 + len(screens) * 380, "y": 0,
    })
    return nodes


def edges(catalog: list[tuple[str, str]]) -> list[dict]:
    """Aristas ilustrativas del flujo (landing → detalle → explorar) — no exhaustivas: la
    matriz tiene ~870 nodos, enumerar cada transición sería ruido, no señal."""
    d = slug_range(DEFAULT_RANGE)
    out = [
        {"de": f"cuerpo-{d}", "a": f"detalle-hrv-{d}-full", "etiqueta": "toca HRV"},
        {"de": f"cuerpo-{d}", "a": "explorar-full", "etiqueta": "Ver todas las métricas"},
        {"de": "explorar-full", "a": f"detalle-weight-{d}-full", "etiqueta": "fila → detalle genérico"},
    ]
    # Aristas de «cambia rango» entre landings consecutivos — solo tienen sentido con --full (varios
    # rangos); con un solo rango no hay transición que mostrar.
    for a, b in zip(RANGES, RANGES[1:]):
        out.append({"de": f"cuerpo-{slug_range(a)}", "a": f"cuerpo-{slug_range(b)}", "etiqueta": "cambia rango"})
    return out


def build_manifest(full: bool = False) -> dict:
    """Construye el manifiesto en memoria. `full` selecciona los 6 rangos (misma semántica que `--full`)."""
    global RANGES
    RANGES = FULL_RANGES if full else [DEFAULT_RANGE]
    catalog = read_catalog()
    nodos = landing_nodes() + metric_nodes(catalog) + aux_nodes()
    rangos_txt = "×".join(RANGES) if len(RANGES) > 1 else RANGES[0]
    return {
        "familia": "tendencias",
        "titulo": "Tendencias · Cuerpo",
        "unidad": "estados",
        "blurb": (f"Landing de Cuerpo + detalle de cada una de las {len(catalog)} métricas de "
                  f"MetricCatalog en su rango por defecto ({rangos_txt}) × {len(STATES)} estados "
                  "(con datos / sin lecturas / calibrando). Versión ligera: sin repetir por rango "
                  "(regenerar con --full para los 6 rangos). Más Explorar. "
                  "Ciclo omitido (vive en la familia Ajustes)."),
        "nodos": nodos,
        "aristas": edges(catalog),
    }


def _serialize(manifest: dict) -> str:
    return json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"


def _diff_summary(generated: str, on_disk: str) -> str:
    """Resumen: nodos que faltan/sobran por id + N líneas distintas."""
    gen = json.loads(generated)
    try:
        disk = json.loads(on_disk) if on_disk else {"nodos": []}
    except ValueError:
        disk = {"nodos": []}
    gen_ids = {n["id"] for n in gen.get("nodos", []) if "id" in n}
    disk_ids = {n["id"] for n in disk.get("nodos", []) if "id" in n}
    faltan = sorted(gen_ids - disk_ids)   # generados que no están en disco
    sobran = sorted(disk_ids - gen_ids)   # en disco que el generador ya no emite
    gen_lines = generated.splitlines()
    disk_lines = on_disk.splitlines()
    n_diff = sum(1 for a, b in zip(gen_lines, disk_lines) if a != b) + abs(len(gen_lines) - len(disk_lines))
    parts = []
    if faltan:
        parts.append(f"faltan {len(faltan)} nodo(s): {', '.join(faltan[:8])}{'…' if len(faltan) > 8 else ''}")
    if sobran:
        parts.append(f"sobran {len(sobran)} nodo(s): {', '.join(sobran[:8])}{'…' if len(sobran) > 8 else ''}")
    parts.append(f"{n_diff} líneas distintas")
    return "; ".join(parts)


def check_uptodate(full: bool = False) -> int:
    """Compara el manifiesto generado con OUT_PATH. Exit 0/1 (2 lo lanza read_catalog)."""
    generated = _serialize(build_manifest(full=full))
    if not OUT_PATH.is_file():
        print(f"gen-mapa-tendencias: no existe {OUT_PATH.relative_to(REPO_ROOT)}")
        print(_diff_summary(generated, ""))
        print("regenera con `python3 Tools/gen-mapa-tendencias.py`")
        return 1
    on_disk = OUT_PATH.read_text(encoding="utf-8")
    if generated == on_disk:
        print("✅ gen-mapa-tendencias: docs/appmap/mapa/tendencias.json al día")
        return 0
    print(f"gen-mapa-tendencias: {OUT_PATH.relative_to(REPO_ROOT)} desfasado — {_diff_summary(generated, on_disk)}")
    print("regenera con `python3 Tools/gen-mapa-tendencias.py`")
    return 1


def main(full: bool = False) -> None:
    manifest = build_manifest(full=full)
    nodos = manifest["nodos"]
    catalog_len = len(read_catalog())
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(_serialize(manifest), encoding="utf-8")

    omitidos = [n for n in nodos if "omitido" in n]
    print(f"gen-mapa-tendencias: {catalog_len} métricas ({len(RICH_KEYS)} rutas ricas, "
          f"{catalog_len - len(RICH_KEYS)} vía Explorar) × {len(RANGES)} rango(s) × {len(STATES)} estados")
    print(f"  {len(nodos)} nodos totales → {OUT_PATH.relative_to(REPO_ROOT)}")
    print(f"  {len(omitidos)} omitidos (Ciclo)")
    print(f"  {len(nodos) - len(omitidos)} capturables")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Genera docs/appmap/mapa/tendencias.json")
    ap.add_argument("--full", action="store_true",
                    help="matriz completa: los 6 rangos de ExploreRange (default: solo el rango por defecto)")
    ap.add_argument("--check", action="store_true",
                    help="no escribe: falla si tendencias.json no coincide con lo que generaría el script")
    a = ap.parse_args()
    if a.check:
        raise SystemExit(check_uptodate(full=a.full))
    main(full=a.full)
