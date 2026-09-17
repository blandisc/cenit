#!/usr/bin/env python3
"""Dos guardas sobre el catálogo de strings del app. Ambas fallan el CI (`i18n-guard`).

1. **missing-es** — una clave del catálogo sin traducción `es`.
   La auditoría de Hoy (FER-audit) encontró strings en inglés que veía un usuario es-MX
   («Getting to know you», «Unloading»…): no había ningún gate para «falta es». Este lo cierra
   sin exigir traducir las 129 heredadas de golpe — usa una línea base (`Tools/i18n-es-baseline.txt`)
   y solo falla sobre las que se agreguen de ahora en adelante. Para bajar la base: traduce y
   quita su clave del archivo.

2. **missing-key** — una clave que el CÓDIGO usa y que NO existe en el catálogo (FER-123).
   El chequeo 1 tenía un falso negativo estructural: solo itera las claves que YA están en el
   catálogo. Una clave nueva (`String(localized: "prep.titulo", defaultValue: "Preparation")`)
   que nunca se agregó al catálogo es invisible para él —no está, luego no se itera, luego pasa
   en verde—. Y ese es justo el error más común al agregar copy: en FER-119 entraron 6 strings
   nuevos sin catálogo y el gate quedó verde; los cazó a mano el verificador independiente.
   Este chequeo va en la dirección contraria: extrae del Swift las claves que se usan y falla si
   alguna no está en su catálogo. Su línea base es `Tools/i18n-keys-baseline.txt`.

   Los literales con interpolación (`Text("… \\(a) …")` / `String(localized: "… \\(a)")`) también
   entran (FER-493). El runtime de Foundation genera claves con `%@` / `%lld` (nunca posicionales
   `%1$@`); el extractor convierte cada `\\(…)` en un patrón que casa esos especificadores y
   exige que alguna clave del catálogo del scope lo case. Si solo existe la variante posicional,
   el gate falla — FER-488 cayó a inglés en silencio por exactamente eso. Lo heredado se congela
   en `Tools/i18n-keys-baseline.txt` (issue de copy aparte).

   (`Tools/find-dead-strings.py` recorre el mismo eje al revés: claves del catálogo que el código
   ya no usa. Aquel decide qué sobra; este, qué falta.)

Recordatorio de la regla dura del repo: una clave nueva va SIEMPRE bajo la llave `es`, nunca bajo
`es-MX` — una clave es-MX secuestra el idioma y tira el app entero a inglés.
"""
import json, sys, os, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
CAT = "Cenit/Resources/Localizable.xcstrings"
BASELINE = os.path.join(HERE, "i18n-es-baseline.txt")
KEYS_BASELINE = os.path.join(HERE, "i18n-keys-baseline.txt")

# ---------------------------------------------------------------------------- 1. missing-es

def missing_es():
    strings = json.load(open(CAT, encoding="utf-8")).get("strings", {})
    out = set()
    for key, entry in strings.items():
        # una clave vacía "" no necesita traducción; el resto sí.
        if key.strip() == "": continue   # claves de formato/espaciado no son copy
        es = entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("value")
        if not es:
            out.add(key)
    return out

# ---------------------------------------------------------------------------- 2. missing-key

# Cada target embebido tiene SU catálogo, y `String(localized:)`/`Text(_:)` resuelven contra el
# bundle principal de quien los hospeda. Por eso una clave del widget no se busca en el catálogo
# del app: se buscaría siempre en vano.
CATALOGS = {
    "app":     "Cenit/Resources/Localizable.xcstrings",
    "widgets": "CenitWidgets/Resources/Localizable.xcstrings",
    "watch":   "CenitWatch/Resources/Localizable.xcstrings",
}
# El código compartido (CenitShared, Packages) se compila DENTRO de varios targets, así que su
# clave puede vivir legítimamente en cualquiera de los tres catálogos: ahí se acepta la unión.
SCOPES = [
    ("CenitWidgets", ("widgets",)),
    ("CenitWatch",   ("watch",)),
    ("CenitShared",  ("app", "widgets", "watch")),
    ("Packages",     ("app", "widgets", "watch")),
    ("CenitApp",     ("app",)),
    ("Cenit",        ("app",)),
]
SKIP_PATH = re.compile(r"/\.build/|/Tests/|/Preview Content/")

