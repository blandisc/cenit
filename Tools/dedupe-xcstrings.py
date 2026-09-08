#!/usr/bin/env python3
"""Find (and optionally remove) top-level keys that appear more than once in a String Catalog.

Why this exists
---------------
`Localizable.xcstrings` is JSON, but it is also a file people edit as raw text (see
`docs/design-system/I18N.md` §2.1 on the IDE-parser churn). Xcode's extractor can
re-append a key block that already exists, leaving the same key as two sibling JSON
objects. Nothing breaks at runtime — a JSON parser silently keeps the LAST occurrence —
which is exactly what makes it dangerous: a hand edit applied to the first block is
dead text, and `git diff` shows a change that has no effect.

    a key is redundant <=> the same key text opens two top-level blocks.

Which block survives
--------------------
Never a guess. One block is kept only if it *dominates* the other: it carries every
locale the loser carries, with byte-identical content, and at least as many locales
overall. Identical blocks collapse to the first. Anything else — the two blocks
disagree on some locale's value or state — is a CONFLICT: the script reports it and
changes nothing, because merging two different translations is a human call.

Usage
-----
    python3 Tools/dedupe-xcstrings.py                 # report on all three catalogs
    python3 Tools/dedupe-xcstrings.py --diff          # report + per-locale diff
    python3 Tools/dedupe-xcstrings.py --apply         # drop the redundant blocks
    python3 Tools/dedupe-xcstrings.py <catalog> ...   # limit to given catalogs

`--apply` deletes whole key blocks textually — never a `json.dump` round-trip of the
whole file — so the diff is exactly the removed blocks and nothing else.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

DEFAULT_CATALOGS = [
    REPO / "Cenit/Resources/Localizable.xcstrings",
    REPO / "CenitWidgets/Resources/Localizable.xcstrings",
    REPO / "CenitWatch/Resources/Localizable.xcstrings",
]


# ---------------------------------------------------------------------------
# Textual block parsing — string-aware, so a brace inside a value cannot fool it.
# ---------------------------------------------------------------------------

def _scan_braces(line: str) -> int:
    """Net brace depth contributed by `line`, ignoring braces inside JSON strings."""
    depth = 0
    in_str = False
    escaped = False
    for ch in line:
        if in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
    return depth


def _key_at(line: str) -> str | None:
    """If `line` opens a top-level key block (4-space indent), return the decoded key."""
    if not line.startswith('    "') or line.startswith("     "):
        return None
    if not line.rstrip().endswith("{"):
        return None
    # The key is the JSON string that starts at column 4.
    dec = json.JSONDecoder()
    try:
        key, end = dec.raw_decode(line[4:])
    except ValueError:
        return None
    if not isinstance(key, str):
        return None
    # Accept the canonical `"key" : {` and the compact `"key": {`.
    if line[4 + end :].strip() not in (": {", ":{"):
        return None
    return key


def parse_blocks(lines: list[str]) -> tuple[int, list[tuple[str, int, int]], int]:
    """Locate each top-level key block.

    Returns (header_end, [(key, first_line, last_line_inclusive)], footer_start).
    """
    blocks: list[tuple[str, int, int]] = []
    header_end: int | None = None
    i = 0
    while i < len(lines):
        key = _key_at(lines[i])
        if key is not None:
            if header_end is None:
                header_end = i
            depth = _scan_braces(lines[i])
            j = i
            while depth > 0:
                j += 1
                if j >= len(lines):
                    raise SystemExit("unterminated key block — is this a String Catalog?")
                depth += _scan_braces(lines[j])
            blocks.append((key, i, j))
            i = j + 1
            continue
        i += 1
    if header_end is None:
        raise SystemExit("no key blocks found — is this a String Catalog?")
    return header_end, blocks, blocks[-1][2] + 1


def block_value(lines: list[str], start: int, end: int) -> dict:
    """Parse one key block's value object."""
    raw = "\n".join(lines[start : end + 1]).strip().rstrip(",")
    return json.loads("{" + raw + "}")[_key_at(lines[start])]


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

def locales(value: dict) -> dict:
    return value.get("localizations", {}) or {}


def _norm(value: dict) -> dict:
    """The block minus its locale table — comment, extractionState, shouldTranslate…"""
    return {k: v for k, v in value.items() if k != "localizations"}


def dominates(a: dict, b: dict) -> bool:
    """True if keeping `a` and dropping `b` loses nothing."""
    la, lb = locales(a), locales(b)
    for loc, val in lb.items():
        if loc not in la or la[loc] != val:
            return False
    if len(la) < len(lb):
        return False
    # Metadata must not regress either: `a` has to carry every field `b` states.
    na, nb = _norm(a), _norm(b)
    for k, v in nb.items():
        if k == "extractionState":
            continue  # churn field: Xcode rewrites it, it never carries user text
        if na.get(k) != v:
            return False
    return True


def describe(value: dict) -> str:
    locs = locales(value)
    parts = []
    for loc in sorted(locs):
        unit = locs[loc].get("stringUnit", {})
        state = unit.get("state", "?")
        text = unit.get("value", "")
        parts.append(f"{loc}={state}:{text!r}")
    if not parts:
        parts.append("<no localizations>")
    extra = _norm(value)
    if extra:
        parts.append(f"meta={json.dumps(extra, ensure_ascii=False, sort_keys=True)}")
    return "; ".join(parts)


