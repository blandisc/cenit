#!/usr/bin/env python3
"""Tests for Tools/build-features.py (L9b, épico FER-428, FER-439).

Sobre un repo temporal de juguete — nunca sobre el árbol real: una semilla de tres entradas, un
catálogo mínimo con sus claves `ensenanza.*` y un FEATURES.md con prosa manual alrededor de las
secciones. Lo que importa: los marcadores nacen solos la primera vez, lo manual se conserva byte a
byte, la regeneración es idempotente y `--check` ve el desfase.
"""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "build_features", os.path.join(_HERE, "..", "build-features.py"))
bf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bf)


def _entrada(fid, requiere=(), piezas=("ayuda",), desde=None):
    e = {"id": fid, "pestana": fid.split(".")[0], "requiere": list(requiere), "piezas": list(piezas),
         "mapa": [], "nombre": {"en": f"N {fid}", "es": ""}, "paraQue": {"en": f"P {fid}.", "es": ""},
         "dondeVive": {"en": f"D {fid}.", "es": ""}}
    if desde:
        e["desde"] = desde
    return e


ENTRADAS = [
    _entrada("hoy.palabra", requiere=["watch", "noches:4"]),
    _entrada("hoy.matriz"),
    _entrada("transversal.widgets", desde="1.90"),
]

PREFIJO = "# Guía\n\nProsa manual de arriba.\n\n---\n\n## At a glance\n\nIntro manual de la tabla:\n\n"
TABLA_VIEJA = "| Tab | What it is |\n| --- | --- |\n| **Hoy** | Vieja. |\n| **Ajustes** | Vieja. |\n"
ENTRE = "\nProsa manual entre la tabla y Hoy.\n\n---\n\n## Hoy — Today\n\n"
CUERPO_HOY_VIEJO = "**Tab: Hoy.** Prosa vieja de Hoy que se pudre.\n\n- viejo ítem\n\n"
SUFIJO = "---\n\n## Data Sources\n\nManual hasta el final.\n\n---\n\n## Privacy\n\nManual.\n"
FEATURES_VIEJO = PREFIJO + TABLA_VIEJA + ENTRE + CUERPO_HOY_VIEJO + SUFIJO


def _repo(tmp, entradas=ENTRADAS, features=FEATURES_VIEJO, catalogo_extra=None, sin_clave=None):
    os.makedirs(os.path.join(tmp, "Tools"), exist_ok=True)
    with open(os.path.join(tmp, "Tools/ensenanza-semilla.json"), "w", encoding="utf-8") as fh:
        json.dump({"_nota": "", "desde": "1.85", "entradas": entradas}, fh, ensure_ascii=False)
    strings = {}
    for e in entradas:
        for campo in ("nombre", "paraQue", "dondeVive"):
            key = f"ensenanza.{e['id']}.{campo}"
            if key == sin_clave:
                continue
            strings[key] = {"localizations": {"en": {"stringUnit": {"value": e[campo]["en"]}}}}
    strings.update(catalogo_extra or {})
    os.makedirs(os.path.join(tmp, "Cenit/Resources"), exist_ok=True)
    with open(os.path.join(tmp, "Cenit/Resources/Localizable.xcstrings"), "w", encoding="utf-8") as fh:
        json.dump({"sourceLanguage": "en", "strings": strings, "version": "1.0"}, fh)
    os.makedirs(os.path.join(tmp, "docs"), exist_ok=True)
    with open(os.path.join(tmp, "docs/FEATURES.md"), "w", encoding="utf-8") as fh:
        fh.write(features)
    return tmp


def _main(tmp, *args):
    with contextlib.redirect_stdout(io.StringIO()):
        return bf.main(["--repo", tmp, *args])


def _leer(tmp):
    return open(os.path.join(tmp, "docs/FEATURES.md"), encoding="utf-8").read()


