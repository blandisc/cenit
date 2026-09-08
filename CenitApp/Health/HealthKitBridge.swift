#if os(iOS)
import Foundation
import CryptoKit
import HealthKit
import StrandAnalytics
import StrandImport
import BiometricStreams
import CenitStore

/// La puerta entre Apple Health y el almacén local, del lado iOS.
///
/// HealthKit solo existe en iOS, así que aquí la app no depende de un archivo de exportación: lee en
/// vivo lo que el usuario ya tiene en Salud y lo deja en las MISMAS filas de `CenitStore` que produce
/// el importador de macOS, bajo la fuente `apple-health`. La única escritura de vuelta es el
/// `HKWorkout` de fuerza, y solo si el usuario lo enciende. Nada sale del dispositivo.
@MainActor
final class HealthKitBridge: ObservableObject {

    /// Cómo está la conexión con Salud. `unavailable` = el dispositivo no tiene HealthKit.
    enum AuthState: Equatable {
        case unknown
        case unavailable
        case denied
        case authorized
    }

    /// Live progress of the running `sync`. `done/total` counts pipeline stages; `stageKey` names the
    /// current one ("hrv", "sleep", "saving", …) so the UI maps it to a localized "Importing HRV…"
    /// label. Nil whenever idle. (FER-70)
    struct SyncProgress: Equatable {
        let stageKey: String
        let done: Int
        let total: Int
    }

    @Published private(set) var auth: AuthState = .unknown
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncing = false
    /// El último fallo de `sync`, o `nil` tras una corrida buena. La UI se ata aquí para que un
    /// permiso revocado, una cuota de HealthKit o una muestra inválida se vean, en vez de perderse
    /// en silencio.
    @Published private(set) var lastError: String?
    /// Live stage of the running import (nil when idle), so the card shows real progress instead of a
    /// context-free spinner. (FER-70)
    @Published private(set) var syncProgress: SyncProgress?
    /// FER-437: the rows each FINISHED stage of the current — or the LAST — run brought, keyed by
    /// `stageKey` — days for the per-day collectors, workouts / HR samples for the workout stages,
    /// and the total of upserted rows for `saving` (recorded only after the store write succeeds).
    /// Cumulative over the run, not "the stage that just finished": the onboarding samples this map
    /// every 100 ms, and a stage that finishes faster than that would otherwise drop off the wire —
    /// with the "every stage of the group finished" rule, one lost stage would mute its strophe
    /// forever. It OUTLIVES the run (qa r1 · D2): `syncProgress` goes nil in `sync()`'s `defer` in
    /// the same main-actor turn that records `saving`, so a sampler reading the progress value could
    /// never see the last stage's count and «Guardando en tu iPhone» was a coin toss. Emptied when a
    /// run starts, filled by `finished(_:rows:)`, never touched by the `defer`. The single source of
    /// the count (FER-475): the onboarding reads it during the run and once it is over.
    @Published private(set) var syncRowsByStage: [String: Int] = [:]
    /// What actually landed in the store under the apple-health source: days per metric + overall
    /// span. Reloaded after every `sync` and on demand via `refreshStatus`. Powers the coverage
    /// summary and the per-metric status list. (FER-70)
    @Published private(set) var coverage: AppleHealthCoverage?

    private let store = HKHealthStore()
    private let repo: Repository
    /// Id de fuente bajo el que aterriza todo lo importado de HealthKit (el mismo que
    /// `AppModel.appleDeviceId`), para que nunca se mezcle con otras particiones del almacén.
    private let appleDeviceId: String

    /// Persists "the user already connected Apple Health" across launches. HealthKit keeps the grant
    /// itself, but never reveals *read* authorization (it's private), so `authorizationStatus` can't
    /// tell us on launch whether we're connected. Without our own flag, `auth` reset to `.unknown`
    /// every launch and the scenePhase auto-sync silently no-op'd (its `guard auth == .authorized`),
    /// leaving Today's Key Metrics empty until a manual reconnect. (FER-94)
    private static let connectedDefaultsKey = "appleHealthConnected"

    /// Mirrors the Settings toggle (`@AppStorage`): write finished strength sessions to Apple Health
    /// as `HKWorkout`s (FER-390). Default off — opt-in, so we never write or prompt without consent.
    static let saveStrengthWorkoutsKey = "health.saveStrengthWorkouts"

    /// Why `sync` was called. `.foreground` is the automatic scenePhase-active trigger that fires on
    /// every launch/return; it opts into the FER-872 delta window + no-op refresh guard below. Every
    /// other caller (manual "Sync now", onboarding, the FER-226 re-bucket that reads the returned key
    /// set) is `.manual` and always does the caller's full window and a dashboard refresh.
    enum SyncTrigger { case manual, foreground }

    /// FER-872: extra days of back-margin a delta foreground sync reaches past `lastSync`, so a night
    /// Apple wrote late (or the overnight backfill) is re-pulled within the session (FER-406/407). The
    /// deep case — a Watch/iCloud dump of several STALE days that a lastSync window would step past
    /// forever — is caught by the first foreground sync of the NEXT session, which is always full.
    private static let deltaBackMarginDays = 3

    /// True once a foreground sync has completed this session. The first foreground sync stays full
    /// (this and `lastAppleWriteSignature` reset each launch); only subsequent ones go delta.
    private var didFullForegroundSyncThisSession = false

    /// Stable signature of the Apple rows written by the last sync THIS session, to skip a dashboard
    /// rebuild when a foreground re-pull produced identical data (FER-872). In-memory (per-session) for
    /// the delta comparison between subsequent foregrounds. A stale value can never cause a FALSE skip —
    /// it's recomputed from the freshly-pulled rows each run.
    private var lastAppleWriteSignature: String?

    /// FER-881: the stable signature persisted from the last session's FIRST-foreground (full 30-day)
    /// sync. The first foreground of a NEW session — which is always full — compares its fresh signature
    /// against this to skip the redundant cold-start rebuild when the Apple data is unchanged since last
    /// session (the launch full-refresh already surfaced it). Only full foreground syncs read/write it,
    /// so the window is always the same 30 days and the comparison is apples-to-apples.
    private static let lastFullSyncSigKey = "appleHealthLastFullSyncSig"
    init(repo: Repository, appleDeviceId: String) {
        self.repo = repo
        self.appleDeviceId = appleDeviceId
        if !HKHealthStore.isHealthDataAvailable() {
            auth = .unavailable
        } else if UserDefaults.standard.bool(forKey: Self.connectedDefaultsKey) {
            // Restore the prior connection so the launch auto-sync runs without forcing a reconnect.
            auth = .authorized
        }
    }

    // MARK: - Types

    /// Todo lo que el diálogo de permisos de Salud va a pedir al conectar, en cuatro grupos con una
    /// razón cada uno. Se arma por grupos —no en una lista plana— porque la pregunta que importa al
    /// revisar este archivo es «¿por qué pedimos esto?», y así la respuesta está junto al tipo.
    private var readTypes: Set<HKObjectType> {
        var scopes = Set<HKObjectType>()

        // 1) Las cantidades diarias que `sync` agrega en `DailyBucket`.
        for pull in Self.dailyQuantityPulls {
            if let type = HKObjectType.quantityType(forIdentifier: pull.identifier) { scopes.insert(type) }
        }
        // 2) Sueño y entrenamientos: las dos series no numéricas del pipeline.
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { scopes.insert(sleep) }
        scopes.insert(HKObjectType.workoutType())
        // 3) Latido a latido de la noche, para el RMSSD nocturno on-device (R2 · FER-1008). HealthKit
        //    exige que la serie de latidos venga acompañada de heartRateVariabilitySDNN, y esa ya
        //    entró en el grupo 1.
        scopes.insert(HKSeriesType.heartbeat())
        // 4) Perfil, solo para prellenar el onboarding (FER-361) desde `readProfileCharacteristics()`:
        //    sexo, fecha de nacimiento (de ahí la edad), peso y estatura.
        for id in [HKCharacteristicTypeIdentifier.biologicalSex, .dateOfBirth] {
            if let type = HKObjectType.characteristicType(forIdentifier: id) { scopes.insert(type) }
        }
        for id in [HKQuantityTypeIdentifier.bodyMass, .height] {
            if let type = HKObjectType.quantityType(forIdentifier: id) { scopes.insert(type) }
        }
        return scopes
    }

