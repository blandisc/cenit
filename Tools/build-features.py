#!/usr/bin/env python3
"""Regenera las secciones de producto de docs/FEATURES.md desde el registro de enseñanza (L9b,
épico FER-428, FER-439) — para que la guía de funcionalidades no se pudra a mano.

Fuente: `Tools/ensenanza-semilla.json` (qué funcionalidades hay, en qué pestaña, qué requieren,
desde cuándo) + `Cenit/Resources/Localizable.xcstrings` (los textos `en` de
`ensenanza.<id>.{nombre,paraQue,dondeVive}` — FEATURES.md es inglés y el catálogo es la verdad
que la app muestra). Un `test_semillaCoincideConRegistro` en `Packages/CenitEnsenanza` garantiza
que la semilla dice lo mismo que el registro Swift.

Escribe SOLO lo que está entre `<!-- GENERATED:ensenanza:<seccion> START -->` y
`<!-- GENERATED:ensenanza:<seccion> END -->` para las secciones `at-a-glance`, `hoy`,
`tendencias`, `entrenar`, `ajustes` y `fuera-del-iphone` (la pestaña `transversal` del registro).
Todo lo demás del archivo (atribución, privacidad, disclaimer, Data Sources, Illness
early-warning, onboarding, gates, Support) es manual y se conserva byte a byte. La primera vez que
una sección no trae marcadores, los inserta alrededor de la sección existente (reemplazando su
cuerpo) — o, si la sección no existe, la crea antes de `## Data Sources`.

Formato por sección: la tabla «At a glance» (Tab · What it is) lleva una fila por pestaña con
≥ 1 funcionalidad de Ayuda, con la frase fija de FRASE; cada sección de pestaña lleva esa frase y
una lista `- **<nombre>** — <paraQue> _(<dondeVive>)_`, más `Needs Apple Watch` cuando
`requiere` incluye `watch` y `since <desde>` solo si ≠ la versión base de la semilla.

Uso: build-features.py [--check] [--repo <raíz>]
  --check: no escribe; falla (exit 1, con el diff resumido) si docs/FEATURES.md difiere de lo
           que se generaría — así CI atrapa el desfase.
Exit 0 = verde / escrito; 1 = desfase (--check); 2 = error de entrada (falta una fuente, un
anchor o una clave del catálogo).
"""
import argparse
import difflib
import json
import os
import sys
import textwrap

SEED_PATH = "Tools/ensenanza-semilla.json"
CATALOG_PATH = "Cenit/Resources/Localizable.xcstrings"
FEATURES_PATH = "docs/FEATURES.md"

MARK_START = "<!-- GENERATED:ensenanza:{seccion} START -->"
MARK_END = "<!-- GENERATED:ensenanza:{seccion} END -->"

SECCIONES = ["at-a-glance", "hoy", "tendencias", "entrenar", "ajustes", "fuera-del-iphone"]
PESTANA_DE_SECCION = {
    "hoy": "hoy",
    "tendencias": "tendencias",
    "entrenar": "entrenar",
    "ajustes": "ajustes",
    "fuera-del-iphone": "transversal",
}
# Solo las cuatro pestañas reales van a la tabla «At a glance» (la columna se llama Tab);
# `transversal` tiene su propia sección más abajo.
PESTANAS_TABLA = ["hoy", "tendencias", "entrenar", "ajustes"]
ROTULO = {"hoy": "Hoy", "tendencias": "Tendencias", "entrenar": "Entrenar", "ajustes": "Ajustes"}
# La frase fija por pestaña: la misma que ya decía la tabla «At a glance» a mano.
FRASE = {
    "hoy": "The verdict home — today's readiness word (El Ecosistema) and La Matriz of signals.",
    "tendencias": "Your body over time — the trend of every signal, plus sleep, stress, vitals, "
                  "body composition and longevity.",
    "entrenar": "The training planner — plan, routines, a guided live strength session, plus "
                "Breathe and Intervals.",
    "ajustes": "Profile, units, data & backup, illness watch, reminders, support.",
    "transversal": "Beyond the four tabs — widgets, the Live Activity, Apple Watch, local notices "
                   "and every gesture with its button.",
}
# Encabezados de las secciones (la primera corrida los busca para envolver el cuerpo existente).
ENCABEZADO = {
    "hoy": "## Hoy — Today",
    "tendencias": "## Tendencias — your body over time",
    "entrenar": "## Entrenar — Train",
    "ajustes": "## Ajustes — Settings",
    "fuera-del-iphone": "## Fuera del iPhone — widgets, Live Activity, Watch",
}
ENCABEZADO_AT_A_GLANCE = "## At a glance"
# Ante quién se inserta una sección nueva la primera vez (la sección manual que sigue a las de
# pestaña).
ANCLA_SECCION_NUEVA = "## Data Sources"
ANCHO = 100


