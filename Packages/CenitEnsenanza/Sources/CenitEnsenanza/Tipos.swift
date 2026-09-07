import Foundation

// MARK: - Tipos del registro de enseñanza (épico FER-428, L4/FER-430)
//
// Regla dura: este paquete guarda TEXTO (claves del catálogo de la app) y RUTAS (la pestaña),
// nunca lógica ni estado. Si una funcionalidad necesita una condición, es un `Requisito`
// declarativo — no una función. Cero SwiftUI/TipKit/UIKit: es Foundation-only para correr en el
// fast loop (`swift test`) y en la matriz de ubuntu de `swift-packages.yml`.

/// Las cuatro pestañas del app + «transversal» (widgets, Live Activity, Watch, avisos, gestos:
/// nada que viva en una sola pestaña).
public enum Pestana: String, CaseIterable, Sendable {
    case hoy, tendencias, entrenar, ajustes, transversal
}

/// Qué necesita el usuario para que una funcionalidad aplique. Declarativo: el registro no
/// evalúa nada, solo lo nombra — quien consume el registro decide qué hacer con el dato.
public enum Requisito: Equatable, Sendable {
    case watch
    case noches(Int)
    case entrenos
    case permiso(Permiso)

    public enum Permiso: String, Sendable {
        case salud, notificaciones, calendario
    }
}

/// Una pieza de enseñanza. Cada caso lleva su propio dato (una clave del catálogo, un id de tip,
/// la pestaña de destino…), nunca una acción ejecutable — el registro no dibuja nada.
public enum Pieza: Equatable, Sendable {
    /// Clave del catálogo que describe el estado vacío (la consume `CenitDesign.LiquidVacio`).
    case vacio(clave: String)
    /// `id` == el id de la funcionalidad, o `"<id>.<sufijo>"` cuando una funcionalidad reparte
    /// varios tips (p. ej. `entrenar.amrap-drop.amrap` / `.drop`).
    case tip(id: String)
    /// Idem `tip`, para los hitos de una sola vez que consume L3 (TipKit con `MaxDisplayCount(1)`).
    case hito(id: String)
    /// En qué sección de «Cómo funciona Cénit» sale esta funcionalidad (la consume L2).
    case ayuda(seccion: Pestana)
    /// Novedad de una versión; `mayor` decide si además gana la tarjeta de una vez al fondo de
    /// Hoy (D2 del épico FER-428).
    case novedad(version: String, mayor: Bool)
    /// Un gesto (long-press, swipe…) que también tiene un botón equivalente (principio 4 del
    /// épico: «cada gesto tiene un botón»). Ambos valores son claves del catálogo.
    case gestoConBoton(gesto: String, boton: String)
}

/// Una funcionalidad del app: dónde vive, qué necesita, con qué piezas se enseña y desde cuándo
/// existe. Las tres claves derivadas son la convención completa — nunca se escriben a mano
/// (mata la clase «clave con typo»).
public struct Funcionalidad: Identifiable, Equatable, Sendable {
    public let id: FuncionalidadID
    public let pestana: Pestana
    public let requiere: [Requisito]
    public let piezas: [Pieza]
    /// Versión en la que existe esta funcionalidad, p. ej. `"1.85"`.
    public let desde: String

    public init(
        id: FuncionalidadID,
        pestana: Pestana,
        requiere: [Requisito] = [],
        piezas: [Pieza],
        desde: String
    ) {
        self.id = id
        self.pestana = pestana
        self.requiere = requiere
        self.piezas = piezas
        self.desde = desde
    }

    public var nombreKey: String { "ensenanza.\(id.rawValue).nombre" }
    public var paraQueKey: String { "ensenanza.\(id.rawValue).paraQue" }
    public var dondeViveKey: String { "ensenanza.\(id.rawValue).dondeVive" }
}
