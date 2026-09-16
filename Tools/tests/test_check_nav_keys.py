#!/usr/bin/env python3
"""Tests for Tools/check-nav-keys.py (FER-497).

Sobre un repo temporal de juguete — nunca sobre el árbol real. Cubre R1 (clave muerta),
R2 (nav desconocida), árbol consistente, rawValues explícitos/implícitos y comentarios `//`.
"""
import importlib.util
import json
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_nav_keys", os.path.join(_HERE, "..", "check-nav-keys.py"))
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)


SCREENSHOT_NAV = """\
enum ScreenshotNav {
    private static let screens = [
        "today", "body", "library", "workouthistory",
    ]
}
"""

ROOT_TAB = """\
struct RootTabView {
    private enum SecondaryScreen: String {
        case library
        case workoutHistory = "workouthistory"
        case breathe, intervals
        // case ghost = "should-not-count"
        case explore
    }

    func handle(_ screen: String) {
        let tab: Tab? = switch screen {
        case "today":              .today
        case "body", "trends":     .body
        default:                   nil
        }
        _ = tab
    }
}
"""

MAPA = {
    "familia": "hoy",
    "nodos": [
        {"id": "apunto", "pasos": [{"nav": "today", "settle": 2}]},
        {"id": "cuerpo", "pasos": [{"nav": "body"}]},
    ],
}

UITEST = """\
func test_example() {
    nav("today", app: a, settle: 2)
    nav("library", app: a)
}
"""


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def _repo(tmp, screenshot=SCREENSHOT_NAV, root=ROOT_TAB, mapa=MAPA, uitest=UITEST):
    _write(os.path.join(tmp, "CenitApp/App/ScreenshotNav.swift"), screenshot)
    _write(os.path.join(tmp, "CenitApp/App/RootTabView.swift"), root)
    _write(os.path.join(tmp, "docs/appmap/mapa/hoy.json"),
           json.dumps(mapa, ensure_ascii=False))
    _write(os.path.join(tmp, "CenitUITests/CenitScreenshotTests.swift"), uitest)
    return tmp


class CheckNavKeys(unittest.TestCase):
    def test_parse_secondary_explicit_rawvalue(self):
        # `case x = "y"` se lee como `y`, no como `x`.
        raws = gate.parse_secondary_rawvalues(ROOT_TAB)
        self.assertIn("workouthistory", raws)
        self.assertNotIn("workoutHistory", raws)

    def test_parse_secondary_comma_cases(self):
        # `case a, b` produce dos rawValues implícitos.
        raws = gate.parse_secondary_rawvalues(ROOT_TAB)
        self.assertIn("breathe", raws)
        self.assertIn("intervals", raws)

    def test_parse_secondary_ignora_comentarios(self):
        # Un `case` dentro de un comentario `//` no cuenta.
        raws = gate.parse_secondary_rawvalues(ROOT_TAB)
        self.assertNotIn("should-not-count", raws)
        self.assertNotIn("ghost", raws)

    def test_screens_con_clave_muerta_falla_r1(self):
        dead = """\
enum ScreenshotNav {
    private static let screens = [
        "today", "body", "library", "workouthistory", "compare",
    ]
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, screenshot=dead)
            problems = gate.check(tmp)
            self.assertTrue(any("clave nav muerta" in p and "compare" in p for p in problems),
                            problems)

    def test_manifiesto_con_nav_no_declarada_falla_r2(self):
        mapa = {
            "familia": "hoy",
            "nodos": [
                {"id": "x", "pasos": [{"nav": "fantasma"}]},
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, mapa=mapa)
            problems = gate.check(tmp)
            self.assertTrue(
                any("clave nav desconocida" in p and "fantasma" in p
                    and "docs/appmap/mapa/hoy.json" in p for p in problems),
                problems,
            )

    def test_arbol_consistente_cero_violaciones(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            self.assertEqual(gate.check(tmp), [])


if __name__ == "__main__":
    unittest.main()
