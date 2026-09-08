#if os(iOS) && DEBUG
import Foundation
import BiometricStreams
import CenitStore
import CenitModels

/// Estados de fixture de la familia **Tendencias** para el mapa 100 % (FER-381 · Ola 2B FER-384).
///
/// Dos estados, compartidos por las ~36 métricas del catálogo (no uno por métrica): el detalle de
/// CADA métrica lee el mismo store/dashboard, así que UN fixture de historia larga basta para su
/// «full», y UN fixture de un solo día para su «calibrando». «Sin lecturas» no necesita fixture —
/// `-cenit.freshStore YES` (que `test_mapa` ya añade a todo nodo) deja el store realmente vacío.
///
/// Tres sustratos, porque el catálogo no lee todos sus datos del mismo sitio (FER-104/TND-29):
///   1. `DailyMetric` (`repo.setDashboard`) — las 13 claves «resolubles del dashboard»
///      (`MetricSeriesResolver.dashboardPicker`): recovery/hrv/rhr/resp_rate/spo2/skin_temp/steps +
///      el bloque de sueño. Leídas tanto por el Explorador genérico como por los 5 vitales ricos
///      que abren `MetricDetailScreen` desde Cuerpo (hrv/rhr/resp_rate/spo2/steps).
///   2. `metricSeries` (EAV, `store.upsertMetricSeries`) — las 22 claves import-only (peso, grasa,
///      BMI, VO₂max, splits de zona FC, calorías, sueño «extra»…) que el Explorador genérico lee
///      vía `repo.series(key:source:)` cuando el dashboard no las resuelve.
///   3. `AppleDaily` (`store.upsertAppleDaily`) — la tabla ANCHA de Apple Salud que
///      `CuerpoView.vitalSeries(for: "vo2max")` lee para el detalle RICO de VO₂max (distinta de la
///      serie EAV que usa el Explorador genérico para la MISMA métrica — dos caminos, FER-257).
/// + un trazo intradía de FC (`Streams.hr`) para el bloque protagonista de Heart Rate.
enum TendenciasFixtures {
    static let all: [String: FixtureRegistry.Seed] = [
        "tendencias_full": { model in await seed(model, days: 40) },
        "tendencias_calibrando": { model in await seed(model, days: 1) },
    ]

    /// `-cenit.range <W|M|3M|6M|1Y|ALL>` (FER-384): la ventana inicial para la captura del mapa 100 %,
    /// compartida por Cuerpo / `MetricDetailScreen` / `MetricExplorerView` (las tres pantallas de esta
    /// familia con su propio `@State … ExploreRange`) — un solo parseo del arg, no uno por pantalla.
    /// `nil` con el arg ausente o con un valor que no reconoce: cada caller cae a su `.month` de siempre.
    static func debugRange() -> ExploreRange? {
        switch UserDefaults.standard.string(forKey: "cenit.range")?.uppercased() {
        case "W":   return .week
        case "M":   return .month
        case "3M":  return .quarter
        case "6M":  return .half
        case "1Y":  return .year
        case "ALL": return .all
        default:    return nil
        }
    }

    // MARK: - Seed