# Lo que vive tras `#if DEBUG` o dentro de un `#Preview` no llega al usuario (mismo recorte que
# `check-hardcoded-strings.py`), conservando los saltos de línea para no mover los números.
PREVIEW = re.compile(r"#if DEBUG.*?#endif|#Preview\([^)]*\)\s*\{.*?\n\}", re.S)

# Un literal de una línea, seguido de `,` o `)`. El lookahead es la defensa contra el falso
# positivo clásico: `Text(" · " + otro)` NO localiza nada (es el init de String, no el de
# LocalizedStringKey), y sin él lo reportaríamos como clave faltante.
LIT = r'"((?:[^"\\\n]|\\.)*)"\s*(?=[,)])'
PATTERNS = [
    re.compile(r'String\(\s*localized:\s*' + LIT + r'\s*,\s*defaultValue:'),  # la clave es el 1er literal
    re.compile(r'String\(\s*localized:\s*' + LIT),                            # la clave ES el texto
    re.compile(r'\bText\(\s*' + LIT),
    re.compile(r'\bLocalizedStringKey\(\s*' + LIT),
]

_ESC = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}
_UNI = re.compile(r"\\u\{([0-9A-Fa-f]+)\}")

def unescape(lit):
    """Del literal como se escribe en Swift al texto que Xcode guarda como clave."""
    lit = _UNI.sub(lambda m: chr(int(m.group(1), 16)), lit)
    out, i = [], 0
    while i < len(lit):
        if lit[i] == "\\" and i + 1 < len(lit):
            out.append(_ESC.get(lit[i + 1], lit[i + 1])); i += 2
        else:
            out.append(lit[i]); i += 1
    return "".join(out)

# Marcador interno al convertir `\(…)` → patrón de catálogo. El runtime emite `%@`/`%lld`/…
# sin índice posicional; `%1$@` NO debe casar (FER-488/FER-493).
_ARG = "\x00ARG\x00"
_ARG_RE = r"%(?:@|lld|ld|d|lf|f|\.\d+f|lu|u|s)"

def interpolation_pattern(raw):
    r"""Del literal Swift con `\(…)` al regex que casa la clave del catálogo.

    Cada interpolación (paréntesis balanceados, puede anidar) se sustituye por un marcador;
    el resto pasa por unescape + re.escape; un `%` literal se vuelve `%%` antes de escapar.
    Devuelve `("pattern", regex, literal_original)`.
    """
    parts, i, n = [], 0, len(raw)
    while i < n:
        if raw[i] == "\\" and i + 1 < n and raw[i + 1] == "(":
            depth, j = 1, i + 2
            while j < n and depth:
                if raw[j] == "(": depth += 1
                elif raw[j] == ")": depth -= 1
                j += 1
            parts.append(_ARG)
            i = j
        else:
            start = i
            while i < n and not (raw[i] == "\\" and i + 1 < n and raw[i + 1] == "("):
                i += 1
            chunk = raw[start:i].replace("%", "%%")
            parts.append(re.escape(unescape(chunk)))
    return ("pattern", "".join(parts).replace(_ARG, _ARG_RE), raw)

