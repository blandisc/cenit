import Foundation

/// Un tramo de una noche: qué etapa se durmió y entre qué segundos.
///
/// `start`/`end` se miden en segundos transcurridos desde el inicio de la noche, no en fechas
/// absolutas: así todos los tramos de una misma noche caen sobre un solo eje `0...total` y el
/// hipnograma los dibuja sin convertir nada.
public struct SleepInterval: Sendable, Identifiable {
    /// Identidad de pieza para SwiftUI: dos tramos iguales siguen siendo dos tramos.
    public let id: UUID = .init()
    /// Qué se durmió en este tramo.
    public let stage: SleepStage
    /// Segundos desde el inicio de la noche en que empieza y termina el tramo.
    public let start: TimeInterval
    public let end: TimeInterval
    /// Lo que duró la etapa. Nunca negativo, ni siquiera con un par invertido.
    public var duration: TimeInterval { Swift.max(0, end - start) }

    public init(stage etapa: SleepStage, start desde: TimeInterval, end hasta: TimeInterval) {
        (stage, start, end) = (etapa, desde, hasta)
    }
}
