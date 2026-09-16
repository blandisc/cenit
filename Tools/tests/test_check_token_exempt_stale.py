#!/usr/bin/env python3
"""Tests for Tools/check-token-exempt-stale.py (FER-510 · C12)."""
import importlib.util
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_token_exempt_stale",
    os.path.join(_HERE, "..", "check-token-exempt-stale.py"),
)
stale = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(stale)


def _write(tmp: str, name: str, body: str) -> str:
    path = os.path.join(tmp, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    return path


class TokenExemptStale(unittest.TestCase):
    def test_negativo_exencion_legitima_pasa(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "Ok.swift",
                'RoundedRectangle(cornerRadius: 4)  // token-exempt(dato): geometría de dato\n',
            )
            self.assertEqual(stale.main([path]), 0)

    def test_positivo_linea_font_system_falla_con_iconSF(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "BadFont.swift",
                ".font(.system(size: 9, weight: .semibold))  "
                "// token-exempt(falta-pieza): microtexto <10pt\n",
            )
            self.assertEqual(stale.main([path]), 1)

    def test_positivo_spring_05_08_falla_con_ringProgress(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "BadSpring.swift",
                ".strandAnimation(.spring(response: 0.5, dampingFraction: 0.8), value: acwr)  "
                "// token-exempt(unico): marcador ACWR\n",
            )
            self.assertEqual(stale.main([path]), 1)

    def test_positivo_razon_cita_vota_retirado(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "BadVota.swift",
                ".strokeBorder(color.opacity(0.45), lineWidth: 1)  "
                "// token-exempt(paridad): mismo aro al 45 % del sello «vota» de la Matriz\n",
            )
            # opacity 0.45 también dispara CenitOpacity.dim; cualquiera basta.
            self.assertEqual(stale.main([path]), 1)

    def test_positivo_opacity_045_falla_con_dim(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "BadDim.swift",
                ".opacity(0.45)  // token-exempt(falta-pieza): atenuación sin token\n",
            )
            self.assertEqual(stale.main([path]), 1)

    def test_positivo_exencion_sobre_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "BadToken.swift",
                ".padding(.top, LiquidSpace.s800)  "
                "// token-exempt(falta-pieza): aire del grabber\n",
            )
            self.assertEqual(stale.main([path]), 1)

    def test_positivo_razon_cita_iconSF(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(
                tmp,
                "Cite.swift",
                "let x = 1  // token-exempt(falta-pieza): falta iconSF todavía\n",
            )
            self.assertEqual(stale.main([path]), 1)

    def test_archivo_inexistente_exit_2(self):
        self.assertEqual(stale.main(["/no/existe/X.swift"]), 2)


if __name__ == "__main__":
    unittest.main()
