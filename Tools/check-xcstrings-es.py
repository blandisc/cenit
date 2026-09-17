#!/usr/bin/env python3
"""Seis guardas sobre el catálogo de strings del app. Fallan el CI (`i18n-guard`).

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

3. **glosario-es** (FER-503 · C5) — palabras/frases prohibidas en `es`
   («Apple Health», «entreno(s)», «teléfono», «bpm» — canónico **lpm** —, frases de
   «equipo» como aparato). «Sin equipo» (gimnasio) se permite.

4. **shared-es** (FER-503 · C5) — claves presentes en ≥2 de los tres catálogos
   (iPhone / Watch / widgets) deben compartir el mismo `es`.

5. **plural-blind** (FER-505 · C7) — clave cuyo `es` tiene `%lld` + sustantivo en plural
   (palabra tras `%lld` que termina en «s») SIN `variations.plural`. Molde: `%lld sets` /
   `%lld exercises`. Lo heredado fuera del censo C7 se congela en
   `Tools/i18n-plural-baseline.txt`. Aplica a iPhone / Watch / widgets.

6. **es-eq-en** (FER-505 · C7) — clave con palabra española cuyo `es == en` (o `en` ausente y
   `es == clave`). Caza «Empezar», «Tendencias», «✓ Serie» que el guard de ñ/acentos no ve.
   Allow-list de marca (`Cénit`). Lo heredado fuera de C7 se congela en
   `Tools/i18n-es-eq-en-baseline.txt`. Aplica a iPhone / Watch / widgets.

Recordatorio de la regla dura del repo: una clave nueva va SIEMPRE bajo la llave `es`, nunca bajo
`es-MX` — una clave es-MX secuestra el idioma y tira el app entero a inglés.
"""
import json, sys, os, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
CAT = "Cenit/Resources/Localizable.xcstrings"
BASELINE = os.path.join(HERE, "i18n-es-baseline.txt")
KEYS_BASELINE = os.path.join(HERE, "i18n-keys-baseline.txt")
PLURAL_BASELINE = os.path.join(HERE, "i18n-plural-baseline.txt")
ES_EQ_EN_BASELINE = os.path.join(HERE, "i18n-es-eq-en-baseline.txt")

def _loc_has_plural(loc):
    """True si la localización trae `variations.plural` en cualquier nivel (incl. substitutions)."""
    if not loc:
        return False
    return '"plural"' in json.dumps(loc, ensure_ascii=False)

# ---------------------------------------------------------------------------- 1. missing-es

def missing_es():
    strings = json.load(open(CAT, encoding="utf-8")).get("strings", {})
    out = set()
    for key, entry in strings.items():
        # una clave vacía "" no necesita traducción; el resto sí.
        if key.strip() == "": continue   # claves de formato/espaciado no son copy
        loc = entry.get("localizations", {}).get("es") or {}
        es = (loc.get("stringUnit") or {}).get("value")
        # FER-505: `variations.plural` (one/other) cuenta como traducción es — no exigir
        # también un stringUnit plano (los moldes `%lld sets` / `%lld exercises` solo traen plural).
        if not es and not _loc_has_plural(loc):
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

# ---------------------------------------------------------------------------- 3. glosario es-MX (FER-503 · C5)

# Unidad canónica: el catálogo ya predomina con «lpm» (≈30 vs ≈9 «bpm»). LENGUAJE §8 se alineó.
# «equipo» de gimnasio («Sin equipo») es legítimo; solo se prohíben frases de aparato.
FORBIDDEN_ES = [
    # (nombre, regex sobre el valor es, flags)
    ("Apple Health", re.compile(r"Apple Health"), 0),
    ("entreno/entrenos", re.compile(r"\bentreno(s)?\b"), 0),
    ("teléfono", re.compile(r"\btel[eé]fono(s)?\b", re.I), 0),
    ("bpm (canónico: lpm)", re.compile(r"\bbpm\b", re.I), 0),
    ("equipo-aparato", re.compile(
        r"\b(en tu equipo|mi propio equipo|su propio equipo|en el equipo|este equipo)\b", re.I), 0),
]

def _es_value(entry):
    return (entry.get("localizations") or {}).get("es", {}).get("stringUnit", {}).get("value")

def forbidden_es_hits(strings):
    """[(catálogo_label no aplica aquí)] → [(clave, regla, valor)]."""
    out = []
    for key, entry in strings.items():
        es = _es_value(entry)
        if not es:
            continue
        for name, rx, _ in FORBIDDEN_ES:
            if rx.search(es):
                out.append((key, name, es))
    return out

