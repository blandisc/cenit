import Foundation

/// Un tramo de una noche: qué etapa se durmió y entre qué segundos.
///
/// `start`/`end` se miden en segundos transcurridos desde el inicio de la noche, no en fechas
/// absolutas: así todos los tramos de una misma noche caen sobre un solo eje `0...total` y el
/// hipnograma los dibuja sin convertir nada.
public struct SleepInterval: Sendable, Identifiable {
    public let id = UUID()
    /// Segundos desde el inicio de la noche en que empieza y termina el tramo.
    public var start, end: TimeInterval
    public var stage: SleepStage
    /// Lo que duró la etapa. Nunca negativo, ni siquiera con un par invertido.
    public var duration: TimeInterval { Swift.max(0, end - start) }

    public init(stage: SleepStage,
                start: TimeInterval,
                end: TimeInterval) {
        (self.stage, self.start, self.end) = (stage, start, end)
    }
}
