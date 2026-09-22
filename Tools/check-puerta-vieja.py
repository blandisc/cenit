#!/usr/bin/env python3
"""La puerta vieja solo puede cerrarse (ola 3).

Escanea Cenit/ y CenitApp/ y compara los archivos que todavía usan una pieza
de la generación anterior contra Tools/puerta-vieja.txt. Un archivo nuevo en
esa lista falla. Un archivo que ya migró también falla, hasta que la lista
baje en el mismo cambio: la lista tiene que decir la verdad.

Reloj, widgets y la actividad de pantalla bloqueada no entran: son excepciones
ya decididas.
"""
import os
import re
import sys

ROOTS = ["Cenit", "CenitApp"]
LIST = os.path.join(os.path.dirname(__file__), "puerta-vieja.txt")
PATTERNS = [
    re.compile(r"\bSegmentedPillControl\b"),
    re.compile(r"\bInstrumentoType\b"),
    re.compile(r"\.instrumentoOverline\b"),
    re.compile(r"\.instrumentoConfirm\b"),
    re.compile(r"\.instrumentoHero\b"),
    re.compile(r"\.instrumentoInput\b"),
    re.compile(r"\.font\(\.system\b|Font\.system\(size:"),
]


def scan(repo):
    found = set()
    for root in ROOTS:
        base = os.path.join(repo, root)
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, repo).replace("\\", "/")
                text = open(path, encoding="utf-8").read().splitlines()
                for line in text:
                    code = line.split("//", 1)[0]
                    if any(rx.search(code) for rx in PATTERNS):
                        found.add(rel)
                        break
    return found


def read_list():
    if not os.path.exists(LIST):
        return set()
    out = set()
    for line in open(LIST, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line)
    return out


def write_list(found):
    with open(LIST, "w", encoding="utf-8") as fh:
        fh.write("# Archivos que todavía usan una pieza de la generación anterior.\n")
        fh.write("# Lo regenera Tools/check-puerta-vieja.py --write. No se edita a mano.\n")
        for path in sorted(found):
            fh.write(path + "\n")


def main(argv):
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    found = scan(repo)
    if "--write" in argv:
        write_list(found)
        print(f"puerta vieja: {len(found)} archivos escritos")
        return 0
    listed = read_list()
    extra = sorted(found - listed)
    gone = sorted(listed - found)
    if not extra and not gone:
        print(f"✅ puerta vieja: {len(found)} archivos, ninguno nuevo")
        return 0
    if extra:
        print("❌ una pantalla nueva usa una pieza vieja:")
        for path in extra:
            print(f"   + {path}")
    if gone:
        print("❌ la lista nombra pantallas que ya no usan la pieza vieja. Baja la lista con --write:")
        for path in gone:
            print(f"   - {path}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