    @MainActor
    private static func seed(_ model: AppModel, days nDays: Int) async {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // 1) `DailyMetric` — las 13 claves dashboard-resolvables (incluye los 5 vitales ricos que NO
        // son VO₂max/Heart Rate). Ola simple, sin la coreografía de veredictos de ScreenshotFixtures —
        // a este fixture solo le importa que cada métrica tenga UNA serie no vacía que enseñar.
        var days: [DailyMetric] = []
        for ago in stride(from: nDays - 1, through: 0, by: -1) {
            let idx = nDays - 1 - ago
            let dayKey = Repository.localDayKey(cal.date(byAdding: .day, value: -ago, to: today)!)
            days.append(DailyMetric(
                day: dayKey, totalSleepMin: 430 + wobble(idx, 20), efficiency: 0.88 + wobble(idx, 0.03),
                deepMin: 90 + wobble(idx, 8), remMin: 105 + wobble(idx, 8), lightMin: 235 + wobble(idx, 10),
                disturbances: 3, restingHr: 52 + Int(wobble(idx, 3)), avgHrv: 58 + wobble(idx, 6),
                recovery: 68 + wobble(idx, 10), strain: 10 + wobble(idx, 3), exerciseCount: 1,
                spo2Pct: 97.3 + wobble(idx, 0.6), skinTempDevC: 0.05 + wobble(idx, 0.1),
                respRateBpm: 14.6 + wobble(idx, 0.6), steps: 8200 + Int(wobble(idx, 1200)),
                activeKcalEst: 460 + wobble(idx, 90)))
        }
        // Store writes FIRST, the dashboard publish LAST (mirrors `ScreenshotFixtures`'s own
        // "primed" case): `setDashboard` bumps `repo.refreshSeq`, which is what re-triggers
        // `CuerpoLanding.loadAll()` — publishing early would fire that reload BEFORE these rows
        // land, so `appleDays`/`hrPoints` (read straight from the store, not `repo.dashboard`)
        // would reload empty and never retry (no second bump follows).
        if let store = await model.repo.storeHandle() {
            // 2) `metricSeries` (EAV) — las claves import-only, derivadas del propio catálogo (no una
            // lista a mano que pueda desalinearse de `MetricSeriesResolver`).
            var byDeviceId: [String: [MetricPoint]] = [:]
            for d in MetricCatalog.all where MetricSeriesResolver.dashboardPicker(for: d.key) == nil {
                let base = plausibleValue(for: d.key)
                for (i, dayKey) in days.map(\.day).enumerated() {
                    byDeviceId[d.source, default: []].append(
                        MetricPoint(day: dayKey, key: d.key, value: base + wobble(i, base * 0.05)))
                }
            }
            for (deviceId, rows) in byDeviceId {
                _ = try? await store.upsertMetricSeries(rows, deviceId: deviceId)
            }

            // 3) `AppleDaily` — solo VO₂max lo necesita aquí (es la única de las 7 rutas ricas de
            // `-cenit.route tendencias/<clave>` que lee esta tabla en vez de `metricSeries`).
            let appleRows = days.enumerated().map { i, row in
                AppleDaily(day: row.day, steps: row.steps, activeKcal: row.activeKcalEst, basalKcal: nil,
                          vo2max: plausibleValue(for: "vo2max") + wobble(i, 1.5), avgHr: nil, maxHr: nil,
                          walkingHr: nil, weightKg: nil)
            }
            _ = try? await store.upsertAppleDaily(appleRows, deviceId: "apple-health")

            // + un trazo intradía de FC — el bloque protagonista de Heart Rate (`hrPoints`, no
            // `series`). «calibrando» (1 día) deja un puñado de puntos, no la jornada completa: la
            // curva se ve apenas empezada, no un día lleno con historia de una sola noche (incoherente).
            let hr = syntheticHRSamples(today: today, sparse: nDays == 1)
            if !hr.isEmpty { _ = try? await store.insert(Streams(hr: hr), deviceId: model.legacyDeviceId) }
        }

        model.repo.setDashboard(days: days, appleHealthDays: Set(days.map(\.day)))
    }

    /// Un valor representativo por clave — nunca leído por su precisión, solo por estar presente (para
    /// que el numeral del detalle no salga en blanco). Unidades siguiendo `MetricCatalog` (kg/%/min/…).
    private static func plausibleValue(for key: String) -> Double {
        switch key {
        case "avg_hr":               return 68
        case "max_hr":                return 152
        case "energy_kcal":           return 2250
        case "vo2max":                return 41
        case "in_bed_min":            return 480
        case "hours_vs_needed_pct":   return 94
        case "sleep_consistency":     return 78
        case "restorative_pct":       return 32
        case "restorative_min":       return 145
        case "sleep_need_min":        return 455
        case "sleep_debt_min":        return 22
        case "sleep_performance":     return 82
        case "hr_zones13_min":        return 38
        case "hr_zones45_min":        return 9
        case "hr_zones_all_min":      return 47
        case "strength_min":          return 28
        case "active_kcal":           return 430
        case "weight":                return 76
        case "body_fat":              return 19
        case "lean_mass":             return 61
        case "bmi":                   return 23.5
        case "stress":                return 1.3
        default:                      return 10
        }
    }

    /// Un puñado de muestras de FC de hoy: 3600 s (13 puntos a 5 min) para «calibrando» (la curva
    /// apenas arranca); el día completo hasta ahora (5 min de cadencia) para «full».
    private static func syntheticHRSamples(today: Date, sparse: Bool) -> [HRSample] {
        let midnight = Int(today.timeIntervalSince1970)
        let now = Int(Date().timeIntervalSince1970)
        guard now > midnight else { return [] }
        let end = sparse ? min(now, midnight + 3600) : now
        var out: [HRSample] = []
        var ts = midnight
        while ts <= end {
            let hour = Double(ts - midnight) / 3600.0
            var bpm = 58.0 + 8.0 * sin(hour / 24.0 * 2 * .pi)
            if !sparse, hour >= 7, hour < 8 { bpm = 118 + 20 * sin((hour - 7) * .pi) }   // rebote de entreno matutino
            out.append(HRSample(ts: ts, bpm: Int(bpm.rounded())))
            ts += 300
        }
        return out
    }

    /// Pequeño vaivén determinista (sin RNG → reproducible) para que las series no salgan planas.
    private static func wobble(_ idx: Int, _ amp: Double) -> Double { amp * sin(Double(idx) * 0.6) }
}
#endif
