#if DEBUG && CENIT_SPIKE_SERIES12
#if os(iOS)
import Foundation
import HealthKit

/// Sonda desechable FER-523: mide densidad de FC + HRV de la última noche en HealthKit.
/// Solo lectura. Cero red. Cero escritura. No toca el store ni el bridge de producción.
struct SpikeSeries12DensityProbe {

    /// Umbrales del spike (calibración de producto, no clínicos).
    enum Thresholds {
        /// Intervalo mediano de FC (s) por debajo del cual se considera ~5 s.
        static let hrMedianSecondsHighDensity: TimeInterval = 8
        /// Muestras de HRV en la ventana para llamar «denso» (baseline ~1/noche).
        static let hrvSampleCountHighDensity: Int = 10
        /// Cobertura horaria mínima de FC (fracción de horas con ≥1 muestra).
        static let hrHourCoverageHighDensity: Double = 0.5
    }

    enum HRVKind: String {
        case rmssd = "heartRateVariabilityRMSSD"
        case sdnnFallback = "heartRateVariabilitySDNN"
    }

    enum Verdict: String {
        case highDensity = "Densidad alta detectada"
        case normalDensity = "Densidad normal"
        case insufficientData = "Datos insuficientes"
    }

    struct MetricDensity: Equatable {
        var sampleCount: Int
        /// Intervalo mediano entre muestras consecutivas, en segundos. nil si < 2 muestras.
        var medianIntervalSeconds: Double?
        /// Horas civiles (0…23) con al menos una muestra, sobre las horas que toca la ventana.
        var hoursCovered: Int
        var hoursInWindow: Int
        var hourCoverage: Double { hoursInWindow > 0 ? Double(hoursCovered) / Double(hoursInWindow) : 0 }
    }

    struct Report: Equatable {
        var windowStart: Date
        var windowEnd: Date
        var windowSource: String
        var hrvKind: HRVKind
        var heartRate: MetricDensity
        var hrv: MetricDensity
        var verdict: Verdict
        var notes: [String]
    }

    private let store = HKHealthStore()

    // MARK: - Auth

