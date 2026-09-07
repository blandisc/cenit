#if os(iOS)
import SwiftUI
import TipKit
import CenitEnsenanza

// MARK: - Consejos contextuales de Tendencias (FER-432 · L5)
//
// Mismo patrón que `HoyTips` / `EntrenarTips`. TipGroup propio de la pestaña, solo iOS 18+.
// Estilo visual: `LiquidConsejoTipStyle` en la raíz — no se repite.

// MARK: TipGroup (iOS 18+)

@available(iOS 18, *)
enum TendenciasTipGroup {
    static let ordered = TipGroup(.ordered) {
        TendenciasPeriodoTip()
        TendenciasPreparacionTip()
        TendenciasCompararTip()
        TendenciasExplorarTip()
        TendenciasMapaDelDiaTip()
    }
}

// MARK: 6 · tendencias.periodo

struct TendenciasPeriodoTip: Tip {
    @Parameter
    static var diasConDato: Int = 0

    var id: String { Registro.tipID(.tendenciasPeriodo) }
    var title: Text { Text("tip.tendencias.periodo.title") }
    var message: Text? { Text("tip.tendencias.periodo.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.$diasConDato) { $0 >= 14 }
    }
}

// MARK: 7 · tendencias.preparacion

struct TendenciasPreparacionTip: Tip {
    @Parameter
    static var hayVeredicto: Bool = false

    var id: String { Registro.tipID(.tendenciasPreparacion) }
    var title: Text { Text("tip.tendencias.preparacion.title") }
    var message: Text? { Text("tip.tendencias.preparacion.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.$hayVeredicto) { $0 == true }
    }
}

// MARK: 8 · tendencias.comparar

struct TendenciasCompararTip: Tip {
    @Parameter
    static var diasConDosMetricas: Int = 0

    var id: String { Registro.tipID(.tendenciasComparar) }
    var title: Text { Text("tip.tendencias.comparar.title") }
    var message: Text? { Text("tip.tendencias.comparar.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.$diasConDosMetricas) { $0 >= 30 }
    }
}

// MARK: 9 · tendencias.explorar

struct TendenciasExplorarTip: Tip {
    var id: String { Registro.tipID(.tendenciasExplorar) }
    var title: Text { Text("tip.tendencias.explorar.title") }
    var message: Text? { Text("tip.tendencias.explorar.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        // Misma regla que comparar: reusa el mismo `@Parameter`.
        #Rule(TendenciasCompararTip.$diasConDosMetricas) { $0 >= 30 }
    }
}

// MARK: 10 · tendencias.mapa-del-dia

struct TendenciasMapaDelDiaTip: Tip {
    @Parameter
    static var permisoCalendario: Bool = true

    static let detalleEstresAbierto: Event = Event(id: "tendencias.mapa-del-dia.detalle-estres")

    var id: String { Registro.tipID(.tendenciasMapaDelDia) }
    var title: Text { Text("tip.tendencias.mapa-del-dia.title") }
    var message: Text? { Text("tip.tendencias.mapa-del-dia.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.detalleEstresAbierto) { $0.donations.count >= 2 }
        #Rule(Self.$permisoCalendario) { $0 == false }
    }
}

// MARK: Helpers

enum TendenciasTips {
    static func alimentarParametros(
        diasConDato: Int,
        diasConDosMetricas: Int,
        hayVeredicto: Bool,
        permisoCalendario: Bool
    ) {
        TendenciasPeriodoTip.diasConDato = diasConDato
        TendenciasCompararTip.diasConDosMetricas = diasConDosMetricas
        TendenciasPreparacionTip.hayVeredicto = hayVeredicto
        TendenciasMapaDelDiaTip.permisoCalendario = permisoCalendario
    }
}
#endif
