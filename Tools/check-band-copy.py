#!/usr/bin/env python3
"""FER-402 — gate «cero legado»: nada de NOOP / WHOOP / banda-dispositivo en el árbol.

El dueño decidió (2026-09-06) cero rastro del proyecto anterior, de WHOOP, o de una
banda física: Cénit es 100% Apple Watch. Este gate barre archivos de texto buscando:

  - `noop`, `whoop`, `strap` — case-insensitive, en cualquier parte.
  - «banda»/«band» en sentido DISPOSITIVO (el wearable retirado) — no el sentido
    ESTADÍSTICO (rango de valores en una gráfica, p. ej. «banda gris», «banda de
    recuperación», «healthy band»), que se conserva y es mucho más frecuente en
    la prosa real del repo.

  «banda» sola no basta para acusar dispositivo: la prosa del repo usa «banda»
  constantemente para rangos de gráfica. Este gate solo la marca cuando aparece
  en la MISMA línea que una palabra de contexto de EMPAREJAMIENTO/HARDWARE
  (conecta, empareja, vincula, Bluetooth, sincroniza, WHOOP, wear, pair, bond,
  connect...) — alta precisión, prefiere un falso negativo a inundar el gate de
  ruido sobre bandas de gráfica. Ver `DEVICE_CONTEXT_RE`.

Excepciones explícitas (no son legado, se dejan pasar):

  - Rutas de disco del checkout del dueño: `~/code/noop`, su forma absoluta
    `/Users/fer.iracheta/code/noop`, y el patrón de worktree
    `-Users-fer-iracheta-code-noop` — nombran una carpeta real, no el proyecto.
  - «banda» ESTADÍSTICA — cualquier mención sin una palabra de contexto de
    hardware en la misma línea (ver arriba): `LiquidChartBanda`, `LiquidBandaEdad`,
    «banda de recuperación», «banda gris», «healthy band», etc.
  - `NOTICE` — el aviso histórico que exige la licencia del código anterior es la
    ÚNICA mención a NOOP permitida en todo el árbol.

Excluye siempre estos directorios/archivos (generados, o fuera de alcance):
`.git`, `.build`, `docs/appmap/`, `docs/design-system/tokens/`, `Cenit.xcodeproj`.

Uso:
  python3 Tools/check-band-copy.py                                   # barre todo el repo
  python3 Tools/check-band-copy.py --paths README.md docs CHANGELOG.md CLAUDE.md

Activación en CI (pendiente, NO activa en este cambio): correr este script como un
job dedicado (o dentro de un lint existente) sobre el árbol completo sería el
siguiente paso natural, pero decidir si es bloqueante o solo informativo — y sobre
qué ramas — es una decisión del dueño que este cambio no toma. No se agrega a
`.github/workflows/` todavía.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

EXCLUDE_DIR_PARTS = {".git", ".build", "appmap", "tokens"}
EXCLUDE_PATH_SUBSTRINGS = ("Cenit.xcodeproj",)

# Extensions this gate reads as text. Anything else (images, binaries) is skipped.
TEXT_SUFFIXES = {
    ".md", ".txt", ".yml", ".yaml", ".sh", ".py", ".json", ".html", ".svg",
    ".gitignore", ".cfg", ".ini", "",
}

# The one file allowed to mention NOOP: the historical NOTICE required by the
# predecessor project's own license.
NOTICE_EXEMPT_NAME = "NOTICE"

# Disk-path exceptions: substrings that legitimately contain "noop" because they
# name a real folder on the owner's machine, not the retired project.
DISK_PATH_EXCEPTIONS = (
    "~/code/noop",
    "-Users-fer-iracheta-code-noop",
    "/Users/fer.iracheta/code/noop",
)

# A line only counts as DEVICE "banda"/"band" when a HARDWARE-only-context word
# shares the line. Generic verbs like "connect"/"sync"/"wear" are excluded on
# purpose — they also describe Apple Health ("Connect Apple Health") and
# historical, already-retired band narration, both far more common in the repo's
# prose than a live pairing instruction. Absent one of these, "banda"/"band" is
# read as the statistical sense (a chart/value range) and left alone.
DEVICE_CONTEXT_RE = re.compile(
    r"\b(bluetooth|bond(ed)?|pair(ed|ing)?|empareja\w*|vincul\w*|whoop)\b",
    re.IGNORECASE,
)
BANDA_WORD_RE = re.compile(r"\bbandas?\b|\bbands?\b", re.IGNORECASE)

# A line describing the band's ABSENCE or its historical retirement is not a
# regression — it's exactly the honest copy FER-1003 wants ("no band to pair",
# "ya no empareja banda", "retired with the band"). Suppress those.
NEGATION_RE = re.compile(
    r"\bno\s+\w*\s*(band|banda)|(band|banda)[^.\n]{0,20}\bto pair\b|"
    r"\bya no\b|\bno longer\b|\bwas retired\b|\bretired with\b|\bstopped\b|"
    r"\bwas removed\b|\bearlier versions\b|\bexternal band pairing was\b",
    re.IGNORECASE,
)

# CHANGELOG.md is an append-only historical record: accurately narrating a
# retired band-era feature there is documentation, not a live regression. Still
# fully checked for noop/whoop/strap — only exempt from the banda-device check.
BANDA_CHECK_EXEMPT_FILES = {"CHANGELOG.md"}

NOOP_RE = re.compile(r"noop", re.IGNORECASE)
WHOOP_RE = re.compile(r"whoop", re.IGNORECASE)
STRAP_RE = re.compile(r"\bstrap\b", re.IGNORECASE)


def is_excluded(path: Path) -> bool:
    parts = set(path.parts)
    if parts & EXCLUDE_DIR_PARTS:
        return True
    s = str(path)
    return any(sub in s for sub in EXCLUDE_PATH_SUBSTRINGS)


def strip_disk_path_exceptions(line: str) -> str:
    """Remove the two allowed disk-path substrings so a bare 'noop' inside them
    never trips the NOOP check."""
    for exc in DISK_PATH_EXCEPTIONS:
        line = line.replace(exc, "")
    return line


def line_has_device_banda(line: str) -> bool:
    """True only if `line` mentions 'banda'/'band' AND a hardware/pairing-context
    word on the same line — otherwise it's read as the (far more common)
    statistical/chart sense and left alone. A line that describes the band's
    ABSENCE or retirement (negation) is not flagged either."""
    if not BANDA_WORD_RE.search(line):
        return False
    if not DEVICE_CONTEXT_RE.search(line):
        return False
    return not NEGATION_RE.search(line)


def scan_file(path: Path) -> list[str]:
    if path.name == NOTICE_EXEMPT_NAME:
        return []
    banda_exempt = path.name in BANDA_CHECK_EXEMPT_FILES
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []  # binary or unreadable — not a copy/doc source

    offenders = []
    for i, raw_line in enumerate(text.splitlines(), 1):
        line = strip_disk_path_exceptions(raw_line)
        hits = []
        if NOOP_RE.search(line):
            hits.append("noop")
        if WHOOP_RE.search(line):
            hits.append("whoop")
        if STRAP_RE.search(line):
            hits.append("strap")
        if not banda_exempt and line_has_device_banda(line):
            hits.append("banda(dispositivo)")
        if hits:
            offenders.append(f"{path}:{i}: [{', '.join(hits)}] {raw_line.strip()[:140]}")
    return offenders


def iter_files(paths: list[Path]):
    for base in paths:
        if base.is_file():
            if not is_excluded(base):
                yield base
            continue
        for candidate in sorted(base.rglob("*")):
            if candidate.is_dir():
                continue
            if is_excluded(candidate):
                continue
            if candidate.suffix not in TEXT_SUFFIXES and candidate.name != ".gitignore":
                continue
            yield candidate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--paths", nargs="+", default=["."],
        help="Files/directories to sweep, relative to the repo root (default: the whole tree).",
    )
    args = parser.parse_args()

    targets = [ROOT / p for p in args.paths]
    offenders: list[str] = []
    for f in iter_files(targets):
        offenders.extend(scan_file(f))

    if offenders:
        print("❌ Rastro de NOOP/WHOOP/banda-dispositivo encontrado:")
        print("\n".join(offenders))
        return 1
    print("✅ Cero rastro de NOOP/WHOOP/banda-dispositivo en lo barrido.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