    func requestReadAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ProbeError.healthUnavailable
        }
        var read: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        let hrvId = Self.resolveHRVIdentifier().id
        if let hrv = HKObjectType.quantityType(forIdentifier: hrvId) { read.insert(hrv) }
        // Sueño solo para acotar la ventana; si falla el permiso, caemos a 8 h.
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { read.insert(sleep) }
        try await store.requestAuthorization(toShare: [], read: read)
    }

    // MARK: - Measure

    func measureLastNight(now: Date = Date(), calendar: Calendar = .current) async throws -> Report {
        let (windowStart, windowEnd, windowSource) = await resolveNightWindow(now: now, calendar: calendar)
        let (hrvId, hrvKind) = Self.resolveHRVIdentifier()

        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let hrvType = HKQuantityType.quantityType(forIdentifier: hrvId)

        let hrDates: [Date]
        if let hrType {
            hrDates = await sampleStartDates(type: hrType, start: windowStart, end: windowEnd)
        } else {
            hrDates = []
        }

        let hrvDates: [Date]
        if let hrvType {
            hrvDates = await sampleStartDates(type: hrvType, start: windowStart, end: windowEnd)
        } else {
            hrvDates = []
        }

        let hrDensity = Self.density(of: hrDates, windowStart: windowStart, windowEnd: windowEnd, calendar: calendar)
        let hrvDensity = Self.density(of: hrvDates, windowStart: windowStart, windowEnd: windowEnd, calendar: calendar)

        var notes: [String] = []
        notes.append("Tipo HRV usado: \(hrvKind.rawValue).")
        if hrvKind == .sdnnFallback {
            notes.append("RMSSD no resolvió en runtime; midiendo SDNN como respaldo.")
        }
        notes.append("Ventana: \(windowSource).")
        notes.append(
            "Baseline Watch normal: FC esparcida (minutos) + HRV ~1/noche. GO: FC mediana ≤ \(Int(Thresholds.hrMedianSecondsHighDensity)) s y HRV ≥ \(Thresholds.hrvSampleCountHighDensity) muestras."
        )

        let verdict = Self.verdict(hr: hrDensity, hrv: hrvDensity, notes: &notes)

        return Report(
            windowStart: windowStart,
            windowEnd: windowEnd,
            windowSource: windowSource,
            hrvKind: hrvKind,
            heartRate: hrDensity,
            hrv: hrvDensity,
            verdict: verdict,
            notes: notes
        )
    }

    // MARK: - HRV type resolution

    /// Prefiere RMSSD en iOS 27+; si el tipo no existe en runtime, cae a SDNN.
    static func resolveHRVIdentifier() -> (id: HKQuantityTypeIdentifier, kind: HRVKind) {
        if #available(iOS 27.0, *) {
            let rmssd = HKQuantityTypeIdentifier.heartRateVariabilityRMSSD
            if HKObjectType.quantityType(forIdentifier: rmssd) != nil {
                return (rmssd, .rmssd)
            }
        }
        return (.heartRateVariabilitySDNN, .sdnnFallback)
    }

    // MARK: - Window

    /// Última sesión de sueño (unión de tramos asleep) o, si no hay, las últimas 8 h.
    private func resolveNightWindow(now: Date, calendar: Calendar) async -> (Date, Date, String) {
        let lookbackStart = calendar.date(byAdding: .hour, value: -36, to: now) ?? now.addingTimeInterval(-36 * 3600)
        if let sleep = await lastAsleepSession(start: lookbackStart, end: now) {
            return (sleep.start, sleep.end, "sueño (última sesión asleep)")
        }
        let start = calendar.date(byAdding: .hour, value: -8, to: now) ?? now.addingTimeInterval(-8 * 3600)
        return (start, now, "últimas 8 h (sin sueño en Salud)")
    }

    private func lastAsleepSession(start: Date, end: Date) async -> (start: Date, end: Date)? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, raw, _ in
                cont.resume(returning: (raw as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleepIntervals = samples
            .filter { asleep.contains($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        guard !asleepIntervals.isEmpty else { return nil }

        // Sesiones separadas por hueco ≥ 1 h; nos quedamos con la última.
        var sessions: [(start: Date, end: Date)] = []
        var curStart = asleepIntervals[0].start
        var curEnd = asleepIntervals[0].end
        for iv in asleepIntervals.dropFirst() {
            if iv.start.timeIntervalSince(curEnd) >= 3600 {
                sessions.append((curStart, curEnd))
                curStart = iv.start
                curEnd = iv.end
            } else {
                curEnd = max(curEnd, iv.end)
            }
        }
        sessions.append((curStart, curEnd))
        return sessions.last
    }

    // MARK: - Samples

    private func sampleStartDates(type: HKSampleType, start: Date, end: Date) async -> [Date] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, raw, _ in
                let dates = ((raw as? [HKSample]) ?? []).map(\.startDate)
                cont.resume(returning: dates)
            }
            store.execute(q)
        }
    }

    // MARK: - Stats

    static func density(of dates: [Date], windowStart: Date, windowEnd: Date, calendar: Calendar) -> MetricDensity {
        let sorted = dates.sorted()
        let median: Double?
        if sorted.count >= 2 {
            var gaps: [Double] = []
            gaps.reserveCapacity(sorted.count - 1)
            for i in 1..<sorted.count {
                gaps.append(sorted[i].timeIntervalSince(sorted[i - 1]))
            }
            gaps.sort()
            median = gaps[gaps.count / 2]
        } else {
            median = nil
        }

        let hoursInWindow = hourSlots(from: windowStart, to: windowEnd, calendar: calendar)
        let covered: Set<Date> = Set(sorted.map { calendar.dateInterval(of: .hour, for: $0)?.start ?? $0 })
        let hoursCovered = hoursInWindow.filter { covered.contains($0) }.count

        return MetricDensity(
            sampleCount: sorted.count,
            medianIntervalSeconds: median,
            hoursCovered: hoursCovered,
            hoursInWindow: hoursInWindow.count
        )
    }

    private static func hourSlots(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard end > start else { return [] }
        var slots: [Date] = []
        var cursor = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        while cursor < end {
            slots.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return slots
    }

    static func verdict(hr: MetricDensity, hrv: MetricDensity, notes: inout [String]) -> Verdict {
        if hr.sampleCount == 0 && hrv.sampleCount == 0 {
            notes.append("Sin muestras de FC ni HRV en la ventana.")
            return .insufficientData
        }
        let hrDense = (hr.medianIntervalSeconds ?? .infinity) <= Thresholds.hrMedianSecondsHighDensity
            && hr.hourCoverage >= Thresholds.hrHourCoverageHighDensity
            && hr.sampleCount >= 50
        let hrvDense = hrv.sampleCount >= Thresholds.hrvSampleCountHighDensity

        if hrDense && hrvDense {
            notes.append("FC ~densa y HRV con varias muestras → GO para capa densa.")
            return .highDensity
        }
        if hrDense && !hrvDense {
            notes.append("FC densa pero HRV aún cerca del baseline (~1/noche). NO-GO completo.")
        } else if !hrDense && hrvDense {
            notes.append("HRV denso pero FC no llega a ~5 s. NO-GO completo.")
        } else {
            notes.append("Ambas señales en rango de Watch normal.")
        }
        return .normalDensity
    }

    enum ProbeError: LocalizedError {
        case healthUnavailable
        var errorDescription: String? {
            switch self {
            case .healthUnavailable: return "HealthKit no está disponible en este dispositivo."
            }
        }
    }
}
#endif
#endif
