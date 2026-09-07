import CenitStore
import Foundation
import StrandAnalytics
import StrandImport
import StrandModels

/// Deja una exportación de Apple Salud guardada en la base local, bajo su propio identificador de
/// fuente, para que conviva al lado de las demás fuentes en las páginas por fuente y en el consenso.
///
/// Llena cuatro tablas de un jalón: los agregados diarios de Apple, la métrica diaria unificada, la
/// serie genérica que alimenta al explorador, y los entrenamientos.
enum AppleHealthImport {

    /// Lee el archivo, lo agrega por día y lo escribe. Devuelve el resumen que produjo el parseo.
    ///
    /// - Parameters:
    ///   - url: el archivo de exportación ya accesible en disco.
    ///   - store: la base local abierta.
    ///   - deviceId: la fuente bajo la que se guarda todo lo de esta corrida.
    ///   - maxHR: pulso máximo del usuario, si se conoce; alimenta la estimación de esfuerzo.
    ///   - sex: sexo declarado, para la misma estimación.
    ///   - progress: se llama desde el hilo del parseo con el conteo de registros leídos.
    ///   - isCancelled: se consulta durante el parseo; si responde `true`, la corrida lanza
    ///     `CancellationError` y no escribe nada.
    @discardableResult
    static func importExport(
        url: URL,
        into store: CenitStore,
        deviceId: String,
        maxHR: Double? = nil,
        sex: String = "male",
        progress: AppleHealthImporter.ProgressHandler? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async throws -> ImportSummary {
        // El parseo agrega por día conforme lee, así que `daily` ya viene fusionado: no hace falta
        // una segunda pasada. Consulta `isCancelled` mientras corre y aborta si el usuario se salió
        // a media importación (FER-33).
        let parsed = try ImportCoordinator().importAppleHealth(from: url,
                                                              progress: progress,
                                                              isCancelled: isCancelled)
        let daily = parsed.daily

        // Una cancelación pudo llegar entre el fin del parseo y este punto. Mejor no empezar una
        // escritura que toca cuatro tablas.
        try Task.checkCancellation()

        try await writeAppleDaily(daily, into: store, deviceId: deviceId)
        try await writeDailyMetrics(daily,
                                    workouts: parsed.workouts,
                                    into: store,
                                    deviceId: deviceId,
                                    maxHR: maxHR,
                                    sex: sex)
        try await writeMetricSeries(daily, into: store, deviceId: deviceId)
        try await writeWorkouts(parsed.workouts, into: store, deviceId: deviceId)

        return parsed.summary
    }

    // MARK: - Agregados propios de Apple

    /// Pasos, energía, VO₂ máx. y los tres pulsos del día. El peso no viene por esta ruta.
    private static func writeAppleDaily(
        _ daily: [AppleDailyAggregate],
        into store: CenitStore,
        deviceId: String
    ) async throws {
        let rows = daily.map { day in
            AppleDaily(
                day: day.day,
                steps: day.steps.map { Int($0) },
                activeKcal: day.activeKcal,
                basalKcal: day.basalKcal,
                vo2max: day.vo2max,
                avgHr: day.avgHr.map { Int($0.rounded()) },
                maxHr: day.maxHr.map { Int($0.rounded()) },
                walkingHr: day.walkingHr.map { Int($0.rounded()) },
                weightKg: nil
            )
        }
        try await store.upsertAppleDaily(rows, deviceId: deviceId)
    }

    // MARK: - Métrica diaria unificada

    /// Sueño, pulso en reposo, variabilidad y esfuerzo estimado, en la tabla que comparten todas las
    /// fuentes.
    ///
    /// CARGA VIVA: la exportación en XML no trae pulso por entrenamiento, así que la clasificación
    /// aquí solo puede salir «descanso» o «sin dato», nunca «carga». Una sincronización posterior con
    /// pulso real sube esos mismos días por la misma llave de upsert (fuente + día).
    private static func writeDailyMetrics(
        _ daily: [AppleDailyAggregate],
        workouts: [HealthWorkout],
        into store: CenitStore,
        deviceId: String,
        maxHR: Double?,
        sex: String
    ) async throws {
        // La llave de día sale del desfase de zona horaria de cada registro, no de la zona del
        // teléfono: de otro modo no empata con la llave que trae el agregado diario.
        let daysWithWorkout = Set(workouts.map {
            AppleHealthAggregator.localDay($0.start, tzOffsetMin: $0.tzOffsetMin)
        })
        let today = DayKey.local(Date())

        let rows = daily.map { day -> DailyMetric in
            let activity = AppleLoadEstimator.DayActivity(
                workoutHR: [],
                steps: day.steps.map { Int($0) },
                activeKcal: day.activeKcal,
                hasWorkout: daysWithWorkout.contains(day.day)
            )
            let classified = AppleLoadEstimator.classify(
                activity,
                maxHR: maxHR,
                restingHR: day.restingHr ?? StrainScorer.defaultRestingHR,
                sex: sex
            )

            return DailyMetric(
                day: day.day,
                totalSleepMin: day.asleepMin,
                efficiency: nil,
                deepMin: day.deepMin,
                remMin: day.remMin,
                lightMin: day.coreMin,
                disturbances: nil,
                restingHr: day.restingHr.map { Int($0.rounded()) },
                avgHrv: day.hrvSDNN,
                recovery: nil,
                strain: strain(for: classified, day: day.day, today: today),
                exerciseCount: nil,
                spo2Pct: day.spo2Pct,
                skinTempDevC: nil,
                respRateBpm: day.respRate
            )
        }
        try await store.upsertDailyMetrics(rows, deviceId: deviceId)
    }

    /// El esfuerzo solo se guarda para días ya cerrados — la misma puerta que aplica la
    /// sincronización en vivo, para que un día a medias no se congele con la cifra de la mañana.
    private static func strain(
        for classified: AppleLoadEstimator.DayLoad,
        day: String,
        today: String
    ) -> Double? {
        guard AppleLoadEstimator.isCompletedDay(day, today: today) else { return nil }
        switch classified {
        case .rest:            return 0
        case .load(let value): return value
        case .missing:         return nil
        }
    }

    // MARK: - Serie genérica

    /// Todo lo demás, sin interpretar, para el explorador de métricas.
    private static func writeMetricSeries(
        _ daily: [AppleDailyAggregate],
        into store: CenitStore,
        deviceId: String
    ) async throws {
        let points = AppleHealthAggregator.metricPoints(daily).map {
            MetricPoint(day: $0.day, key: $0.key, value: $0.value)
        }
        try await store.upsertMetricSeries(points, deviceId: deviceId)
    }

    // MARK: - Entrenamientos

    /// La exportación no trae pulso ni zonas por entrenamiento; esas columnas quedan vacías a
    /// propósito y las llena después la sincronización en vivo.
    private static func writeWorkouts(
        _ workouts: [HealthWorkout],
        into store: CenitStore,
        deviceId: String
    ) async throws {
        let rows = workouts.map { workout in
            WorkoutRow(
                startTs: Int(workout.start.timeIntervalSince1970),
                endTs: Int(workout.end.timeIntervalSince1970),
                sport: workout.activityType,
                // Valor persistido: así quedaron marcadas las filas ya guardadas en el teléfono.
                source: "apple_health",
                durationS: workout.durationS,
                energyKcal: workout.energyKcal,
                avgHr: nil,
                maxHr: nil,
                strain: nil,
                distanceM: workout.distanceM,
                zonesJSON: nil,
                notes: nil
            )
        }
        try await store.upsertWorkouts(rows, deviceId: deviceId)
    }
}
