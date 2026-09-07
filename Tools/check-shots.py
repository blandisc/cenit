#!/usr/bin/env python3
"""Guardia anti-falso-verde del mapa (FER-381).

El harness pasa aunque una captura salga en blanco o repita la pantalla anterior (las viejas claves
`nav` muertas —coach/automations— capturaban el frame previo con otro nombre y el test seguía verde).
Este guardia mata esa clase: contra los manifiestos de `docs/appmap/mapa/`, exige que cada nodo×frame
tenga su PNG en `docs/appmap/shots/`, que no sea un marco casi vacío, y que un nodo no sea idéntico al
nodo anterior de su misma familia (pantalla ajena con nombre prestado).

Uso:
    python3 Tools/check-shots.py                     # todas las familias
    python3 Tools/check-shots.py --familia hoy,entrenar
    python3 Tools/check-shots.py --mapa docs/appmap/mapa --shots docs/appmap/shots

Sale 0 si todo cuadra; 1 con una tabla de fallas. Solo Pillow + stdlib (igual que Tools/diff-shot.py).
"""
import argparse, os, sys, glob, json

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("Falta Pillow (python3 -m pip install --user pillow).")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLANK_FRAC = 0.98    # ≥98 % del marco dentro de ±TOL del color de fondo → marco vacío
BLANK_TOL  = 6
DUP_TOL    = 1.0     # % de píxeles que difieren bajo el cual dos marcos se consideran idénticos


def frame_png(node, frame):
    base = node.get("png") or f"{node['_familia']}-{node['id']}.png"
    if frame == 0:
        return base
    stem, ext = os.path.splitext(base)
    return f"{stem}-f{frame}{ext or '.png'}"


def load_nodes(mapa_dir, familias):
    """Lista plana de nodos esperados, en el orden del manifiesto (para el chequeo de duplicado
    contra el nodo ANTERIOR de la misma familia)."""
    nodes = []
    for path in sorted(glob.glob(os.path.join(mapa_dir, "*.json"))):
        fam = os.path.splitext(os.path.basename(path))[0]
        if familias and fam not in familias:
            continue
        m = json.load(open(path, encoding="utf-8"))
        famname = m.get("familia", fam)
        for n in m.get("nodos", []):
            n["_familia"] = famname
            frames = int(n.get("frames", 1) or 1)
            # `omitido`: estado sin palanca viable — se declara a propósito (FER-381 · A2), no se
            # captura y no se le exige PNG; el lienzo lo dibuja como tarjeta gris.
            nodes.append({"familia": famname, "id": n["id"], "omitido": n.get("omitido"),
                          "pngs": [frame_png(n, f) for f in range(frames)]})
    return nodes


def blank_fraction(im):
    """Fracción de píxeles dentro de ±BLANK_TOL del color de fondo (esquina superior izquierda)."""
    small = im.convert("RGB").resize((120, 260), Image.LANCZOS)
    bg = Image.new("RGB", small.size, small.getpixel((3, 3)))
    diff = ImageChops.difference(small, bg).convert("L")
    hist = diff.histogram()
    near = sum(hist[: BLANK_TOL + 1])
    return near / (small.size[0] * small.size[1])


def diff_pct(a, b):
    """% de píxeles que difieren (reescalados a 100×216, ±4 por ruido de compresión)."""
    ra = a.convert("RGB").resize((100, 216), Image.LANCZOS)
    rb = b.convert("RGB").resize((100, 216), Image.LANCZOS)
    d = ImageChops.difference(ra, rb).convert("L").point(lambda p: 255 if p > 4 else 0)
    hist = d.histogram()
    return 100.0 * hist[255] / (ra.size[0] * ra.size[1])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mapa", default=os.path.join(ROOT, "docs", "appmap", "mapa"))
    ap.add_argument("--shots", default=os.path.join(ROOT, "docs", "appmap", "shots"))
    ap.add_argument("--familia", default="", help="lista separada por comas; vacío = todas")
    a = ap.parse_args()
    familias = [x.strip() for x in a.familia.split(",") if x.strip()]

    nodes = load_nodes(a.mapa, familias)
    if not nodes:
        print("check-shots: no hay nodos que revisar (¿familia inexistente?)"); return 1

    fails, checked = [], 0
    prev_by_fam = {}   # familia -> (id, Image del frame 0) del nodo anterior
    for node in nodes:
        if node.get("omitido"):
            continue
        first_img = None
        for i, png in enumerate(node["pngs"]):
            p = os.path.join(a.shots, png)
            if not os.path.exists(p):
                fails.append((node["familia"], node["id"], png, "FALTA el PNG"))
                continue
            checked += 1
            try:
                im = Image.open(p)
            except Exception as e:
                fails.append((node["familia"], node["id"], png, f"no abre ({e})")); continue
            bf = blank_fraction(im)
            if bf >= BLANK_FRAC:
                fails.append((node["familia"], node["id"], png, f"marco casi vacío ({bf*100:.0f}% fondo)"))
            if i == 0:
                first_img = im
        # Duplicado contra el nodo anterior de la misma familia (clave muerta / pantalla ajena).
        if first_img is not None:
            prev = prev_by_fam.get(node["familia"])
            if prev is not None:
                dp = diff_pct(prev[1], first_img)
                if dp < DUP_TOL:
                    fails.append((node["familia"], node["id"], node["pngs"][0],
                                  f"idéntico a «{prev[0]}» ({dp:.1f}% distinto) — ¿captura de pantalla ajena?"))
            prev_by_fam[node["familia"]] = (node["id"], first_img)

    total = sum(0 if n.get("omitido") else len(n["pngs"]) for n in nodes)
    if fails:
        print(f"\ncheck-shots: {len(fails)} FALLA(S) de {total} marcos esperados\n")
        w = max(len(f"{f[0]}/{f[1]}") for f in fails)
        for fam, nid, png, why in fails:
            print(f"  ✗ {fam+'/'+nid:<{w}}  {png:<34}  {why}")
        print()
        return 1
    print(f"check-shots: OK · {checked} marcos, {total} esperados, {len(nodes)} nodos "
          f"({sum(1 for n in nodes if n.get('omitido'))} omitidos a propósito)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
