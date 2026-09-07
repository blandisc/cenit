import Foundation

/// El registro único de las 68 funcionalidades del app (épico FER-428, L4/FER-430). Namespace
/// puro — nunca se instancia. Las listas por pestaña viven en `Registro+<Pestaña>.swift`; este
/// archivo solo las combina y expone los accesores comunes.
public enum Registro {
    /// Orden: hoy → tendencias → entrenar → ajustes → transversal, y dentro de cada pestaña el
    /// orden de la semilla (D8: el orden del registro es el orden en que aparecen los tips).
    public static let todas: [Funcionalidad] = hoy + tendencias + entrenar + ajustes + transversal

    public static func por(_ pestana: Pestana) -> [Funcionalidad] {
        switch pestana {
        case .hoy: return hoy
        case .tendencias: return tendencias
        case .entrenar: return entrenar
        case .ajustes: return ajustes
        case .transversal: return transversal
        }
    }

    /// Busca una funcionalidad por su id. El registro es la fuente de verdad: si `id` existe en
    /// `FuncionalidadID` pero no en `todas`, el registro está incompleto — eso es un error de
    /// programación, no un caso a manejar en tiempo de ejecución.
    public static subscript(_ id: FuncionalidadID) -> Funcionalidad {
        guard let funcionalidad = todas.first(where: { $0.id == id }) else {
            fatalError("CenitEnsenanza.Registro: no hay Funcionalidad para \(id.rawValue) — el registro está incompleto.")
        }
        return funcionalidad
    }

    /// Todos los ids de `.tip`/`.hito` del registro, tal como los consume TipKit.
    public static var tipIDs: Set<String> {
        Set(todas.flatMap { funcionalidad in
            funcionalidad.piezas.compactMap { pieza -> String? in
                switch pieza {
                case .tip(let id), .hito(let id): return id
                default: return nil
                }
            }
        })
    }
}
