#!/usr/bin/env python3
"""Genera el código y el catálogo del registro CenitEnsenanza a partir de la semilla
(`Tools/ensenanza-semilla.json`, FER-430). NO se corre en CI — es una herramienta de una sola vez
(o de re-siembra manual) para no escribir 68 entradas × 3 claves a mano.

Genera:
  - Packages/CenitEnsenanza/Sources/CenitEnsenanza/FuncionalidadID.swift
  - Packages/CenitEnsenanza/Sources/CenitEnsenanza/Registro+<Pestaña>.swift (uno por pestaña)
  - inserta las 204 entradas del catálogo en Cenit/Resources/Localizable.xcstrings, como texto
    crudo con la indentación de 2 espacios que ya usa el archivo (NUNCA json.dump: reescribir todo
    el árbol cambia el formato de Xcode y revienta el diff).

Cada entrada puede llevar `mapa` (FER-439): los nodos del Mapa 100 % donde vive la funcionalidad,
como `<familia>/<nodo-id>` de `docs/appmap/mapa/<familia>.json`. Se emite como `mapa:` en la
`Funcionalidad` y `--check` valida que cada nodo exista (vía `Tools/check-ensenanza-mapa.py`, la
misma verdad que corre en CI).

OJO al re-sembrar: desde FER-433 los `Registro+*.swift` llevan piezas `.vacio(clave:)` añadidas a
mano que la semilla no conoce — regenerar los pisaría. Compara el diff antes de aceptar.

Uso: python3 Tools/gen-ensenanza.py [--check]
  --check: no escribe nada, solo valida la semilla (ids, formato, conteos, `mapa` contra el mapa).
"""
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SEMILLA = os.path.join(HERE, "ensenanza-semilla.json")
SRC = os.path.join(REPO, "Packages/CenitEnsenanza/Sources/CenitEnsenanza")
CATALOG = os.path.join(REPO, "Cenit/Resources/Localizable.xcstrings")
GATE_MAPA = os.path.join(HERE, "check-ensenanza-mapa.py")

# Una línea si cabe; si no, un nodo por línea (mismo umbral para el generador y las ediciones a
# mano, así el diff de una re-siembra solo trae cambios reales).
MAPA_ANCHO_MAX = 100

ID_RE = re.compile(r"^[a-z]+(?:\.[a-z0-9-]+)+$")

PESTANAS_ORDEN = ["hoy", "tendencias", "entrenar", "ajustes", "transversal"]


def camel_id(fid):
    """'hoy.primer-veredicto' -> 'hoyPrimerVeredicto'; 'tendencias.mapa-del-dia' -> 'tendenciasMapaDelDia'."""
    partes_punto = fid.split(".")
    out = []
    for i, parte in enumerate(partes_punto):
        palabras = parte.split("-")
        if i == 0:
            out.append(palabras[0])
            palabras = palabras[1:]
        for p in palabras:
            out.append(p[:1].upper() + p[1:])
    return "".join(out)


def requisito_swift(r):
    if r == "watch":
        return ".watch"
    if r == "entrenos":
        return ".entrenos"
    if r.startswith("noches:"):
        return f".noches({r.split(':', 1)[1]})"
    if r.startswith("permiso:"):
        return f".permiso(.{r.split(':', 1)[1]})"
    raise ValueError(f"requiere desconocido: {r!r}")


def pieza_swift(p, pestana):
    if p == "ayuda":
        return f".ayuda(seccion: .{pestana})"
    if p.startswith("tip:"):
        return f'.tip(id: "{p.split(":", 1)[1]}")'
    if p.startswith("hito:"):
        return f'.hito(id: "{p.split(":", 1)[1]}")'
    if p.startswith("gesto:"):
        # "gesto:<clave del gesto>|<clave del botón>" (FER-434: cada gesto tiene un botón).
        gesto, boton = p.split(":", 1)[1].split("|", 1)
        return f'.gestoConBoton(gesto: "{gesto}", boton: "{boton}")'
    raise ValueError(f"pieza desconocida: {p!r}")


