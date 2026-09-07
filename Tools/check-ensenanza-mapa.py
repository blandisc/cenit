#!/usr/bin/env python3
"""El registro de enseñanza y el Mapa 100 % no pueden desfasarse (L9b, épico FER-428, FER-439).

Cada entrada de `Tools/ensenanza-semilla.json` declara en `mapa` los nodos del mapa de pantallas
(`docs/appmap/mapa/<familia>.json`, épico FER-379) donde vive la funcionalidad, como
`<familia>/<nodo-id>`. Este gate cruza las dos fuentes en ambos sentidos:

  - Directo: todo `mapa` apunta a un nodo que EXISTE (familia conocida y nodo declarado en su
    JSON). Un `mapa` roto falla siempre — miente sobre dónde vive la funcionalidad.
  - Inverso: todo nodo de pantalla (todas las familias salvo `componentes`, que son piezas del
    sistema de diseño y no pantallas) está referido por ≥ 1 funcionalidad. Los que hoy no lo
    están viven en `Tools/ensenanza-mapa-baseline.txt` (una ruta `familia/nodo` por línea), que
    SOLO puede bajar (`--base <baseline-de-la-base>`, mismo principio que `check-ensenanza.py`).
    Un nodo del baseline que ya está cubierto, o que ya no existe en el mapa, falla («quita la
    línea»: el baseline refleja el mapa real, nunca fantasmas ni deuda ya pagada).

Límite conocido: el cruce se limita a los nodos que el mapa YA declara. Una pantalla o estado sin
nodo en `docs/appmap/mapa/` es invisible aquí (la ve `Tools/check-ensenanza.py`, que exige el
marcador `// ensenanza:` por archivo nuevo); cuando FER-379 le dé nodo, entra al cruce solo.

Uso: check-ensenanza-mapa.py [--repo .] [--base <baseline-de-la-base>]
Exit 0 = verde; 1 = hay problemas; 2 = error de entrada (falta la semilla o el mapa).
"""
import argparse
import glob
import json
import os
import re
import sys

SEED_PATH = "Tools/ensenanza-semilla.json"
MAPA_DIR = "docs/appmap/mapa"
BASELINE_PATH = "Tools/ensenanza-mapa-baseline.txt"
# Familia de piezas del sistema de diseño (LiquidGlassButton, StatTile…): no son pantallas, así
# que nunca son destino de un `mapa` ni cuentan para la cobertura inversa.
FAMILIA_COMPONENTES = "componentes"

REF_RE = re.compile(r"^([a-z][a-z0-9-]*)/([A-Za-z0-9][A-Za-z0-9-]*)$")


class EntradaInvalida(Exception):
    """Falta o no se puede leer una de las dos fuentes (exit 2)."""


def load_seed(repo):
    path = os.path.join(repo, SEED_PATH)
    if not os.path.exists(path):
        raise EntradaInvalida(f"no encontré {SEED_PATH}")
    try:
        data = json.load(open(path, encoding="utf-8"))
    except ValueError as e:
        raise EntradaInvalida(f"{SEED_PATH} no es JSON válido: {e}")
    return data["entradas"]


def load_mapa(repo):
    """{familia: [nodo-id, …]} de todos los JSON de docs/appmap/mapa/, sin `componentes`."""
    root = os.path.join(repo, MAPA_DIR)
    paths = sorted(glob.glob(os.path.join(root, "*.json")))
    if not paths:
        raise EntradaInvalida(f"no encontré ningún manifiesto en {MAPA_DIR}/")
    familias = {}
    for path in paths:
        try:
            data = json.load(open(path, encoding="utf-8"))
        except ValueError as e:
            raise EntradaInvalida(f"{os.path.relpath(path, repo)} no es JSON válido: {e}")
        familia = os.path.splitext(os.path.basename(path))[0]
        if familia == FAMILIA_COMPONENTES or data.get("unidad") == FAMILIA_COMPONENTES:
            continue
        familias[familia] = [n["id"] for n in data.get("nodos", [])]
    return familias


def load_baseline(path):
    if not os.path.exists(path):
        return set()
    return {
        line.strip()
        for line in open(path, encoding="utf-8")
        if line.strip() and not line.strip().startswith("#")
    }


def _nodos_validos(familias, familia):
    return ", ".join(familias[familia])


