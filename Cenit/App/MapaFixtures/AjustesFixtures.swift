#if os(iOS) && DEBUG
import Foundation
import CenitStore

/// Estados de fixture de la familia **Ajustes** para el mapa 100 % (FER-389 · Ola 2E).
///
/// Dos estados reales, ninguno tocando HealthKit: `appleHealthDays` puebla la fuente "apple-health"
/// (aggregates + series) para que `AppleHealthView` muestre tiles/gráficas con datos; `historialFAOculta`
/// siembra UNA fila `apple_rmssd_night` para que `HistorialFAPuerta.estado` lea «ya llegan series
/// densas» y la sección de `AjustesHistorialFA` se calle sola (su estado por defecto, sin fixture, ya
/// es el visible — «informa» — así que solo el estado opuesto necesita siembra).
enum AjustesFixtures {
    static let all: [String: FixtureRegistry.Seed] = [
        "appleHealthDays": { model in await seedAppleHealthDays(model) },
        "historialFAOculta": { model in await seedHistorialFAOculta(model) },
    ]

    /// «Apple Salud · con filas» (`AppleHealthView`): dos semanas de aggregates (`AppleDaily`) + series
    /// por métrica (`MetricPoint`), ambas bajo la fuente "apple-health" — las MISMAS dos tablas que
    /// `HealthKitBridge` llenaría en un sync real, así los tiles y las gráficas de esa pantalla salen
    /// con datos sin pedir ningún permiso de HealthKit.
    @MainActor
    private static func seedAppleHealthDays(_ model: AppModel) async {
        guard let store = await model.repo.storeHandle() else { return }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        var dailyRows: [AppleDaily] = []
        var points: [MetricPoint] = []
        for ago in stride(from: 13, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -ago, to: today) else { continue }
            let day = Repository.localDayKey(d)
            let idx = 13 - ago
            let steps = 7200 + idx * 120
            let active = 380.0 + Double(idx) * 6
            let rhr = 52 + (idx % 4)
            let hrv = 58.0 - Double(idx % 5)
            let vo2 = 46.5 + Double(idx) * 0.05
            dailyRows.append(AppleDaily(day: day, steps: steps, activeKcal: active, basalKcal: 1600,
                                        vo2max: vo2, avgHr: 70, maxHr: 145, walkingHr: 92, weightKg: 78.0))
            points.append(MetricPoint(day: day, key: "steps", value: Double(steps)))
            points.append(MetricPoint(day: day, key: "active_kcal", value: active))
            points.append(MetricPoint(day: day, key: "vo2max", value: vo2))
            points.append(MetricPoint(day: day, key: "resting_hr", value: Double(rhr)))
            points.append(MetricPoint(day: day, key: "hrv", value: hrv))
            points.append(MetricPoint(day: day, key: "spo2", value: 97.2))
            points.append(MetricPoint(day: day, key: "resp_rate", value: 14.6))
            points.append(MetricPoint(day: day, key: "asleep_min", value: 430))
            // Composición corporal medida una vez por semana → dispersa a propósito, como el import real.
            if idx % 7 == 0 {
                points.append(MetricPoint(day: day, key: "weight", value: 78.0))
                points.append(MetricPoint(day: day, key: "body_fat", value: 17.5))
                points.append(MetricPoint(day: day, key: "lean_mass", value: 64.3))
                points.append(MetricPoint(day: day, key: "bmi", value: 24.6))
            }
        }
        _ = try? await store.upsertAppleDaily(dailyRows, deviceId: "apple-health")
        _ = try? await store.upsertMetricSeries(points, deviceId: "apple-health")
    }

    /// «Historial de FA · oculta» (`AjustesHistorialFA`): una sola fila reciente de `apple_rmssd_night`
    /// (la partición `Repository.appleComputedDeviceId`) basta — `HistorialFAPuerta.estado` la lee como
    /// evidencia de que el motor YA emitió un RMSSD nocturno, y la sección deja de pintarse.
    @MainActor
    private static func seedHistorialFAOculta(_ model: AppModel) async {
        guard let store = await model.repo.storeHandle() else { return }
        let day = Repository.localDayKey(Date())
        let punto = MetricPoint(day: day, key: HistorialFAPuerta.claveRmssd, value: 42)
        _ = try? await store.upsertMetricSeries([punto], deviceId: Repository.appleComputedDeviceId)
    }
}
#endif