class BuildFeatures(unittest.TestCase):
    def test_primera_vez_inserta_marcadores_y_conserva_lo_manual(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            self.assertEqual(_main(tmp), 0)
            nuevo = _leer(tmp)
            # Lo manual, byte a byte: antes de la tabla, entre la tabla y Hoy, y de Data Sources al fin.
            self.assertTrue(nuevo.startswith(PREFIJO))
            self.assertIn(ENTRE, nuevo)
            self.assertTrue(nuevo.endswith(SUFIJO))
            # Lo viejo se fue; los marcadores están, uno por sección.
            self.assertNotIn("Vieja.", nuevo)
            self.assertNotIn("Prosa vieja de Hoy", nuevo)
            for seccion in bf.SECCIONES:
                self.assertEqual(nuevo.count(bf.MARK_START.format(seccion=seccion)), 1, seccion)
                self.assertEqual(nuevo.count(bf.MARK_END.format(seccion=seccion)), 1, seccion)

    def test_regenerar_es_idempotente_y_check_pasa(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            self.assertEqual(_main(tmp), 0)
            primera = _leer(tmp)
            self.assertEqual(_main(tmp), 0)
            self.assertEqual(_leer(tmp), primera)
            self.assertEqual(_main(tmp, "--check"), 0)

    def test_check_ve_el_desfase_y_no_escribe(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            self.assertEqual(_main(tmp, "--check"), 1)
            self.assertEqual(_leer(tmp), FEATURES_VIEJO, "--check no debe escribir")

    def test_edicion_a_mano_dentro_de_marcadores_se_sobreescribe_y_fuera_se_conserva(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            _main(tmp)
            bueno = _leer(tmp)
            start = bf.MARK_START.format(seccion="hoy")
            editado = bueno.replace(start, start + "\nAlguien escribió aquí a mano.\n")
            editado = editado.replace("Manual hasta el final.", "Manual hasta el final, y una nota nueva.")
            with open(os.path.join(tmp, "docs/FEATURES.md"), "w", encoding="utf-8") as fh:
                fh.write(editado)
            self.assertEqual(_main(tmp, "--check"), 1)
            _main(tmp)
            final = _leer(tmp)
            self.assertNotIn("Alguien escribió aquí a mano.", final)
            self.assertIn("Manual hasta el final, y una nota nueva.", final)

    def test_seccion_nueva_nace_antes_de_data_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            _main(tmp)
            nuevo = _leer(tmp)
            enc = bf.ENCABEZADO["fuera-del-iphone"]
            self.assertIn(enc, nuevo)
            self.assertLess(nuevo.index(bf.ENCABEZADO["hoy"]), nuevo.index(enc))
            self.assertLess(nuevo.index(enc), nuevo.index("## Data Sources"))
            self.assertIn("**N transversal.widgets** — P transversal.widgets. _(D transversal.widgets.)_", nuevo)

    def test_formato_de_item_watch_y_since(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            _main(tmp)
            nuevo = _leer(tmp)
            self.assertIn("- **N hoy.palabra** — P hoy.palabra. _(D hoy.palabra.)_ · Needs Apple Watch", nuevo)
            self.assertIn("- **N hoy.matriz** — P hoy.matriz. _(D hoy.matriz.)_\n", nuevo)
            self.assertIn("_(D transversal.widgets.)_ · since 1.90", nuevo)

    def test_tabla_solo_lleva_pestanas_con_ayuda(self):
        with tempfile.TemporaryDirectory() as tmp:
            entradas = ENTRADAS + [_entrada("entrenar.hero", piezas=["tip:entrenar.hero"])]
            _repo(tmp, entradas=entradas)
            _main(tmp)
            nuevo = _leer(tmp)
            self.assertIn("| **Hoy** |", nuevo)
            self.assertNotIn("| **Entrenar** |", nuevo)
            self.assertNotIn("| **Ajustes** |", nuevo)
            # Y una funcionalidad sin `ayuda` tampoco se lista en su sección.
            self.assertNotIn("N entrenar.hero", nuevo)

    def test_textos_salen_del_catalogo_no_de_la_semilla(self):
        with tempfile.TemporaryDirectory() as tmp:
            extra = {"ensenanza.hoy.matriz.nombre": {"localizations": {"en": {"stringUnit": {"value": "Del catálogo"}}}}}
            _repo(tmp, catalogo_extra=extra)
            _main(tmp)
            self.assertIn("**Del catálogo**", _leer(tmp))
            self.assertNotIn("**N hoy.matriz**", _leer(tmp))

    def test_clave_faltante_en_el_catalogo_es_error_de_entrada(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, sin_clave="ensenanza.hoy.matriz.paraQue")
            self.assertEqual(_main(tmp), 2)
            self.assertEqual(_leer(tmp), FEATURES_VIEJO)

    def test_sin_anchor_es_error_de_entrada(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, features="# Guía\n\nSin secciones.\n")
            self.assertEqual(_main(tmp), 2)

    def test_marcadores_rotos_es_error_de_entrada(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp)
            _main(tmp)
            roto = _leer(tmp).replace(bf.MARK_END.format(seccion="hoy"), "")
            with open(os.path.join(tmp, "docs/FEATURES.md"), "w", encoding="utf-8") as fh:
                fh.write(roto)
            self.assertEqual(_main(tmp, "--check"), 2)


if __name__ == "__main__":
    unittest.main()