def extract(src):
    """{clave|patrón: línea} de cada clave que un archivo Swift usa. Aquí vive TODA la heurística
    (y `--self-test` la clava contra una tabla de casos, para que nadie la deje ciega sin notarlo).

    Clave exacta: str. Interpolada: `("pattern", regex, literal_original)` — el runtime genera
    `%@`/`%lld` no posicionales; el patrón los casa y rechaza `%1$@` (FER-493)."""
    src = PREVIEW.sub(lambda m: "\n" * m.group(0).count("\n"), src)
    # Las líneas de comentario (`//`, `///`) se vacían, no se borran: los números siguen ciertos.
    src = "\n".join("" if l.lstrip().startswith("//") else l for l in src.splitlines())
    out, seen = {}, set()
    for pat in PATTERNS:
        for m in pat.finditer(src):
            if m.start() in seen: continue     # `defaultValue:` gana sobre el patrón corto
            seen.add(m.start())
            raw = m.group(1)
            if "\\(" in raw:
                key = interpolation_pattern(raw)
            else:
                key = unescape(raw)
                if not key.strip(): continue   # espaciado puro no es copy
            out.setdefault(key, src.count("\n", 0, m.start()) + 1)
    return out

def used_keys():
    """{clave|patrón: {cats, sites}} de cada clave que el Swift usa, con el catálogo donde puede vivir."""
    found = {}
    for root, cats in SCOPES:
        for path in sorted(glob.glob(f"{root}/**/*.swift", recursive=True)):
            if SKIP_PATH.search("/" + path): continue
            for key, line in extract(open(path, encoding="utf-8").read()).items():
                found.setdefault(key, {"cats": set(), "sites": []})
                found[key]["cats"].update(cats)
                found[key]["sites"].append(f"{path}:{line}")
    return found

def missing_keys():
    catalogs = {name: set(json.load(open(p, encoding="utf-8")).get("strings", {}))
                for name, p in CATALOGS.items() if os.path.exists(p)}
    out = {}
    for key, info in used_keys().items():
        scope = set().union(*(catalogs.get(c, set()) for c in info["cats"]))
        if isinstance(key, tuple) and key and key[0] == "pattern":
            _, regex, lit = key
            if any(re.fullmatch(regex, ck) for ck in scope): continue
            out[lit] = info["sites"]          # reporta el literal original (repr estable)
        else:
            if key in scope: continue
            out[key] = info["sites"]
    return out

# ---------------------------------------------------------------------------- main

def read_baseline(path):
    if not os.path.exists(path): return set()
    return {l.rstrip("\n") for l in open(path, encoding="utf-8")
            if l.strip() and not l.startswith("#")}

def check_es():
    missing = missing_es()
    base = read_baseline(BASELINE)
    nuevas = sorted(missing - base)
    if nuevas:
        print(f"❌ {len(nuevas)} clave(s) NUEVA(s) sin traducción es-MX (agrégalas al catálogo):")
        print("\n".join(f"  {k!r}" for k in nuevas[:40]))
        return 1
    # Aviso amable si la base bajó (para poder recortarla).
    resueltas = base - missing
    if resueltas:
        print(f"ℹ️  {len(resueltas)} de la base ya tienen es — quítalas de i18n-es-baseline.txt.")
    print(f"✅ sin claves nuevas sin es ({len(missing)} heredadas en la base)")
    return 0

def check_keys():
    missing = missing_keys()
    base = read_baseline(KEYS_BASELINE)
    # La línea base se escribe con `repr()` para que un salto de línea o un espacio al final
    # sean visibles en el archivo (y en el diff) en vez de perderse.
    nuevas = sorted(k for k in missing if repr(k) not in base)
    if nuevas:
        print(f"❌ {len(nuevas)} clave(s) usada(s) en el código que NO están en el catálogo.")
        print("   Agrégalas a Cenit/Resources/Localizable.xcstrings con su valor `es`")
        print("   (SIEMPRE bajo la llave «es», nunca «es-MX»), o —si de verdad no se traduce—")
        print("   añade su repr a Tools/i18n-keys-baseline.txt con una razón.")
        for k in nuevas[:40]:
            print(f"  {missing[k][0]}\n      {k!r}")
        if len(nuevas) > 40: print(f"  … y {len(nuevas) - 40} más")
        return 1
    resueltas = base - {repr(k) for k in missing}
    if resueltas:
        print(f"ℹ️  {len(resueltas)} de la base de claves ya no falta(n) — quítalas de i18n-keys-baseline.txt.")
    print(f"✅ toda clave usada existe en su catálogo ({len(missing)} excepciones en la base)")
    return 0

