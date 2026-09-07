#!/usr/bin/env python3
"""Construye la «galería viva» (el «Figma casero» del dueño) como UN HTML autocontenido listo para
publicarse como Artifact: cada pieza de CenitDesign y cada estado de pantalla es un PNG REAL del
simulador (harness `CenitUITests/CenitScreenshotTests` → `docs/appmap/shots/`). Este script NO
redibuja UI: recorta cada captura a su contenido, la pone sobre su propio lienzo, la etiqueta con
el índice de `docs/design-system/CATALOGO.md` y mide la cobertura contra ese índice.

Fuentes de verdad que lee (nunca las copia):
  · `Tools/build-appmap.py`            → manifiesto de pantallas (MAP) y de piezas (COMPONENTS)
  · `docs/appmap/shots/*.png`          → los pixeles (reescalados a 800 px por capture-appmap.sh)
  · `docs/design-system/CATALOGO.md`   → rol · símbolo · archivo · cuándo usarlo · cuándo no
  · `LiquidGlass/LiquidColor.swift`    → la paleta (claro y oscuro) de «Liquid Glass · El Eje»

Regenerar tras capturar:   Tools/capture-appmap.sh && python3 Tools/build-galeria-artifact.py
Salida (por defecto):      $TMPDIR/galeria-viva.html  (o --out <ruta>); pesa ~1 MB, sin red.
Requiere Pillow (el del sistema, mismo que Tools/diff-shot.py).
"""
import argparse, base64, datetime, html, importlib.util, io, os, re, subprocess, sys, tempfile, unicodedata
from itertools import groupby

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "appmap", "shots")
CATALOGO = os.path.join(ROOT, "docs", "design-system", "CATALOGO.md")
LIQUID_COLOR = os.path.join(ROOT, "Packages", "CenitDesign", "Sources", "CenitDesign",
                            "LiquidGlass", "LiquidColor.swift")

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("Falta Pillow (python3 -m pip install --user pillow) — recorta y codifica las capturas.")


