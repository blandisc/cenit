#!/usr/bin/env python3
"""Tests for Tools/check-ensenanza-mapa.py (L9b, épico FER-428, FER-439).

Sobre un repo temporal de juguete — nunca sobre el árbol real: una semilla de tres entradas, dos
familias del mapa (`hoy`, `entrenar`) más `componentes`, y un baseline según el caso. El caso
sintético del criterio de aceptación es `test_mapa_a_nodo_inexistente_falla_con_mensaje_claro`.
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
    "check_ensenanza_mapa", os.path.join(_HERE, "..", "check-ensenanza-mapa.py"))
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

MAPA_HOY = {"familia": "hoy", "unidad": "estados", "nodos": [{"id": "apunto"}, {"id": "vacio"}], "aristas": []}
MAPA_ENTRENAR = {"familia": "entrenar", "unidad": "estados", "nodos": [{"id": "hub"}], "aristas": []}
MAPA_COMPONENTES = {"familia": "componentes", "unidad": "componentes",
                    "nodos": [{"id": "LiquidGlassButton"}], "aristas": []}


def _entrada(fid, mapa):
    pestana = fid.split(".")[0]
    return {"id": fid, "pestana": pestana, "requiere": [], "piezas": ["ayuda"], "mapa": mapa,
            "nombre": {"en": fid, "es": fid}, "paraQue": {"en": fid, "es": fid},
            "dondeVive": {"en": fid, "es": fid}}


def _repo(tmp, entradas, baseline_lines=None, familias=None):
    """Arma un repo de juguete: semilla + docs/appmap/mapa/*.json + baseline (si se pide)."""
    tools = os.path.join(tmp, "Tools")
    os.makedirs(tools, exist_ok=True)
    with open(os.path.join(tools, "ensenanza-semilla.json"), "w", encoding="utf-8") as fh:
        json.dump({"_nota": "", "desde": "1.85", "entradas": entradas}, fh, ensure_ascii=False)
    mapa_dir = os.path.join(tmp, "docs/appmap/mapa")
    os.makedirs(mapa_dir, exist_ok=True)
    for fam in (familias if familias is not None else [MAPA_HOY, MAPA_ENTRENAR, MAPA_COMPONENTES]):
        with open(os.path.join(mapa_dir, fam["familia"] + ".json"), "w", encoding="utf-8") as fh:
            json.dump(fam, fh)
    if baseline_lines is not None:
        with open(os.path.join(tools, "ensenanza-mapa-baseline.txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(baseline_lines) + ("\n" if baseline_lines else ""))
    return tmp


def _main_silencioso(tmp):
    """`main()` imprime su veredicto; aquí solo importa el exit code."""
    with contextlib.redirect_stdout(io.StringIO()):
        return gate.main(["--repo", tmp])


# Las tres entradas cubren los tres nodos de pantalla: verde sin baseline.
CUBRE_TODO = [
    _entrada("hoy.palabra", ["hoy/apunto"]),
    _entrada("hoy.sin-datos", ["hoy/vacio"]),
    _entrada("entrenar.hero", ["entrenar/hub"]),
]


class CheckEnsenanzaMapa(unittest.TestCase):
    def test_mapa_completo_pasa(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO)
            self.assertEqual(gate.check(tmp), [])

    def test_mapa_a_nodo_inexistente_falla_con_mensaje_claro(self):
        # El caso sintético del criterio de aceptación: un `mapa` que apunta a un nodo que no está
        # en su familia. El mensaje nombra la funcionalidad, la ruta rota, el JSON y los nodos válidos.
        with tempfile.TemporaryDirectory() as tmp:
            entradas = CUBRE_TODO + [_entrada("hoy.acta", ["hoy/no-existe"])]
            _repo(tmp, entradas)
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            msg = problems[0]
            self.assertIn("`hoy.acta`", msg)
            self.assertIn("`hoy/no-existe`", msg)
            self.assertIn("docs/appmap/mapa/hoy.json", msg)
            self.assertIn("nodos válidos: apunto, vacio", msg)

    def test_mapa_a_familia_inexistente_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO + [_entrada("hoy.acta", ["marte/apunto"])])
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("marte.json", problems[0])
            self.assertIn("familias válidas: entrenar, hoy", problems[0])

    def test_mapa_a_componentes_falla(self):
        # `componentes` son piezas, no pantallas: nunca un destino válido, aunque el nodo exista.
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO + [_entrada("hoy.acta", ["componentes/LiquidGlassButton"])])
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("componentes", problems[0])
            self.assertIn("piezas", problems[0])

    def test_mapa_con_formato_invalido_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO + [_entrada("hoy.acta", ["apunto"])])
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("formato inválido", problems[0])

    def test_mapa_repetido_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, [_entrada("hoy.palabra", ["hoy/apunto", "hoy/apunto", "hoy/vacio"]),
                        _entrada("entrenar.hero", ["entrenar/hub"])])
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("repite", problems[0])
            self.assertIn("hoy/apunto", problems[0])

    def test_mapa_vacio_es_valido(self):
        # 0..n nodos: una funcionalidad sin pantalla propia (un hito de TipKit) lleva `mapa: []`.
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO + [_entrada("hoy.primer-veredicto", [])])
            self.assertEqual(gate.check(tmp), [])

    def test_entrada_sin_campo_mapa_es_lista_vacia(self):
        with tempfile.TemporaryDirectory() as tmp:
            sin_mapa = _entrada("hoy.primer-veredicto", [])
            del sin_mapa["mapa"]
            _repo(tmp, CUBRE_TODO + [sin_mapa])
            self.assertEqual(gate.check(tmp), [])

    def test_nodo_sin_dueno_fuera_del_baseline_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO[:2])  # nadie cubre entrenar/hub
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("`entrenar/hub`", problems[0])
            self.assertIn("ninguna funcionalidad", problems[0])

    def test_nodo_sin_dueno_en_el_baseline_pasa(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO[:2], baseline_lines=["entrenar/hub"])
            self.assertEqual(gate.check(tmp), [])

    def test_baseline_con_nodo_ya_cubierto_falla(self):
        # Deuda ya pagada: la línea sobra y el gate lo dice (el baseline no guarda fantasmas).
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO, baseline_lines=["entrenar/hub"])
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("ya lo cubre", problems[0])

    def test_baseline_con_nodo_inexistente_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO, baseline_lines=["hoy/fantasma"])
            problems = gate.check(tmp)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("`hoy/fantasma`", problems[0])
            self.assertIn("ya no existe", problems[0])

    def test_baseline_ignora_comentarios_y_lineas_vacias(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO[:2], baseline_lines=["# nota", "", "entrenar/hub"])
            self.assertEqual(gate.check(tmp), [])

    def test_baseline_que_sube_falla_con_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, [CUBRE_TODO[0]], baseline_lines=["entrenar/hub", "hoy/vacio"])
            base = os.path.join(tmp, "base-baseline.txt")
            with open(base, "w") as fh:
                fh.write("entrenar/hub\n")
            problems = gate.check(tmp, base_path=base)
            self.assertTrue(any("solo puede bajar" in p and "hoy/vacio" in p for p in problems), problems)

    def test_baseline_que_baja_pasa_con_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO[:2], baseline_lines=["entrenar/hub"])
            base = os.path.join(tmp, "base-baseline.txt")
            with open(base, "w") as fh:
                fh.write("entrenar/hub\nhoy/vacio\n")
            self.assertEqual(gate.check(tmp, base_path=base), [])

    def test_base_ausente_o_vacia_es_alta_estructural_no_falla(self):
        # Primera vez que el baseline existe (este PR): `git show` en la base no lo encuentra y el
        # step escribe un archivo vacío (`|| true`). Nacimiento, no subida.
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO[:2], baseline_lines=["entrenar/hub"])
            vacia = os.path.join(tmp, "base-vacia.txt")
            open(vacia, "w").close()
            self.assertEqual(gate.check(tmp, base_path=vacia), [])
            self.assertEqual(gate.check(tmp, base_path=os.path.join(tmp, "no-existe.txt")), [])

    def test_componentes_no_cuenta_para_la_cobertura_inversa(self):
        # LiquidGlassButton no tiene dueño y no debe pedirlo: no es una pantalla.
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO)
            self.assertEqual(gate.check(tmp), [])

    def test_sin_semilla_o_sin_mapa_es_error_de_entrada(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO)
            os.remove(os.path.join(tmp, "Tools/ensenanza-semilla.json"))
            with self.assertRaises(gate.EntradaInvalida):
                gate.check(tmp)
            self.assertEqual(_main_silencioso(tmp), 2)
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO, familias=[])
            with self.assertRaises(gate.EntradaInvalida):
                gate.check(tmp)

    def test_main_devuelve_0_verde_y_1_con_problemas(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO)
            self.assertEqual(_main_silencioso(tmp), 0)
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, CUBRE_TODO[:2])
            self.assertEqual(_main_silencioso(tmp), 1)


if __name__ == "__main__":
    unittest.main()
