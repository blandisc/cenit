#!/usr/bin/env python3
"""Ninguna pantalla nueva se merge sin enseñanza (D6, épico FER-428, gate de L4/FER-430).

Antes del registro (`Packages/CenitEnsenanza`), nada obligaba a que una funcionalidad nueva
apareciera en Ayuda, Novedades o un tip — por eso el diagnóstico del épico encontró un README que
promete un «What's new» retirado, un FEATURES.md desfasado y una tarjeta del taller que ya no
existe. Este gate cierra esa clase, con el mismo criterio que el gate de i18n (FER-123): un
baseline versionado congela lo que ya existe, y cualquier archivo NUEVO bajo `Cenit/Screens/**`
tiene que declarar con qué id del registro se enseña.

Regla:
  - Todo `Cenit/Screens/**/*.swift` que NO esté en `Tools/ensenanza-baseline.txt` debe llevar una
    línea `// ensenanza: <id>[, <id>…]` con id(s) que existan en
    `Packages/CenitEnsenanza/Sources/CenitEnsenanza/FuncionalidadID.swift`.
  - Un marcador con un id inexistente falla SIEMPRE, incluso si el archivo está en el baseline
    (un marcador roto es peor que ninguno: miente sobre qué lo enseña).
  - Una ruta del baseline que ya no existe en el árbol falla («quita la línea» — el baseline
    tiene que reflejar el árbol real, nunca fantasmas).
  - Con `--base <baseline-de-la-base>`, cualquier ruta que esté en el baseline actual y NO en el
    de la base falla: el baseline SOLO puede bajar (mismo principio que
    `Tools/check-baseline-monotony.py` para el sistema de diseño).

Límite conocido (documentado, no un bug): el gate ve ARCHIVOS nuevos bajo `Cenit/Screens/**`; no
ve una hoja o celda nueva agregada DENTRO de un archivo existente, ni pantallas bajo
`Cenit/Onboarding` o `Cenit/App`.

Uso: check-ensenanza.py [--repo .] [--base <baseline-de-la-base>]
Exit 0 = verde; 1 = hay problemas; 2 = error de entrada (falta FuncionalidadID.swift).
"""
import argparse
import os
import re
import sys

FID_PATH = "Packages/CenitEnsenanza/Sources/CenitEnsenanza/FuncionalidadID.swift"
BASELINE_PATH = "Tools/ensenanza-baseline.txt"
SCREENS_ROOT = "Cenit/Screens"

# Mismo espíritu que el regex que compila el enum: un `case nombre = "pestana.slug"` con
# cualquier indentación por delante.
ID_CASE_RE = re.compile(r'^\s*case\s+\w+\s*=\s*"([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+)"', re.M)
MARKER_RE = re.compile(r"//\s*ensenanza:\s*(.+)")


def load_ids(repo):
    path = os.path.join(repo, FID_PATH)
    if not os.path.exists(path):
        return None
    text = open(path, encoding="utf-8").read()
    return set(ID_CASE_RE.findall(text))


def load_baseline(path):
    if not os.path.exists(path):
        return set()
    return {
        line.strip()
        for line in open(path, encoding="utf-8")
        if line.strip() and not line.strip().startswith("#")
    }


def screen_files(repo):
    root = os.path.join(repo, SCREENS_ROOT)
    out = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for f in filenames:
            if not f.endswith(".swift"):
                continue
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, repo).replace(os.sep, "/")
            out.append(rel)
    return sorted(out)


def markers_in(path):
    text = open(path, encoding="utf-8").read()
    ids = []
    for m in MARKER_RE.finditer(text):
        for piece in m.group(1).split(","):
            piece = piece.strip()
            if piece:
                ids.append(piece)
    return ids


MENSAJE_SIN_MARCADOR = (
    "❌ ensenanza: {rel} es una pantalla nueva sin entrada de enseñanza. Agrega "
    "« // ensenanza: <id> » con un id de FuncionalidadID.swift, o crea la funcionalidad "
    "(caso en FuncionalidadID + entrada en Registro+<Pestaña>.swift + 3 claves "
    "«ensenanza.<id>.*» en el catálogo). Ver CONTRIBUTING «Add a new screen» paso 5."
)


def check(repo=".", base_path=None):
    ids = load_ids(repo)
    if ids is None:
        return [f"❌ ensenanza: no encontré {FID_PATH} — ¿se movió el paquete CenitEnsenanza?"]
    if not ids:
        return [f"❌ ensenanza: no pude leer ningún id de {FID_PATH} — ¿cambió el formato del enum?"]

    baseline = load_baseline(os.path.join(repo, BASELINE_PATH))
    files = screen_files(repo)
    files_set = set(files)

    problems = []

    for p in sorted(baseline):
        if p not in files_set:
            problems.append(
                f"❌ ensenanza: {p} está en {BASELINE_PATH} pero ya no existe en el árbol — quita esa línea."
            )

    for rel in files:
        marker_ids = markers_in(os.path.join(repo, rel))
        if not marker_ids:
            if rel not in baseline:
                problems.append(MENSAJE_SIN_MARCADOR.format(rel=rel))
            continue
        for mid in marker_ids:
            if mid not in ids:
                problems.append(
                    f"❌ ensenanza: {rel} marca « // ensenanza: {mid} » pero ese id no existe en {FID_PATH}."
                )

    if base_path is not None:
        base_baseline = load_baseline(base_path)
        subidas = sorted(baseline - base_baseline)
        if subidas:
            problems.append(
                "❌ ensenanza: el baseline solo puede bajar — subió con: " + ", ".join(subidas)
            )

    return problems


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--base", default=None, help="ruta al ensenanza-baseline.txt de la rama base")
    args = ap.parse_args(argv)

    if load_ids(args.repo) is None:
        print(f"❌ ensenanza: no encontré {FID_PATH}")
        return 2

    problems = check(args.repo, args.base)
    if problems:
        for p in problems:
            print(p)
        return 1
    print("✅ ensenanza: toda pantalla de Cenit/Screens está en el baseline o lleva un marcador válido")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