def check_forbidden_es():
    """Palabras/frases prohibidas en `es` de los tres catálogos."""
    malos = []
    for name, path in CATALOGS.items():
        if not os.path.exists(path):
            continue
        strings = json.load(open(path, encoding="utf-8")).get("strings", {})
        for key, rule, es in forbidden_es_hits(strings):
            malos.append((name, key, rule, es))
    if malos:
        print(f"❌ {len(malos)} cadena(s) es con palabra/frase de glosario prohibida (FER-503 · C5):")
        for cat, key, rule, es in malos[:40]:
            print(f"  [{cat}] {key!r} · regla {rule!r}\n      {es!r}")
        if len(malos) > 40:
            print(f"  … y {len(malos) - 40} más")
        return 1
    print("✅ glosario es: sin Apple Health / entreno / teléfono / bpm / equipo-aparato")
    return 0

def shared_key_es_diffs(catalogs=None):
    """Claves presentes en ≥2 catálogos cuyo `es` diverge."""
    catalogs = catalogs or {
        name: json.load(open(path, encoding="utf-8")).get("strings", {})
        for name, path in CATALOGS.items() if os.path.exists(path)
    }
    names = sorted(catalogs)
    diffs = []
    # Pairwise over every shared key
    seen = set()
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            for key in set(catalogs[a]) & set(catalogs[b]):
                ea, eb = _es_value(catalogs[a][key]), _es_value(catalogs[b][key])
                if ea is None or eb is None:
                    continue
                if ea != eb and (key, a, b) not in seen:
                    seen.add((key, a, b))
                    diffs.append((key, {a: ea, b: eb}))
    return diffs

def check_shared_es():
    """El `es` de una clave compartida entre iPhone/Watch/widgets debe coincidir."""
    diffs = shared_key_es_diffs()
    if diffs:
        print(f"❌ {len(diffs)} clave(s) compartida(s) con `es` distinto entre catálogos (FER-503 · C5):")
        for key, vals in diffs[:40]:
            print(f"  {key!r}: {vals}")
        if len(diffs) > 40:
            print(f"  … y {len(diffs) - 40} más")
        return 1
    print("✅ claves compartidas: mismo `es` entre iPhone / Watch / widgets")
    return 0

# ---------------------------------------------------------------------------- 5. plural-blind (FER-505 · C7)

# Sustantivo justo después de `%lld` (o `%1$lld` / `%#@…@` ya resuelto en el valor plano).
_NOUN_AFTER_LLD = re.compile(r"%(?:\d+\$)?lld\s+([A-Za-zÁÉÍÓÚÜáéíóúüñÑ]+)")

def _es_flat_value(entry):
    """Valor `es` plano (stringUnit) si existe — el que se muestra cuando NO hay plural."""
    loc = (entry.get("localizations") or {}).get("es") or {}
    unit = loc.get("stringUnit") or {}
    return unit.get("value")

def plural_blind_hits(strings):
    """[(clave, es)] con `%lld` + sustantivo en «s» sin `variations.plural`."""
    out = []
    for key, entry in strings.items():
        loc = (entry.get("localizations") or {}).get("es") or {}
        if _loc_has_plural(loc):
            continue
        es = _es_flat_value(entry)
        if not es or "%lld" not in es:
            continue
        nouns = _NOUN_AFTER_LLD.findall(es)
        if any(w.lower().endswith("s") for w in nouns):
            out.append((key, es))
    return out

def check_plural_blind():
    """Clave con conteo + sustantivo plural en es sin variations.plural (FER-505 · C7)."""
    base = read_baseline(PLURAL_BASELINE)
    malos = []
    for name, path in CATALOGS.items():
        if not os.path.exists(path):
            continue
        strings = json.load(open(path, encoding="utf-8")).get("strings", {})
        for key, es in plural_blind_hits(strings):
            token = f"{name}:{key}"
            if token in base or key in base:
                continue
            malos.append((name, key, es))
    if malos:
        print(f"❌ {len(malos)} clave(s) con `%lld` + sustantivo plural en es SIN variations.plural (FER-505 · C7):")
        for cat, key, es in malos[:40]:
            print(f"  [{cat}] {key!r}\n      {es!r}")
        if len(malos) > 40:
            print(f"  … y {len(malos) - 40} más")
        return 1
    print("✅ plural-blind: sin `%lld` + sustantivo en «s» sin variations.plural (nuevas)")
    return 0

# ---------------------------------------------------------------------------- 6. es == en con palabra española (FER-505 · C7)