def check(repo=".", base_path=None):
    """→ lista de problemas (vacía = verde). Lanza EntradaInvalida si falta una fuente."""
    entradas = load_seed(repo)
    familias = load_mapa(repo)
    problems = []
    referidos = set()

    for e in entradas:
        fid = e["id"]
        mapa = e.get("mapa", [])
        if not isinstance(mapa, list):
            problems.append(f"❌ ensenanza-mapa: `{fid}` tiene un `mapa` que no es lista: {mapa!r}")
            continue
        if len(mapa) != len(set(mapa)):
            dup = sorted({r for r in mapa if mapa.count(r) > 1})
            problems.append(f"❌ ensenanza-mapa: `{fid}` repite en `mapa`: {', '.join(dup)}")
        for ref in mapa:
            m = REF_RE.match(str(ref))
            if not m:
                problems.append(
                    f"❌ ensenanza-mapa: `{fid}` tiene el `mapa` {ref!r} con formato inválido "
                    f"(esperaba `<familia>/<nodo-id>`)."
                )
                continue
            familia, nodo = m.groups()
            if familia == FAMILIA_COMPONENTES:
                problems.append(
                    f"❌ ensenanza-mapa: `{fid}` apunta a `{ref}`; `{FAMILIA_COMPONENTES}` son piezas, "
                    f"no pantallas — un `mapa` solo apunta a familias de pantalla ({', '.join(sorted(familias))})."
                )
                continue
            if familia not in familias:
                problems.append(
                    f"❌ ensenanza-mapa: `{fid}` apunta a `{ref}` pero no existe "
                    f"{MAPA_DIR}/{familia}.json; familias válidas: {', '.join(sorted(familias))}."
                )
                continue
            if nodo not in familias[familia]:
                problems.append(
                    f"❌ ensenanza-mapa: `{fid}` apunta a `{ref}` que no existe en "
                    f"{MAPA_DIR}/{familia}.json; nodos válidos: {_nodos_validos(familias, familia)}."
                )
                continue
            referidos.add(ref)

    todos = {f"{familia}/{nodo}" for familia, nodos in familias.items() for nodo in nodos}
    baseline = load_baseline(os.path.join(repo, BASELINE_PATH))

    for ref in sorted(baseline):
        if ref not in todos:
            problems.append(
                f"❌ ensenanza-mapa: `{ref}` está en {BASELINE_PATH} pero ya no existe en el mapa — quita esa línea."
            )
        elif ref in referidos:
            problems.append(
                f"❌ ensenanza-mapa: `{ref}` está en {BASELINE_PATH} pero ya lo cubre una funcionalidad — "
                f"quita esa línea (el baseline solo guarda nodos sin dueño)."
            )

    sin_dueno = sorted(todos - referidos - baseline)
    for ref in sin_dueno:
        problems.append(
            f"❌ ensenanza-mapa: el nodo `{ref}` no está en el `mapa` de ninguna funcionalidad. Agrega "
            f"`{ref}` al `mapa` de la entrada que lo enseña en {SEED_PATH} (y su `mapa:` en "
            f"Registro+<Pestaña>.swift), o crea la funcionalidad. Ver CONTRIBUTING «Add a new screen» paso 5."
        )

    if base_path is not None:
        base_baseline = load_baseline(base_path)
        # Base vacía (el archivo no existe todavía en la rama base): alta estructural del propio
        # baseline, no una subida — mismo criterio que check-ensenanza.py.
        if base_baseline:
            subidas = sorted(baseline - base_baseline)
            if subidas:
                problems.append(
                    "❌ ensenanza-mapa: el baseline solo puede bajar — subió con: " + ", ".join(subidas)
                )

    return problems


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--base", default=None, help="ruta al ensenanza-mapa-baseline.txt de la rama base")
    args = ap.parse_args(argv)

    try:
        problems = check(args.repo, args.base)
    except EntradaInvalida as e:
        print(f"❌ ensenanza-mapa: {e}")
        return 2
    if problems:
        for p in problems:
            print(p)
        return 1
    baseline = load_baseline(os.path.join(args.repo, BASELINE_PATH))
    familias = load_mapa(args.repo)
    total = sum(len(n) for n in familias.values())
    print(
        f"✅ ensenanza-mapa: todo `mapa` apunta a un nodo real y los {total - len(baseline)}/{total} "
        f"nodos de pantalla tienen dueño ({len(baseline)} en el baseline)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