def mapa_swift(mapa, indent="            "):
    """`mapa: ["hoy/apunto", "hoy/exigido"]` en una línea, o un nodo por línea si no cabe."""
    items = ", ".join(json.dumps(m) for m in mapa)
    linea = f"{indent}mapa: [{items}]"
    if len(linea) <= MAPA_ANCHO_MAX:
        return [linea]
    out = [f"{indent}mapa: ["]
    out.extend(f"{indent}    {json.dumps(m)}," for m in mapa)
    out.append(f"{indent}]")
    return out


def check_mapa():
    """Cruza `mapa` con docs/appmap/mapa/*.json usando el gate real (una sola verdad)."""
    spec = importlib.util.spec_from_file_location("check_ensenanza_mapa", GATE_MAPA)
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    try:
        problemas = gate.check(REPO)
    except gate.EntradaInvalida as e:
        raise SystemExit(f"mapa: {e}")
    if problemas:
        raise SystemExit("\n".join(problemas))


def load_semilla():
    data = json.load(open(SEMILLA, encoding="utf-8"))
    entradas = data["entradas"]
    desde = data["desde"]
    # Validación de forma (mata la clase «semilla mal formada» antes de generar código roto).
    ids = [e["id"] for e in entradas]
    if len(ids) != len(set(ids)):
        dup = [i for i in ids if ids.count(i) > 1]
        raise SystemExit(f"ids duplicados en la semilla: {sorted(set(dup))}")
    for e in entradas:
        if not ID_RE.match(e["id"]):
            raise SystemExit(f"id con formato inválido: {e['id']!r}")
        if e["pestana"] not in PESTANAS_ORDEN:
            raise SystemExit(f"pestana desconocida en {e['id']!r}: {e['pestana']!r}")
        for campo in ("nombre", "paraQue", "dondeVive"):
            for lang in ("en", "es"):
                v = e[campo][lang]
                if "—" in v:
                    raise SystemExit(f"guion largo en {e['id']!r}.{campo}.{lang}: {v!r}")
    return desde, entradas


def gen_funcionalidad_id(entradas):
    lines = [
        "// Los 68 ids estables del registro (épico FER-428, L4/FER-430). Un id nunca se",
        "// renombra: también es el `id` de su `Tip` (TipKit lo pide así). Archivo generado por",
        "// `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json` — no editar a mano",
        "// sin regenerar. SOLO este enum vive aquí: es el archivo que",
        "// `Tools/check-ensenanza.py` grepea con",
        '// `^\\s*case\\s+\\w+\\s*=\\s*"([a-z][a-z0-9-]*(?:\\.[a-z0-9-]+)+)"` para saber qué ids existen.',
        "public enum FuncionalidadID: String, CaseIterable, Sendable {",
    ]
    by_pestana = {p: [] for p in PESTANAS_ORDEN}
    for e in entradas:
        by_pestana[e["pestana"]].append(e)
    for p in PESTANAS_ORDEN:
        lines.append(f"    // MARK: - {p.capitalize()}")
        lines.append("")
        for e in by_pestana[p]:
            lines.append(f'    case {camel_id(e["id"])} = "{e["id"]}"')
        lines.append("")
    # quita la última línea en blanco sobrante
    while lines and lines[-1] == "":
        lines.pop()
    lines.append("}")
    return "\n".join(lines) + "\n"