# Palabras españolas que el guard de ñ/acentos NO ve (Empezar, Tendencias, Serie…) más acentos.
_ES_WORD = re.compile(
    r"(?:[¿¡ñÑ«»áéíóúÁÉÍÓÚüÜ]"
    r"|\b(?:Empezar|Tendencias|Serie|Series|Guardar|Compartir|REIMPRIMIR|"
    r"Ajustes|Entrenar|Cancelar|Aceptar|Continuar|Volver|Descartar|Terminar|"
    r"Imprimir|Recibo|Historial|Sesión|Sesiones|Rutina|Rutinas|Recibos|"
    r"Reimprimir|Salud|Dejar|Recalibrar|Vista|clásica)\b)",
    re.I,
)
_ES_EQ_EN_ALLOW = {"Cénit", "Cénit %@"}

def _lang_value(entry, lang):
    loc = (entry.get("localizations") or {}).get(lang) or {}
    if "stringUnit" in loc:
        return (loc.get("stringUnit") or {}).get("value")
    plur = ((loc.get("variations") or {}).get("plural") or {})
    other = (plur.get("other") or {}).get("stringUnit") or {}
    return other.get("value")

def es_eq_en_hits(strings):
    """[(clave, es)] donde la clave ES un literal español (key == es) y en no lo corrige.

    El bug C7: `Text("Empezar")` / `Text("Tendencias")` / `Text("✓ Serie")` — la clave es
    español, así que el inglés también sale en español. Ids semánticos (`recibo.foo`) y
    claves inglesas con `es` distinto no entran.
    """
    out = []
    for key, entry in strings.items():
        if key in _ES_EQ_EN_ALLOW:
            continue
        if not _ES_WORD.search(key):
            continue
        es = _lang_value(entry, "es")
        if not es or es != key:
            continue
        en = _lang_value(entry, "en")
        # Si `en` ya es distinto del español, el catálogo corrige el idioma fuente.
        if en is not None and en != key and en != es:
            continue
        out.append((key, es))
    return out