def diff_lines(a: dict, b: dict, la_name: str, lb_name: str) -> list[str]:
    """Per-locale diff of two blocks, labelled with their [n] positions."""
    out = []
    la, lb = locales(a), locales(b)
    for loc in sorted(set(la) | set(lb)):
        ua, ub = la.get(loc), lb.get(loc)
        if ua == ub:
            out.append(f"      = {loc}: {json.dumps(ua, ensure_ascii=False)}")
        else:
            out.append(f"      - {la_name} {loc}: {json.dumps(ua, ensure_ascii=False)}")
            out.append(f"      + {lb_name} {loc}: {json.dumps(ub, ensure_ascii=False)}")
    na, nb = _norm(a), _norm(b)
    if na != nb:
        out.append(f"      - {la_name} meta: {json.dumps(na, ensure_ascii=False, sort_keys=True)}")
        out.append(f"      + {lb_name} meta: {json.dumps(nb, ensure_ascii=False, sort_keys=True)}")
    return out


# ---------------------------------------------------------------------------
# Surgery
# ---------------------------------------------------------------------------

def drop_blocks(catalog: Path, lines: list[str], drop: set[int]) -> None:
    """Rewrite the catalog without the blocks whose first-line index is in `drop`."""
    header_end, blocks, footer_start = parse_blocks(lines)
    kept = [b for b in blocks if b[1] not in drop]
    out = lines[:header_end]
    for idx, (_key, start, end) in enumerate(kept):
        block = lines[start : end + 1]
        block[-1] = block[-1].rstrip(",")
        if idx != len(kept) - 1:
            block[-1] += ","
        out.extend(block)
    out.extend(lines[footer_start:])
    catalog.write_text("\n".join(out), encoding="utf-8")


def process(catalog: Path, show_diff: bool, apply: bool) -> tuple[int, int]:
    """Returns (redundant_found, conflicts_found)."""
    lines = catalog.read_text(encoding="utf-8").split("\n")
    _header, blocks, _footer = parse_blocks(lines)

    by_key: dict[str, list[tuple[int, int]]] = {}
    for key, start, end in blocks:
        by_key.setdefault(key, []).append((start, end))
    dupes = {k: v for k, v in by_key.items() if len(v) > 1}

    rel = catalog.relative_to(REPO) if catalog.is_relative_to(REPO) else catalog
    print(f"{rel}: {len(blocks)} key blocks, {len(by_key)} distinct keys, {len(dupes)} duplicated")
    if not dupes:
        return 0, 0

    drop: set[int] = set()
    conflicts = 0
    redundant = 0
    for key in sorted(dupes):
        spans = dupes[key]
        values = [block_value(lines, s, e) for s, e in spans]
        print(f'\n  "{key}" — {len(spans)} blocks at lines '
              f'{", ".join(str(s + 1) for s, _ in spans)}')
        for n, v in enumerate(values, 1):
            print(f"    [{n}] {describe(v)}")

        # Pick a survivor: one block that dominates every other.
        winner = None
        for i, vi in enumerate(values):
            if all(dominates(vi, vj) for j, vj in enumerate(values) if j != i):
                winner = i
                break
        if winner is None:
            conflicts += 1
            print("    VERDICT: CONFLICT — blocks disagree; not touching. Resolve by hand.")
            print("\n".join(diff_lines(values[0], values[1], "[1]", "[2]")))
            continue

        redundant += len(spans) - 1
        print(f"    VERDICT: keep [{winner + 1}] (line {spans[winner][0] + 1}); "
              f"drop {len(spans) - 1} redundant block(s)")
        if show_diff:
            for j in range(len(values)):
                if j != winner:
                    print("\n".join(diff_lines(
                        values[winner], values[j], f"[{winner + 1} keep]", f"[{j + 1} drop]")))
        for j, (s, _e) in enumerate(spans):
            if j != winner:
                drop.add(s)

    if apply and drop:
        drop_blocks(catalog, lines, drop)
        print(f"\n  applied: removed {len(drop)} redundant block(s) from {rel}")
    elif drop:
        print(f"\n  (dry run — re-run with --apply to remove {len(drop)} block(s))")
    return redundant, conflicts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("catalogs", nargs="*", type=Path, help="catalogs to check (default: all three)")
    ap.add_argument("--diff", action="store_true", help="show a per-locale diff of every duplicate pair")
    ap.add_argument("--apply", action="store_true", help="remove the redundant blocks in place")
    args = ap.parse_args()

    catalogs = args.catalogs or DEFAULT_CATALOGS
    total_redundant = total_conflicts = 0
    for c in catalogs:
        c = c if c.is_absolute() else (REPO / c)
        if not c.exists():
            print(f"missing: {c}", file=sys.stderr)
            return 2
        r, k = process(c, args.diff, args.apply)
        total_redundant += r
        total_conflicts += k
        print()

    print(f"total: {total_redundant} redundant block(s), {total_conflicts} conflict(s)")
    if total_conflicts:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
