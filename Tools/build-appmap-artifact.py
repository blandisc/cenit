#!/usr/bin/env python3
"""Construye el «Mapa vivo» como Artifact(s) autocontenido(s) (FER-392): el mismo lienzo pan/zoom +
flechas de `Tools/build-appmap.py`, pero con cada captura EMBEBIDA como data-URI WebP (no `shots/…`),
para publicarse como Artifact sin red y sin la carpeta de PNG.

Reusa `build-appmap.py` (MAP/render/STYLE/JS) — solo cambia el `src_of` a un data-URI y quita el
`<link>` de Google Fonts (bloqueado por la CSP del Artifact; el chrome cae a system-ui, los PNG llevan
la tipografía real de la app). Si el HTML de todo el mapa pasa el tope (~14 MB), parte en un archivo
por área + un índice.

Uso:
    python3 Tools/build-appmap-artifact.py                 # $TMPDIR/mapa-vivo*.html
    python3 Tools/build-appmap-artifact.py --out-dir DIR   # en DIR
Requiere Pillow (el del sistema, igual que build-galeria-artifact.py).
"""
import argparse, base64, io, os, sys, importlib.util, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "appmap", "shots")
MAX_BYTES = 14 * 1024 * 1024   # tope prudente bajo el límite de 16 MB del Artifact

try:
    from PIL import Image
except ImportError:
    sys.exit("Falta Pillow (python3 -m pip install --user pillow).")

def _appmap():
    s = importlib.util.spec_from_file_location("ba", os.path.join(ROOT, "Tools", "build-appmap.py"))
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m

_CACHE = {}
def data_uri(png, width=380, quality=80):
    """docs/appmap/shots/<png> → data:image/webp;base64,… (reescalado, cacheado). Un PNG faltante
    (un nodo que no capturó) cae a un 1×1 transparente para no romper el lienzo."""
    if png in _CACHE: return _CACHE[png]
    p = os.path.join(SHOTS, png)
    try:
        im = Image.open(p).convert("RGB")
        if im.size[0] > width:
            im = im.resize((width, round(im.size[1] * width / im.size[0])), Image.LANCZOS)
        b = io.BytesIO(); im.save(b, "WEBP", quality=quality, method=6)
        uri = "data:image/webp;base64," + base64.b64encode(b.getvalue()).decode("ascii")
    except FileNotFoundError:
        # Nodo sin captura (omitido / pendiente): tarjeta gris clara con el rótulo, no un marco negro.
        ph = Image.new("RGB", (width, round(width * 2.17)), (232, 230, 224))
        b = io.BytesIO(); ph.save(b, "WEBP", quality=70, method=4)
        uri = "data:image/webp;base64," + base64.b64encode(b.getvalue()).decode("ascii")
    _CACHE[png] = uri
    return uri

def _one(m, groups, title):
    """Un HTML autocontenido para `groups` (sublista de m.MAP)."""
    saved = m.MAP
    try:
        m.MAP = groups
        doc = m.render(lambda png: data_uri(png), font_css="")   # sin Google Fonts → system-ui
    finally:
        m.MAP = saved
    return doc.replace("<title>Cénit · Mapa de estados</title>", f"<title>{title}</title>")

def build(out_dir):
    m = _appmap()
    os.makedirs(out_dir, exist_ok=True)
    full = _one(m, m.MAP, "Cénit · Mapa vivo")
    size = len(full.encode("utf-8"))
    if size <= MAX_BYTES:
        out = os.path.join(out_dir, "mapa-vivo.html")
        open(out, "w", encoding="utf-8").write(full)
        print(f"escrito {out} · {size//1024//1024} MB · {sum(len(g['nodes']) for g in m.MAP)} nodos (un solo lienzo)")
        return [out]
    # Demasiado grande: un archivo por familia + un índice.
    print(f"el mapa completo pesa {size//1024//1024} MB (> {MAX_BYTES//1024//1024}) — partiendo por área")
    outs, rows = [], []
    for g in m.MAP:
        slug = g["name"].split("·")[0].strip().lower().replace(" ", "-")
        doc = _one(m, [g], f"Cénit · Mapa · {g['name']}")
        p = os.path.join(out_dir, f"mapa-{slug}.html")
        open(p, "w", encoding="utf-8").write(doc)
        outs.append(p); rows.append((g["name"], len(g["nodes"]), f"mapa-{slug}.html", len(doc.encode())//1024))
        print(f"  · {g['name']}: {len(g['nodes'])} nodos → {os.path.basename(p)} ({len(doc.encode())//1024} KB)")
    idx = ["<!doctype html><meta charset=utf-8><title>Cénit · Mapa vivo</title>",
           "<style>body{font:15px -apple-system,system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 20px;color:#221D16}"
           "h1{font-size:26px}a{color:#0C8F62;text-decoration:none}li{margin:8px 0}</style>",
           "<h1>Cénit · Mapa vivo</h1><p>El mapa completo se partió por área para caber. Cada enlace es su propio lienzo:</p><ul>"]
    for name, n, href, kb in rows:
        idx.append(f'<li><a href="{href}">{name}</a> — {n} estados ({kb} KB)</li>')
    idx.append("</ul>")
    ip = os.path.join(out_dir, "mapa-vivo-index.html"); open(ip, "w", encoding="utf-8").write("\n".join(idx))
    outs.insert(0, ip); print(f"  índice → {os.path.basename(ip)}")
    return outs

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out-dir", default=tempfile.gettempdir())
    a = ap.parse_args()
    build(a.out_dir)