def check_es_eq_en():
    """Clave con palabra española cuyo es == en (FER-505 · C7)."""
    base = read_baseline(ES_EQ_EN_BASELINE)
    malos = []
    for name, path in CATALOGS.items():
        if not os.path.exists(path):
            continue
        strings = json.load(open(path, encoding="utf-8")).get("strings", {})
        for key, es in es_eq_en_hits(strings):
            token = f"{name}:{key}"
            if token in base or key in base:
                continue
            malos.append((name, key, es))
    if malos:
        print(f"❌ {len(malos)} clave(s) con palabra española y es == en (FER-505 · C7):")
        for cat, key, es in malos[:40]:
            print(f"  [{cat}] {key!r}\n      {es!r}")
        if len(malos) > 40:
            print(f"  … y {len(malos) - 40} más")
        return 1
    print("✅ es==en: sin claves españolas con es idéntico a en (nuevas)")
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

    # FER-503 · C5 — glosario: palabras prohibidas + claves compartidas.
    # Prueba negativa: una cadena es con «Apple Health» debe fallar.
    fake_bad = {"demo.apple": {"localizations": {
        "es": {"stringUnit": {"state": "translated", "value": "Conecta Apple Health ahora"}}}}}
    hits = forbidden_es_hits(fake_bad)
    if not hits or hits[0][1] != "Apple Health":
        print(f"❌ self-test glosario: esperaba fallo por Apple Health, obtuvo {hits!r}")
        return 1
    fake_ok = {"demo.ok": {"localizations": {
        "es": {"stringUnit": {"state": "translated", "value": "Conecta Apple Salud ahora"}}}}}
    if forbidden_es_hits(fake_ok):
        print("❌ self-test glosario: Apple Salud no debe fallar")
        return 1
    # entreno / bpm / teléfono / equipo-aparato
    for val, rule in [
        ("Recordatorio de entreno", "entreno/entrenos"),
        ("máx 120 bpm", "bpm (canónico: lpm)"),
        ("en tu teléfono", "teléfono"),
        ("guarda solo en tu equipo", "equipo-aparato"),
    ]:
        h = forbidden_es_hits({"k": {"localizations": {
            "es": {"stringUnit": {"state": "translated", "value": val}}}}})
        if not h or h[0][1] != rule:
            print(f"❌ self-test glosario: {val!r} debía disparar {rule!r}, obtuvo {h!r}")
            return 1
    # gym «Sin equipo» NO falla
    if forbidden_es_hits({"No equipment": {"localizations": {
            "es": {"stringUnit": {"state": "translated", "value": "Sin equipo"}}}}}):
        print("❌ self-test glosario: «Sin equipo» (gimnasio) no debe fallar")
        return 1
    # claves compartidas divergentes
    fake_cats = {
        "app": {"Next": {"localizations": {"es": {"stringUnit": {"value": "Siguiente"}}}}},
        "watch": {"Next": {"localizations": {"es": {"stringUnit": {"value": "Sigue"}}}}},
    }
    diffs = shared_key_es_diffs(fake_cats)
    if not diffs or diffs[0][0] != "Next":
        print(f"❌ self-test compartidas: esperaba diff en Next, obtuvo {diffs!r}")
        return 1
    fake_same = {
        "app": {"Next": {"localizations": {"es": {"stringUnit": {"value": "Sigue"}}}}},
        "watch": {"Next": {"localizations": {"es": {"stringUnit": {"value": "Sigue"}}}}},
    }
    if shared_key_es_diffs(fake_same):
        print("❌ self-test compartidas: mismo es no debe fallar")
        return 1
    print("✅ self-test: glosario es + claves compartidas OK")

    # FER-505 · C7 — plural-blind: `%lld` + sustantivo en «s» sin variations.plural debe fallar.
    fake_plural_bad = {"%lld sessions": {"localizations": {
        "es": {"stringUnit": {"state": "translated", "value": "%lld sesiones"}}}}}
    if not plural_blind_hits(fake_plural_bad):
        print("❌ self-test plural-blind: esperaba fallo en «%lld sesiones»")
        return 1
    fake_plural_ok = {"%lld sessions": {"localizations": {"es": {"variations": {"plural": {
        "one": {"stringUnit": {"state": "translated", "value": "%lld sesión"}},
        "other": {"stringUnit": {"state": "translated", "value": "%lld sesiones"}}}}}}}}
    if plural_blind_hits(fake_plural_ok):
        print("❌ self-test plural-blind: con variations.plural no debe fallar")
        return 1
    # sin sustantivo en «s» (frase invariante) no falla
    fake_plural_inv = {"Night · %lld cycles": {"localizations": {
        "es": {"stringUnit": {"state": "translated", "value": "Noche · %lld ciclos"}}}}}
    # «ciclos» termina en s → SÍ debe fallar (sustantivo plural ciego)
    if not plural_blind_hits(fake_plural_inv):
        print("❌ self-test plural-blind: «%lld ciclos» debía fallar")
        return 1
    fake_plural_no_noun = {"Rest %lld seconds": {"localizations": {
        "es": {"stringUnit": {"state": "translated", "value": "Descanso de %lld segundos"}}}}}
    # «segundos» también termina en s — la regla es mecánica (termina en s), no léxica
    if not plural_blind_hits(fake_plural_no_noun):
        print("❌ self-test plural-blind: «%lld segundos» debía fallar")
        return 1

    # FER-505 · C7 — es == en con palabra española debe fallar.
    fake_eq_bad = {"Empezar": {"localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "Empezar"}},
        "es": {"stringUnit": {"state": "translated", "value": "Empezar"}}}}}
    if not es_eq_en_hits(fake_eq_bad):
        print("❌ self-test es==en: esperaba fallo en «Empezar»")
        return 1
    fake_eq_ok = {"Start": {"localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "Start"}},
        "es": {"stringUnit": {"state": "translated", "value": "Empezar"}}}}}
    if es_eq_en_hits(fake_eq_ok):
        print("❌ self-test es==en: Start/Empezar no debe fallar")
        return 1
    # Clave española con `en` ya corregido tampoco falla
    fake_eq_fixed = {"Empezar": {"localizations": {
        "en": {"stringUnit": {"state": "translated", "value": "Start"}},
        "es": {"stringUnit": {"state": "translated", "value": "Empezar"}}}}}
    if es_eq_en_hits(fake_eq_fixed):
        print("❌ self-test es==en: Empezar con en=Start no debe fallar")
        return 1
    # marca allow-list
    fake_brand = {"Cénit": {"localizations": {
        "es": {"stringUnit": {"state": "translated", "value": "Cénit"}}}}}
    if es_eq_en_hits(fake_brand):
        print("❌ self-test es==en: marca Cénit no debe fallar")
        return 1
    print("✅ self-test: plural-blind + es==en OK")
    return 0

if "--self-test" in sys.argv:
    sys.exit(self_test())
sys.exit(
    check_es()
    | check_keys()
    | check_forbidden_es()
    | check_shared_es()
    | check_plural_blind()
    | check_es_eq_en()
)
