#!/usr/bin/env python3
"""FER-510 · C12 — exenciones `token-exempt` caducas.

Una exención `// token-exempt(...)` es deuda congelada. Este gate falla cuando la
exención ya no tiene sentido porque:

  1. La razón **cita un símbolo que ya existe** en el sistema de diseño
     (`iconSF`, `ringProgress`, `CenitOpacity.dim`, `tintFillStrong`, …), o
  2. La razón **cita una pieza retirada** (p. ej. el sello «vota» de FER-55), o
  3. La línea exenta **casa con un patrón** cuya pieza sustituta ya existe
     (`.font(.system(size:` → `LiquidType.iconSF`; `.spring(0.5, 0.8)` →
     `LiquidMotion.ringProgress` / `suave`; `.opacity(0.45)` → `CenitOpacity.dim`;
     opacidad 0.14–0.18 → `tintFillStrong`), o
  4. La exención está **sobre un token** (la línea solo usa tokens Liquid/Cenit
     y no trae un literal que justifique el escape).

Standalone (como `check-ensenanza.py`): no es regla de `check-design-drift.py`,
así que no toca la matriz de CONTRATO. Corre en `design-lint.yml` y en
`verify.sh quick`.

Uso:
    python3 Tools/check-token-exempt-stale.py
    python3 Tools/check-token-exempt-stale.py Cenit/Screens/X.swift

Exit 0 = verde; 1 = hay caducas; 2 = error de entrada.
"""
from __future__ import annotations

import os
import re
import sys

ROOTS = [
    "Cenit/Screens",
    "Cenit/Onboarding",
    "Cenit/System",
    "Cenit/App",
    "Cenit/Data",
    "Cenit/LiveActivity",
    "Cenit/Media",
    "Packages/CenitDesign/Sources",
    "CenitApp",
]

EXEMPT_RE = re.compile(
    r"""//\s*token-exempt(?:\((?P<cat>[^)]+)\))?\s*:\s*(?P<reason>.*)$"""
)

# Símbolos vivos: si la razón los nombra, la exención es caduca (ya no «falta»).
EXISTING_SYMBOLS = (
    "iconSF",
    "ringProgress",
    "CenitOpacity.dim",
    "tintFillStrong",
    "LiquidType.iconSF",
    "LiquidMotion.ringProgress",
    "LiquidMotion.suave",
    "verticalHitTarget",
    "LiquidControl.hitTarget",
)

# Piezas retiradas: citarlas en la razón (paridad con algo que ya no existe) falla.
RETIRED_IN_REASON = (
    re.compile(r"sello\s+[«\"]?vota", re.I),
    re.compile(r"[«\"]vota[»\"]"),
    re.compile(r"\bvota\b.*\b(Matriz|retirad)", re.I),
)

# Línea exenta → pieza que ya cubre ese literal.
STALE_LINE_PATTERNS = (
    (re.compile(r"\.font\(\s*\.system\s*\(\s*size:\s*\d+"), "LiquidType.iconSF"),
    (
        re.compile(
            r"\.spring\s*\(\s*response:\s*0\.5\s*,\s*dampingFraction:\s*0\.8\s*\)"
        ),
        "LiquidMotion.ringProgress",
    ),
    (re.compile(r"\.opacity\s*\(\s*0\.45\s*\)"), "CenitOpacity.dim"),
    (
        re.compile(r"\.opacity\s*\(\s*0\.1[4-8]\s*\)"),
        "CenitOpacity.tintFillStrong",
    ),
)

# Literal que todavía justificaría un escape (número crudo, hex, spring ad-hoc, etc.).
LITERAL_NEEDING_EXEMPT = re.compile(
    r"""
    Color\s*\(\s*hex: |
    \.font\s*\(\s*\.system\s*\( |
    \.opacity\s*\( |
    \.spring\s*\( |
    \.ease(?:In|Out|InOut)?\s*\( |
    cornerRadius:\s*\d |
    (?:padding|spacing|lineWidth|frame|offset|tracking)\s*[:(].*\b\d
    """,
    re.X,
)

