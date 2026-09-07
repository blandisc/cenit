#!/usr/bin/env python3
"""Tests for Tools/check-ensenanza.py (D6, épico FER-428, gate de L4/FER-430).

Los tres casos del diseño técnico (sección 5), sobre un repo temporal de juguete — nunca sobre el
árbol real: un `FuncionalidadID.swift` de tres ids y una pantalla que existe o no, según el caso.
"""
import importlib.util
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_ensenanza", os.path.join(_HERE, "..", "check-ensenanza.py"))
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

FUNCIONALIDAD_ID_SWIFT = '''\
public enum FuncionalidadID: String, CaseIterable, Sendable {
    case hoyPalabra = "hoy.palabra"
    case hoyActa = "hoy.acta"
    case entrenarRir = "entrenar.rir"
}
'''


def _repo(tmp, screens, baseline_lines):
    """Arma un repo de juguete: FuncionalidadID.swift + Cenit/Screens/{screens} + baseline."""
    fid_dir = os.path.join(tmp, "Packages/CenitEnsenanza/Sources/CenitEnsenanza")
    os.makedirs(fid_dir, exist_ok=True)
    with open(os.path.join(fid_dir, "FuncionalidadID.swift"), "w") as fh:
        fh.write(FUNCIONALIDAD_ID_SWIFT)

    screens_dir = os.path.join(tmp, "Cenit/Screens")
    os.makedirs(screens_dir, exist_ok=True)
    for name, content in screens.items():
        with open(os.path.join(screens_dir, name), "w") as fh:
            fh.write(content)

    tools_dir = os.path.join(tmp, "Tools")
    os.makedirs(tools_dir, exist_ok=True)
    with open(os.path.join(tools_dir, "ensenanza-baseline.txt"), "w") as fh:
        fh.write("\n".join(baseline_lines) + ("\n" if baseline_lines else ""))

    return tmp


class CheckEnsenanza(unittest.TestCase):
    def test_pantalla_nueva_sin_marcador_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {"Dummy.swift": "struct Dummy {}\n"}, baseline_lines=[])
            problems = gate.check(tmp)
            self.assertTrue(problems, "una pantalla nueva sin marcador debería fallar")
            self.assertIn("Dummy.swift", problems[0])
            self.assertIn("sin entrada de enseñanza", problems[0])

    def test_pantalla_nueva_con_id_valido_pasa(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {"Dummy.swift": "// ensenanza: hoy.palabra\nstruct Dummy {}\n"}, baseline_lines=[])
            problems = gate.check(tmp)
            self.assertEqual(problems, [])

    def test_pantalla_nueva_con_id_inexistente_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {"Dummy.swift": "// ensenanza: no.existe\nstruct Dummy {}\n"}, baseline_lines=[])
            problems = gate.check(tmp)
            self.assertTrue(problems)
            self.assertIn("no.existe", problems[0])

    def test_pantalla_del_baseline_sin_marcador_pasa(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {"Vieja.swift": "struct Vieja {}\n"}, baseline_lines=["Cenit/Screens/Vieja.swift"])
            problems = gate.check(tmp)
            self.assertEqual(problems, [])

    def test_marcador_roto_falla_aunque_este_en_el_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(
                tmp,
                {"Vieja.swift": "// ensenanza: no.existe\nstruct Vieja {}\n"},
                baseline_lines=["Cenit/Screens/Vieja.swift"],
            )
            problems = gate.check(tmp)
            self.assertTrue(problems, "un marcador roto falla aunque el archivo esté en el baseline")

    def test_ruta_del_baseline_que_ya_no_existe_falla(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {}, baseline_lines=["Cenit/Screens/Fantasma.swift"])
            problems = gate.check(tmp)
            self.assertTrue(problems)
            self.assertIn("Fantasma.swift", problems[0])
            self.assertIn("ya no existe", problems[0])

    def test_baseline_que_sube_falla_con_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(
                tmp,
                {"Vieja.swift": "struct Vieja {}\n", "Nueva.swift": "struct Nueva {}\n"},
                baseline_lines=["Cenit/Screens/Nueva.swift", "Cenit/Screens/Vieja.swift"],
            )
            base_baseline = os.path.join(tmp, "base-baseline.txt")
            with open(base_baseline, "w") as fh:
                fh.write("Cenit/Screens/Vieja.swift\n")
            problems = gate.check(tmp, base_path=base_baseline)
            self.assertTrue(problems, "el baseline no puede subir respecto a la base")
            self.assertTrue(any("Nueva.swift" in p and "solo puede bajar" in p for p in problems))

    def test_baseline_que_baja_pasa_con_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {"Vieja.swift": "struct Vieja {}\n"}, baseline_lines=["Cenit/Screens/Vieja.swift"])
            base_baseline = os.path.join(tmp, "base-baseline.txt")
            with open(base_baseline, "w") as fh:
                fh.write("Cenit/Screens/Vieja.swift\nCenit/Screens/OtraVieja.swift\n")
            problems = gate.check(tmp, base_path=base_baseline)
            self.assertEqual(problems, [])

    def test_base_ausente_o_vacia_es_alta_estructural_no_falla(self):
        # La primera vez que Tools/ensenanza-baseline.txt existe (este mismo PR), la rama base
        # todavía no lo tiene: `git show` no encuentra el archivo y el step de CI escribe un
        # /tmp/ens-base.txt vacío (`|| true`). Eso es el nacimiento del baseline, no una subida.
        with tempfile.TemporaryDirectory() as tmp:
            _repo(tmp, {"Vieja.swift": "struct Vieja {}\n"}, baseline_lines=["Cenit/Screens/Vieja.swift"])
            base_baseline = os.path.join(tmp, "base-baseline-vacia.txt")
            open(base_baseline, "w").close()  # existe pero vacío, como el `|| true` del CI
            problems = gate.check(tmp, base_path=base_baseline)
            self.assertEqual(problems, [])

            base_inexistente = os.path.join(tmp, "no-existe.txt")
            problems = gate.check(tmp, base_path=base_inexistente)
            self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
