#!/usr/bin/env python3
"""Toda clave `cenit.nav.<k>` de ScreenshotNav debe ser alcanzable (FER-497).

Una clave DEBUG muerta hace que el barrido de capturas fotografíe la pantalla ANTERIOR con
nombre ajeno y el test siga verde — pasó con `coach`/`dieta`/`automations` (FER-381) y con
`compare` (FER-489). Este gate cruza estáticamente:

  - R1: todo elemento de `ScreenshotNav.screens` está en los alias de pestaña de
    `RootTabView` o en los `rawValue` de `SecondaryScreen` (si no → «clave nav muerta»).
  - R2: toda `nav` de los manifiestos `docs/appmap/mapa/*.json` y de `CenitUITests/*.swift`
    está declarada en `screens` (si no → «clave nav desconocida»).
  - R3: toda `fixture` de un nodo no omitido en `docs/appmap/mapa/*.json` existe en
    `Cenit/App/MapaFixtures/*.swift` o en la lista blanca de `ScreenshotFixtures.swift`
    (si no → «fixture … que no existe»). Caza inexistente/renombrada; no valida que sea
    la correcta para el estado (FER-512).

Uso: check-nav-keys.py [--repo .]
Exit 0 = verde; 1 = hay violaciones; 2 = falta una fuente (archivo o bloque).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

SCREENSHOT_NAV = "CenitApp/App/ScreenshotNav.swift"
ROOT_TAB = "CenitApp/App/RootTabView.swift"
MAPA_GLOB = "docs/appmap/mapa/*.json"
UITESTS_GLOB = "CenitUITests/*.swift"
MAPA_FIXTURES_GLOB = "Cenit/App/MapaFixtures/*.swift"
SCREENSHOT_FIXTURES = "Cenit/App/ScreenshotFixtures.swift"

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
MAPA_FIXTURE_KEY_RE = re.compile(r'^\s*"([A-Za-z0-9_-]+)"\s*:\s*\{')
SCREENSHOT_WHITELIST_RE = re.compile(
    r'\[\s*((?:"[A-Za-z0-9_-]+"\s*,?\s*)+)\]\s*\.contains\(raw\)',
    re.S,
)


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


def parse_mapa_fixture_keys(src: str) -> set[str]:
    """Claves `"foo": {` de un archivo MapaFixtures (ignora líneas `//`)."""
    keys: set[str] = set()
    for line in src.splitlines():
        if line.lstrip().startswith("//"):
            continue
        m = MAPA_FIXTURE_KEY_RE.match(line)
        if m:
            keys.add(m.group(1))
    return keys


def parse_screenshot_whitelist(src: str) -> set[str]:
    """Literales de la lista blanca `[…].contains(raw)` en ScreenshotFixtures."""
    m = SCREENSHOT_WHITELIST_RE.search(src)
    if not m:
        raise EntradaInvalida(
            "no encontré la lista blanca `[…].contains(raw)` en "
            f"{SCREENSHOT_FIXTURES}"
        )
    return set(STRING_RE.findall(m.group(1)))


def parse_fixture_uses(data: dict, rel: str) -> list[tuple[str, str, str, str]]:
    """→ [(relpath, id, familia, fixture), …] de nodos no omitidos con `fixture`."""
    familia = data.get("familia", "")
    uses: list[tuple[str, str, str, str]] = []
    for nodo in data.get("nodos", []):
        if not isinstance(nodo, dict):
            continue
        if "omitido" in nodo:
            continue
        fixture = nodo.get("fixture")
        if not isinstance(fixture, str):
            continue
        uses.append((rel, nodo.get("id", ""), familia, fixture))
    return uses


def _read(repo: str, rel: str) -> str:
    path = os.path.join(repo, rel)
    if not os.path.isfile(path):
        raise EntradaInvalida(f"no encontré {rel}")
    return open(path, encoding="utf-8").read()


def _load_fixtures(
    repo: str,
) -> tuple[set[str], list[tuple[str, str, str, str]]]:
    """(declared_fixtures, uses[(rel, id, familia, fixture), …])."""
    declared: set[str] = set()
    for path in sorted(glob.glob(os.path.join(repo, MAPA_FIXTURES_GLOB))):
        declared |= parse_mapa_fixture_keys(open(path, encoding="utf-8").read())

    screenshot_path = os.path.join(repo, SCREENSHOT_FIXTURES)
    if os.path.isfile(screenshot_path):
        declared |= parse_screenshot_whitelist(
            open(screenshot_path, encoding="utf-8").read()
        )

    if not declared:
        raise EntradaInvalida(
            f"no encontré fixtures declaradas en {MAPA_FIXTURES_GLOB} ni en "
            f"{SCREENSHOT_FIXTURES}"
        )

    mapa_paths = sorted(glob.glob(os.path.join(repo, MAPA_GLOB)))
    if not mapa_paths:
        raise EntradaInvalida(f"no encontré ningún manifiesto en {MAPA_GLOB}")

    uses: list[tuple[str, str, str, str]] = []
    for path in mapa_paths:
        rel = os.path.relpath(path, repo)
        data = json.load(open(path, encoding="utf-8"))
        uses.extend(parse_fixture_uses(data, rel))
    return declared, uses


def _load(
    repo: str,
) -> tuple[
    list[str],
    set[str],
    list[tuple[str, str]],
    set[str],
    list[tuple[str, str, str, str]],
]:
    """(screens, reachable, uses, declared_fixtures, fixture_uses)."""
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

    declared, fixture_uses = _load_fixtures(repo)
    return screens, reachable, uses, declared, fixture_uses


def check(repo: str = ".") -> list[str]:
    """→ lista de violaciones (vacía = verde). Lanza EntradaInvalida si falta una fuente."""
    screens, reachable, uses, declared, fixture_uses = _load(repo)
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
    for rel, node_id, familia, fixture in fixture_uses:
        if fixture not in declared:
            problems.append(
                f"❌ nav-keys: nodo `{node_id}` ({familia}, {rel}) declara la "
                f"fixture `{fixture}` que no existe en {MAPA_FIXTURES_GLOB} ni "
                f"en {SCREENSHOT_FIXTURES}"
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
        screens, _reachable, uses, declared, fixture_uses = _load(args.repo)
    except EntradaInvalida as e:
        print(f"❌ nav-keys: {e}", file=sys.stderr)
        return 2
    if problems:
        for p in problems:
            print(p)
        return 1
    print(
        f"✅ nav-keys: {len(screens)} claves en ScreenshotNav, todas alcanzables; "
        f"{len(uses)} usos en manifiestos/UITests, todos declarados; "
        f"{len(fixture_uses)} fixtures de nodos, todas declaradas "
        f"({len(declared)} declaradas)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
