import CenitDesign

// MARK: - Los rótulos de `LiquidTabBar`, traducidos (FER-112 / FER-490)
//
// El dock de la app es la tab bar del sistema: sus `Label` usan estas mismas claves
// («Train» / «Body» / «Settings») directo en `RootTabView`. Esto queda para `LiquidTabBar`
// (galería y previews): `CenitDesign` no tiene catálogo, y sin estas cadenas la pieza
// se veía en español aunque el teléfono estuviera en inglés.
//
// FER-490: tres rótulos (Entrenar · Cuerpo · Ajustes). «Body» ya traduce a «Cuerpo» en es-MX;
// el paso 9 puede renombrar la clave de catálogo si hace falta.
extension LiquidTabRotulos {
    static var cenit: LiquidTabRotulos {
        .init(entrenar: String(localized: "Train"),
              cuerpo: String(localized: "Body"),
              // Ronda 2 #24: clave «Settings» (inglés), no el texto español «Ajustes» — esa era
              // una isla marcada `stale` en el catálogo, en riesgo de que un prune del catálogo se
              // la llevara y dejara el dock en español bajo UI inglesa. El encabezado de la propia
              // pantalla (`AjustesView.header`) usa la MISMA clave, así que dock y pantalla siguen
              // diciendo lo mismo («Ajustes» en es-MX) sin depender de un literal español.
              ajustes: String(localized: "Settings"))
    }
}