# --- Manifiesto: lo comparte con el muro, para que una pieza nueva entre a los dos sin tocar nada ---
def load_appmap():
    spec = importlib.util.spec_from_file_location("build_appmap", os.path.join(ROOT, "Tools", "build-appmap.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

# --- Paleta: se LEE del design system; fallback solo si el archivo no está donde siempre ---
def palette():
    try:
        src = open(LIQUID_COLOR).read()
    except OSError:
        src = ""
    dyn = {n: (l, d) for n, l, d in re.findall(
        r'static let (\w+) = LiquidTheme\.dynamic\(light: Color\(hex: "(#[0-9A-Fa-f]{6})"\), '
        r'dark: Color\(hex: "(#[0-9A-Fa-f]{6})"\)\)', src)}
    flat = dict(re.findall(r'static let (\w+) = Color\(hex: "(#[0-9A-Fa-f]{6})"\)', src))
    def tok(name, fb_light, fb_dark):
        if name in dyn: return dyn[name]
        if name in flat: return (flat[name], flat[name])
        return (fb_light, fb_dark)
    def rgba(hexv, a):
        r, g, b = (int(hexv[i:i+2], 16) for i in (1, 3, 5)); return f"rgba({r},{g},{b},{a})"
    tinta = tok("tinta900", "#221D16", "#ECE9E0")
    verde = tok("verdePrimario", "#0C8F62", "#2EB27D")
    t = {
        "tinta":  tinta,
        "tinta2": tok("tinta700", "#5C5648", "#A6A298"),
        "tinta3": tok("tinta500", "#6F6857", "#8B8370"),
        "verde":  verde,
        "ambar":  tok("ambar", "#C4631F", "#E08A45"),
        "rosa":   tok("rosa", "#B85068", "#BD546C"),
        "pozoA":  tok("fondoAlto", "#FEFEFD", "#0C0B0A"),
        "pozoB":  tok("fondoBajo", "#F3F4F2", "#000000"),
        "tarjeta": tok("papelTarjeta", "#FFFFFF", "#1A1714"),
    }
    # El lienzo de El Eje es BLANCO (DESIGN.md), no un token de papel; en oscuro, el fondo neutro.
    light = {k: v[0] for k, v in t.items()}; light["lienzo"] = "#FFFFFF"
    dark  = {k: v[1] for k, v in t.items()}; dark["lienzo"] = t["pozoA"][1]
    for m in (light, dark):
        m["hair"] = rgba(m["tinta"], ".10"); m["hair7"] = rgba(m["tinta"], ".07")
        m["tint"] = rgba(m["verde"], ".09"); m["vidrio"] = rgba(m["lienzo"], ".76")
    return light, dark

def css_vars(m):
    return ";".join(f"--{k}:{v}" for k, v in m.items())

# --- Índice del catálogo: rol → símbolo → archivo → cuándo usarlo → cuándo no ---
def catalog_index():
    rows = []
    try:
        txt = open(CATALOGO, encoding="utf-8").read()
    except OSError:
        return rows
    sec = txt.split("## Índice de componentes", 1)[-1]
    for line in sec.splitlines():
        if not line.startswith("| ") or line.startswith("| Rol") or line.startswith("|---"): continue
        cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
        if len(cells) < 5: continue
        rol, simbolo, archivo, usar, no = cells[:5]
        rows.append({"rol": rol, "simbolo": simbolo.strip("`"), "archivo": archivo.strip("`"),
                     "usar": usar, "no": no, "clave": symbol_key(simbolo)})
    return rows

def symbol_key(sym):
    """`LiquidGlassButton(.solida)` → LiquidGlassButton · `ConfirmCard / .instrumentoConfirm` → ConfirmCard
    · `.saveErrorToast` → saveErrorToast · `liquidGlass(_:)` → liquidGlass."""
    s = sym.strip("`").split(" / ")[0].split(" · ")[0].split("(")[0].strip()
    return s.lstrip(".")

# Piezas del índice que NO entran a la galería todavía y por qué (clasificación editorial, explícita):
# generación anterior «Instrumento» (reciben `theme:` obligatorio o viven en el inventario legado) o
# modificadores de app. La regla del rol «(Instrumento)» cubre el resto.
LEGADO = {
    "CenitCTAButton":     "barra CTA de tinta — flujos Instrumento/Entrenar, sin envoltorio Liquid",
    "BackButton":         "recibe `theme:` obligatorio (Instrumento)",
    "HeaderActionButton": "recibe `theme:` obligatorio (Instrumento)",
    "OutlineCapsule":     "recibe `theme:` obligatorio (Instrumento)",
    "UndoToast":          "recibe `theme:` obligatorio (receta Instrumento aún)",
    "TrendChart":         "inventario Instrumento — sucesor Liquid ya capturado (LiquidTrendChart)",
    "saveErrorToast":     "modifier de app (Cenit/Screens), no pieza de CenitDesign",
}

def coverage(index, captured):
    cap = {r["clave"] for r in index if r["clave"] in captured}
    done, next_batch, legacy = [], [], []
    seen = set()
    for r in index:
        k = r["clave"]
        if k in seen: continue
        seen.add(k)
        if k in cap: done.append(r)
        elif k in LEGADO or "(Instrumento)" in r["rol"]:
            r = dict(r, motivo=LEGADO.get(k, "generación anterior «Instrumento» — en migración")); legacy.append(r)
        else: next_batch.append(r)
    huerfanas = sorted(captured - {r["clave"] for r in index})   # capturadas sin renglón en el índice
    return done, next_batch, legacy, huerfanas

# --- Imágenes: recorte al contenido (sobre su propio lienzo) + WebP en base64 ---
STATUS_BAR = 130   # px (a 800 de ancho): la hora 9:41 y los iconos no son parte de la pieza
PAD = 36

def open_shot(png):
    return Image.open(os.path.join(SHOTS, png)).convert("RGB")

def crop_piece(im):
    """bbox de lo que difiere del lienzo (degradado casi blanco) bajo la status bar; el recorte
    conserva el degradado real de fondo, así la pieza sigue sobre su propio suelo."""
    w, h = im.size
    body = im.crop((0, STATUS_BAR, w, h))
    bg = Image.new("RGB", body.size, body.getpixel((8, 8)))
    mask = ImageChops.difference(body, bg).convert("L").point(lambda p: 255 if p > 18 else 0)
    bb = mask.getbbox()
    if not bb: return im
    x0, y0, x1, y1 = bb
    box = (max(0, x0 - PAD), max(0, y0 + STATUS_BAR - PAD), min(w, x1 + PAD), min(h, y1 + STATUS_BAR + PAD))
    return im.crop(box)

def webp_b64(im, width=None, quality=86):
    if width and im.size[0] > width:
        im = im.resize((width, round(im.size[1] * width / im.size[0])), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, "WEBP", quality=quality, method=6)
    return "data:image/webp;base64," + base64.b64encode(b.getvalue()).decode("ascii"), im.size

def hexpx(im, xy):
    r, g, b = im.getpixel(xy); return f"#{r:02X}{g:02X}{b:02X}"

def esc(s): return html.escape(str(s), quote=True)

def fold(s):
    """Clave de búsqueda sin acentos ni mayúsculas."""
    return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")

def git(*args):
    try: return subprocess.check_output(["git", "-C", ROOT, *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception: return ""


# --- Render ---------------------------------------------------------------------------------------
def build(out_path):
    appmap = load_appmap()
    light, dark = palette()
    index = catalog_index()
    by_key = {}
    for r in index: by_key.setdefault(r["clave"], r)

    # Piezas (grupo «Componentes» del muro), por familia en el orden del manifiesto.
    pieces = []
    for i, (name, fam) in enumerate(appmap.COMPONENTS):
        png = f"componente-{name}.png"
        if not os.path.exists(os.path.join(SHOTS, png)): print(f"  (sin captura: {png})"); continue
        im = open_shot(png)
        crop = crop_piece(im)
        card, (cw, ch) = webp_b64(crop)
        full, _ = webp_b64(im, width=600, quality=84)
        row = by_key.get(name, {})
        pieces.append({"name": name, "fam": fam, "card": card, "cw": cw, "ch": ch, "full": full,
                       "top": hexpx(crop, (2, 2)), "bot": hexpx(crop, (2, crop.size[1] - 3)),
                       "rol": row.get("rol", "sin renglón en el índice del catálogo"),
                       "archivo": row.get("archivo", ""), "usar": row.get("usar", ""), "no": row.get("no", "")})
    fam_order = []
    for _, fam in appmap.COMPONENTS:
        if fam not in fam_order: fam_order.append(fam)

    # Pantallas (los demás grupos del muro): cada nodo = un estado real.
    screens = []
    for g in appmap.MAP:
        if g.get("unit") == "componentes": continue
        nodes = []
        for nid, (png, title, cond, x, y) in sorted(g["nodes"].items(), key=lambda kv: (kv[1][3], kv[1][4])):
            if not os.path.exists(os.path.join(SHOTS, png)): continue
            src, _ = webp_b64(open_shot(png), width=560, quality=84)
            nodes.append({"id": nid, "title": title, "cond": cond, "src": src})
        screens.append({"name": g["name"], "blurb": g["blurb"], "nodes": nodes})

    captured = {p["name"] for p in pieces}
    done, nxt, legacy, huerfanas = coverage(index, captured)
    n_index = len({r["clave"] for r in index})
    n_screens = sum(len(s["nodes"]) for s in screens)
    total = len(pieces) + n_screens

    shots_date = git("log", "-1", "--format=%ad", "--date=short", "--", "docs/appmap/shots") or "—"
    shots_pr = re.search(r"\(#(\d+)\)", git("log", "-1", "--format=%s", "--", "docs/appmap/shots") or "")
    head = git("rev-parse", "--short", "HEAD") or "—"
    today = datetime.date.today().isoformat()

    # ---- HTML ----
    L = []
    L.append(f"""<meta charset="utf-8">
<title>Figma casero</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap">
<style>
:root{{{css_vars(light)};color-scheme:light}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{{css_vars(dark)};color-scheme:dark}}}}
:root[data-theme="dark"]{{{css_vars(dark)};color-scheme:dark}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--lienzo);color:var(--tinta);font:14px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased}}
.g{{font-family:"Space Grotesk","SF Pro Display",-apple-system,Arial,sans-serif}}
.mono{{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:12px}}
.kicker{{font-family:"Space Grotesk",-apple-system,sans-serif;font-size:11px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--tinta3)}}
a{{color:var(--verde)}}
:focus-visible{{outline:2px solid var(--verde);outline-offset:3px;border-radius:6px}}

/* --- barra superior: el único vidrio de la página --- */
.top{{position:sticky;top:0;z-index:20;background:var(--vidrio);-webkit-backdrop-filter:blur(18px) saturate(1.2);backdrop-filter:blur(18px) saturate(1.2);border-bottom:1px solid var(--hair)}}
.top .in{{max-width:1360px;margin:0 auto;padding:14px 28px;display:flex;align-items:center;gap:22px;flex-wrap:wrap}}
.top h1{{margin:0;font-size:24px;line-height:1.05;font-weight:700;letter-spacing:-.02em}}
.top .meta{{color:var(--tinta2);font-size:12.5px;max-width:34ch;line-height:1.35}}
.buscar{{display:flex;align-items:center;gap:8px;flex:1 1 280px;max-width:460px;height:40px;padding:0 12px 0 14px;border-radius:20px;background:var(--tarjeta);border:1px solid var(--hair);color:var(--tinta)}}
.buscar svg{{flex:none;width:16px;height:16px;stroke:var(--tinta3);fill:none;stroke-width:2;stroke-linecap:round}}
.buscar input{{flex:1;min-width:0;border:0;background:transparent;font:15px inherit;font-family:inherit;color:var(--tinta);outline:none}}
.buscar input::placeholder{{color:var(--tinta3)}}
.buscar button{{flex:none;width:22px;height:22px;border:0;border-radius:11px;background:var(--hair);color:var(--tinta2);font-size:14px;line-height:1;cursor:pointer;display:none}}
.buscar.con button{{display:block}}
.top nav{{display:flex;gap:4px;margin-left:auto}}
.top nav a{{text-decoration:none;color:var(--tinta2);font-weight:500;font-size:13px;padding:7px 12px;border-radius:15px}}
.top nav a:hover{{background:var(--hair7);color:var(--tinta)}}
.hits{{color:var(--tinta3);font-size:12.5px;font-variant-numeric:tabular-nums;white-space:nowrap}}

main{{max-width:1360px;margin:0 auto;padding:36px 28px 80px}}
section.bloque{{padding:26px 0 14px;border-top:1px solid var(--hair)}}
section.bloque:first-child{{border-top:0;padding-top:0}}
.cab{{display:flex;align-items:baseline;gap:16px;flex-wrap:wrap;margin-bottom:6px}}
.cab h2{{margin:0;font-size:22px;font-weight:700;letter-spacing:-.015em;text-wrap:balance}}
.cab p{{margin:0;color:var(--tinta2);max-width:68ch}}
.nota{{color:var(--tinta2);max-width:72ch;margin:0 0 18px}}

/* --- familias y piezas --- */
.familia{{margin:22px 0 8px}}
.familia h3{{margin:0 0 12px;font-size:15px;font-weight:600;display:flex;align-items:center;gap:10px}}
.familia h3 small{{color:var(--tinta3);font-weight:500;font-variant-numeric:tabular-nums}}
.familia h3::after{{content:"";flex:1;height:1px;background:var(--hair7)}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px}}
.pieza{{display:flex;flex-direction:column;gap:10px;padding:0;border:0;background:transparent;text-align:left;color:inherit;font:inherit;cursor:zoom-in}}
.pozo{{height:280px;border-radius:14px;border:1px solid var(--hair);display:grid;place-items:center;overflow:hidden;padding:12px}}
.pozo img{{display:block;max-width:100%;max-height:100%;width:auto;height:auto}}
.pieza:hover .pozo{{border-color:var(--tinta3)}}
.pieza .pie b{{display:block;font-size:14px;font-weight:600}}
.pieza .pie span{{display:block;color:var(--tinta2);font-size:12.5px;margin-top:2px}}
.pieza[hidden],.familia[hidden],.frame[hidden],.pantalla[hidden]{{display:none}}

/* --- pantallas --- */
.pantalla{{margin:22px 0 10px}}
.pantalla h3{{margin:0 0 4px;font-size:15px;font-weight:600}}
.pantalla p.blurb{{margin:0 0 14px;color:var(--tinta2);max-width:72ch}}
.fila{{display:flex;gap:16px;overflow-x:auto;padding:4px 2px 12px;scroll-snap-type:x proximity}}
.frame{{flex:0 0 212px;scroll-snap-align:start;display:flex;flex-direction:column;gap:9px;padding:0;border:0;background:transparent;text-align:left;color:inherit;font:inherit;cursor:zoom-in}}
.frame .tel{{border-radius:26px;overflow:hidden;border:1px solid var(--hair);background:var(--pozoA);line-height:0}}
.frame .tel img{{width:100%;display:block}}
.frame:hover .tel{{border-color:var(--tinta3)}}
.frame b{{font-size:13px;font-weight:600}}
.frame span{{color:var(--tinta2);font-size:12px;line-height:1.4}}

/* --- cobertura --- */
.cob{{display:grid;grid-template-columns:minmax(220px,1fr) 2fr;gap:28px;align-items:start}}
.cob .num{{font-size:52px;line-height:1;font-weight:700;letter-spacing:-.03em;font-variant-numeric:tabular-nums}}
.cob .num small{{font-size:16px;font-weight:500;letter-spacing:0;color:var(--tinta2);margin-left:6px}}
.barra{{margin:14px 0 8px;height:8px;border-radius:4px;background:var(--hair)}}
.barra i{{display:block;height:100%;border-radius:4px;background:var(--verde)}}
.cob .lee{{color:var(--tinta2);max-width:38ch;margin:0}}
.listas{{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:22px}}
.listas h4{{margin:0 0 8px;font-size:12px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--tinta3);display:flex;gap:8px;align-items:center}}
.listas h4 .chip{{font-size:11px;padding:2px 8px;border-radius:9px;background:var(--hair7);color:var(--tinta2);letter-spacing:0;font-variant-numeric:tabular-nums}}
.listas h4 .chip.v{{background:var(--tint);color:var(--verde)}}
.listas ul{{list-style:none;margin:0;padding:0}}
.listas li{{padding:7px 0;border-top:1px solid var(--hair7);font-size:13px;display:flex;flex-direction:column;gap:1px}}
.listas li code{{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:12px;color:var(--tinta)}}
.listas li span{{color:var(--tinta2);font-size:12px}}

footer{{border-top:1px solid var(--hair);margin-top:30px;padding-top:22px;color:var(--tinta2);display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}}
footer h4{{margin:0 0 8px;color:var(--tinta);font-size:14px}}
footer ol{{margin:0;padding-left:20px}} footer li{{margin:4px 0}}
footer code{{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:12px;background:var(--hair7);padding:1px 5px;border-radius:4px;color:var(--tinta)}}

/* --- lupa --- */
#lb{{position:fixed;inset:0;z-index:40;background:rgba(0,0,0,.55);display:grid;place-items:center;padding:24px}}
#lb[hidden]{{display:none}}
#lb .caja{{display:grid;grid-template-columns:auto minmax(260px,340px);gap:0;max-width:min(1100px,96vw);max-height:92vh;background:var(--lienzo);border-radius:18px;overflow:hidden;border:1px solid var(--hair);box-shadow:0 30px 80px rgba(0,0,0,.35)}}
#lb .img{{background:var(--pozoA);display:grid;place-items:center;padding:18px}}
#lb .img img{{display:block;max-height:calc(92vh - 36px);max-width:min(52vw,520px);width:auto;height:auto;border-radius:22px}}
#lb .txt{{padding:24px 24px 20px;overflow:auto;border-left:1px solid var(--hair);display:flex;flex-direction:column;gap:12px}}
#lb .txt h3{{margin:0;font-size:20px;font-weight:700;letter-spacing:-.015em;word-break:break-word}}
#lb .txt .rol{{color:var(--tinta2);margin:-6px 0 0}}
#lb dl{{margin:0;display:grid;grid-template-columns:auto 1fr;gap:6px 12px;font-size:13px}}
#lb dt{{color:var(--tinta3);font-size:11px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;padding-top:2px}}
#lb dd{{margin:0;color:var(--tinta);word-break:break-word}}
#lb .cerrar{{position:absolute;top:18px;right:22px;width:36px;height:36px;border-radius:18px;border:1px solid rgba(255,255,255,.4);background:rgba(0,0,0,.35);color:#fff;font-size:18px;cursor:pointer}}
@media (max-width:760px){{#lb .caja{{grid-template-columns:1fr;max-height:92vh;overflow:auto}} #lb .img img{{max-width:80vw;max-height:60vh}} #lb .txt{{border-left:0;border-top:1px solid var(--hair)}} .cob{{grid-template-columns:1fr}}}}
@media (prefers-reduced-motion:no-preference){{#lb .caja{{animation:pop .16s ease-out}} @keyframes pop{{from{{transform:scale(.97);opacity:0}}}}}}
</style>

<header class="top"><div class="in">
  <div><div class="kicker">Cénit · Liquid Glass · El Eje</div><h1 class="g">Figma casero</h1></div>
  <div class="meta">{total} capturas reales del simulador (iPhone 17 Pro · iOS 26). Nada está redibujado: si una pieza no aparece aquí, no está capturada.</div>
  <label class="buscar"><svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.6-3.6"/></svg><input id="q" type="search" placeholder="Buscar pieza, familia o estado…" autocomplete="off" aria-label="Buscar"><button id="limpiar" type="button" aria-label="Limpiar búsqueda">×</button></label>
  <span class="hits" id="hits">{total} de {total}</span>
  <nav><a href="#piezas">Piezas</a><a href="#pantallas">Pantallas</a><a href="#cobertura">Cobertura</a></nav>
</div></header>
<main>""")

    # --- Piezas ---
    L.append(f"""<section class="bloque" id="piezas"><div class="cab"><h2 class="g">Piezas</h2>
<p>{len(pieces)} piezas de <code class="mono">CenitDesign</code> en {len(fam_order)} familias, cada una a escala 1:1 en puntos sobre su propio lienzo. Toca una para verla en el iPhone completo, con su archivo y cuándo usarla.</p></div>""")
    idx = 0
    for fam in fam_order:
        fp = [p for p in pieces if p["fam"] == fam]
        if not fp: continue
        L.append(f'<section class="familia" data-fam="{esc(fam)}"><h3 class="g">{esc(fam)} <small>{len(fp)}</small></h3><div class="grid">')
        for p in fp:
            q = fold(" ".join([p["name"], fam, p["rol"], p["archivo"]]))
            L.append(f'<button class="pieza" type="button" data-i="{idx}" data-q="{esc(q)}">'
                     f'<div class="pozo" style="background:linear-gradient({p["top"]},{p["bot"]})">'
                     f'<img src="{p["card"]}" width="{p["cw"]//2}" height="{p["ch"]//2}" alt="{esc(p["name"])}" loading="lazy"></div>'
                     f'<div class="pie"><b class="g">{esc(p["name"])}</b><span>{esc(p["rol"])}</span></div></button>')
            idx += 1
        L.append("</div></section>")
    L.append("</section>")

    # --- Pantallas ---
    L.append(f"""<section class="bloque" id="pantallas"><div class="cab"><h2 class="g">Pantallas</h2>
<p>{n_screens} estados reales, sembrados con fixtures (no con Salud): cada marco es lo que el iPhone pinta en esa condición.</p></div>""")
    for s in screens:
        L.append(f'<section class="pantalla"><h3 class="g">{esc(s["name"])}</h3><p class="blurb">{esc(s["blurb"])}</p><div class="fila">')
        for n in s["nodes"]:
            q = fold(" ".join([s["name"], n["title"], n["cond"]]))
            L.append(f'<button class="frame" type="button" data-i="{idx}" data-q="{esc(q)}">'
                     f'<div class="tel"><img src="{n["src"]}" alt="{esc(n["title"])}" loading="lazy"></div>'
                     f'<b class="g">{esc(n["title"])}</b><span>{esc(n["cond"])}</span></button>')
            idx += 1
        L.append("</div></section>")
    L.append("</section>")

    # --- Cobertura ---
    pct = round(100 * len(done) / n_index) if n_index else 0
    def li(rows, motivo=False):
        return "".join(f'<li><code>{esc(r["simbolo"])}</code><span>{esc(r["rol"])}'
                       + (f' — {esc(r["motivo"])}' if motivo else "") + "</span></li>" for r in rows)
    huer = (f' Además hay {len(huerfanas)} capturada{"s" if len(huerfanas)!=1 else ""} sin renglón en el índice '
            f'({", ".join(f"<code class=mono>{esc(h)}</code>" for h in huerfanas)}).') if huerfanas else ""
    L.append(f"""<section class="bloque" id="cobertura"><div class="cab"><h2 class="g">Cobertura del índice</h2>
<p>Contra el «Índice de componentes» de <code class="mono">CATALOGO.md</code> (generado del código, {n_index} roles).</p></div>
<div class="cob">
  <div><div class="num g">{len(done)}<small>de {n_index} roles</small></div>
    <div class="barra" role="img" aria-label="{pct} por ciento capturado"><i style="width:{pct}%"></i></div>
    <p class="lee">{pct} % del índice ya tiene su pixel real. Quedan {len(nxt)} piezas Liquid por capturar (el siguiente lote) y {len(legacy)} de la generación anterior que no entran hasta migrarse.{huer}</p></div>
  <div class="listas">
    <div><h4>Siguiente lote <span class="chip v">{len(nxt)}</span></h4><ul>{li(nxt)}</ul></div>
    <div><h4>Legado · no se captura <span class="chip">{len(legacy)}</span></h4><ul>{li(legacy, motivo=True)}</ul></div>
    <div><h4>Capturadas <span class="chip">{len(done)}</span></h4><ul>{li(done)}</ul></div>
  </div>
</div></section>""")

    # --- Pie ---
    pr = f" · PR #{shots_pr.group(1)}" if shots_pr else ""
    L.append(f"""<footer>
  <div><h4 class="g">Cómo se regenera</h4><ol>
    <li><code>Tools/capture-appmap.sh</code> corre el harness en el simulador (firmado, Reduce Motion, reloj 9:41) y deja los PNG en <code>docs/appmap/shots/</code>.</li>
    <li><code>python3 Tools/build-galeria-artifact.py</code> recorta cada captura a su pieza, la etiqueta con el índice del catálogo y arma esta página.</li>
    <li>Claude la publica en el mismo enlace. Una pieza nueva entra con un renglón en <code>ComponentGallery.entries</code> + <code>componentNames</code> + <code>COMPONENTS</code>.</li>
  </ol></div>
  <div><h4 class="g">De dónde sale</h4>
    <p style="margin:0 0 6px">Capturas del {esc(shots_date)}{pr}. Página armada el {today} sobre el árbol <code>{esc(head)}</code>. Paleta leída de <code>LiquidColor.swift</code>; tipografía Space Grotesk, la misma que va en el bundle.</p>
    <p style="margin:0">Cada pieza se monta con el launch-arg <code>-cenit.component &lt;Nombre&gt;</code> sobre <code>LiquidColor.fondoGradient</code>, con el uso de su propio <code>#Preview</code>.</p></div>
</footer>
</main>

<div id="lb" hidden role="dialog" aria-modal="true" aria-label="Detalle"><button class="cerrar" type="button" aria-label="Cerrar">×</button><div class="caja"><div class="img"><img id="lb-img" alt=""></div><div class="txt"><h3 class="g" id="lb-t"></h3><p class="rol" id="lb-r"></p><dl id="lb-d"></dl></div></div></div>
<script>
(function(){{
  var D=""" )
    # Datos de la lupa (solo texto + la imagen grande; las miniaturas ya están en el DOM).
    import json
    detail = []
    for p in pieces:
        detail.append({"t": p["name"], "r": p["rol"], "img": p["full"], "d": [
            ["Familia", p["fam"]], ["Archivo", p["archivo"]], ["Se monta con", f"-cenit.component {p['name']}"],
            ["Cuándo usarlo", p["usar"]], ["Cuándo no", p["no"]]]})
    for s in screens:
        for n in s["nodes"]:
            detail.append({"t": n["title"], "r": s["name"], "img": n["src"], "d": [["Condición", n["cond"]]]})
    L.append(json.dumps(detail, ensure_ascii=False).replace("</", "<\\/"))
    L.append(f""";
  var lb=document.getElementById('lb'),img=document.getElementById('lb-img'),t=document.getElementById('lb-t'),r=document.getElementById('lb-r'),dl=document.getElementById('lb-d');
  var last=null;
  function open(i,src){{var d=D[i];if(!d)return;last=src;img.src=d.img;img.alt=d.t;t.textContent=d.t;r.textContent=d.r;
    dl.innerHTML='';d.d.forEach(function(kv){{if(!kv[1])return;var dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=kv[0];dd.textContent=kv[1];dl.appendChild(dt);dl.appendChild(dd)}});
    lb.hidden=false;document.body.style.overflow='hidden';lb.querySelector('.cerrar').focus()}}
  function close(){{lb.hidden=true;document.body.style.overflow='';if(last)last.focus()}}
  document.querySelectorAll('[data-i]').forEach(function(b){{b.addEventListener('click',function(){{open(+b.dataset.i,b)}})}});
  lb.addEventListener('click',function(e){{if(e.target===lb||e.target.closest('.cerrar'))close()}});
  document.addEventListener('keydown',function(e){{if(e.key==='Escape'&&!lb.hidden)close()}});

  var q=document.getElementById('q'),wrap=q.parentNode,hits=document.getElementById('hits'),total={total};
  function fold(s){{return s.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,'')}}
  function filtra(){{var v=fold(q.value.trim());wrap.classList.toggle('con',!!v);var n=0;
    document.querySelectorAll('[data-q]').forEach(function(el){{var ok=!v||el.dataset.q.indexOf(v)>=0;el.hidden=!ok;if(ok)n++}});
    document.querySelectorAll('.familia,.pantalla').forEach(function(sec){{sec.hidden=!sec.querySelector('[data-q]:not([hidden])')}});
    hits.textContent=n+' de '+total}}
  q.addEventListener('input',filtra);
  document.getElementById('limpiar').addEventListener('click',function(){{q.value='';filtra();q.focus()}});
  document.addEventListener('keydown',function(e){{if(e.key==='/'&&document.activeElement!==q&&lb.hidden){{e.preventDefault();q.focus()}}}});
}})();
</script>""")

    doc = "\n".join(L)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    open(out_path, "w", encoding="utf-8").write(doc)
    kb = os.path.getsize(out_path) // 1024
    print(f"escrito {out_path} · {kb} KB · {len(pieces)} piezas + {n_screens} estados · "
          f"cobertura {len(done)}/{n_index} (siguiente lote {len(nxt)}, legado {len(legacy)})")
    return out_path


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "galeria-viva.html"),
                    help="ruta del HTML autocontenido (default: $TMPDIR/galeria-viva.html)")
    a = ap.parse_args()
    build(a.out)