# ---------------------------------------------------------------------------- 3. glosario es (FER-503 · C5)
#
# Una cosa, un nombre. Dos guardas:
#   (a) palabras prohibidas en valores `es` (Apple Health, entreno, bpm, teléfono, equipo-aparato…);
#   (b) claves compartidas entre iPhone / Watch / widgets deben tener el MISMO `es`.
#
# Decisión bpm vs lpm (FER-503): el catálogo ya predominaba en «lpm» (29 vs 7); LENGUAJE §8
# decía «bpm se mantiene» y estaba rancio. Canónico = **lpm**; el gate prohíbe «bpm» en `es`.

FORBIDDEN_ES = [
    # (regex, etiqueta_para_mensaje)
    (re.compile(r"Apple Health"), "Apple Health → Apple Salud"),
    (re.compile(r"\bentrenos?\b"), "entreno(s) → entrenamiento(s)"),
    (re.compile(r"\bbpm\b"), "bpm → lpm"),
    (re.compile(r"\btel[eé]fono\b", re.I), "teléfono → iPhone / dispositivo"),
    # Solo el sentido «aparato» (no el gym «Equipo» / «Sin equipo» / «Elige el equipo»).
    (re.compile(r"\b(?:tu|este|propio) equipo\b"), "equipo (aparato) → dispositivo / iPhone"),
]

def _es_value(entry):
    return (entry.get("localizations") or {}).get("es", {}).get("stringUnit", {}).get("value")

def forbidden_es_hits(catalog_path=CAT):
    """[(clave, regla, fragmento_es)] de valores es que rompen el glosario."""
    strings = json.load(open(catalog_path, encoding="utf-8")).get("strings", {})
    out = []
    for key, entry in strings.items():
        es = _es_value(entry)
        if not es:
            continue
        for rx, label in FORBIDDEN_ES:
            if rx.search(es):
                out.append((key, label, es))
                break
    return out

def check_forbidden_es():
    # Los tres catálogos: una fuga en Watch/widgets también llega al usuario.
    rc = 0
    for name, path in CATALOGS.items():
        if not os.path.exists(path):
            continue
        hits = forbidden_es_hits(path)
        if hits:
            print(f"❌ {name}: {len(hits)} valor(es) es con palabra prohibida del glosario (FER-503):")
            for key, label, es in hits[:40]:
                print(f"  [{label}] {key!r}\n      {es!r}")
            if len(hits) > 40:
                print(f"  … y {len(hits) - 40} más")
            rc = 1
        else:
            print(f"✅ {name}: sin palabras prohibidas del glosario en es")
    return rc

def shared_es_diffs():
    """Claves presentes en ≥2 catálogos cuyo `es` difiere. Devuelve [(clave, {cat: es})]."""
    loaded = {}
    for name, path in CATALOGS.items():
        if os.path.exists(path):
            loaded[name] = json.load(open(path, encoding="utf-8")).get("strings", {})
    # Pares (y el triple) — toda clave en al menos dos catálogos.
    names = list(loaded)
    out = []
    seen = set()
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            for key in set(loaded[a]) & set(loaded[b]):
                if key in seen:
                    continue
                vals = {}
                for n in names:
                    if key not in loaded[n]:
                        continue
                    es = _es_value(loaded[n][key])
                    if es:
                        vals[n] = es
                if len(vals) >= 2 and len(set(vals.values())) > 1:
                    seen.add(key)
                    out.append((key, vals))
    return out