    /// The ONLY share (write) types Cénit ever asks for, and only when the user opts into saving
    /// strength workouts (FER-390). Connecting Apple Health asks for READ scopes alone — FER-398:
    /// the connect prompt used to also request resting HR / HRV / SpO₂ / respiratory rate / sleep
    /// for a write-back that FER-1003 had already switched off, i.e. permission to write data the
    /// app never writes. Asking for it is exactly the ask App Review reads as dishonest, and it is.
    private var workoutShareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(energy) }
        return s
    }

    /// Una cantidad diaria de Salud descrita entera: de dónde sale, en qué unidad se lee, cómo se
    /// resume el día y dónde aterriza.
    ///
    /// `stageKey` es contrato con la UI (`DataSourcesView.stageLabel` y `OnbEtapa`): es la clave que
    /// se traduce a «Importando HRV…». Cambiarla deja la barra de progreso sin nombre.
    private struct QuantityPull {
        let stageKey: String
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let statistic: HKStatisticsOptions
        /// Factor sobre el valor crudo de HealthKit. Solo la saturación lo usa: Apple la entrega
        /// en 0…1 y el almacén la guarda en por ciento.
        var scale: Double = 1
        let apply: (Double, inout DailyBucket) -> Void
    }

    /// Las once cantidades diarias en UNA tabla, en vez de once llamadas calcadas.
    ///
    /// De aquí salen tres cosas a la vez: el permiso que se pide (`readTypes`), la etapa de progreso
    /// que ve el usuario y el volcado a `DailyBucket`. Agregar una métrica es agregar un renglón, y
    /// su unidad vive en un solo lugar en vez de repetirse en el sitio de llamada.
    ///
    /// El orden **es** el orden de las etapas, así que mover un renglón mueve la barra de progreso.
    private static let dailyQuantityPulls: [QuantityPull] = {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        return [
            QuantityPull(stageKey: "resting_hr", identifier: .restingHeartRate,
                         unit: perMinute, statistic: .discreteAverage) { $1.restingHr = $0 },
            QuantityPull(stageKey: "avg_hr", identifier: .heartRate,
                         unit: perMinute, statistic: .discreteAverage) { $1.avgHr = $0 },
            QuantityPull(stageKey: "max_hr", identifier: .heartRate,
                         unit: perMinute, statistic: .discreteMax) { $1.maxHr = $0 },
            QuantityPull(stageKey: "hrv", identifier: .heartRateVariabilitySDNN,
                         unit: .secondUnit(with: .milli), statistic: .discreteAverage) { $1.hrv = $0 },
            QuantityPull(stageKey: "spo2", identifier: .oxygenSaturation,
                         unit: .percent(), statistic: .discreteAverage, scale: 100) { $1.spo2 = $0 },
            QuantityPull(stageKey: "resp_rate", identifier: .respiratoryRate,
                         unit: perMinute, statistic: .discreteAverage) { $1.respRate = $0 },
            QuantityPull(stageKey: "steps", identifier: .stepCount,
                         unit: .count(), statistic: .cumulativeSum) { $1.steps = $0 },
            QuantityPull(stageKey: "active_kcal", identifier: .activeEnergyBurned,
                         unit: .kilocalorie(), statistic: .cumulativeSum) { $1.activeKcal = $0 },
            QuantityPull(stageKey: "basal_kcal", identifier: .basalEnergyBurned,
                         unit: .kilocalorie(), statistic: .cumulativeSum) { $1.basalKcal = $0 },
            QuantityPull(stageKey: "vo2max", identifier: .vo2Max,
                         unit: HKUnit(from: "ml/kg*min"), statistic: .discreteAverage) { $1.vo2max = $0 },
            // FER-882: temperatura de muñeca dormido, absoluta en °C. La desviación contra la
            // baseline PROPIA de Apple se calcula más abajo, justo antes de armar `DailyMetric`.
            QuantityPull(stageKey: "skin_temp", identifier: .appleSleepingWristTemperature,
                         unit: .degreeCelsius(), statistic: .discreteAverage) { $1.skinTempC = $0 }
        ]
    }()

    // MARK: - Authorization

    /// Request READ permission only (FER-398). HealthKit never reveals whether *read* was granted, so
    /// we treat a successful request as `.authorized` and let queries return empty if the user declined.
    /// Nothing is shared here: the one write Cénit does (the strength `HKWorkout`) asks separately, in
    /// `requestWorkoutShareAuthorization`, the moment the user turns that toggle on.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            auth = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            auth = .denied
            return
        }
        auth = .authorized
        // FER-94: se recuerda la conexión, porque HealthKit no permite preguntarla en el siguiente
        // arranque; sin esta bandera el auto-sync de lanzamiento no correría.
        UserDefaults.standard.set(true, forKey: Self.connectedDefaultsKey)
        await refreshStatus()   // que la cobertura que ya existía se vea de inmediato
    }

    /// Request share (write) permission for workouts + active energy — asked ONLY when the user turns
    /// on "Guardar entrenamientos en Apple Salud" (FER-390), so a workout-write prompt never reaches
    /// someone who didn't opt in. Read scopes and the main connection state are left untouched.
    func requestWorkoutShareAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: workoutShareTypes, read: [])
    }

    // MARK: - Profile characteristics (FER-361)

    /// Sexo / edad / peso / estatura de Apple Health para prellenar el Perfil del onboarding. Todo
    /// opcional: cada campo viene solo si Health lo tiene (auto-fill parcial, campo por campo).
    struct ProfileCharacteristics: Equatable {
        var sex: String?       // "male" | "female" | "nonbinary"
        var age: Int?
        var weightKg: Double?
        var heightCm: Double?
    }

    /// Lee las características del perfil de Apple Health. On-device; nada sale del dispositivo.
    func readProfileCharacteristics() async -> ProfileCharacteristics {
        guard HKHealthStore.isHealthDataAvailable() else { return ProfileCharacteristics() }
        var out = ProfileCharacteristics()
        if let bs = try? store.biologicalSex().biologicalSex {
            switch bs {
            case .male:   out.sex = "male"
            case .female: out.sex = "female"
            case .other:  out.sex = "nonbinary"
            default:      break
            }
        }
        if let comps = try? store.dateOfBirthComponents(),
           let dob = Calendar.current.date(from: comps),
           let years = Calendar.current.dateComponents([.year], from: dob, to: Date()).year,
           (13...120).contains(years) {
            out.age = years
        }
        out.weightKg = await mostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        out.heightCm = await mostRecentQuantity(.height, unit: .meterUnit(with: .centi))
        return out
    }

    /// La muestra más reciente de un tipo de cantidad, en la unidad dada. `nil` si no hay ninguna.
    private func mostRecentQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Reload what the status panel shows *without* running an import: the coverage already stored.
    /// Call from the card's `.task` so opening it shows "X days imported" and the per-metric list
    /// right away. (FER-70)
    func refreshStatus() async {
        guard let db = await repo.storeHandle() else { return }
        coverage = try? await db.appleHealthCoverage(deviceId: appleDeviceId)
    }

    // MARK: - Lectura → almacén

    /// Trae los últimos `days` días de Apple Health al almacén local bajo la fuente `apple-health`.
    /// Se puede llamar cuantas veces sea: los upserts van llaveados por día, así que repetir no
    /// duplica. Devuelve las claves de día LOCAL escritas en esta corrida — el re-bucket de FER-226
    /// las usa para podar los huérfanos en UTC. Vacío si salió temprano o si falló la escritura.
    @discardableResult
    func sync(days: Int = 30, trigger: SyncTrigger = .manual) async -> Set<String> {
        guard auth == .authorized, !syncing else { return [] }
        syncing = true
        syncRowsByStage = [:]   // FER-437: una corrida nueva empieza con conteos nuevos (el `defer` no los toca)
        defer {
            syncing = false
            syncProgress = nil
        }
        guard let db = await repo.storeHandle() else { return [] }

        let calendar = Calendar.current
        let end = Date()
        // FER-872: the scenePhase foreground trigger fires on every launch/return; re-pulling the full
        // 30-day window each time (13 HK stages + upserts + a dashboard rebuild) is wasted work when
        // nothing changed. The FIRST foreground sync of a session stays full — the delta state resets
        // each launch, so a Watch/iCloud backfill of several STALE days (which a lastSync window would
        // step past forever) is caught here — and subsequent foregrounds pull only a short delta window
        // from `lastSync` plus a few days of back-margin, so a late-arriving night / the overnight Apple
        // backfill is never missed (FER-406/407). Manual/onboarding/re-bucket keep the caller's window.
        let effectiveDays: Int = {
            guard trigger == .foreground, didFullForegroundSyncThisSession, let last = lastSync else { return days }
            let sinceLast = end.timeIntervalSince(last)
            guard sinceLast > 0, sinceLast < Double(days) * 86_400 else { return days }
            return min(days, Int(sinceLast / 86_400) + Self.deltaBackMarginDays)
        }()
        guard let start = calendar.date(byAdding: .day, value: -effectiveDays,
                                        to: calendar.startOfDay(for: end)) else { return [] }

        var byDay: [String: DailyBucket] = [:]

        // El pipeline son las once cantidades de `dailyQuantityPulls` más cuatro etapas propias:
        // sueño, entrenamientos, pulso de entrenamiento (FER-883) y el guardado. La etapa se publica
        // ANTES de correrla, así el jalón silencioso se vuelve «Importando HRV… (4/15)» en pantalla;
        // `done` cuenta las que ya terminaron. (FER-70)
        let quantityStages = Self.dailyQuantityPulls.count
        let total = quantityStages + 4
        func stage(_ done: Int, _ key: String) { syncProgress = SyncProgress(stageKey: key, done: done, total: total) }
        // FER-437: cuántas filas trajo la etapa `key`. Va a `syncRowsByStage` (que sobrevive a la
        // corrida), para que el onboarding pueda mostrar «la espera enseña».
        func finished(_ key: String, rows: Int) { syncRowsByStage[key] = rows }

        // Cantidades diarias: una pasada por la tabla. Cada renglón trae su unidad, su forma de
        // resumir el día y a qué campo del cubo va, así que aquí no se repite ninguna de las tres.
        for (position, pull) in Self.dailyQuantityPulls.enumerated() {
            stage(position, pull.stageKey)
            finished(pull.stageKey, rows: await pullDailyQuantity(pull, start: start, end: end) { day, value in
                var bucket = byDay[day] ?? DailyBucket()
                pull.apply(value * pull.scale, &bucket)
                byDay[day] = bucket
            })
        }

        // Minutos de sueño por día (las etapas dormido se suman y se atribuyen al día de despertar).
        stage(quantityStages, "sleep")
        finished("sleep", rows: await pullNightlySleep(start: start, end: end) { night in
            var bucket = byDay[night.day] ?? DailyBucket()
            bucket.asleepMin = night.asleep
            bucket.deepMin = night.deep
            bucket.remMin = night.rem
            bucket.coreMin = night.core
            bucket.inBedMin = night.inBed
            byDay[night.day] = bucket
        })

        // Entrenamientos: se leen directo de HealthKit y se guardan junto a los de la app.
        stage(quantityStages + 1, "workouts")
        let hkWorkouts = await collectHKWorkouts(start: start, end: end)
        finished("workouts", rows: hkWorkouts.count)
        let wkRows = Self.mapWorkouts(hkWorkouts)

        // FER-883: per-workout heart-rate samples (raw only — strain is scored at read time).
        // Skipped in legacyOnly so we never pull Apple HR into the store when the mode excludes Apple;
        // the stage is still published so the progress bar stays 15-step consistent.
        stage(quantityStages + 2, "hr_apple_workouts")
        let workoutHrSamples: [HRSample]
        if repo.dataSourceMode == .legacyOnly {
            workoutHrSamples = []
        } else {
            workoutHrSamples = await collectWorkoutHeartRate(workouts: hkWorkouts)
        }
        finished("hr_apple_workouts", rows: workoutHrSamples.count)

        // FER-486: per-night Apple sleep SESSIONS with a stage timeline (for the Detalle de Sueño
        // hypnogram), ALONGSIDE the daily totals from pullNightlySleep above — F3 is additive. Pure decode
        // (SleepHKDecoder, StrandImport); the idempotent upsert below keeps a re-sync from duplicating.
        let appleSleepSessions = SleepHKDecoder.sessions(from: await collectSleepSamples(start: start, end: end))

        // FER-1006: the daily row's `efficiency` is READ OFF the decoded sessions rather than
        // recomputed from `DailyBucket`'s per-day minute sums. Two computations meant two denominators —
        // the decoder divides by the session span, a minute-sum version divides by summed `inBed`
        // spans — and they diverge whenever a night has more than one in-bed block. Both surface on
        // the SAME screen (the per-night tile reads `CachedSleepSession.efficiency`, the trend reads
        // `DailyMetric.efficiency`), so the user would have seen two different numbers for one night.
        // One source, keyed by the same wake-day attribution `pullNightlySleep` uses.
        // Longest session wins a day that has several (a nap plus the night): the main night is the
        // one whose efficiency the score should reflect, and a 20-minute nap at 96% must not
        // outrank it just by landing first in the array.
        var effByDay: [String: Double] = [:]
        var effSpanByDay: [String: Int] = [:]
        for s in appleSleepSessions {
            guard let eff = s.efficiency else { continue }
            let day = HealthKitBridge.dayString(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            let span = s.endTs - s.startTs
            if span > (effSpanByDay[day] ?? -1) {
                effSpanByDay[day] = span
                effByDay[day] = eff
            }
        }

        // CARGA VIVA: group workout HR by local day + the set of days that had ≥1 HKWorkout,
        // so AppleLoadEstimator can classify rest(0) / load(TRIMP) / missing(NA) before we write
        // DailyMetric.strain. dayString is the canonical write-side day key (DayKey.local).
        var workoutHRByDay: [String: [HRSample]] = [:]
        for s in workoutHrSamples {
            let day = Self.dayString(Date(timeIntervalSince1970: TimeInterval(s.ts)))
            workoutHRByDay[day, default: []].append(s)
        }
        let workoutDays: Set<String> = Set(hkWorkouts.map { Self.dayString($0.startDate) })

        stage(quantityStages + 3, "saving")

        // Filas del almacén bajo la fuente apple-health.
        // `walkingHr` y `weightKg` van en nil a propósito: este camino no los lee.
        let appleRows = byDay.map { day, bucket in
            AppleDaily(day: day,
                       steps: bucket.steps.map { Int($0) },
                       activeKcal: bucket.activeKcal,
                       basalKcal: bucket.basalKcal,
                       vo2max: bucket.vo2max,
                       avgHr: bucket.avgHr.map { Int($0.rounded()) },
                       maxHr: bucket.maxHr.map { Int($0.rounded()) },
                       walkingHr: nil,
                       weightKg: nil)
        }
        // FER-882: Apple's OWN rolling skin-temp baseline over the sync window, then the same final
        // state's deviation applied to every night (one fold over the window, not a per-day
        // incremental). Never mixed with the band's baseline.
        let skinCfg = Baselines.metricCfg["skin_temp"]!   // minVal 20 / maxVal 42 °C absolute
        let skinSeq: [(day: String, value: Double?)] = byDay.keys.sorted().map { (day: $0, value: byDay[$0]?.skinTempC) }
        let appleSkinBase = Baselines.foldHistory(skinSeq, epoch: nil, cfg: skinCfg)
        func appleSkinDev(_ v: Double?) -> Double? {
            guard let v, appleSkinBase.usable else { return nil }
            return (Baselines.deviation(v, state: appleSkinBase).delta * 100.0).rounded() / 100.0
        }
        // Persist DailyMetric.strain only for completed days. Writing today's (partial) strain freezes
        // the "Esfuerzo del día" tile and blocks the live estimatedStrain fallback (AppModel / Repository).
        let todayKey = Self.dayString(Date())
        let dmRows = byDay.map { day, bucket -> DailyMetric in
            let activity = AppleLoadEstimator.DayActivity(
                workoutHR: workoutHRByDay[day] ?? [],
                steps: bucket.steps.map { Int($0) },
                activeKcal: bucket.activeKcal,
                hasWorkout: workoutDays.contains(day))
            let dayLoad = AppleLoadEstimator.classify(activity,
                                                      maxHR: repo.strainHRmax,
                                                      restingHR: bucket.restingHr ?? StrainScorer.defaultRestingHR,
                                                      sex: repo.strainSex)
            var strainValue: Double?
            if AppleLoadEstimator.isCompletedDay(day, today: todayKey) {
                switch dayLoad {
                case .rest:              strainValue = 0
                case .load(let scored):  strainValue = scored
                case .missing:           strainValue = nil
                }
            }
            // `disturbances`, `recovery` y `exerciseCount` quedan en nil: son señales que este
            // camino no observa, y fingirlas con un cero mentiría en la pantalla.
            return DailyMetric(day: day,
                               totalSleepMin: bucket.asleepMin,
                               efficiency: effByDay[day],
                               deepMin: bucket.deepMin,
                               remMin: bucket.remMin,
                               lightMin: bucket.coreMin,
                               disturbances: nil,
                               restingHr: bucket.restingHr.map { Int($0.rounded()) },
                               avgHrv: bucket.hrv,
                               recovery: nil,
                               strain: strainValue,
                               exerciseCount: nil,
                               spo2Pct: bucket.spo2,
                               skinTempDevC: appleSkinDev(bucket.skinTempC),
                               respRateBpm: bucket.respRate,
                               steps: bucket.steps.map { Int($0) })
        }
        // Generic metricSeries points. The per-source pages (Apple Health, Explore, Compare) and the
        // Today sparklines read from metricSeries, which the structured appleDaily/dailyMetric upserts
        // above do NOT populate — only the XML importer did, so a live sync left those screens empty.
        // Mirror the importer's keys (AppleHealthAggregator.metricPoints) so a live sync surfaces the
        // same way as an import; only non-nil values are emitted. (FER-97)
        let seriesRows: [MetricPoint] = byDay.flatMap { (day, a) -> [MetricPoint] in
            var pts: [MetricPoint] = []
            func add(_ key: String, _ value: Double?) { if let v = value { pts.append(MetricPoint(day: day, key: key, value: v)) } }
            add("resting_hr", a.restingHr)
            add("hrv", a.hrv)
            add("spo2", a.spo2)
            add("resp_rate", a.respRate)
            add("avg_hr", a.avgHr)
            add("max_hr", a.maxHr)
            add("steps", a.steps)
            add("active_kcal", a.activeKcal)
            add("basal_kcal", a.basalKcal)
            add("vo2max", a.vo2max)
            add("asleep_min", a.asleepMin)
            // FER-1006: now that `inBed` survives `pullNightlySleep`, emit the series key the XML
            // importer already writes (`AppleHealthAggregator`) so the live-sync path stops being
            // the only one missing it — the gap FER-1002 catalogued for `in_bed_min`.
            add("in_bed_min", a.inBedMin)
            add("deep_min", a.deepMin)
            add("rem_min", a.remMin)
            add("core_min", a.coreMin)
            return pts
        }
        // Las seis escrituras de abajo son UNA sola unidad. Si alguna falla, `lastSync` NO avanza —el
        // siguiente sync delta tiene que volver a intentar esta misma ventana— y el error se muestra en
        // vez de tragárselo con `try?`: un upsert fallido en silencio movía `lastSync` de todos modos,
        // la ventana se saltaba y ese dato se perdía para siempre.
        //
        // FER-872/881: la huella estable de lo que esta corrida dejaría a la vista (todo lo escrito sale
        // de `byDay`, más entrenamientos y sesiones de sueño). Un re-jalón en primer plano con datos
        // idénticos no debe mover `refreshSeq`, que rehace TodayView.loadAll + insights + esfuerzo vivo
        // para nada.
        let signature = Self.stableAppleSignature(byDay: byDay, workouts: wkRows, sleeps: appleSleepSessions)
        let isFullSync = (effectiveDays == days)
        do {
            try await db.upsertAppleDaily(appleRows, deviceId: appleDeviceId)
            try await db.upsertDailyMetrics(dmRows, deviceId: appleDeviceId)
            try await db.upsertMetricSeries(seriesRows, deviceId: appleDeviceId)
            try await db.upsertWorkouts(wkRows, deviceId: appleDeviceId)
            // FER-883: pulso crudo de entrenamiento bajo apple-health — nunca se funde en las
            // baselines; el esfuerzo se puntúa al leer, en `Repository.appleStrainEstimates`. Vacío
            // es un no-op (idempotente).
            if !workoutHrSamples.isEmpty {
                try await db.insert(Streams(hr: workoutHrSamples), deviceId: appleDeviceId)
            }
            try await db.upsertSleepSessions(appleSleepSessions, deviceId: appleDeviceId)   // FER-486 (F3): línea de etapas por noche
            // FER-437: el guardado es la última etapa y no le sigue nada; `syncRowsByStage["saving"]`
            // es como el onboarding distingue «guardado terminó con N filas» de «guardando». No se
            // registra si la escritura lanzó.
            finished("saving", rows: appleRows.count + dmRows.count + seriesRows.count + wkRows.count
                     + workoutHrSamples.count + appleSleepSessions.count)
            // B (FER-1003): el write-back a Apple Health de métricas DERIVADAS del dispositivo anterior
            // (RHR/HRV/SpO2/resp/sueño de esa partición) está APAGADO. Esas filas son viejas y
            // escribirlas contaminaría Salud: metería un RMSSD ajeno bajo el SDNN de Apple. El
            // `HKWorkout` de fuerza (`saveStrengthWorkoutIfEnabled`) es otra cosa y SÍ se conserva.
            // FER-398 borró la función `writeBack`, ya muerta, y con ella el permiso que pedía.
            lastSync = Date()
            lastError = nil
            if trigger == .foreground { didFullForegroundSyncThisSession = true }
            // Only rebuild the dashboard when the Apple rows actually changed. A manual sync always
            // refreshes so the user sees an unmistakable response to tapping "Sync now" (FER-872).
            let changed: Bool
            if trigger != .foreground {
                changed = true
            } else if isFullSync {
                // FER-881: first foreground of the session (full 30d). Compare against the signature
                // persisted from the last session's full sync — equal ⇒ the store already holds this
                // exact Apple data (the launch full-refresh surfaced it) ⇒ skip the redundant cold-start
                // rebuild. This is the second of the two launch refreshes FER-881 removes (the other is
                // analyzeRecent's), taking a recurring Apple-Health user's cold start to ≤2.
                changed = (signature != UserDefaults.standard.string(forKey: Self.lastFullSyncSigKey))
                UserDefaults.standard.set(signature, forKey: Self.lastFullSyncSigKey)
            } else {
                // Subsequent delta foreground within the same session.
                changed = (signature != lastAppleWriteSignature)
            }
            lastAppleWriteSignature = signature
            // R2/D1: ingerir el RMSSD nocturno ANTES del refresh, para que la tendencia lo lea recién
            // escrito. Si se ingiere después (o el refresh se salta por `!changed`), el primer sync computa
            // la tendencia sobre la partición VACÍA → «0 de 21 noches» + un banner falso de «pocas muestras»
            // hasta el siguiente refresh o relaunch. Aditivo, partición propia; se salta en legacyOnly.
            var ingestedNocturnal = false
            if repo.dataSourceMode != .legacyOnly {
                ingestedNocturnal = await ingestNocturnalHRV()
            }
            if changed || ingestedNocturnal {
                await repo.refresh()   // surface the freshly-synced Apple Health days + la tendencia al día
            }
            coverage = try? await db.appleHealthCoverage(deviceId: appleDeviceId)
            return Set(byDay.keys)   // FER-226: los días locales escritos aquí, para la poda del re-bucket
        } catch {
            lastError = "Apple Health sync failed: \(error.localizedDescription)"
            // Nada quedó guardado, así que el re-bucket NO debe podar filas de Apple en esta corrida.
            return []
        }
    }

    // MARK: - Strength session → Apple Health (FER-390)

    /// Write a finished guided strength session into Apple Health as an `HKWorkout`, but only when the
    /// user opted in. Best-effort and **non-throwing**: the session is already persisted in `CenitStore`
    /// (the source of truth), so a Health failure must never throw to the caller or block the session.
    /// Idempotent by external UUID — re-saving the same session replaces its prior workout instead of
    /// duplicating it. The estimated active-energy sample inside `[start, end]` is what lets the iPhone's
    /// **Move ring** credit the session (no Apple Watch needed). Energy is a MET-based estimate
    /// (`Calories.estimateStrengthCalories`, Ainsworth 2011) — the session records no per-second HR.
    func saveStrengthWorkoutIfEnabled(sessionId: String, start: Date, end: Date, profile: UserProfile,
                                      hrSamples: [HRSample] = [], hrMax: Int? = nil) async {
        guard UserDefaults.standard.bool(forKey: Self.saveStrengthWorkoutsKey) else { return }
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }
        // Gate on the workout share grant directly (independent of the read connection): if the user
        // toggled on but the prompt wasn't granted, surface it honestly — never crash, never block.
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            lastError = "No pudimos guardar el entrenamiento en Apple Salud. Revisa los permisos en Ajustes."
            return
        }

        // Keytel si la sesión trajo pulso del dispositivo anterior (FER-399); si no, MET. Camino B: ese
        // pulso solo alimenta la estimación — NO se escribe en Apple Health como muestras de frecuencia.
        let kcal = Calories.estimateStrengthEnergy(hrSamples: hrSamples, durationSeconds: end.timeIntervalSince(start),
                                                   profile: profile, hrMax: hrMax.map(Double.init))
        // FER-398: one source of truth for the key, shared with the watch (`WorkoutMirrorKey`), instead
        // of the literal that used to live here beside it. New writes carry `cenit:strength:<id>`.
        let externalUUID = WorkoutMirrorKey.externalUUID(for: sessionId)
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining

        do {
            // Idempotencia: se borra el entrenamiento previo de ESTA sesión y se escribe uno nuevo.
            // Acotado a las muestras de esta app y al UUID externo de la sesión, en sus DOS
            // escrituras (FER-398): la clave vieja sigue viva en Salud de usuarios antiguos, así que
            // una sesión guardada con ella se REEMPLAZA —no se duplica— al volverse a guardar con el
            // prefijo nuevo. `WorkoutMirrorKey.dedupeUUIDs` es quien conoce ambas cadenas.
            let fromThisApp = HKQuery.predicateForObjects(from: HKSource.default())
            let withSessionKey = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                allowedValues: WorkoutMirrorKey.dedupeUUIDs(for: sessionId))
            let ours = NSCompoundPredicate(andPredicateWithSubpredicates: [fromThisApp, withSessionKey])
            _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: ours)

            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: start)
            if kcal > 0, let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                let energy = HKQuantitySample(type: energyType,
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                              start: start, end: end)
                // `HKWorkoutBuilder.add(_:)` ships completion-only (no async bridge), so wrap it.
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    builder.add([energy]) { _, error in
                        if let error { cont.resume(throwing: error) } else { cont.resume() }
                    }
                }
            }
            try await builder.addMetadata([HKMetadataKeyExternalUUID: externalUUID])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Lo que un día civil acumula mientras corre el sync, antes de convertirse en filas. Un campo
    /// por línea con su unidad: es la única tabla donde se puede comprobar de un vistazo que lo leído
    /// y lo guardado están en la misma escala.
    private struct DailyBucket {
        var restingHr: Double?      // lpm
        var avgHr: Double?          // lpm
        var maxHr: Double?          // lpm
        var hrv: Double?            // SDNN, ms
        var spo2: Double?           // por ciento (0…100)
        var respRate: Double?       // respiraciones por minuto
        var steps: Double?          // conteo
        var activeKcal: Double?     // kcal
        var basalKcal: Double?      // kcal
        var vo2max: Double?         // ml/kg·min
        var asleepMin: Double?      // minutos dormido (suma de etapas)
        var deepMin: Double?        // minutos
        var remMin: Double?         // minutos
        var coreMin: Double?        // minutos
        /// FER-1006: minutos en cama. Vive aquí por la clave de serie `in_bed_min` y por la huella
        /// del sync. NO es una etapa y nunca se suma a `asleepMin`. Tampoco es el denominador de la
        /// eficiencia: esa se lee de las sesiones decodificadas (ver `dmRows`), para que exista un
        /// solo cálculo.
        var inBedMin: Double?
        var skinTempC: Double?      // FER-882: temperatura de muñeca dormido, absoluta en °C
    }

    /// FER-872/881: a STABLE, order-independent fingerprint of the Apple rows a sync run would surface.
    /// `byDay` carries every daily/series/appleDaily value (they're all derived from it); workouts and
    /// sleep sessions fold in by their identifying fields. SHA-256 over a deterministic string (NOT the
    /// per-process `Hasher`, whose seed varies per launch) so it can be PERSISTED across launches and
    /// compared on the next session's first foreground sync (FER-881). Values are formatted at fixed
    /// precision so an exact re-pull hashes identically.
    private static func stableAppleSignature(byDay: [String: DailyBucket],
                                             workouts: [WorkoutRow],
                                             sleeps: [CachedSleepSession]) -> String {
        func f(_ d: Double?) -> String { d.map { String(format: "%.4f", $0) } ?? "-" }
        var s = ""
        for key in byDay.keys.sorted() {
            let a = byDay[key]!
            // FER-1006: `inBedMin` rides in the fingerprint. Without it, a user whose Apple data is
            // otherwise unchanged keeps matching the PREVIOUS signature, the FER-881 gate skips the
            // dashboard rebuild, and the newly-available sleep efficiency never reaches the screen —
            // the feature would ship and silently do nothing until some other value happened to move.
            s += "\(key):\(f(a.restingHr)),\(f(a.avgHr)),\(f(a.maxHr)),\(f(a.hrv)),\(f(a.spo2)),\(f(a.respRate)),\(f(a.steps)),\(f(a.activeKcal)),\(f(a.basalKcal)),\(f(a.vo2max)),\(f(a.asleepMin)),\(f(a.deepMin)),\(f(a.remMin)),\(f(a.coreMin)),\(f(a.inBedMin)),\(f(a.skinTempC));"
        }
        s += "|W:"
        for w in workouts.sorted(by: { ($0.startTs, $0.endTs, $0.sport) < ($1.startTs, $1.endTs, $1.sport) }) {
            s += "\(w.startTs)-\(w.endTs)-\(w.sport)-\(f(w.durationS))-\(f(w.energyKcal));"
        }
        s += "|S:"
        for sl in sleeps.sorted(by: { ($0.startTs, $0.endTs) < ($1.startTs, $1.endTs) }) {
            s += "\(sl.startTs)-\(sl.endTs)-\(f(sl.efficiency))-\(sl.restingHr.map(String.init) ?? "-")-\(f(sl.avgHrv))-\(sl.stagesJSON ?? "-");"
        }
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// FER-1004: the ONLY way this file may build a read predicate. Every HealthKit READ must
    /// exclude this app's own samples, because Cénit writes into Apple Health — today
    /// `saveStrengthWorkoutIfEnabled` saves an `HKWorkout` per strength session, and until FER-398
    /// the retired `writeBack` also mirrored resting HR / HRV / SpO2 / respiratory rate and the
    /// staged hypnogram. Reading with a date-only predicate pulled those straight back in as if
    /// Apple had measured them: a self-feeding loop that polluted the very Apple baselines
    /// `DailyStressModel` z-scores against, and duplicated every
    /// strength session as an "apple-health" workout row (`mapWorkouts` labels unconditionally).
    ///
    /// It is the same contamination class as FER-519/623/629/631/632/633/635/639/640/670/882 —
    /// band numbers reaching an Apple baseline — but through the mirror instead of the merge.
    /// Worse there, because the old mirror wrote the band's RMSSD under Apple's *SDNN*
    /// identifier: the value read back was not just foreign, it was mislabelled. The samples it
    /// left in a long-time user's Health vault are still there, so the exclusion still earns its keep.
    ///
    /// The WRITE path already scopes its deletes to `HKSource.default()`. Reads need the INVERSE of
    /// that same predicate. `HealthKitReadPredicateGuardTests` fails the build if a raw
    /// `predicateForSamples` reappears in this file outside this helper.
    nonisolated static func readPredicate(start: Date, end: Date,
                                          options: HKQueryOptions = []) -> NSPredicate {
        let byDate = HKQuery.predicateForSamples(withStart: start, end: end, options: options)
        let notOurs = NSCompoundPredicate(
            notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        return NSCompoundPredicate(andPredicateWithSubpredicates: [byDate, notOurs])
    }

    /// El resumen que corresponde a una estadística según cómo se pidió agregar el día. Puro y
    /// aparte de la consulta, para que la regla se lea entera en cinco líneas.
    ///
    /// El caso por omisión es el promedio: una opción que no sea suma ni máximo describe una serie
    /// discreta, y el promedio es su resumen honesto.
    private nonisolated static func quantity(from stats: HKStatistics,
                                             for statistic: HKStatisticsOptions) -> HKQuantity? {
        switch statistic {
        case .cumulativeSum:   return stats.sumQuantity()
        case .discreteMax:     return stats.maximumQuantity()
        default:               return stats.averageQuantity()
        }
    }

    /// Corre UN renglón de `dailyQuantityPulls`: una `HKStatisticsCollectionQuery` cubetada en días
    /// civiles locales, anclada al inicio del primer día de la ventana.
    ///
    /// FER-978: el handler de HealthKit corre en la cola de HealthKit, no en este actor. Llamar al
    /// `sink` desde ahí (que toca estado de `@MainActor`) era una carrera de verdad. Por eso el
    /// handler solo junta pares `(día, valor)` —que sí son Sendable—, reanuda con ellos, y el `sink`
    /// se aplica de regreso en el actor principal, después del `await`.
    private func pullDailyQuantity(_ pull: QuantityPull, start: Date, end: Date,
                                   sink: @escaping (String, Double) -> Void) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: pull.identifier) else { return 0 }
        let anchor = Calendar.current.startOfDay(for: start)
        let predicate = Self.readPredicate(start: start, end: end, options: .strictStartDate)
        // Se sacan del renglón ANTES de la consulta: el handler no debe capturar el `QuantityPull`
        // entero, que lleva dentro un cierre atado a este actor.
        let unit = pull.unit
        let statistic = pull.statistic

        let daily: [(day: String, value: Double)] = await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(quantityType: type,
                                                    quantitySamplePredicate: predicate,
                                                    options: statistic,
                                                    anchorDate: anchor,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var collected: [(day: String, value: Double)] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    guard let quantity = HealthKitBridge.quantity(from: stats, for: statistic) else { return }
                    collected.append((day: HealthKitBridge.dayString(stats.startDate),
                                      value: quantity.doubleValue(for: unit)))
                }
                cont.resume(returning: collected)
            }
            store.execute(query)
        }
        for entry in daily { sink(entry.day, entry.value) }
        return daily.count   // FER-437: cuántas filas por día se entregaron
    }

    /// Una muestra de sueño reducida a lo único que el plegado necesita: qué noche, qué app la
    /// escribió, qué etapa y cuántos minutos dura. Cruzar la continuación con esto —y no con
    /// `HKCategorySample`— es lo que permite que el plegado sea puro y viva fuera de la cola de
    /// HealthKit.
    private struct StagedSleepSample: Sendable {
        let day: String
        let source: String
        let stage: Int
        let minutes: Double
    }

    /// Una noche ya resuelta: los minutos de la fuente ganadora, atribuidos a su día de despertar.
    private struct NightlySleep: Sendable {
        let day: String
        let asleep: Double?
        let deep: Double?
        let rem: Double?
        let core: Double?
        let inBed: Double?
    }

    /// De muestras sueltas a noches. Función pura, sin HealthKit y sin actor: toda la regla de
    /// negocio del sueño diario cabe aquí y se puede razonar leyéndola sola.
    ///
    /// **Una sola fuente por noche** (H1, auditoría de estrés). Antes se sumaban las etapas de TODAS
    /// las fuentes de Salud; con Apple Watch más otra app de sueño (o el Sleep Schedule del iPhone)
    /// la misma noche, el total y el profundo/REM se DOBLE-CONTABAN y la eficiencia se iba a un falso
    /// 100 %. Ahora las etapas se agrupan por (noche, fuente) y por noche gana una sola
    /// —`SleepSourceSelection`: primero Apple/Watch, luego la de más minutos—; las demás se
    /// descartan. Sumar entre fuentes no tendría ni sentido físico: ¿de qué etapa sería ese minuto?
    ///
    /// **`inBed` va por el máximo, no por la suma** (FER-1006, D2 del gate de /qa). Es el envolvente
    /// de la eficiencia; ahora que `asleep` viene de una sola fuente, sumar el `inBed` de dos
    /// fuentes traslaparía el denominador y subestimaría la eficiencia. El máximo es el envolvente
    /// más grande sin doble-contar — y como el Apple Watch no escribe `inBed`, casi siempre sale del
    /// iPhone. Dentro de UNA fuente sus bloques sí se suman: ese es su propio envolvente.
    private nonisolated static func foldNightlySleep(_ samples: [StagedSleepSample]) -> [NightlySleep] {
        struct StageMinutes {
            var asleep = 0.0
            var deep = 0.0
            var rem = 0.0
            var core = 0.0
        }
        var stagesByNight: [String: [String: StageMinutes]] = [:]
        var inBedByNight: [String: [String: Double]] = [:]

        for sample in samples {
            if sample.stage == HKCategoryValueSleepAnalysis.inBed.rawValue {
                inBedByNight[sample.day, default: [:]][sample.source, default: 0] += sample.minutes
                continue
            }
            var minutes = stagesByNight[sample.day]?[sample.source] ?? StageMinutes()
            switch sample.stage {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                minutes.deep += sample.minutes
                minutes.asleep += sample.minutes
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                minutes.rem += sample.minutes
                minutes.asleep += sample.minutes
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                minutes.core += sample.minutes
                minutes.asleep += sample.minutes
            default:
                break   // despierto, o un valor que Apple agregue después: no suma minutos…
            }
            // …pero la fuente SÍ queda registrada aunque solo haya escrito «despierto». Es la
            // conducta previa y `SleepSourceSelection` cuenta con verla entre las candidatas.
            stagesByNight[sample.day, default: [:]][sample.source] = minutes
        }

        var nights: [NightlySleep] = []
        for (day, bySource) in stagesByNight {
            guard let winner = SleepSourceSelection.pick(asleepMinutesBySource: bySource.mapValues(\.asleep)),
                  let minutes = bySource[winner], minutes.asleep > 0 else { continue }
            nights.append(NightlySleep(day: day,
                                       asleep: minutes.asleep,
                                       deep: minutes.deep > 0 ? minutes.deep : nil,
                                       rem: minutes.rem > 0 ? minutes.rem : nil,
                                       core: minutes.core > 0 ? minutes.core : nil,
                                       inBed: inBedByNight[day]?.values.max()))
        }
        return nights
    }

    /// Trae el sueño de la ventana y lo entrega ya plegado, una noche a la vez.
    ///
    /// La consulta es la cáscara delgada; la regla vive en `foldNightlySleep`. La muestra se atribuye
    /// al día en que TERMINA, así una noche que cruza la medianoche cuenta para el día en que la
    /// persona despertó. FER-978: el plegado corre de regreso en este actor, nunca en la cola de
    /// HealthKit.
    private func pullNightlySleep(start: Date, end: Date,
                                  sink: @escaping (NightlySleep) -> Void) async -> Int {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let predicate = Self.readPredicate(start: start, end: end)

        let staged: [StagedSleepSample] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let staged = (samples ?? []).compactMap { sample -> StagedSleepSample? in
                    guard let category = sample as? HKCategorySample else { return nil }
                    return StagedSleepSample(
                        day: HealthKitBridge.dayString(category.endDate),
                        source: category.sourceRevision.source.bundleIdentifier,
                        stage: category.value,
                        minutes: category.endDate.timeIntervalSince(category.startDate) / 60)
                }
                cont.resume(returning: staged)
            }
            store.execute(query)
        }
        let nights = Self.foldNightlySleep(staged)
        for night in nights { sink(night) }
        return nights.count   // FER-437: cuántas noches se entregaron, para `syncRowsByStage`
    }

    /// FER-486: las mismas muestras de `sleepAnalysis`, pero como descriptores sin HealthKit, para
    /// que el decodificador puro `SleepHKDecoder` (StrandImport) las agrupe en un
    /// `CachedSleepSession` por noche con su línea de etapas — el hipnograma del Detalle de Sueño.
    /// Corre JUNTO a `pullNightlySleep`, que sigue produciendo los totales diarios: F3 es aditivo.
    /// Aquí no se agrupa ni se mapea nada de negocio; esta función es solo la cáscara de la consulta.
    private func collectSleepSamples(start: Date, end: Date) async -> [SleepHKSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = Self.readPredicate(start: start, end: end)
        return await withCheckedContinuation { (cont: CheckedContinuation<[SleepHKSample], Never>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let descriptors: [SleepHKSample] = (samples ?? []).compactMap { sample in
                    guard let category = sample as? HKCategorySample else { return nil }
                    return SleepHKSample(hkValue: category.value,
                                         start: category.startDate,
                                         end: category.endDate,
                                         dedupeKey: "")
                }
                cont.resume(returning: descriptors)
            }
            store.execute(query)
        }
    }

    // MARK: - Nocturnal HRV ingestion (R2, FER-1008)

    /// Convierte la serie de latidos nocturnos de Apple en un RMSSD por noche (R2): trae los intervalos
    /// beat-to-beat en una ventana incremental, recorta cada noche a la UNIÓN de sus tramos dormido (la
    /// misma atribución de día de despertar que usa `pullNightlySleep`), y corre el motor puro
    /// `NocturnalHRV.night` (StrandAnalytics) sobre los latidos ya recortados. Persiste en su PROPIA
    /// partición vía `metricSeries` — aditivo, nunca toca `byDay`/`DailyMetric`/el camino del
    /// dispositivo anterior. No-op silencioso (0 filas, sin crash) si falta el permiso de la serie de
    /// latidos o si Apple simplemente no tiene datos beat-to-beat en la ventana.
    /// Devuelve `true` si escribió alguna fila (para que el caller refresque la tendencia). `false` si no
    /// hubo permiso/datos/noches — el caller entonces no necesita re-refrescar por esto.
    @discardableResult
    private func ingestNocturnalHRV() async -> Bool {
        // A) Re-auth una sola vez: una conexión de Apple Health ya existente NO re-prompea solo porque
        // `readTypes` ganó un tipo nuevo (HealthKit solo re-prompea por scopes que nunca vio), así que
        // usuarios conectados antes de este cambio necesitan un request explícito, una sola vez.
        let requestedKey = "appleHeartbeatSeriesRequested"
        if !UserDefaults.standard.bool(forKey: requestedKey) {
            var scopes: Set<HKObjectType> = [HKSeriesType.heartbeat()]
            if let sdnn = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { scopes.insert(sdnn) }
            try? await store.requestAuthorization(toShare: [], read: scopes)
            UserDefaults.standard.set(true, forKey: requestedKey)
        }

        // B) Piso incremental sobre la partición propia: today-45d, o (última noche escrita - 2 días),
        // lo que sea MÁS TARDE — el margen de 2 días re-cubre una noche que Apple terminó de escribir
        // tarde, sin reprocesar los 45 días completos en cada sync.
        guard let dbStore = await repo.storeHandle() else { return false }
        // Dato en disco: es el id de partición con el que ya se escribieron las filas de usuarios
        // existentes. Cambiar la cadena dejaría esas noches huérfanas.
        let deviceId = "apple-health-noop"
        let today = Date()
        let calendar = Calendar.current
        guard let floor45 = calendar.date(byAdding: .day, value: -45, to: calendar.startOfDay(for: today)) else {
            return false
        }
        var windowStartDate = floor45
        let latestDay = try? await dbStore.metricDays(deviceId: deviceId, key: "apple_rr_clean_night")?.latest
        if let latestDay, let latestDate = HealthKitBridge.date(from: latestDay) {
            let minus2 = calendar.date(byAdding: .day, value: -2, to: latestDate) ?? latestDate
            windowStartDate = max(floor45, minus2)
        }
        let predicate = Self.readPredicate(start: windowStartDate, end: today)

        // C) Serie de latidos en la ventana — misma forma de query que `exportAppleHeartbeatSeries`.
        let seriesType = HKSeriesType.heartbeat()
        let samples: [HKHeartbeatSeriesSample] = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: seriesType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s as? [HKHeartbeatSeriesSample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return false }   // sin permiso o sin datos → 0 filas, sin crash

        // D) Latidos → [TimedNN]. Sin gate de rango aquí — NocturnalHRV/HRVAnalyzer lo aplican después.
        var beats: [TimedNN] = []
        for sample in samples {
            for row in await beatToBeat(of: sample) { beats.append(TimedNN(ts: row.ts, nnMs: row.rrMs)) }
        }

        // E) Ventana por noche = UNIÓN de los tramos realmente dormido de esa noche (misma atribución de
        // día de despertar que pullNightlySleep). Solo etapas de sueño real — inBed/awake quedan fuera.
        let sleepSamples = await collectSleepSamples(start: windowStartDate, end: today)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        // D2: agrupar los tramos asleep en SESIONES (corte por hueco ≥ 1 h) y atribuir CADA sesión a su
        // wake-day (el día en que TERMINA), no por-muestra. Así una noche que cruza medianoche queda como
        // UNA noche en un solo día civil, en vez de partirse en dos (que double-contaría a un madrugador o
        // perdería la noche si ninguna mitad llega al gate de densidad). Es el wake-day que pide el paquete
        // («dayKey = localDayKey(session.end); unir TODO asleep del wake-day»), no el sample.end.
        let asleep = sleepSamples
            .filter { asleepValues.contains($0.hkValue) }
            .map { (start: $0.start.timeIntervalSince1970, end: $0.end.timeIntervalSince1970) }
            .sorted { $0.start < $1.start }
        var intervalsByDay: [String: [(start: Double, end: Double)]] = [:]
        var session: [(start: Double, end: Double)] = []
        var sessionMaxEnd = 0.0
        func flushSession() {
            guard !session.isEmpty else { return }
            let day = HealthKitBridge.dayString(Date(timeIntervalSince1970: sessionMaxEnd))
            intervalsByDay[day, default: []].append(contentsOf: session)
            session = []; sessionMaxEnd = 0.0
        }
        for iv in asleep {
            if !session.isEmpty, iv.start - sessionMaxEnd >= 3600 { flushSession() }   // hueco ≥ 1 h → nueva sesión
            session.append(iv); sessionMaxEnd = max(sessionMaxEnd, iv.end)
        }
        flushSession()
        func merged(_ xs: [(start: Double, end: Double)]) -> [(start: Double, end: Double)] {
            let sorted = xs.sorted { $0.start < $1.start }
            var out: [(start: Double, end: Double)] = []
            for iv in sorted {
                if var last = out.last, iv.start <= last.end {
                    last.end = max(last.end, iv.end)
                    out[out.count - 1] = last
                } else {
                    out.append(iv)
                }
            }
            return out
        }

        // F) Por noche: recorta los latidos a la unión, corre el motor, arma las filas.
        var rows: [MetricPoint] = []
        for (day, rawIvs) in intervalsByDay {
            let ivs = merged(rawIvs)
            let nightBeats = beats.filter { b in ivs.contains { $0.start <= b.ts && b.ts <= $0.end } }
            let result = NocturnalHRV.night(intervals: nightBeats, windowStart: nil, windowEnd: nil)
            if let rmssd = result.rmssdMs {
                rows.append(MetricPoint(day: day, key: "apple_rmssd_night", value: rmssd))   // solo si densa
            }
            rows.append(MetricPoint(day: day, key: "apple_rr_clean_night", value: Double(result.nClean)))
            rows.append(MetricPoint(day: day, key: "apple_rr_pairs_night", value: Double(result.nPairs)))
        }
        guard !rows.isEmpty else { return false }
        _ = try? await dbStore.upsertMetricSeries(rows, deviceId: deviceId)
        return true
    }

    #if DEBUG
    // MARK: - DEV · Apple heartbeat-series export (FER-1008 spike)

    /// One-shot, on-device validation dump: the beat-to-beat (R-R) intervals Apple stored in HealthKit as
    /// `HKHeartbeatSeriesSample`s over the last `daysBack` days, as CSV rows `ts,rrMs` (epoch seconds,
    /// milliseconds) — la MISMA forma que la tabla `rrInterval` heredada — so a nocturnal Apple RMSSD can be
    /// measured against the band's on paired nights. Opt-in: requests its own `HKSeriesType.heartbeat()`
    /// read scope on demand and touches neither the store nor the normal sync. Returns the CSV plus a
    /// per-night density summary — the whole open question is whether Apple samples densely enough at night.
    func exportAppleHeartbeatSeries(daysBack: Int = 45) async -> (csv: String, summary: String) {
        guard HKHealthStore.isHealthDataAvailable() else { return ("", "Apple Health no disponible.") }
        let seriesType = HKSeriesType.heartbeat()
        // Dedicated read consent, asked only when this dev button is tapped (keeps the normal connect
        // prompt unchanged — heartbeat is never added to the shipped `readTypes`). HealthKit REQUIRES
        // `heartRateVariabilitySDNN` to be requested ALONGSIDE `HeartbeatSeries` (beat-to-beat can derive
        // HRV): asking for the series alone throws an NSInvalidArgumentException synchronously at the call
        // site — an ObjC exception `try?` can't catch, so it crashed the app. Request both together.
        var readScopes: Set<HKObjectType> = [seriesType]
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { readScopes.insert(hrv) }
        try? await store.requestAuthorization(toShare: [], read: readScopes)

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end)
            ?? end.addingTimeInterval(-Double(daysBack) * 86_400)
        let predicate = Self.readPredicate(start: start, end: end)

        // 1) The heartbeat-series samples in the window (each is a run of beats, e.g. one sleep segment).
        let samples: [HKHeartbeatSeriesSample] = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: seriesType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s as? [HKHeartbeatSeriesSample]) ?? [])
            }
            store.execute(q)
        }

        // 2) Stream each series into R-R intervals (skip gap-preceded beats + non-physiological values).
        var rows: [(ts: Double, rrMs: Double)] = []
        for sample in samples { rows.append(contentsOf: await beatToBeat(of: sample)) }
        rows.sort { $0.ts < $1.ts }

        // 3) CSV (ts,rrMs) — las mismas columnas que la tabla `rrInterval` heredada, para que el análisis corra igual.
        var csv = "ts,rrMs\n"
        csv.reserveCapacity(rows.count * 14 + 8)
        for r in rows { csv += "\(Int(r.ts.rounded())),\(Int(r.rrMs.rounded()))\n" }

        // 4) Per-night density summary (local civil day) so the answer is visible immediately.
        var perNight: [String: Int] = [:]
        for r in rows { perNight[Self.dayString(Date(timeIntervalSince1970: r.ts)), default: 0] += 1 }
        let nights = perNight.keys.sorted()
        let usable = perNight.values.filter { $0 >= 500 }.count
        let median = perNight.isEmpty ? 0 : perNight.values.sorted()[perNight.count / 2]
        var summary = "Series: \(samples.count) · intervalos R-R: \(rows.count)\n"
        summary += "Noches con datos: \(nights.count) · con ≥500 intervalos: \(usable) · mediana \(median)/noche\n"
        if let lo = nights.first, let hi = nights.last { summary += "Rango: \(lo) → \(hi)" }
        if rows.isEmpty { summary += "\nApple no guardó latido-a-latido en esta ventana (o falta el permiso)." }
        return (csv, summary)
    }
    #endif

    /// Stream one `HKHeartbeatSeriesSample` into absolute-timestamped R-R intervals (ms). A beat flagged
    /// `precededByGap` breaks the chain (its interval spans missing data). Emits every remaining interval
    /// UNFILTERED by range — `NocturnalHRV`/`HRVAnalyzer` apply the [300, 2000] ms gate downstream, at the
    /// mismo punto que limpia los intervalos RR heredados. Compiles in release: `ingestNocturnalHRV` (R2)
    /// calls this outside of any dev-only path.
    private func beatToBeat(of sample: HKHeartbeatSeriesSample) async -> [(ts: Double, rrMs: Double)] {
        let base = sample.startDate.timeIntervalSince1970
        return await withCheckedContinuation { (cont: CheckedContinuation<[(ts: Double, rrMs: Double)], Never>) in
            var out: [(ts: Double, rrMs: Double)] = []
            var prev: Double? = nil
            let q = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, timeSinceStart, precededByGap, done, error in
                if error == nil {
                    if let p = prev, !precededByGap {
                        let rr = (timeSinceStart - p) * 1000.0
                        out.append((ts: base + timeSinceStart, rrMs: rr))   // sin gate de rango; el motor lo hace
                    }
                    prev = timeSinceStart
                }
                if done { cont.resume(returning: out) }
            }
            store.execute(q)
        }
    }

    // MARK: - Workout helpers

    /// Raw `HKWorkout`s in [start, end] — shared by `mapWorkouts` and `collectWorkoutHeartRate`
    /// so we don't re-query HealthKit for the same window. (FER-883)
    private func collectHKWorkouts(start: Date, end: Date) async -> [HKWorkout] {
        // FER-1004: excludes our own `HKWorkout`s. `saveStrengthWorkout` mirrors every strength
        // session here, and `mapWorkouts` labels whatever comes back `source: "apple-health"`
        // unconditionally — so a date-only read re-imported each session as a second, Apple-branded
        // copy of a workout StrandTraining already owns.
        let predicate = Self.readPredicate(start: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (cont: CheckedContinuation<[HKWorkout], Never>) in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    /// Map raw `HKWorkout`s to store rows (same shape as pre-FER-883 `collectWorkouts`). FER-362 · C4:
    /// `source` now carries the writing app's real name — `"apple-health:" + sourceRevision.source.name`,
    /// or bare `"apple-health"` when HealthKit reports no name — for EVERY Apple workout, not just
    /// strength (a run synced from Strava gets its real name too). This rides the existing `source`
    /// column; no migration, since `upsertWorkouts`' natural key is `(deviceId, startTs, sport)` and
    /// `source = excluded.source` updates in place. `WorkoutSource.classify`/`appleAppName` read it.
    private nonisolated static func mapWorkouts(_ workouts: [HKWorkout]) -> [WorkoutRow] {
        workouts.map { w in
            let name = w.sourceRevision.source.name
            let source = name.isEmpty ? "apple-health" : "apple-health:" + name
            return WorkoutRow(
                startTs: Int(w.startDate.timeIntervalSince1970),
                endTs:   Int(w.endDate.timeIntervalSince1970),
                sport:   Self.activityTypeName(w.workoutActivityType),
                source:  source,
                durationS:  w.duration > 0 ? w.duration : nil,
                energyKcal: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                avgHr: nil, maxHr: nil, strain: nil,
                distanceM: w.totalDistance?.doubleValue(for: .meter()),
                zonesJSON: nil, notes: nil
            )
        }
    }

    /// Heart-rate samples belonging to each workout, merged + sorted + deduped by `ts`.
    /// Scopes via `HKQuery.predicateForObjects(from:)` only — that already limits to the workout.
    /// Raw HR only; strain is scored at read time. (FER-883)
    private func collectWorkoutHeartRate(workouts: [HKWorkout]) async -> [HRSample] {
        guard !workouts.isEmpty,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        var all: [HRSample] = []
        all.reserveCapacity(workouts.count * 600)
        for w in workouts {
            let samples = await withCheckedContinuation { (cont: CheckedContinuation<[HRSample], Never>) in
                let predicate = HKQuery.predicateForObjects(from: w)
                let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, raw, _ in
                    let unitLocal = unit
                    let out: [HRSample] = (raw as? [HKQuantitySample] ?? []).map { s in
                        HRSample(ts: Int(s.startDate.timeIntervalSince1970),
                                 bpm: Int(s.quantity.doubleValue(for: unitLocal).rounded()))
                    }
                    cont.resume(returning: out)
                }
                store.execute(q)
            }
            all.append(contentsOf: samples)
        }
        // Sort ascending by ts, then keep first occurrence of each ts (overlapping workouts).
        all.sort { $0.ts < $1.ts }
        var seen = Set<Int>()
        seen.reserveCapacity(all.count)
        return all.filter { seen.insert($0.ts).inserted }
    }

    /// Convert an HKWorkoutActivityType to the camelCase string that matches what the XML export
    /// importer stores (e.g. "TraditionalStrengthTraining"). displaySport() then inserts spaces.
    nonisolated static func activityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .americanFootball:             return "AmericanFootball"
        case .archery:                      return "Archery"
        case .australianFootball:           return "AustralianFootball"
        case .badminton:                    return "Badminton"
        case .baseball:                     return "Baseball"
        case .basketball:                   return "Basketball"
        case .bowling:                      return "Bowling"
        case .boxing:                       return "Boxing"
        case .climbing:                     return "Climbing"
        case .crossTraining:                return "CrossTraining"
        case .curling:                      return "Curling"
        case .cycling:                      return "Cycling"
        case .dance:                        return "Dance"
        case .elliptical:                   return "Elliptical"
        case .equestrianSports:             return "EquestrianSports"
        case .fencing:                      return "Fencing"
        case .fishing:                      return "Fishing"
        case .functionalStrengthTraining:   return "FunctionalStrengthTraining"
        case .golf:                         return "Golf"
        case .gymnastics:                   return "Gymnastics"
        case .handball:                     return "Handball"
        case .hiking:                       return "Hiking"
        case .hockey:                       return "Hockey"
        case .lacrosse:                     return "Lacrosse"
        case .martialArts:                  return "MartialArts"
        case .mindAndBody:                  return "MindAndBody"
        case .paddleSports:                 return "PaddleSports"
        case .play:                         return "Play"
        case .preparationAndRecovery:       return "PreparationAndRecovery"
        case .racquetball:                  return "Racquetball"
        case .rowing:                       return "Rowing"
        case .rugby:                        return "Rugby"
        case .running:                      return "Running"
        case .sailing:                      return "Sailing"
        case .skatingSports:                return "SkatingSports"
        case .snowSports:                   return "SnowSports"
        case .soccer:                       return "Soccer"
        case .softball:                     return "Softball"
        case .squash:                       return "Squash"
        case .stairClimbing:                return "StairClimbing"
        case .surfingSports:                return "SurfingSports"
        case .swimming:                     return "Swimming"
        case .tableTennis:                  return "TableTennis"
        case .tennis:                       return "Tennis"
        case .trackAndField:                return "TrackAndField"
        case .traditionalStrengthTraining:  return "TraditionalStrengthTraining"
        case .volleyball:                   return "Volleyball"
        case .walking:                      return "Walking"
        case .waterFitness:                 return "WaterFitness"
        case .waterPolo:                    return "WaterPolo"
        case .waterSports:                  return "WaterSports"
        case .wrestling:                    return "Wrestling"
        case .yoga:                         return "Yoga"
        case .barre:                        return "Barre"
        case .coreTraining:                 return "CoreTraining"
        case .crossCountrySkiing:           return "CrossCountrySkiing"
        case .downhillSkiing:               return "DownhillSkiing"
        case .flexibility:                  return "Flexibility"
        case .highIntensityIntervalTraining: return "HighIntensityIntervalTraining"
        case .jumpRope:                     return "JumpRope"
        case .kickboxing:                   return "Kickboxing"
        case .pilates:                      return "Pilates"
        case .snowboarding:                 return "Snowboarding"
        case .stairs:                       return "Stairs"
        case .stepTraining:                 return "StepTraining"
        case .taiChi:                       return "TaiChi"
        case .mixedCardio:                  return "MixedCardio"
        case .handCycling:                  return "HandCycling"
        case .discSports:                   return "DiscSports"
        case .fitnessGaming:                return "FitnessGaming"
        case .cardioDance:                  return "CardioDance"
        case .socialDance:                  return "SocialDance"
        case .pickleball:                   return "Pickleball"
        case .cooldown:                     return "Cooldown"
        case .swimBikeRun:                  return "SwimBikeRun"
        case .transition:                   return "Transition"
        case .underwaterDiving:             return "UnderwaterDiving"
        default:                            return "Other"
        }
    }

    // MARK: - La clave del día

    // Día civil LOCAL (FER-226). Toda fuente llavea `dailyMetric.day` por el día civil del
    // dispositivo —la misma convención de `Repository.localDayKey`—, así lo de la tarde cuenta para
    // el día correcto en una zona UTC− en vez de rodar al siguiente. Esto REVIERTE la elección de
    // UTC de FER-32: el duplicado entre zonas que aquella cuidaba lo resuelve ahora el
    // último-en-escribir-gana sobre la llave (deviceId, day), más la poda de filas futuras del
    // re-bucket. En un día de viaje queda a lo más una costura definida, nunca duplicados callados.
    //
    // Son `nonisolated` para poder correr en la cola de callbacks de HealthKit sin saltar al actor
    // principal (la clase entera es `@MainActor`); el formateador es una constante inmutable y
    // Sendable, segura de leer desde cualquier contexto. Local a propósito: las fechas de las
    // muestras de HealthKit son conceptos de día civil. Este es el formateador canónico del lado de
    // ESCRITURA, el mismo con el que se acuñan las claves de `DailyMetric.day` (FER-754).
    nonisolated private static let dayFormatter = DayKey.localFormatter
    nonisolated private static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    nonisolated private static func date(from day: String) -> Date? { dayFormatter.date(from: day) }
}
#endif