class EntradaInvalida(Exception):
    """Falta una fuente, un anchor del archivo o una clave del catálogo (exit 2)."""


# MARK: - Fuentes

def load_seed(repo):
    path = os.path.join(repo, SEED_PATH)
    if not os.path.exists(path):
        raise EntradaInvalida(f"no encontré {SEED_PATH}")
    data = json.load(open(path, encoding="utf-8"))
    return data["desde"], data["entradas"]


def load_catalog_en(repo):
    """{clave: valor en} del catálogo — solo lo que empieza con `ensenanza.` (el archivo pesa ~2 MB)."""
    path = os.path.join(repo, CATALOG_PATH)
    if not os.path.exists(path):
        raise EntradaInvalida(f"no encontré {CATALOG_PATH}")
    strings = json.load(open(path, encoding="utf-8"))["strings"]
    out = {}
    for key, entry in strings.items():
        if not key.startswith("ensenanza."):
            continue
        try:
            out[key] = entry["localizations"]["en"]["stringUnit"]["value"]
        except (KeyError, TypeError):
            continue
    return out


def textos(entrada, catalog):
    fid = entrada["id"]
    out = {}
    for campo in ("nombre", "paraQue", "dondeVive"):
        key = f"ensenanza.{fid}.{campo}"
        if key not in catalog or not catalog[key]:
            raise EntradaInvalida(f"falta `{key}` (valor `en`) en {CATALOG_PATH}")
        out[campo] = catalog[key]
    return out


# MARK: - Render

def _wrap(texto, subsequent_indent=""):
    """Envuelve a ANCHO columnas como el resto del archivo (los ítems de lista siguen con dos
    espacios, la prosa sin sangría)."""
    return textwrap.fill(
        texto, width=ANCHO, subsequent_indent=subsequent_indent,
        break_long_words=False, break_on_hyphens=False,
    )


def render_at_a_glance(entradas):
    con_ayuda = {e["pestana"] for e in entradas if "ayuda" in e.get("piezas", [])}
    lines = ["| Tab | What it is |", "| --- | --- |"]
    for pestana in PESTANAS_TABLA:
        if pestana in con_ayuda:
            lines.append(f"| **{ROTULO[pestana]}** | {FRASE[pestana]} |")
    return "\n".join(lines)


def render_pestana(pestana, entradas, catalog, desde_base):
    mias = [e for e in entradas if e["pestana"] == pestana and "ayuda" in e.get("piezas", [])]
    lines = [_wrap(FRASE[pestana]), ""]
    for e in mias:
        t = textos(e, catalog)
        item = f"- **{t['nombre']}** — {t['paraQue']} _({t['dondeVive']})_"
        if "watch" in e.get("requiere", []):
            item += " · Needs Apple Watch"
        desde = e.get("desde", desde_base)
        if desde != desde_base:
            item += f" · since {desde}"
        lines.append(_wrap(item, subsequent_indent="  "))
    return "\n".join(lines)


def render(seccion, entradas, catalog, desde_base):
    if seccion == "at-a-glance":
        return render_at_a_glance(entradas)
    return render_pestana(PESTANA_DE_SECCION[seccion], entradas, catalog, desde_base)


# MARK: - Marcadores

def _bloque(seccion, cuerpo):
    return "\n".join([MARK_START.format(seccion=seccion), cuerpo, MARK_END.format(seccion=seccion)])


def _reemplazar_entre_marcadores(text, seccion, cuerpo):
    start = MARK_START.format(seccion=seccion)
    end = MARK_END.format(seccion=seccion)
    i = text.find(start)
    j = text.find(end)
    if i == -1 or j == -1 or j < i:
        raise EntradaInvalida(f"marcadores de `{seccion}` rotos en {FEATURES_PATH} (START sin END o al revés)")
    return text[:i] + _bloque(seccion, cuerpo) + text[j + len(end):]