def check_shared_es():
    diffs = shared_es_diffs()
    if diffs:
        print(f"❌ {len(diffs)} clave(s) compartida(s) con `es` distinto entre catálogos (FER-503):")
        for key, vals in diffs[:40]:
            detail = ", ".join(f"{n}={v!r}" for n, v in sorted(vals.items()))
            print(f"  {key!r}: {detail}")
        if len(diffs) > 40:
            print(f"  … y {len(diffs) - 40} más")
        return 1
    print("✅ claves compartidas: mismo `es` entre iPhone / Watch / widgets")
    return 0

# ---------------------------------------------------------------------------- --self-test

# Lo que el extractor DEBE ver y lo que DEBE ignorar. La primera mitad son los seis strings que
# FER-119 metió sin catálogo; la segunda, cada falso positivo que costó trabajo descartar.
# Casos exactos: (src, {claves_str}). Casos patrón FER-493: (src, ("pattern", [sí], [no])).
CASES = [
    (r'String(localized: "prep.titulo", defaultValue: "Preparation")', {"prep.titulo"}),
    (r'String(localized: "Not enough signal")', {"Not enough signal"}),
    (r'Text("Preparation").font(InstrumentoType.grotesk(12))', {"Preparation"}),
    (r'LocalizedStringKey("hero.title.full")', {"hero.title.full"}),
    (r'String(' + "\n" + r'    localized: "multi.linea",' + "\n" + r'    defaultValue: "x")', {"multi.linea"}),
    (r'Text("linea\nrota")', {"linea\nrota"}),                        # escapes resueltos…
    (r'Text("punto\u{00B7}medio")', {"punto\u00b7medio"}),            # …también los unicode
    (r'Text(" \u{00B7} " + String(localized: "x"))', {"x"}),           # la concatenación NO localiza
    (r'Text(verbatim: "crudo")', set()),
    (r'// Text("comentado")', set()),
    ("#if DEBUG\nText(\"solo debug\")\n#endif", set()),
    (r'Text("")', set()),
    (r'Text(titulo)', set()),
    # FER-493 · interpoladas → patrón %@/%lld (nunca posicional). Si alguien vuelve el `continue`, fallan.
    (r'Text("Today I keep \(a) at \(b)")',
     ("pattern", ["Today I keep %@ at %@", "Today I keep %lld at %lld"],
                 ["Today I keep %1$@ at %2$@"])),
    (r'Text("\(days) days ago")',
     ("pattern", ["%lld days ago"], ["%1$lld days ago"])),
    (r'Text("Set \(StrengthDisplay.weight(kg, system: u)) done")',
     ("pattern", ["Set %@ done", "Set %lld done"], ["Set %1$@ done"])),
    (r'Text("\(p)% of goal")',
     ("pattern", ["%lld%% of goal", "%@%% of goal"], ["%1$lld%% of goal"])),
    (r'String(localized: "Confidence: \(n) of \(t) nights")',
     ("pattern", ["Confidence: %@ of %@ nights", "Confidence: %lld of %lld nights"],
                 ["Confidence: %1$@ of %2$@ nights"])),
    # sin interpolación sigue siendo clave exacta (no regresión)
    (r'Text("Preparation")', {"Preparation"}),
]

def _patterns(extracted):
    return [k for k in extracted if isinstance(k, tuple) and k and k[0] == "pattern"]

def _exact(extracted):
    return {k for k in extracted if not (isinstance(k, tuple) and k and k[0] == "pattern")}

