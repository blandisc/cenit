import Foundation
import StrandModels

// MARK: - El proxy diario de carga autonómica (0–3)
//
// La contraparte DIARIA de `StressEngine` (que mira el día por dentro). Aquí sólo vive la
// aritmética; el copy de cada banda, sus colores y los textos de «tiempo en calma» se quedan en la
// capa app (`Cenit/Screens/StressModel.swift`).
//
// De dónde sale el 0–3 de un día, en ese orden:
//   1. De la serie `stress` ya guardada, si ese día tiene un valor: se respeta tal cual.
//   2. Si no, se DEDUCE de cuánto se apartan hoy la FC en reposo y la HRV de la línea base
//      personal de los 30 días previos:
//
//        z de pulso   = (pulso de hoy − media)  / desviación     ← sube cuando el pulso SUBE
//        z de HRV     = (media − HRV de hoy)    / desviación     ← sube cuando la HRV BAJA
//        crudo        = z de pulso + z de HRV                    ← carga autonómica combinada
//        proxy        = 3 / (1 + e^(−crudo))                     ← 0 calma · 1.5 base · 3 alto
//
//   Bandas: 0–1 baja · 1–2 media · 2–3 alta.
//
// El proxy nunca cruza fuentes: una lectura sólo se compara contra la línea base de SU PROPIA
// fuente (ver el comentario del inicializador).

// MARK: - La aritmética, suelta y probable por separado

public enum StressMath {

    /// Promedio simple. `nil` cuando no hay ni una muestra: no se inventa un centro.
    public static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Desviación estándar POBLACIONAL (divide entre n). Cero cuando no hay centro o hay una sola
    /// muestra: una serie sin dispersión no tiene de dónde sacar un z-score.
    public static func std(_ xs: [Double], mean m: Double?) -> Double {
        guard let m, xs.count > 1 else { return 0 }
        let varianza = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
        return varianza.squareRoot()
    }

    /// Piso de dispersión. Por debajo de esto la línea base es plana y su término no entra:
    /// dividir entre ~0 convertiría el ruido del sensor en una alarma.
    private static let dispersionMinima = 0.0001

    /// Suma de los z-scores autonómicos. Ambos empujan hacia arriba: el pulso al subir, la HRV al
    /// bajar. Un término sin dato, sin centro o con la base plana simplemente no suma — el
    /// resultado se apoya en el que sí llegó, y con ninguno vale 0 (la base misma).
    public static func rawScore(
        rhrToday: Double?, meanRHR: Double?, sdRHR: Double,
        hrvToday: Double?, meanHRV: Double?, sdHRV: Double
    ) -> Double {
        var acumulado = 0.0
        if let pulso = rhrToday, let centro = meanRHR, sdRHR > dispersionMinima {
            acumulado += (pulso - centro) / sdRHR            // arriba = más carga
        }
        if let hrv = hrvToday, let centro = meanHRV, sdHRV > dispersionMinima {
            acumulado += (centro - hrv) / sdHRV              // abajo = más carga
        }
        return acumulado
    }

    /// Aplasta la suma de z contra el rango 0–3 con una logística. El crudo 0 —estar exactamente
    /// en la línea base— cae en 1.5, el centro del rango.
    public static func squash(_ raw: Double) -> Double {
        let proxy = 3.0 / (1.0 + exp(-raw))
        return min(max(proxy, 0), 3)
    }
}

// MARK: - Los tres tercios del rango

public enum StressBand: Sendable {
    case low, medium, high

    /// Techo de la banda baja y piso de la alta. El rango 0–3 se parte en tercios enteros.
    private static let techoBaja = 1.0
    private static let pisoAlta = 2.0

    public init(score: Double) {
        if score < Self.techoBaja {
            self = .low
        } else if score < Self.pisoAlta {
            self = .medium
        } else {
            self = .high
        }
    }
}

// MARK: - El modelo del día

public struct DailyStressModel {