def _primera_vez_at_a_glance(text, cuerpo):
    """Envuelve la tabla `| Tab | What it is |` de «At a glance» (solo la tabla; la prosa
    alrededor es manual)."""
    lines = text.split("\n")
    try:
        h = lines.index(ENCABEZADO_AT_A_GLANCE)
    except ValueError:
        raise EntradaInvalida(f"no encontré `{ENCABEZADO_AT_A_GLANCE}` en {FEATURES_PATH}")
    i = next((k for k in range(h, len(lines)) if lines[k].startswith("| Tab |")), None)
    if i is None:
        raise EntradaInvalida(f"no encontré la tabla `| Tab | What it is |` bajo `{ENCABEZADO_AT_A_GLANCE}`")
    j = i
    while j < len(lines) and lines[j].startswith("|"):
        j += 1
    return "\n".join(lines[:i] + [_bloque("at-a-glance", cuerpo)] + lines[j:])


def _primera_vez_pestana(text, seccion, cuerpo):
    """Reemplaza el cuerpo de `## <Encabezado>` (hasta el `---` que cierra la sección) por el
    bloque generado; si la sección no existe, la crea antes de ANCLA_SECCION_NUEVA."""
    lines = text.split("\n")
    encabezado = ENCABEZADO[seccion]
    if encabezado in lines:
        h = lines.index(encabezado)
        j = next((k for k in range(h + 1, len(lines)) if lines[k].strip() == "---"), None)
        if j is None:
            raise EntradaInvalida(f"la sección `{encabezado}` no cierra con `---` en {FEATURES_PATH}")
        nuevo = [encabezado, "", _bloque(seccion, cuerpo), ""]
        return "\n".join(lines[:h] + nuevo + lines[j:])
    if ANCLA_SECCION_NUEVA not in lines:
        raise EntradaInvalida(f"no encontré `{ANCLA_SECCION_NUEVA}` para insertar `{encabezado}` en {FEATURES_PATH}")
    a = lines.index(ANCLA_SECCION_NUEVA)
    nuevo = [encabezado, "", _bloque(seccion, cuerpo), "", "---", ""]
    return "\n".join(lines[:a] + nuevo + lines[a:])


def regenerate(text, entradas, catalog, desde_base):
    for seccion in SECCIONES:
        cuerpo = render(seccion, entradas, catalog, desde_base)
        if MARK_START.format(seccion=seccion) in text:
            text = _reemplazar_entre_marcadores(text, seccion, cuerpo)
        elif seccion == "at-a-glance":
            text = _primera_vez_at_a_glance(text, cuerpo)
        else:
            text = _primera_vez_pestana(text, seccion, cuerpo)
    return text


# MARK: - CLI

def build(repo):
    """→ (texto actual, texto regenerado)."""
    desde_base, entradas = load_seed(repo)
    catalog = load_catalog_en(repo)
    path = os.path.join(repo, FEATURES_PATH)
    if not os.path.exists(path):
        raise EntradaInvalida(f"no encontré {FEATURES_PATH}")
    actual = open(path, encoding="utf-8").read()
    return actual, regenerate(actual, entradas, catalog, desde_base)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--check", action="store_true", help="no escribe; falla si FEATURES.md está desfasado")
    args = ap.parse_args(argv)

    try:
        actual, nuevo = build(args.repo)
    except EntradaInvalida as e:
        print(f"❌ build-features: {e}")
        return 2

    if actual == nuevo:
        print(f"✅ build-features: {FEATURES_PATH} está al día con el registro")
        return 0
    if args.check:
        diff = list(difflib.unified_diff(
            actual.split("\n"), nuevo.split("\n"),
            fromfile=FEATURES_PATH, tofile=f"{FEATURES_PATH} (regenerado)", lineterm="", n=1,
        ))
        print(f"❌ build-features: {FEATURES_PATH} está desfasado del registro — corre "
              f"`python3 Tools/build-features.py` y commitea el resultado.")
        for line in diff[:60]:
            print("   " + line)
        if len(diff) > 60:
            print(f"   … ({len(diff) - 60} líneas más)")
        return 1
    open(os.path.join(args.repo, FEATURES_PATH), "w", encoding="utf-8").write(nuevo)
    print(f"📝 build-features: {FEATURES_PATH} regenerado desde el registro")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
