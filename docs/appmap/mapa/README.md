# Manifiestos del mapa 100 % (FER-381)

Cada familia de pantallas declara sus **nodos** (estados capturables) y **aristas** (flechas de flujo)
en un JSON de esta carpeta. El **mismo** JSON lo leen dos cosas:

- el harness `CenitUITests/CenitScreenshotTests.test_mapa` → captura un PNG real por nodo × frame;
- `Tools/build-appmap.py` → dibuja el lienzo (pan/zoom + flechas) y lo comparte con `build-galeria-artifact.py`.

Así un estado nuevo entra con **un renglón**, sin tocar código. `Tools/check-shots.py` valida después
que ningún PNG salió en blanco, repetido o faltante (mata el falso verde de las claves `nav` muertas).

## Esquema

```json
{
  "familia": "hoy",                     // = nombre del archivo; primer segmento de -cenit.route
  "titulo":  "Hoy · TodayView",         // encabezado del board en el lienzo
  "blurb":   "…",                       // descripción del board
  "unidad":  "estados",                 // "estados" | "componentes" (rótulo del contador)
  "nodos": [
    {
      "id": "apunto",                   // kebab, único por familia
      "titulo": "Veredicto · A punto",
      "condicion": "nivel .primed …",   // subtítulo del nodo
      "fixture": "primed",              // opcional: -cenit.fixture (histórico o de <Familia>Fixtures.swift)
      "args": ["-cenit.hour", "9"],      // opcional: launch-args extra (-cenit.range, -cenit.route, …)
      "pasos": [                         // opcional: navegación tras el arranque (orden literal)
        { "nav": "today", "settle": 5 },        // atajo Darwin cenit.nav.<key>
        { "tapText": "Sueño" },                 // toca un botón/texto (falla si no existe — nunca no-op)
        { "tapId": "matriz-renglon-sleep" },    // toca por accessibilityIdentifier
        { "swipeUp": 1 },                        // desplaza
        { "wait": 2 }                            // espera segundos
      ],
      "frames": 1,                       // nº de marcos (frame 0 = tope; 1+ = scroll «-f1», «-f2»…)
      "png": "hoy-apunto.png",           // opcional: fija el nombre de muro (compatibilidad); si falta = "<familia>-<id>.png"
      "x": 1420, "y": 80,                // opcional: posición en el lienzo; sin ella = cuadrícula automática
      "omitido": "razón"                 // opcional: estado sin palanca viable → tarjeta gris, NO se captura
    }
  ],
  "aristas": [
    { "de": "vacio", "a": "calibrando", "etiqueta": "empareja" },
    { "de": "apunto", "a": "sueno", "etiqueta": "toca Sueño" }   // cross-familia: usa "otrafamilia/id"
  ]
}
```

## Regenerar todo

```bash
Tools/capture-appmap.sh            # corre test_mapa en el simulador → PNG reales → check-shots → index.html
python3 Tools/build-galeria-artifact.py   # (opcional) refresca el «Figma casero»
```

Por familia (una lane): `NOOP_MAPA_FAMILIA=hoy,entrenar Tools/capture-appmap.sh`.
Iterar un JSON sin recompilar el bundle de pruebas: `NOOP_MAPA_DIR=$PWD/docs/appmap/mapa`.

## Palancas DEBUG (solo simulador)

`-cenit.freshStore YES` (base hermética) · `-cenit.route <familia/clave>` (pantalla sin atajo `nav`) ·
`-cenit.fixture <estado>` · `-cenit.component <Pieza>` · y las que cada familia cablea en su ola
(`-cenit.hour`, `-cenit.range`, `-cenit.readError`, …).

## Regenerar el mapa COMPLETO (todas las familias)

El simulador se degrada tras ~50 relanzamientos seguidos, así que la corrida completa va por trozos
con simulador fresco entre cada uno:

```bash
Tools/capture-mapa-all.sh                 # compila 1×, captura por trozos de 30, sim fresco entre trozos
python3 Tools/build-appmap-artifact.py    # arma el Artifact «Mapa vivo» autocontenido (WebP embebido)
```

`capture-appmap.sh` (una familia o el flujo viejo) sigue existiendo; `capture-mapa-all.sh` es el
orquestador resiliente para el mapa entero. **Las capturas (`docs/appmap/shots/`) del mapa completo NO
se versionan** (≈250 PNG, decenas de MB): son un artefacto generado. El entregable compartible es el
Artifact «Mapa vivo»; el repo versiona la FUENTE (manifiestos `mapa/*.json` + el harness + el tooling).
Un estado que no se pudo capturar de forma distinta queda con `"omitido": "<razón>"` en su manifiesto
(el lienzo lo dibuja como tarjeta gris) — la lista de esos huecos es backlog para afinar sus palancas.