    /// Un día del proxy, ya listo para graficar. `date` es la clave del día llevada a epoch en UTC
    /// (estable frente al horario de verano), como manda el contrato de claves del repo (FER-325).
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let value: Double
    }

    public let score: Double            // 0–3 del día ancla
    public let band: StressBand
    public let rhrToday: Int?
    public let hrvToday: Double?
    public let rhrDelta: Double?        // ancla − media de su línea base (lpm)
    public let hrvDelta: Double?        // ancla − media de su línea base (ms)
    public let fullTrend: [Point]       // toda la historia del proxy, vieja→nueva
    public let usingStored: Bool        // el valor del ancla venía guardado, no deducido

    // «Tiempo en calma»: de los últimos ≤30 días graficados, cuántos cayeron en la banda baja.
    public let calmDays: Int
    public let calmWindow: Int          // tamaño real de esa ventana (0 → falta historia)

    // FER-397 — el héroe se ancla al día más reciente que de verdad trae lectura, para que una fila
    // de «hoy» todavía vacía en el cambio de medianoche no deje la pantalla en blanco.
    public let anchorDayKey: String     // de qué día es el número grande
    public let anchorIsToday: Bool      // falso → la vista DEBE fecharlo (es de ayer, no de «hoy»)
    public let heroIsFresh: Bool        // ancla ∈ {hoy, ayer}: se muestra el héroe. Más viejo → se
                                        // esconde, pero la tendencia de abajo sigue dibujándose.

    /// Cuántos días previos entran en la línea base, y cuántos días mira el «tiempo en calma».
    private static let ventana = 30

    /// Valor de respaldo: el centro exacto de la logística (crudo 0).
    private static let proxyEnLaBase = 1.5

    /// Media y dispersión de una fuente. Se calculan juntas porque nunca se usan por separado.
    private struct Baseline {
        let mean: Double?
        let sd: Double

        init(_ xs: [Double]) {
            let centro = StressMath.mean(xs)
            self.mean = centro
            self.sd = StressMath.std(xs, mean: centro)
        }

        /// Hay contra qué comparar esta lectura.
        func canScore(_ reading: Double?) -> Bool { reading != nil && mean != nil }
    }

    /// La misma señal, con una línea base por fuente. Nunca se mezclan.
    private struct SplitBaseline {
        let onDevice: Baseline          // noches de la app en el propio dispositivo
        let appleHealth: Baseline       // noches que llegaron desde Apple Health

        init(_ window: [DailyMetric], appleDays: Set<String>, reading: (DailyMetric) -> Double?) {
            self.onDevice = Baseline(window.filter { !appleDays.contains($0.day) }.compactMap(reading))
            self.appleHealth = Baseline(window.filter { appleDays.contains($0.day) }.compactMap(reading))
        }

        func forDay(_ day: String, appleDays: Set<String>) -> Baseline {
            appleDays.contains(day) ? appleHealth : onDevice
        }
    }

    /// Deduce el proxy de un día contra las líneas base que le tocan. `nil` cuando ninguna de las
    /// dos señales tiene a la vez lectura y centro — arranque en frío honesto, no un 1.5 inventado.
    private static func derive(_ day: DailyMetric, rhr: Baseline, hrv: Baseline) -> Double? {
        let pulso = day.restingHr.map(Double.init)
        let variabilidad = day.avgHrv
        guard rhr.canScore(pulso) || hrv.canScore(variabilidad) else { return nil }
        return StressMath.squash(StressMath.rawScore(
            rhrToday: pulso, meanRHR: rhr.mean, sdRHR: rhr.sd,
            hrvToday: variabilidad, meanHRV: hrv.mean, sdHRV: hrv.sd
        ))
    }

    /// Arma el modelo con los días vieja→nueva más lo que ya estuviera guardado en la serie
    /// `stress`. Devuelve `nil` sólo cuando no hay ninguna señal aprovechable.
    ///
    /// `appleDays` son las claves de día que salieron de Apple Health (`repo.appleHealthDays`).
    /// LAS DOS líneas base se parten por fuente, para que cada lectura se mida contra la base de la
    /// SUYA. En HRV, las noches de la app son RMSSD y las de Apple son SDNN: dos construcciones sin
    /// conversión publicada (Task Force 1996; Shaffer y Ginsberg 2017, *Front Public Health* 5:258).
    /// En FC de reposo, la app la toma del nadir del sueño y Apple de muestras sedentarias
    /// DESPIERTAS, así que la de Apple corre sistemáticamente ~10–13 lpm más alta (Fenland Study,
    /// Gonzales et al. 2023, *PLoS One* 18(5):e0285272: 56.9 dormido contra 67.6 sentado) — no es el
    /// mismo número y el desfase no es fijo, cambia con la persona. El z-score es la moneda común;
    /// los lpm y los ms crudos jamás se comparan entre fuentes (FER-633, que reemplaza la vieja
    /// política de FC fusionada de FER-519). Un `appleDays` vacío es la identidad: una historia
    /// hecha sólo en el dispositivo sale idéntica.
    public init?(days: [DailyMetric], stored: [(day: String, value: Double)], todayKey: String,
                 appleDays: Set<String> = []) {

        // Sólo días de hoy hacia atrás. El filtro tira de paso las filas fantasma con fecha futura
        // que deja el bucketing en UTC (FER-226).
        let usable = days.filter { $0.day <= todayKey }
        guard !usable.isEmpty else { return nil }

        // Lo ya guardado, por día y recortado al rango legal. Ante una clave repetida gana la última.
        let storedByDay = Dictionary(
            stored.map { ($0.day, min(max($0.value, 0), 3)) },
            uniquingKeysWith: { _, ultima in ultima }
        )

        // El ancla es el día más nuevo que trae algo: un valor guardado, o pulso, o HRV.
        let anchorIdx = usable.lastIndex { storedByDay[$0.day] != nil || $0.restingHr != nil || $0.avgHrv != nil }
        guard let anchorIdx else { return nil }
        let anchor = usable[anchorIdx]

        // Línea base: hasta 30 días ESTRICTAMENTE anteriores al ancla, para medirlo contra su propio
        // pasado reciente y no contra sí mismo.
        let window = Array(usable[..<anchorIdx].suffix(Self.ventana))
        let rhrBase = SplitBaseline(window, appleDays: appleDays) { $0.restingHr.map(Double.init) }
        let hrvBase = SplitBaseline(window, appleDays: appleDays) { $0.avgHrv }

        let anchorRHR = rhrBase.forDay(anchor.day, appleDays: appleDays)
        let anchorHRV = hrvBase.forDay(anchor.day, appleDays: appleDays)

        // Guardado si lo hay; si no, deducido. Sin ninguno de los dos el día no sirve de ancla
        // (el primer día de la historia, por ejemplo: no hay pasado contra el cual medirlo).
        let guardado = storedByDay[anchor.day]
        let deducido = Self.derive(anchor, rhr: anchorRHR, hrv: anchorHRV)
        guard guardado != nil || deducido != nil else { return nil }

        let resuelto = guardado ?? deducido ?? Self.proxyEnLaBase
        self.usingStored = guardado != nil
        self.score = resuelto
        self.band = StressBand(score: resuelto)

        // Cuánto se aparta el ancla del centro de SU línea base. `nil` en cuanto falte cualquiera
        // de los dos: sin centro no hay distancia que reportar.
        self.rhrToday = anchor.restingHr
        self.hrvToday = anchor.avgHrv
        self.rhrDelta = anchor.restingHr.flatMap { lectura in
            anchorRHR.mean.map { Double(lectura) - $0 }
        }
        self.hrvDelta = anchor.avgHrv.flatMap { lectura in
            anchorHRV.mean.map { lectura - $0 }
        }

        // De qué día es el héroe y si está lo bastante fresco para enseñarse (hoy o, como mucho,
        // ayer). Ayer se calcula con la aritmética de días del propio paquete, en UTC —
        // `CorrelationEngine.shiftDay` es el único sumador de días con clave que existe aquí.
        self.anchorDayKey = anchor.day
        self.anchorIsToday = anchor.day == todayKey
        self.heroIsFresh = anchor.day == todayKey || anchor.day == CorrelationEngine.shiftDay(todayKey, by: -1)

        // La historia completa: el valor guardado del día si lo hay, y si no la deducción contra
        // LAS MISMAS líneas base, para que la curva sea comparable de punta a punta. Un día sin
        // nada de nada simplemente no aparece.
        var curva: [Point] = []
        for day in usable {
            // Aritmética civil pura de la clave a epoch (la misma de `ComparisonEngine.epochDay`),
            // para no armar un `DateFormatter` por fila en series de hasta ~4 mil días
            // (FER-972 · M-04).
            guard let epoch = ComparisonEngine.epochDay(of: day.day) else { continue }
            let fecha = Date(timeIntervalSince1970: Double(epoch) * 86_400)
            if let ya = storedByDay[day.day] {
                curva.append(Point(date: fecha, value: ya))
            } else if let deducido = Self.derive(day,
                                                 rhr: rhrBase.forDay(day.day, appleDays: appleDays),
                                                 hrv: hrvBase.forDay(day.day, appleDays: appleDays)) {
                curva.append(Point(date: fecha, value: deducido))
            }
        }
        self.fullTrend = curva

        // «Tiempo en calma»: de los últimos 30 días graficados, cuántos se quedaron en la banda baja.
        let recientes = curva.suffix(Self.ventana)
        self.calmWindow = recientes.count
        self.calmDays = recientes.filter { StressBand(score: $0.value) == .low }.count
    }
}
