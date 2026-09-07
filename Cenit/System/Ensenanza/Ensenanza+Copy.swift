import SwiftUI
import CenitEnsenanza

// MARK: - Resolución de copy del registro de enseñanza (épico FER-428, L4/FER-430)
//
// El paquete `CenitEnsenanza` guarda solo CLAVES (`nombreKey`/`paraQueKey`/`dondeViveKey`) — el
// texto real vive en el catálogo del app (`Cenit/Resources/Localizable.xcstrings`), porque un
// paquete Foundation-only no puede resolver `String(localized:)` contra el bundle del app. Esta
// extensión es el único puente: resuelve cada clave con el mismo patrón que el resto del app
// (`Cenit/Screens/MetricDetailSupport.swift:65` y otros, `grep -rn "String.LocalizationValue" Cenit`).
extension Funcionalidad {
    var nombre: Text { Text(String(localized: String.LocalizationValue(nombreKey))) }
    var paraQue: Text { Text(String(localized: String.LocalizationValue(paraQueKey))) }
    var dondeVive: Text { Text(String(localized: String.LocalizationValue(dondeViveKey))) }
}