def gen_registro_extension(pestana, entradas_pestana):
    archivo = pestana.capitalize()
    lines = [
        "import Foundation",
        "",
        f"// Entradas de la pestaña «{pestana}» del registro (semilla del épico FER-428, L4/FER-430).",
        "// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.",
        "extension Registro {",
        f"    public static let {pestana}: [Funcionalidad] = [",
    ]
    for e in entradas_pestana:
        cid = camel_id(e["id"])
        req = ", ".join(requisito_swift(r) for r in e["requiere"])
        piezas = ", ".join(pieza_swift(p, pestana) for p in e["piezas"])
        lines.append("        Funcionalidad(")
        lines.append(f"            id: .{cid},")
        lines.append(f"            pestana: .{pestana},")
        lines.append(f"            requiere: [{req}],")
        lines.append(f"            piezas: [{piezas}],")
        lines.append(f'            desde: "{e["desde_efectivo"]}",')
        lines.extend(mapa_swift(e.get("mapa", [])))
        lines.append("        ),")
    lines.append("    ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def catalog_entry_text(key, en, es):
    """Un bloque de entrada del catálogo, con la indentación EXACTA (2 espacios/nivel) que ya usa
    Localizable.xcstrings. `key`/`en`/`es` se escapan con json.dumps (comillas, backslashes,
    unicode literal — ensure_ascii=False, igual que el resto del archivo)."""
    def q(s):
        return json.dumps(s, ensure_ascii=False)
    return (
        f"    {q(key)} : {{\n"
        f'      "extractionState" : "manual",\n'
        f'      "localizations" : {{\n'
        f'        "en" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f"            \"value\" : {q(en)}\n"
        f"          }}\n"
        f"        }},\n"
        f'        "es" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f"            \"value\" : {q(es)}\n"
        f"          }}\n"
        f"        }}\n"
        f"      }}\n"
        f"    }}"
    )


def insert_catalog_entries(entradas):
    """Inserta las 204 claves nuevas en Localizable.xcstrings como UN bloque, ordenado
    alfabéticamente entre sí, justo antes del cierre de "strings" — nunca con json.dump (ver nota
    de GAP en el reporte del implementador: el archivo NO está globalmente ordenado, así que
    "insertar en su lugar" no tiene una única posición correcta; anexar un bloque propio, sin
    tocar ninguna entrada existente, es la operación de menor riesgo)."""
    text = open(CATALOG, encoding="utf-8").read()
    keys = []
    for e in entradas:
        fid = e["id"]
        for campo in ("nombre", "paraQue", "dondeVive"):
            key = f"ensenanza.{fid}.{campo}"
            en = e[campo]["en"]
            es = e[campo]["es"]
            keys.append((key, en, es))
    keys.sort(key=lambda t: t[0])
    existentes = set(re.findall(r'^\s*"([^"]+)" : \{', text, re.M))
    for key, _, _ in keys:
        if key in existentes:
            raise SystemExit(f"la clave {key!r} ya existe en el catálogo — ¿ya se corrió este generador?")
    blocks = ",\n".join(catalog_entry_text(k, en, es) for k, en, es in keys)
    # El último elemento de "strings" no lleva coma final; el marcador es la línea `  },\n  "version"`.
    marker = '\n  },\n  "version"'
    idx = text.rfind(marker)
    if idx == -1:
        raise SystemExit("no encontré el cierre de \"strings\" en Localizable.xcstrings — formato inesperado")
    nuevo = text[:idx] + ",\n" + blocks + text[idx:]
    open(CATALOG, "w", encoding="utf-8").write(nuevo)
    return len(keys)


def main():
    check_only = "--check" in sys.argv
    desde, entradas = load_semilla()
    for e in entradas:
        e["desde_efectivo"] = e.get("desde", desde)
    check_mapa()
    print(f"semilla OK: {len(entradas)} entradas, desde={desde}, mapa cruzado con docs/appmap/mapa")
    if check_only:
        return 0

    os.makedirs(SRC, exist_ok=True)
    fid_path = os.path.join(SRC, "FuncionalidadID.swift")
    open(fid_path, "w", encoding="utf-8").write(gen_funcionalidad_id(entradas))
    print(f"escrito {fid_path}")

    by_pestana = {p: [] for p in PESTANAS_ORDEN}
    for e in entradas:
        by_pestana[e["pestana"]].append(e)
    for p in PESTANAS_ORDEN:
        path = os.path.join(SRC, f"Registro+{p.capitalize()}.swift")
        open(path, "w", encoding="utf-8").write(gen_registro_extension(p, by_pestana[p]))
        print(f"escrito {path} ({len(by_pestana[p])} entradas)")

    n = insert_catalog_entries(entradas)
    print(f"insertadas {n} claves nuevas en {CATALOG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