# La línea ya habla solo en tokens del sistema.
TOKEN_ONLY_HINT = re.compile(
    r"\b(?:Liquid(?:Space|Type|Color|Motion|Radius|Control|Opacity)|CenitOpacity|CenitMetrics)\."
)


def _iter_swift(roots):
    for root in roots:
        if os.path.isfile(root) and root.endswith(".swift"):
            yield root
            continue
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in (".build", "DerivedData")]
            for name in filenames:
                if name.endswith(".swift"):
                    yield os.path.join(dirpath, name)


def _reason_cites_existing(reason: str) -> str | None:
    for sym in EXISTING_SYMBOLS:
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(sym)}(?![A-Za-z0-9_])", reason):
            return sym
    return None


def _reason_cites_retired(reason: str) -> str | None:
    for rx in RETIRED_IN_REASON:
        if rx.search(reason):
            return rx.pattern
    return None


def _line_matches_stale(code: str, cat: str | None) -> str | None:
    """Patrones de literal con sustituto vivo.

    `iconSF` / `ringProgress` aplican siempre (el literal no debería existir).
    Opacidades 0.45 / 0.14–0.18 solo cuando la categoría pretende «falta pieza»
    o «único» — las rampas `dato`/`optico` deliberadas se dejan.
    """
    for rx, symbol in STALE_LINE_PATTERNS:
        if not rx.search(code):
            continue
        if symbol in ("CenitOpacity.dim", "CenitOpacity.tintFillStrong"):
            if cat not in ("falta-pieza", "unico", None):
                continue
        return symbol
    return None


def _exemption_on_token(code: str, cat: str | None) -> bool:
    """Exención `falta-pieza` sobre una línea que ya solo habla en tokens.

    No aplica al troquel hit-slop (`padding`+`contentShape`+`padding`): eso es
    deuda de pieza compartida, no un escape inútil sobre un escalón de espacio.
    """
    if cat != "falta-pieza":
        return False
    if "contentShape" in code:
        return False
    if not TOKEN_ONLY_HINT.search(code):
        return False
    return LITERAL_NEEDING_EXEMPT.search(code) is None


def check_file(path: str) -> list[str]:
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as e:
        return [f"{path}: no pude leer ({e})"]
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        m = EXEMPT_RE.search(line)
        if not m:
            continue
        cat = (m.group("cat") or "").strip() or None
        reason = (m.group("reason") or "").strip()
        code = line[: m.start()]
        if sym := _reason_cites_existing(reason):
            hits.append(
                f"{path}:{i}: token-exempt-stale — la razón cita `{sym}`, que ya existe"
            )
            continue
        if retired := _reason_cites_retired(reason):
            hits.append(
                f"{path}:{i}: token-exempt-stale — la razón cita una pieza retirada ({retired})"
            )
            continue
        if sym := _line_matches_stale(code, cat):
            hits.append(
                f"{path}:{i}: token-exempt-stale — el literal ya tiene `{sym}`"
            )
            continue
        if _exemption_on_token(code, cat):
            hits.append(
                f"{path}:{i}: token-exempt-stale — exención sobre un token (sin literal)"
            )
    return hits


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    roots = argv if argv else ROOTS
    missing = [r for r in roots if not os.path.exists(r)]
    if missing and argv:
        print(f"token-exempt-stale: no existe {missing[0]}", file=sys.stderr)
        return 2
    hits: list[str] = []
    for path in _iter_swift(roots):
        hits.extend(check_file(path))
    if hits:
        print("❌ token-exempt-stale: exenciones caducas (símbolo vivo, pieza retirada, o escape sobre token):")
        for h in hits:
            print(f"   {h}")
        print(
            "   → usa el token/pieza vigente y quita el `// token-exempt`, "
            "o reescribe la razón si la exención sigue siendo legítima."
        )
        return 1
    print("✅ token-exempt-stale: ninguna exención cita símbolo vivo ni pieza retirada")
    return 0


if __name__ == "__main__":
    sys.exit(main())
