#!/usr/bin/env python3
"""Tests for Tools/check-design-drift.py (FER-263, épico FER-261).

Run:  python3 -m unittest Tools/tests/test_check_design_drift.py  (from the repo root)
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRIPT = os.path.join(_HERE, "..", "check-design-drift.py")
_spec = importlib.util.spec_from_file_location("check_design_drift", _SCRIPT)
drift = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(drift)


def _swift(tmp, rel, lines):
    path = os.path.join(tmp, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return path


class MergeWriteBaseline(unittest.TestCase):
    """--write-baseline must merge per-rule, never clobber the keys of rules that did not run."""

    def test_rerecording_one_rule_preserves_the_others(self):
        with tempfile.TemporaryDirectory() as tmp:
            baseline = os.path.join(tmp, "baseline.json")
            original = {
                "no-spacing-literal": {"Cenit/Screens/A.swift": 3},
                "no-legacy-api": {"Cenit/Screens/B.swift": 2},
            }
            with open(baseline, "w", encoding="utf-8") as fh:
                json.dump(original, fh)
            src = _swift(tmp, "Cenit/Screens/C.swift", ["VStack(spacing: 14) {}"])
            rc = drift.main(["--rules", "no-spacing-literal", "--write-baseline", baseline, src])
            self.assertEqual(rc, 0)
            merged = json.load(open(baseline, encoding="utf-8"))
            self.assertEqual(merged["no-legacy-api"], original["no-legacy-api"],
                             "keys of rules that did not run must survive byte-for-byte")
            self.assertEqual(list(merged["no-spacing-literal"].values()), [1])

    def test_rule_that_ran_clean_drops_its_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            baseline = os.path.join(tmp, "baseline.json")
            with open(baseline, "w", encoding="utf-8") as fh:
                json.dump({"no-spacing-literal": {"Cenit/Screens/A.swift": 3}}, fh)
            src = _swift(tmp, "Cenit/Screens/Clean.swift", ["Text(\"hola\")"])
            drift.main(["--rules", "no-spacing-literal", "--write-baseline", baseline, src])
            merged = json.load(open(baseline, encoding="utf-8"))
            self.assertNotIn("no-spacing-literal", merged)


class LegacyApiRule(unittest.TestCase):
    def test_matches_retired_symbols_and_modifier(self):
        for line in [
            "let theme = InstrumentoTheme.base",
            "PaperStepper(value: $n, range: 1...10)",  # Paper* residual que sigue en el gate
            "InstrumentoSectionBand(\"By sport\")",
            "view.instrumentoTheme(.dia)",
            "InstrumentoType.titulo",
            "Text(\"x\").instrumentoOverline(theme)",
            ".instrumentoConfirm(",
            "CenitPalette.ink",
        ]:
            self.assertTrue(drift.RE_LEGACY_API.search(line), line)

    def test_does_not_match_longer_identifiers_or_liquid(self):
        for line in [
            "InstrumentoThemeEngine.shared",   # \b guard: longer identifier is a different symbol
            "LiquidColor.hierro",
            "liquidGlass(.superficieSolida)",
            ".liquidKicker()",
            "InstrumentoTypeface",
        ]:
            self.assertFalse(drift.RE_LEGACY_API.search(line), line)

    def test_design_package_definitions_are_not_hits(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Packages/CenitDesign/Sources/CenitDesign/Instrumento.swift",
                         ["public struct InstrumentoTheme {}"])
            hits = drift.check([src], ["no-legacy-api"])
            self.assertEqual(hits, [])

    def test_app_call_site_is_a_hit(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["let t = InstrumentoTheme.base"])
            hits = drift.check([src], ["no-legacy-api"])
            self.assertEqual(len(hits), 1)

    def test_comment_line_is_not_a_hit(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "// let t = InstrumentoTheme.base  (histórico, solo comentario)",
                "/* PaperStepper también vivía aquí */",
            ])
            self.assertEqual(drift.check([src], ["no-legacy-api"]), [])

    def test_file_outside_scanned_roots_is_not_walked(self):
        with tempfile.TemporaryDirectory() as tmp:
            _swift(tmp, "CenitWidgets/RestLiveActivity.swift", ["let t = InstrumentoTheme.base"])
            gated = os.path.join(tmp, "Cenit", "Screens")
            os.makedirs(gated, exist_ok=True)
            self.assertEqual(drift.check([gated], ["no-legacy-api"]), [],
                             "un archivo fuera de las raíces pasadas no se escanea (carve-out FER-219)")


class TokenExemptPseudoRule(unittest.TestCase):
    def test_counts_both_annotation_forms_and_silences_other_rules(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                ".padding(14) // token-exempt: geometría de dato",
                ".padding(15) // token-exempt(dato): barras del hipnograma",
                ".padding(16)",
            ])
            hits = drift.check([src], ["no-spacing-literal", "token-exempt"])
            rules = sorted(r for _p, _i, r, _s in hits)
            self.assertEqual(rules, ["no-spacing-literal", "token-exempt", "token-exempt"])

    def test_new_exemption_over_budget_fails_with_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "Text(\"a\") // token-exempt: uno",
                "Text(\"b\") // token-exempt: dos",
            ])
            baseline = {"token-exempt": {drift._key(src): 1}}
            hits = drift.check([src], ["token-exempt"])
            over, _stale = drift.apply_baseline(hits, baseline)
            self.assertEqual(len(over), 1, "the second (new) exemption must be over budget")


class WidgetWatchCarveOut(unittest.TestCase):
    """FER-219: CenitWidgets/CenitWatch quedan fuera de las dos reglas nuevas EN check(), no solo
    por invocación — una corrida con raíces default no debe pintarlos de rojo."""

    def test_legacy_and_exempt_skip_widget_and_watch_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            # FER-314: Widgets/Watch ya hablan Liquid (DECISIONS 2026-09-03) — no-legacy-api SÍ los ve;
            # token-exempt sigue fuera (geometría fija de la Live Activity / watch face).
            w = _swift(tmp, "CenitWidgets/RestLiveActivity.swift",
                       ["let t = InstrumentoTheme.base", ".padding(8) // token-exempt: isla fija"])
            k = _swift(tmp, "CenitWatch/WatchFace.swift", ["let t = InstrumentoTheme.base"])
            hits = drift.check([w, k], ["no-legacy-api", "token-exempt"])
            self.assertEqual(sorted({r for _p, _i, r, _s in hits}), ["no-legacy-api"])
            self.assertEqual(len(hits), 2)


class MergeWriteRobustness(unittest.TestCase):
    def test_corrupt_json_is_refused_not_clobbered(self):
        with tempfile.TemporaryDirectory() as tmp:
            baseline = os.path.join(tmp, "baseline.json")
            with open(baseline, "w", encoding="utf-8") as fh:
                fh.write("{not json <<<<<<< HEAD")
            src = _swift(tmp, "Cenit/Screens/X.swift", ["VStack(spacing: 14) {}"])
            rc = drift.main(["--rules", "no-spacing-literal", "--write-baseline", baseline, src])
            self.assertEqual(rc, 2)
            self.assertEqual(open(baseline, encoding="utf-8").read(), "{not json <<<<<<< HEAD",
                             "un JSON corrupto se rechaza, jamás se reescribe")

    def test_partial_scan_preserves_unwalked_files_of_the_same_rule(self):
        # Como en el uso real: cwd = raíz del repo, rutas relativas (las claves del JSON lo son).
        with tempfile.TemporaryDirectory() as tmp:
            cwd = os.getcwd()
            try:
                os.chdir(tmp)
                _swift(tmp, "Cenit/Screens/A.swift", ["VStack(spacing: 14) {}"])
                _swift(tmp, "Cenit/Screens/B.swift", ["VStack(spacing: 9) {}"])
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift", "Cenit/Screens/B.swift"])
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift"])
                merged = json.load(open("baseline.json", encoding="utf-8"))
                self.assertIn("Cenit/Screens/B.swift", merged["no-spacing-literal"],
                              "un scan parcial no puede tirar el presupuesto de archivos no caminados")
            finally:
                os.chdir(cwd)

    def test_deleted_file_drops_out_on_rerecord(self):
        with tempfile.TemporaryDirectory() as tmp:
            cwd = os.getcwd()
            try:
                os.chdir(tmp)
                _swift(tmp, "Cenit/Screens/A.swift", ["VStack(spacing: 14) {}"])
                _swift(tmp, "Cenit/Screens/Gone.swift", ["VStack(spacing: 9) {}"])
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift", "Cenit/Screens/Gone.swift"])
                os.remove("Cenit/Screens/Gone.swift")
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift"])
                merged = json.load(open("baseline.json", encoding="utf-8"))
                self.assertNotIn("Cenit/Screens/Gone.swift", merged.get("no-spacing-literal", {}))
            finally:
                os.chdir(cwd)


class Ratchet(unittest.TestCase):
    def test_stale_notes_only_for_walked_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["Text(\"a\")"])
            baseline = {"no-spacing-literal": {"Cenit/App/NotWalked.swift": 6}}
            hits = drift.check([src], ["no-spacing-literal"])
            _over, stale = drift.apply_baseline(hits, baseline, walked={drift._key(src)})
            self.assertEqual(stale, [], "sin caminar el archivo, la nota «fewer» miente")
    def test_within_budget_passes_and_below_budget_reports_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["VStack(spacing: 9) {}"])
            baseline = {"no-spacing-literal": {drift._key(src): 2}}
            hits = drift.check([src], ["no-spacing-literal"])
            over, stale = drift.apply_baseline(hits, baseline)
            self.assertEqual(over, [])
            self.assertEqual(stale, [("no-spacing-literal", drift._key(src), 1)])


class Fer271CommentGaps(unittest.TestCase):
    """Huecos medios del review de FER-263: los 3 deben FALLAR contra el linter pre-FER-271."""

    def test_block_comment_prefix_does_not_evade_spacing(self):
        # (a) `/* x */ .padding(99)` escapaba porque stripped.startswith('/*') saltaba la línea.
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["/* x */ .padding(99)"])
            hits = drift.check([src], ["no-spacing-literal"])
            self.assertEqual(len(hits), 1, hits)
            self.assertEqual(hits[0][2], "no-spacing-literal")

    def test_orphan_token_exempt_comment_counts(self):
        # (b) `// token-exempt:` en línea-comentario propia no silencia nada, pero SÍ cuenta.
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "// token-exempt: huérfana — no hay código en esta línea",
                ".padding(1)",
            ])
            hits = drift.check([src], ["token-exempt", "no-spacing-literal"])
            rules = sorted(r for _p, _i, r, _s in hits)
            self.assertEqual(rules, ["no-spacing-literal", "token-exempt"], hits)

    def test_trailing_comment_legacy_symbol_is_not_a_hit(self):
        # (c) `import CenitDesign // InstrumentoTheme` era falso positivo de no-legacy-api.
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/System/RoutineDragAndDrop.swift",
                         ["import CenitDesign   // InstrumentoTheme, CenitMetrics, CenitMotion"])
            self.assertEqual(drift.check([src], ["no-legacy-api"]), [])

    def test_deprecated_metrics_es_prohibicion_y_respeta_carveouts(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/A.swift", [
                ".padding(CenitMetrics.space2)",
                ".padding(CenitMetrics.rowVPad)",       # miembro vivo: no cuenta
                ".padding(LiquidSpace.s200)",
            ])
            hits = drift.check([src], ["no-deprecated-metrics"])
            self.assertEqual([(i, r) for _p, i, r, _s in hits], [(1, "no-deprecated-metrics")])
            watch = _swift(tmp, "CenitWatch/W.swift", [".padding(CenitMetrics.space2)"])
            self.assertEqual(len(drift.check([watch], ["no-deprecated-metrics"])), 1)   # FER-314: el Watch ya se vigila

    def test_instrumento_theme_ve_acceso_y_strandfont_pero_no_rampas(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/B.swift", [
                ".foregroundStyle(theme.ink)",
                ".font(CenitFont.caption)",
                "let c = theme.muscleLoadColor(0.4)",          # rampa de dato: fuera
                "Task { CenitFont.ensureFontsRegistered() }",   # sistema: fuera
                ".outlineCapsule(.outline, size: .sm, theme: theme)",   # pass-through: fuera
                ".foregroundStyle(LiquidColor.tinta900)",
            ])
            hits = drift.check([src], ["no-instrumento-theme"])
            self.assertEqual([i for _p, i, _r, _s in hits], [1, 2])
            widget = _swift(tmp, "CenitWidgets/W.swift", [".foregroundStyle(theme.ink)"])
            self.assertEqual(len(drift.check([widget], ["no-instrumento-theme"])), 1)   # FER-314: los Widgets ya se vigilan

    def test_weight_on_grotesk_solo_en_tokens_grotesk(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/C.swift", [
                ".font(LiquidType.caption.weight(.bold))",        # grotesk: no-op silencioso
                ".font(LiquidType.filaConteo.weight(.bold))",     # .system: el peso sí funciona
                ".font(LiquidType.captionNegrita)",
            ])
            self.assertIn("caption", drift._grotesk_tokens())
            self.assertNotIn("filaConteo", drift._grotesk_tokens())
            hits = drift.check([src], ["no-weight-on-grotesk"])
            self.assertEqual([i for _p, i, _r, _s in hits], [1])

    def test_fontweight_sobre_grotesk_misma_linea_o_siguiente(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/D.swift", [
                ".font(LiquidType.caption).fontWeight(.medium)",   # misma línea
                ".font(LiquidType.tituloGemela)",                  # + siguiente
                "    .fontWeight(.medium)",
                ".font(LiquidType.filaConteo).fontWeight(.bold)",  # .system: válido
                ".font(LiquidType.caption)",
                "    .foregroundStyle(LiquidColor.tinta900)",
            ])
            hits = drift.check([src], ["no-weight-on-grotesk"])
            self.assertEqual([i for _p, i, _r, _s in hits], [1, 2])

    def test_capsule_in_background(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/C.swift", [
                ".background(LiquidColor.tinta900, in: Capsule())",   # 1 sí (FER-342)
                ".background(activo ? LiquidColor.tinta900 : Color.clear, in: Capsule())",  # 2 sí
                ".background(LiquidColor.tinta900, in: Capsule())  // token-exempt(chrome): pieza del catálogo",  # no
                "SegmentedPillControl(items)",                         # no
            ])
            self.assertEqual([i for _p, i, _r, _s in drift.check([src], ["no-capsule-a-mano"])], [1, 2])

    def test_capsule_clipshape(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/K.swift", [
                ".clipShape(Capsule())",                                  # 1 sí (FER-358)
                ".contentShape(Capsule())",                               # no: área de toque, no chrome
                ".clipShape(Capsule())  // token-exempt(chrome): pieza del catálogo",  # no
            ])
            self.assertEqual([i for _p, i, _r, _s in drift.check([src], ["no-capsule-a-mano"])], [1])


class UniqueKeysDictionary(unittest.TestCase):
    """FER-502 — `Dictionary(uniqueKeysWithValues:)` en Screens trapea con una clave repetida."""

    def test_pattern_matches_only_the_trapping_initializer(self):
        for line in ["let m = Dictionary(uniqueKeysWithValues: xs.map { ($0.day, $0) })",
                     "        byDay = Dictionary(uniqueKeysWithValues:"]:
            self.assertTrue(drift.RE_UNIQUE_KEYS_DICT.search(line), line)
        for line in ["Dictionary(xs.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })",
                     "let d: [Int: Int] = [:]"]:
            self.assertFalse(drift.RE_UNIQUE_KEYS_DICT.search(line), line)

    def test_screens_hit_and_exempt_silences(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "let a = Dictionary(uniqueKeysWithValues: xs.map { ($0.id, $0) })",
                "let b = Dictionary(uniqueKeysWithValues: ys) // token-exempt(unico): índices de enumerated()",
            ])
            self.assertEqual([i for _p, i, _r, _s in drift.check([src], ["no-unique-keys-dictionary"])], [1])


if __name__ == "__main__":
    unittest.main()
