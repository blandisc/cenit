#!/usr/bin/env python3
"""Toda clave `cenit.nav.<k>` de ScreenshotNav debe ser alcanzable (FER-497).

Una clave DEBUG muerta hace que el barrido de capturas fotografíe la pantalla ANTERIOR con
nombre ajeno y el test siga verde — pasó con `coach`/`dieta`/`automations` (FER-381) y con
`compare` (FER-489). Este gate cruza estáticamente:

  - R1: todo elemento de `ScreenshotNav.screens` está en los alias de pestaña de
    `RootTabView` o en los `rawValue` de `SecondaryScreen` (si no → «clave nav muerta»).
  - R2: toda `nav` de los manifiestos `docs/appmap/mapa/*.json` y de `CenitUITests/*.swift`
    está declarada en `screens` (si no → «clave nav desconocida»).

Uso: check-nav-keys.py [--repo .]
Exit 0 = verde; 1 = hay violaciones; 2 = falta una fuente (archivo o bloque).
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

SCREENSHOT_NAV = "CenitApp/App/ScreenshotNav.swift"
ROOT_TAB = "CenitApp/App/RootTabView.swift"
MAPA_GLOB = "docs/appmap/mapa/*.json"
UITESTS_GLOB = "CenitUITests/*.swift"

SCREENS_RE = re.compile(
    r"private\s+static\s+let\s+screens\s*=\s*\[(.*?)\]",
    re.S,
)
TAB_SWITCH_MARKER = "let tab: Tab? = switch screen {"
SECONDARY_MARKER = re.compile(
    r"private\s+enum\s+SecondaryScreen\s*:\s*String\b"
)
STRING_RE = re.compile(r'"([^"]+)"')
NAV_JSON_RE = re.compile(r'"nav"\s*:\s*"([^"]+)"')
NAV_SWIFT_RE = re.compile(r'\bnav\("([^"]+)"')
CASE_LINE_RE = re.compile(r"^\s*case\s+(.+)$")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class EntradaInvalida(Exception):
    """Falta o no se puede leer una fuente (exit 2)."""


def _strip_line_comment(line: str) -> str:
    if "//" not in line:
        return line
    return line.split("//", 1)[0]


def _brace_block(src: str, open_brace_idx: int) -> str:
    """Devuelve el interior del `{…}` que empieza en `open_brace_idx` (el índice del `{`)."""
    if open_brace_idx < 0 or open_brace_idx >= len(src) or src[open_brace_idx] != "{":
        raise EntradaInvalida("bloque con llaves mal formado")
    depth = 0
    for i in range(open_brace_idx, len(src)):
        ch = src[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return src[open_brace_idx + 1 : i]
    raise EntradaInvalida("bloque con llaves sin cierre")


def parse_screens(src: str) -> list[str]:
    m = SCREENS_RE.search(src)
    if not m:
        raise EntradaInvalida(
            f"no encontré `private static let screens = […]` en {SCREENSHOT_NAV}"
        )
    return STRING_RE.findall(m.group(1))


def parse_tab_aliases(src: str) -> set[str]:
    idx = src.find(TAB_SWITCH_MARKER)
    if idx < 0:
        raise EntradaInvalida(
            f"no encontré `{TAB_SWITCH_MARKER}` en {ROOT_TAB}"
        )
    brace = src.find("{", idx)
    body = _brace_block(src, brace)
    # Solo los strings de los `case "x", "y":` — `default` no trae comillas.
    return set(STRING_RE.findall(body))


def parse_secondary_rawvalues(src: str) -> set[str]:
    m = SECONDARY_MARKER.search(src)
    if not m:
        raise EntradaInvalida(
            f"no encontré `private enum SecondaryScreen: String` en {ROOT_TAB}"
        )
    brace = src.find("{", m.end())
    body = _brace_block(src, brace)
    raws: set[str] = set()
    for line in body.splitlines():
        line = _strip_line_comment(line).strip()
        if not line:
            continue
        cm = CASE_LINE_RE.match(line)
        if not cm:
            continue
        rest = cm.group(1).strip()
        if "=" in rest:
            # `case x = "y"` → solo el rawValue explícito.
            raws.update(STRING_RE.findall(rest))
        else:
            # `case a, b` → cada identificador es el rawValue implícito.
            raws.update(IDENT_RE.findall(rest))
    return raws


def parse_nav_uses_json(text: str) -> list[str]:
    return NAV_JSON_RE.findall(text)


def parse_nav_uses_swift(src: str) -> list[str]:
    return NAV_SWIFT_RE.findall(src)


def _read(repo: str, rel: str) -> str:
    path = os.path.join(repo, rel)
    if not os.path.isfile(path):
        raise EntradaInvalida(f"no encontré {rel}")
    return open(path, encoding="utf-8").read()


def _load(repo: str) -> tuple[list[str], set[str], list[tuple[str, str]]]:
    """(screens, reachable, uses[(relpath, key), …]). Lanza EntradaInvalida si falta fuente."""
    screens_src = _read(repo, SCREENSHOT_NAV)
    root_src = _read(repo, ROOT_TAB)
    screens = parse_screens(screens_src)
    reachable = parse_tab_aliases(root_src) | parse_secondary_rawvalues(root_src)

    mapa_paths = sorted(glob.glob(os.path.join(repo, MAPA_GLOB)))
    if not mapa_paths:
        raise EntradaInvalida(f"no encontré ningún manifiesto en {MAPA_GLOB}")
    uitest_paths = sorted(glob.glob(os.path.join(repo, UITESTS_GLOB)))
    if not uitest_paths:
        raise EntradaInvalida(f"no encontré ningún Swift en {UITESTS_GLOB}")

    uses: list[tuple[str, str]] = []
    for path in mapa_paths:
        rel = os.path.relpath(path, repo)
        for key in parse_nav_uses_json(open(path, encoding="utf-8").read()):
            uses.append((rel, key))
    for path in uitest_paths:
        rel = os.path.relpath(path, repo)
        for key in parse_nav_uses_swift(open(path, encoding="utf-8").read()):
            uses.append((rel, key))
    return screens, reachable, uses


def check(repo: str = ".") -> list[str]:
    """→ lista de violaciones (vacía = verde). Lanza EntradaInvalida si falta una fuente."""
    screens, reachable, uses = _load(repo)
    screens_set = set(screens)
    problems: list[str] = []
    for key in screens:
        if key not in reachable:
            problems.append(
                f"❌ nav-keys: clave nav muerta en {SCREENSHOT_NAV}: `{key}`"
            )
    for rel, key in uses:
        if key not in screens_set:
            problems.append(
                f"❌ nav-keys: clave nav desconocida en {rel}: `{key}`"
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Cruza claves nav de ScreenshotNav con RootTabView, mapa y UITests"
    )
    ap.add_argument("--repo", default=".")
    args = ap.parse_args(argv)
    try:
        problems = check(args.repo)
        screens, _reachable, uses = _load(args.repo)
    except EntradaInvalida as e:
        print(f"❌ nav-keys: {e}", file=sys.stderr)
        return 2
    if problems:
        for p in problems:
            print(p)
        return 1
    print(
        f"✅ nav-keys: {len(screens)} claves en ScreenshotNav, todas alcanzables; "
        f"{len(uses)} usos en manifiestos/UITests, todos declarados"
    )
    return 0




if __name__ == "__main__":
    sys.exit(main())