def self_test():
    malos = []
    for src, esperado in CASES:
        got = extract(src)
        if isinstance(esperado, tuple) and esperado and esperado[0] == "pattern":
            _, yes, no = esperado
            pats = _patterns(got)
            if len(pats) != 1 or _exact(got):
                malos.append((src, esperado, got)); continue
            regex = pats[0][1]
            if any(not re.fullmatch(regex, k) for k in yes) or any(re.fullmatch(regex, k) for k in no):
                malos.append((src, esperado, (regex, pats[0][2])))
        else:
            if _exact(got) != esperado or _patterns(got):
                malos.append((src, esperado, got))
    for src, esperado, real in malos:
        print(f"❌ {src!r}\n   esperaba {esperado!r}\n   obtuvo   {real!r}")
    if malos:
        print(f"❌ self-test: {len(malos)}/{len(CASES)} caso(s) del extractor fallaron.")
        return 1
    print(f"✅ self-test: {len(CASES)} casos del extractor OK")

    # FER-503 · glosario: las regex de palabras prohibidas + la comparación de compartidas.
    glosario_malos = []
    # (a) cada regla debe disparar sobre un positivo y callar sobre un negativo.
    POS = [
        ("Apple Health no está", "Apple Health → Apple Salud"),
        ("Recordatorio de entreno", "entreno(s) → entrenamiento(s)"),
        ("máx 180 bpm", "bpm → lpm"),
        ("en tu teléfono", "teléfono → iPhone / dispositivo"),
        ("en tu equipo", "equipo (aparato) → dispositivo / iPhone"),
        ("mi propio equipo", "equipo (aparato) → dispositivo / iPhone"),
    ]
    NEG = [
        "Conectar Apple Salud",
        "Recordatorio de entrenamiento",
        "máx 180 lpm",
        "en tu iPhone",
        "en tu dispositivo",
        "Sin equipo",       # gym — no aparato
        "Elige el equipo",  # gym
        "Equipo",           # gym label
    ]
    for sample, label in POS:
        hit = next((lab for rx, lab in FORBIDDEN_ES if rx.search(sample)), None)
        if hit != label:
            glosario_malos.append(f"POS {sample!r}: esperaba {label!r}, obtuvo {hit!r}")
    for sample in NEG:
        hit = next((lab for rx, lab in FORBIDDEN_ES if rx.search(sample)), None)
        if hit is not None:
            glosario_malos.append(f"NEG {sample!r}: no debía disparar, obtuvo {hit!r}")

    # (b) shared_es_diffs ve divergencia cuando dos catálogos discrepan.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        def write_cat(name, mapping):
            path = os.path.join(tmp, f"{name}.xcstrings")
            strings = {k: {"localizations": {"es": {"stringUnit": {"state": "translated", "value": v}}}}
                       for k, v in mapping.items()}
            json.dump({"strings": strings}, open(path, "w", encoding="utf-8"))
            return path
        pa = write_cat("app", {"Next": "Siguiente", "Paused": "En pausa", "SoloApp": "x"})
        pw = write_cat("watch", {"Next": "Sigue", "Paused": "En pausa", "SoloWatch": "y"})
        # monkey-patch CATALOGS for this check
        global CATALOGS
        old = CATALOGS
        try:
            CATALOGS = {"app": pa, "watch": pw, "widgets": write_cat("widgets", {})}
            diffs = dict(shared_es_diffs())
            if "Next" not in diffs:
                glosario_malos.append("shared_es_diffs debió reportar «Next» (Siguiente≠Sigue)")
            if "Paused" in diffs:
                glosario_malos.append("shared_es_diffs NO debió reportar «Paused» (iguales)")
            # negativo: catálogos alineados → sin diffs
            CATALOGS = {
                "app": write_cat("app2", {"Next": "Sigue"}),
                "watch": write_cat("watch2", {"Next": "Sigue"}),
                "widgets": write_cat("w2", {}),
            }
            if shared_es_diffs():
                glosario_malos.append("shared_es_diffs debió quedar vacío con es idéntico")
        finally:
            CATALOGS = old

    if glosario_malos:
        for m in glosario_malos:
            print(f"❌ glosario self-test: {m}")
        print(f"❌ self-test glosario: {len(glosario_malos)} fallo(s)")
        return 1
    print("✅ self-test glosario: palabras prohibidas + claves compartidas OK")
    return 0

if "--self-test" in sys.argv:
    sys.exit(self_test())
sys.exit(check_es() | check_keys() | check_forbidden_es() | check_shared_es())
