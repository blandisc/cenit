import Foundation
import Combine
import CenitStore
import BiometricStreams
import CenitAnalytics

/// Las cifras de sueño por día que la exportación heredada traía ya calculadas: filas de
/// `metricSeries` que escribió el importador de CSV ya retirado, bajo el identificador de la fuente
/// importada.
///
/// El Detalle de Sueño las prefiere sobre sus propios recálculos, porque estos son APROXIMADOS: una
/// cifra que el aparato original publicó vale más que una que nosotros estimamos después.
struct ImportedSleepFigures: Equatable {
    /// Llave de serie `"sleep_performance"`, de 0 a 100.
    var performancePct: Double?
    /// Llave de serie `"sleep_consistency"`, de 0 a 100.
    var consistencyPct: Double?
    /// Llave de serie `"sleep_need_min"`, en minutos.
    var needMin: Double?
    /// Llave de serie `"sleep_debt_min"`, en minutos.
    var debtMin: Double?
}

/// Read model over the on-device CenitStore. Opens its own handle (WAL + busy-timeout makes the
/// single-writer pattern safe: HealthKitBridge/imports write via repo.storeHandle()) and publishes the dashboard caches the screens bind to.
@MainActor
final class Repository: ObservableObject {
    let deviceId: String
    /// The data-source mode (FER-484): which sources feed the dashboard + baseline. Set by `AppModel`
    /// from `SourceModeStore`. `combined` (the default) reads every source exactly as before; capture is
    /// untouched — this only filters reads.
    var dataSourceMode: DataSourceMode = .appleHealthOnly
    /// The baseline cut day-key («Recalibrar recuperación», FER-677): "YYYY-MM-DD" or nil for no cut.
    /// Set by `AppModel` from `ProfileStore.baselineEpochOrNil`. The estimated-recovery path honors it
    /// so the Apple estimate re-anchors at the baseline cut.
    var baselineEpoch: String? = nil
    /// FER-883: the user's effective HRmax + sex for the estimated «Carga del día», set by `AppModel`
    /// from `Profile` (`hrMaxOverride ?? Tanaka(age)`) so the Apple workout-HR estimate uses the SAME
    /// HRmax as the legacy live-strain path used — no discontinuity against Apple. nil ⇒ StrainScorer default.
    var strainHRmax: Double? = nil
    var strainSex: String = "male"
    /// Identificador de fuente para las cifras que el propio aparato calculó a partir de las series
    /// crudas del dispositivo heredado (recuperación, esfuerzo, sueño), con el análisis ya retirado.
    ///
    /// Al leer, estas filas se funden DEBAJO de las importadas: una importación de verdad siempre
    /// gana, y aun así quien nunca importó nada ve un tablero con datos.
    ///
    /// El sufijo es un valor persistido: así están marcadas las filas que ya viven en el teléfono.
    /// Dato en disco: el sufijo con el que se escribió la partición computada on-device (neutro desde
    /// FER-479; la migración `v44` reescribió `strap-noop`→`primary-computed`).
    private static let computedSuffix = "-computed"
    private var computedDeviceId: String { deviceId + Self.computedSuffix }
    /// The Apple-derived nocturnal-HRV partition (R2/R3, FER-1008): a SEPARATE metricSeries deviceId from
    /// the legacy `computedDeviceId` and from raw `apple-health`, so the Apple RMSSD-per-night base is
    /// never mixed with the band's or with SDNN. Fixed string (not derived from `deviceId`).
    static let appleComputedDeviceId = "apple-health-computed"
    private var store: CenitStore?
    /// In-flight store creation, memoized so concurrent first-callers (the launch refresh and
    /// TodayView's parallel queries) share ONE open+migrate instead of racing `ensureStore`'s
    /// await window and opening the DB several times. @MainActor makes the set-before-await safe.
    private var storeInit: Task<CenitStore?, Never>?

    /// The whole dashboard, republished as ONE value. Previously `days`/`sleeps`/`importedSleep`/
    /// `loaded`/`refreshSeq` were five separate `@Published`s, so a single `refresh()` fired up to
    /// four `objectWillChange`s — and every one of the ~22 views observing the Repository re-evaluated
    /// its body that many times per refresh. Folding them into one published value means a refresh is
    /// a single publish, hence a single re-render pass (FER-30). The per-field reads below forward to
    /// it, so every existing `repo.days` / `repo.sleeps` / … call site is unchanged.
    struct DashboardData {
        var days: [DailyMetric] = []
        /// Display-only twin of `days`: legacy-covered days whose measured fields are nil back-fill from
        /// the Apple Health row the merge overwrote (FER-149). The dashboard sparklines/trends read
        /// these so a partial-connection day shows Apple's HRV instead of a gap; the recovery baseline
        /// reads `days` (excluding `appleHealthDays`, FER-519), not `displayDays`.
        var displayDays: [DailyMetric] = []
        var sleeps: [CachedSleepSession] = []
        var appleSleeps: [CachedSleepSession] = []   // FER-486: Apple Health sleep sessions with a real stage timeline (band-uncovered nights), for the Detalle de Sueño hypnogram
        var importedSleep: [String: ImportedSleepFigures] = [:]
        /// Days whose surfaced daily row came from Apple Health (no legacy coverage), so Trends/Sleep
        /// can badge the source without `DailyMetric` carrying a source column. (FER-62)
        var appleHealthDays: Set<String> = []
        /// Days with a stored row per source, UNFILTERED by the data-source mode (FER-485): the diagnostic
        /// coverage reads these so it shows what's stored even in `.legacyOnly`/`appleHealthOnly` — the proof
        /// of the «nothing is deleted» invariant. `storedAppleOnlyDays` excludes legacy days, mirroring the
        /// merge precedence, so these are the always-Combined coverage counts.
        var storedStrapDays: Set<String> = []
        var storedAppleOnlyDays: Set<String> = []
        /// Count of stored legacy sleep sessions, UNFILTERED by the mode (FER-485) — the import block's
        /// «… sleeps stored» line reads this so it stays honest in «Solo Apple Salud».
        var storedSleepsCount: Int = 0
        /// FER-883: Apple workout-HR strain estimate per band-less day, keyed by day.
        /// Surfaced ONLY via `repo.today`/`estimatedStrain`, never folded into
        /// `days`/`displayDays` or any baseline.
        var strainEstimates: [String: Double] = [:]
        /// Ola 1 · E2: the closed days whose strain an ESTIMATED strength session (minutes × effort)
        /// contributed to, so Tendencias can label them «estimada». Never persisted.
        var strengthEstimatedDays: Set<String> = []
        var loaded = false
        /// True once a FULL refresh pass (whole stored history) has published. The launch first-paint
        /// pass (~90 days) publishes `loaded == true` with this still false. RULE: anything that
        /// PERSISTS a value derived from `days` — the engine's baselines (`analyzeRecent`), the
        /// experiment verdict (`closeDueExperiment`), the restore offer — must gate on this flag;
        /// pure display readers may see the short window transiently and self-correct on the full
        /// publish. Monotonic within a session: nothing resets it to false.
        var fullyLoaded = false
        var seq = 0
    }
    @Published private(set) var dashboard = DashboardData()

    /// Daily metrics (recovery/strain/sleep/HRV/RHR…), oldest→newest. Includes Apple-only rows (band-less
    /// nights surfaced from Apple Health). The recovery baseline reads this but EXCLUDES `appleHealthDays`
    /// before folding (FER-519, via `SourceLens.clearBandColumns`), so Apple's SDNN never enters
    /// the band's RMSSD baseline; only the capped `foldApplePrior` seeds resp (breaths/min during sleep —
    /// same metric; RHR is band sleep-nadir vs Apple awake, so it's no longer seeded either, FER-634).
    var days: [DailyMetric] { dashboard.days }
    /// Display-only daily rows: `days`, but legacy-covered days with nil measured fields back-fill from
    /// Apple Health (FER-149). The dashboard sparklines/trends read these; analytics read `days`.
    var displayDays: [DailyMetric] { dashboard.displayDays }
    /// Cached sleep sessions, oldest→newest.
    var sleeps: [CachedSleepSession] { dashboard.sleeps }
    /// Apple Health sleep sessions carrying a real per-epoch stage timeline (FER-486), for nights the
    /// band didn't cover — the Detalle de Sueño draws a full hypnogram from these.
    var appleSleeps: [CachedSleepSession] { dashboard.appleSleeps }
    /// Las cifras de sueño que llegaron ya hechas en una exportación, por día. Vacío mientras no
    /// aterrice una importación.
    var importedSleep: [String: ImportedSleepFigures] { dashboard.importedSleep }
    var loaded: Bool { dashboard.loaded }
    /// True once the FULL history is published (see `DashboardData.fullyLoaded` for the rule).
    var fullyLoaded: Bool { dashboard.fullyLoaded }
    /// Contador que solo sube, una vez por cada `refresh()` que sale bien.
    ///
    /// Las pantallas que se actualizan varias veces al día cuelgan de aquí su recarga: si colgaran de
    /// `today?.day`, esa cadena no cambia en toda la jornada y la vista se quedaría congelada —el
    /// pulso de Hoy, por ejemplo— hasta que cambiara la fecha.
    var refreshSeq: Int { dashboard.seq }
    /// Days surfaced from Apple Health (legacy-uncovered) — Trends/Sleep badge these as "Apple Health". (FER-62)
    var appleHealthDays: Set<String> { dashboard.appleHealthDays }
    /// Stored per-source day coverage, UNFILTERED by the mode — the diagnostic coverage on «Datos y
    /// fuentes» reads these so it stays honest in every mode (FER-485).
    var storedStrapDays: Set<String> { dashboard.storedStrapDays }
    var storedAppleOnlyDays: Set<String> { dashboard.storedAppleOnlyDays }
    var storedSleepsCount: Int { dashboard.storedSleepsCount }
    /// True when today's surfaced strain is an Apple workout-HR estimate (FER-883).
    func isStrainEstimated(_ day: String) -> Bool { dashboard.strainEstimates[day] != nil }
    /// The estimated strain (0–21) for a band-less day; nil unless it's an Apple estimate.
    func estimatedStrain(_ day: String) -> Double? { dashboard.strainEstimates[day] }
    /// Ola 1 · E2: the closed days whose strain an ESTIMATED strength session (minutes × effort)
    /// contributed to — every surface that shows the number must say «estimada».
    var strengthEstimatedDays: Set<String> { dashboard.strengthEstimatedDays }

    init(deviceId: String) { self.deviceId = deviceId }

    /// Dato en disco: el id de la partición raíz (el mismo valor que `AppModel.legacyDeviceId`; neutro
    /// desde FER-479, la migración `v44` reescribió `strap`→`primary`).
    static let legacyDeviceId = "primary"

    /// La fila de hoy, buscada por la fecha local REAL del aparato.
    ///
    /// No es «la fila más nueva que haya»: después de importar historia vieja, esa fila tenía meses y
    /// se pintaba como el héroe de hoy. Nada si todavía no hay fila de hoy — el tablero enseña
    /// entonces su estado vacío.
    var today: DailyMetric? {
        let key = Repository.localDayKey(Date())
        return days.last(where: { $0.day == key })
    }

    /// Los 7 días de CALENDARIO que terminan hoy, del más viejo al más nuevo, para la tira de la
    /// semana. No son «las últimas 7 filas guardadas»: con una importación vieja, esas eran datos
    /// añejos. La llave `yyyy-MM-dd` se compara como texto y sale en orden cronológico.
    var week: [DailyMetric] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return days.filter { $0.day >= cutoff }
    }

    /// `yyyy-MM-dd` en la zona horaria del aparato, que es como se guarda `DailyMetric.day`.
    /// Canonical instance lives in `CenitStore.DayKey` (FER-754); this is the same object.
    private static let dayKeyFormatter = DayKey.localFormatter
    static func localDayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    /// Parse a stored `yyyy-MM-dd` day key back to a Date in UTC (en_US_POSIX). Charts parse keys in
    /// UTC for DST-stable positions — distinct from `localDayKey` (which WRITES keys in local zone).
    /// The single shared inverse of the day-key contract (FER-325).
    /// Pure arithmetic, zero DateFormatter (FER-972 · M-04).
    nonisolated private static let dayKeyParser = DayKey.utcFormatter

    /// Days since 1970-01-01 for a `yyyy-MM-dd` key — civil-from-days arithmetic, no DateFormatter.
    /// Moved here from `ComparisonEngine` (retired with the Camino C+, CEN-67); same algorithm.
    nonisolated static func epochDay(of day: String) -> Int? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(dayOfMonth) else { return nil }
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + dayOfMonth - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    nonisolated static func parseDayKey(_ s: String) -> Date? {
        guard let days = Self.epochDay(of: s) else { return nil }
        return Date(timeIntervalSince1970: Double(days) * 86_400)
    }

    /// Format a chart date BACK to its `yyyy-MM-dd` key in UTC — the exact inverse of `parseDayKey`,
    /// for dates that were parsed/anchored in UTC (trend points). `localDayKey` on such a date shifts
    /// one day back west of UTC (a UTC-midnight 27th is still the 26th in CDMX) — that mislabeled the
    /// stress levels series a day behind its hero (FER-630).
    nonisolated static func utcDayKey(_ date: Date) -> String { dayKeyParser.string(from: date) }

    /// The `yyyy-MM-dd` key for the day BEFORE `s`, computed in UTC (one fixed 24 h step — UTC has no
    /// DST) so it stays on the same DST-stable footing as `parseDayKey`. Used to cap a "fall back to the
    /// most recent reading" at yesterday (FER-397).
    nonisolated static func previousDayKey(_ s: String) -> String? {
        guard let d = dayKeyParser.date(from: s) else { return nil }
        return dayKeyParser.string(from: d.addingTimeInterval(-86_400))
    }

    /// FER-969 (X-03): the store failed to open (wedged migration, corrupt file) — the UI shows an
    /// honest state with retry/restore instead of an eternally empty dashboard. Reset on success.
    @Published private(set) var storeOpenFailed = false

    /// Auditoría de estrés (P0-1): un restore de respaldo intercambia el archivo `.sqlite` en disco.
    /// Si el handle vivo sigue abierto apunta al inodo VIEJO (huérfano tras el swap), y toda escritura
    /// hasta el relanzamiento se pierde. Mientras `quiescedForRestore` esté activo, `ensureStore`
    /// devuelve nil → TODA lectura/escritura del store es no-op (el chokepoint por el que ya pasa cada
    /// write), así que nada toca el inodo huérfano. El archivo intercambiado carga en el próximo
    /// arranque en frío (relanzamiento limpio, sin cachés ni sesiones a medias del estado viejo).
    @Published private(set) var quiescedForRestore = false

    /// Llamado JUSTO ANTES del swap del archivo (ver `DataBackup.runImport(beforeSwap:)`): vuelca el
    /// WAL al archivo actual, suelta el handle (el `DatabasePool` se desaloca → libera el inodo) y
    /// cancela cualquier apertura en vuelo. Deja el store bloqueado hasta relanzar.
    func quiesceForRestore() async {
        _ = await checkpointForBackup()
        storeInit?.cancel()
        storeInit = nil
        store = nil
        quiescedForRestore = true
    }

    /// El swap falló: el `.sqlite` original quedó intacto (rollback de `DataBackup`). Reabre ese
    /// archivo original en el próximo acceso, en vez de dejar la app sin store.
    func unquiesceAfterFailedRestore() { quiescedForRestore = false }

    /// «Reintentar» from the store-failure state: re-attempt the open and the launch refresh that
    /// never ran. `ensureStore` re-tries naturally once `store`/`storeInit` are nil. (FER-969, X-03)
    func retryStoreOpen() async {
        guard store == nil else { return }
        storeOpenFailed = false
        await refresh()
    }

    private func ensureStore() async -> CenitStore? {
        // P0-1: durante/tras un restore de respaldo el store está cerrado a propósito hasta relanzar.
        // Devolver nil aquí convierte toda lectura/escritura en no-op → nada escribe al inodo huérfano.
        if quiescedForRestore { return nil }
        if let store { return store }
        if let storeInit { return await storeInit.value }   // a creation is already in flight — join it
        let task = Task { () -> CenitStore? in
            guard let path = try? StorePaths.defaultDatabasePath() else { return nil }
            // Don't mask a store-open/migration failure as a silent nil (FER-793). This offline app
            // degrades (returns nil) rather than crashing when the DB won't open, but the failure must
            // be observable — a swallowed `try?` here left a wedged migration undebuggable ("app se trabó"
            // with no error). Log the real error; callers still get nil and degrade.
            let s: CenitStore?
            do {
                // FER-970 (R-04): the Repository handle opens a WAL reader pool so the dashboard
                // snapshot read never waits behind a long engine/import write on this same handle.
                // The BLE handle keeps the default `.queue` backend.
                s = try await CenitStore(path: path, backend: .pool(maxReaders: 2))
            } catch {
                print("[FER-793] CenitStore failed to open at \(path): \(error)")
                s = nil
            }
            return s
        }
        storeInit = task              // published synchronously (still on @MainActor) before the await below
        let s = await task.value
        store = s
        storeInit = nil
        storeOpenFailed = (s == nil)  // FER-969 (X-03): surface the failure; clears itself on success
        return s
    }

    /// La misma base, prestada. El importador la pide para guardar las filas que ya mapeó.
    func storeHandle() async -> CenitStore? { await ensureStore() }

    /// "Verify my data": run the store's integrity check. false on any failure (incl. no store yet),
    /// so the UI prompts a retry rather than silently doing nothing.
    func verifyIntegrity() async -> Bool {
        guard let store = await ensureStore() else { return false }
        return (try? await store.integrityCheck()) ?? false
    }

    /// Pliega el WAL dentro del archivo principal si la base ya está abierta, para que un respaldo a
    /// nivel de archivo se lleve todo. Si todavía no hay base abierta no hace nada y responde `false`;
    /// el llamador copia entonces los archivos tal como están en disco, incluido el `-wal`.
    func checkpointForBackup() async -> Bool {
        guard let store else { return false }
        do { try await store.checkpointWAL(); return true } catch { return false }
    }

    /// First-paint pass of the launch refresh: reload only the trailing `firstPaintWindowDays` so
    /// «Hoy» renders in milliseconds instead of waiting for the full history (the window always
    /// contains today's row and every UI baseline ≤ 90 days). Publishes `loaded == true` but
    /// `fullyLoaded == false` — anything that PERSISTS a value derived from `days` (the engine's
    /// baselines, `closeDueExperiment`, the restore offer) must keep waiting for `fullyLoaded`.
    /// Never overwrites an already-full dashboard (`shouldPublish`).
    func refreshFirstPaint() async {
        await performRefresh(windowDays: Self.firstPaintWindowDays, full: false)
    }

    /// Reload the dashboard caches over the full stored history, merging imported history with the
    /// on-device computed scores so a legacy-only user still gets a populated dashboard. Publishes
    /// `fullyLoaded == true`; the heavy merge work runs OFF the main actor (`assembleDashboard`).
    func refresh() async {
        await performRefresh(windowDays: 4000, full: true)
    }

    static let firstPaintWindowDays = 90

    /// Generation counter for in-flight refreshes: only the most recently STARTED refresh may
    /// publish, so a slow old pass (e.g. the launch full pass finishing after a pull-to-refresh)
    /// can never clobber a newer dashboard. @MainActor-confined, so no races.
    private var refreshGen = 0

    /// The local day key (`yyyy-MM-dd`) the last SUCCESSFULLY PUBLISHED dashboard was assembled for.
    /// Set only when a pass actually publishes (never on the early-return read-failure path, which
    /// keeps the prior dashboard). The foreground scene-phase handler compares it to the current day
    /// (`AppModel.shouldForceRefreshOnForeground`) to force exactly one rebuild when the day rolled
    /// over — so «Hoy» re-buckets to the new local day even when Apple has no new data to trigger
    /// `HealthKitBridge.sync`'s own refresh (the FER-224/226/630 "Hoy shows yesterday after midnight"
    /// class). Nil until the first publish. (FER-1024)
    private(set) var lastRefreshDayKey: String?

    /// Whether a finished refresh pass may publish its dashboard. Pure so a unit test can pin the
    /// matrix: a stale generation never publishes; a first-paint pass never overwrites a dashboard
    /// that is already fully loaded (`fullyLoaded` is monotonic within a session).
    nonisolated static func shouldPublish(gen: Int, latestGen: Int,
                                          isFirstPaint: Bool, alreadyFull: Bool) -> Bool {
        gen == latestGen && !(isFirstPaint && alreadyFull)
    }

    private func performRefresh(windowDays nDays: Int, full: Bool) async {
        guard let store = await ensureStore() else { return }
        refreshGen += 1
        let gen = refreshGen
        let now = Date()
        let (fromDay, toDay) = Self.dayWindow(days: nDays, now: now)
        let nowTs = Int(now.timeIntervalSince1970)
        let lo = nowTs - nDays * 86_400, hi = nowTs + 86_400

        // FER-970 (R-03): everything below used to be ~13 sequential actor reads, each with its own
        // hop + read transaction + WAL snapshot (a write could land mid-list and mix two states into
        // one dashboard). `dashboardSnapshot` runs the SAME queries — shared row fetchers, identical
        // SQL — inside ONE transaction: one hop, one snapshot, cross-table consistent. The source-mode
        // query gating (FER-484/486) rides in the request; the in-memory gating below is unchanged.
        // (Unqualified type names: the ACTOR `CenitStore` shadows the module of the same name in
        // qualified lookup from the app layer — `CenitStore.DashboardReadRequest` doesn't resolve.)
        let snap: DashboardSnapshot
        do {
            snap = try await store.dashboardSnapshot(DashboardReadRequest(
                legacyDeviceId: deviceId, computedDeviceId: computedDeviceId, appleDeviceId: "apple-health",
                fromDay: fromDay, toDay: toDay, fromTs: lo, toTs: hi, sleepLimit: 4000,
                includeApple: true,
                includeLegacySeries: false))
        } catch {
            // A failed read (e.g. SQLITE_BUSY past the 5 s timeout against a VACUUM/checkpoint barrier)
            // must NOT publish an empty snapshot as if it were the real dashboard: the previously
            // published `dashboard` stays put, and callers gated on `fullyLoaded` (notably
            // `closeDueExperiment`, which would otherwise persist an irreversible "insufficient" verdict
            // against an empty series) don't act on emptiness caused by a transient read error. Log in
            // the FER-793 vein and bail this pass — the next refresh retries. (FER: dashboard resilience.)
            print("[refresh] dashboardSnapshot failed (\(full ? "full" : "firstPaint")): \(error) — keeping prior dashboard")
            return
        }
        let importedRaw = snap.importedDays
        let computedRaw = snap.computedDays
        // FER-62: Apple Health daily rows — the lowest-precedence fallback layer for the dashboard,
        // so a legacy-uncovered user still sees HRV / resting HR / sleep-stage trends. Read UNGATED
        // (they feed the FER-485 coverage diagnostic even when the mode hides the source).
        let appleRaw = snap.appleDays
        // FER-484 / FER-1003: Apple-only pin — the legacy arrays stay empty; Apple passes through.
        let imported: [DailyMetric] = []
        let computed: [DailyMetric] = []
        let apple = appleRaw
        // FER-485: legacy sleeps arrive UNFILTERED for the diagnostic stored-count, then gate for the dashboard.
        let impSleepRaw = snap.importedSleeps
        let compSleepRaw = snap.computedSleeps
        let impSleep: [CachedSleepSession] = []
        let compSleep: [CachedSleepSession] = []
        // FER-486: Apple Health sleep sessions (real per-epoch stage timeline). The band
        // wins per night, so the appleSleeps surfaced to the Detalle drop any overlapping a legacy session.
        let appleSleepRaw = snap.appleSleeps
        // FER-883: Apple workout-HR samples under apple-health (persisted by HealthKitBridge during
        // HKWorkouts only).
        // FER-970 (R-01): their ONLY consumer is the estimated-strain path for days whose MERGED
        // strain is nil — a band-covered history has none, so skip the HR read (paid on EVERY
        // refresh) entirely instead of loading and grouping it for nothing. The pre-pass reuses
        // the same mergeDaily the assembler runs, so eligibility can't drift. Deliberately OUTSIDE
        // the snapshot: it's a skippable phase-B read, not dashboard state.
        // Spec L1b (A3): the only UI consumer of estimated strain is today (`repo.today`), so the
        // window is local midnight→now (not the full history). Safety cap 200_000 (a day can't near it).
        let appleHrRaw: [HRSample]
        if !Self.strainEstimateEligibleDays(imported: imported, computed: computed, apple: apple).isEmpty {
            let window = Self.appleHrWindow(now: now, tzOffsetSeconds: TimeZone.current.secondsFromGMT())
            let fromTs = Int(window.from.timeIntervalSince1970)
            let toTs = Int(window.to.timeIntervalSince1970)
            do {
                appleHrRaw = try await store.hrSamples(deviceId: "apple-health", from: fromTs, to: toTs, limit: 200_000)
            } catch {
                print("[repo] apple HR read failed: \(error)")
                appleHrRaw = []
            }
        } else {
            appleHrRaw = []
        }

        // Export-verbatim sleep figures (long-format metricSeries rows from the retired CSV import).
        // The Detalle de Sueño prefers these per day over its APPROXIMATE recomputations.
        // FER-670: single-construct fusion inputs the daily rows above don't carry — Apple's step/energy
        // aggregates (appleDaily) and the retired on-device step estimate (steps_est). Gated on the
        // mode like every other read (in the snapshot request), so an excluded source can never appear
        // in a compare row.
        let appleAggRaw = snap.appleAgg
        let stepsEstRaw = snap.stepsEst

        let perf = snap.sleepPerformance
        let cons = snap.sleepConsistency
        let need = snap.sleepNeed
        let debt = snap.sleepDebt

        // R3 (FER-1008): the nocturnal autonomic trend rides ONLY on Apple's own computed
        // RMSSD-per-night partition. Read here (needs the store) but COMPOSED off-main inside
        // `assembleDashboard` — the DB read is I/O on the store's executor, cheap on this actor; the
        // CPU-bound trend + verdict math is what must not run here.
        let asOf = Self.localDayKey(now)

        // The O(n) merge/fusion work over every row read runs OFF the main actor (`assembleDashboard`
        // is nonisolated) — on a years-deep DB the full pass builds the dashboard without stealing
        // frames from the UI the first-paint pass already put up. FER-1040: the autonomic trend AND
        // the «Preparación» verdict (an O(n) hysteresis pass over the whole history) are composed in
        // this SAME off-main hop — they used to run back on the main actor after the publish guard,
        // where the verdict's per-day re-fold was an O(n²) main-thread hang on a multi-year import.
        let assembled = await Self.assembleDashboard(RefreshInputs(
            importedRaw: importedRaw, computedRaw: computedRaw, appleRaw: appleRaw,
            imported: imported, computed: computed, apple: apple,
            impSleepRaw: impSleepRaw, compSleepRaw: compSleepRaw,
            impSleep: impSleep, compSleep: compSleep, appleSleepRaw: appleSleepRaw,
            appleHrRaw: appleHrRaw,
            appleAggRaw: appleAggRaw, stepsEstRaw: stepsEstRaw,
            perf: perf, cons: cons, need: need, debt: debt, baselineEpoch: baselineEpoch,
            strainHRmax: strainHRmax, strainSex: strainSex,
            asOf: asOf, full: full,
            strengthLoads: snap.strengthLoads, appleWorkouts: snap.appleWorkouts))

        // Back on the main actor: publish only if this is still the newest refresh, and never let a
        // first-paint pass overwrite a fully loaded dashboard.
        guard Self.shouldPublish(gen: gen, latestGen: refreshGen,
                                 isFirstPaint: !full, alreadyFull: dashboard.fullyLoaded) else { return }
        var next = assembled
        next.loaded = true
        next.fullyLoaded = full
        next.seq = dashboard.seq + 1
        // One assignment → one objectWillChange for the whole refresh (was four).
        self.dashboard = next
        // FER-1024: record the local day this published dashboard belongs to, so a later foreground
        // that crossed midnight forces a rebuild. Only set here — a failed read returns above without
        // publishing, and must NOT advance this (its stale dashboard is still yesterday's).
        lastRefreshDayKey = Self.localDayKey(now)
        #if DEBUG
        let ms = Int(Date().timeIntervalSince(now) * 1000)
        print("[refresh] \(full ? "full" : "firstPaint") publicado en \(ms) ms · \(next.days.count) días")
        #endif
    }

    /// Every raw query result a refresh pass read, plus the already-mode-filtered variants (the
    /// gating happens at query time, exactly as before). Value types only, so the bundle can cross
    /// off the main actor into `assembleDashboard`.
    struct RefreshInputs {
        var importedRaw: [DailyMetric]; var computedRaw: [DailyMetric]; var appleRaw: [DailyMetric]
        var imported: [DailyMetric]; var computed: [DailyMetric]; var apple: [DailyMetric]
        var impSleepRaw: [CachedSleepSession]; var compSleepRaw: [CachedSleepSession]
        var impSleep: [CachedSleepSession]; var compSleep: [CachedSleepSession]
        var appleSleepRaw: [CachedSleepSession]
        /// FER-883: Apple workout-HR samples (deviceId `apple-health`), empty when `.legacyOnly`.
        var appleHrRaw: [HRSample] = []
        var appleAggRaw: [AppleDaily]; var stepsEstRaw: [MetricPoint]
        var perf: [MetricPoint]; var cons: [MetricPoint]; var need: [MetricPoint]; var debt: [MetricPoint]
        /// Baseline cut day-key for the estimated-recovery path (FER-677); nil = no cut.
        var baselineEpoch: String? = nil
        /// FER-883: effective HRmax + sex for the estimated strain, threaded from the Repository props.
        var strainHRmax: Double? = nil
        var strainSex: String = "male"
        /// The local day key the strength overlay treats as «today».
        var asOf: String = ""
        /// Whether this is the FULL refresh (whole stored history) or the launch first paint.
        var full: Bool = false
        /// Ola 1 · E2: the finished Cénit strength sessions in the window and the Apple workout spans
        /// the overlay needs to tell «the same training» from «extra work».
        var strengthLoads: [StrengthSessionLoad] = []
        var appleWorkouts: [WorkoutSpan] = []
    }

    /// Pure assembly of the dashboard from rows already read — the EXACT merge pipeline `refresh()`
    /// ran inline before the two-pass split, extracted verbatim so the merge/fusion tests keep
    /// pinning it. `nonisolated async` ⇒ runs on the global executor, not the main actor. Returns
    /// the dashboard with `loaded`/`fullyLoaded`/`seq` left at defaults — publication (and whether
    /// it happens at all) is the caller's @MainActor decision.
    nonisolated static func assembleDashboard(_ inputs: RefreshInputs) async -> DashboardData {
        let onDeviceSleeps = Self.mergeSleep(imported: inputs.impSleep, computed: inputs.compSleep)
        let appleSleeps = Self.appleSleepsNotCoveredOnDevice(apple: inputs.appleSleepRaw,
                                                             onDevice: onDeviceSleeps)

        var fig: [String: ImportedSleepFigures] = [:]
        for p in inputs.perf { fig[p.day, default: ImportedSleepFigures()].performancePct = p.value }
        for p in inputs.cons { fig[p.day, default: ImportedSleepFigures()].consistencyPct = p.value }
        for p in inputs.need { fig[p.day, default: ImportedSleepFigures()].needMin = p.value }
        for p in inputs.debt { fig[p.day, default: ImportedSleepFigures()].debtMin = p.value }

        let merged = Self.mergeDaily(imported: inputs.imported, computed: inputs.computed, apple: inputs.apple)
        // R4 (FER-1008): the Apple-Health estimated-recovery chain was fully removed.
        // FER-883: ESTIMATED strain for days whose MEASURED strain is nil (band-less Apple day).
        // Never folded into days/displayDays; surfaced only via estimatedStrain.
        let daysNeedingStrainEstimate = Set(merged.days.filter { $0.strain == nil }.map(\.day))
        // FER-970 (R-01): group by LOCAL day with a day-window cache — one calendar/formatter
        // resolution per day actually crossed instead of a DateFormatter call PER SAMPLE (samples
        // arrive in workout-clustered runs), and only the days an estimate can serve are kept.
        var hrByDayApple: [String: [HRSample]] = [:]
        if !inputs.appleHrRaw.isEmpty, !daysNeedingStrainEstimate.isEmpty {
            let cal = Calendar.current
            var windowStart = Int.max, windowEnd = Int.min, windowDay = ""
            for s in inputs.appleHrRaw {
                if s.ts < windowStart || s.ts >= windowEnd {
                    let d = Date(timeIntervalSince1970: Double(s.ts))
                    let start = cal.startOfDay(for: d)
                    windowStart = Int(start.timeIntervalSince1970)
                    windowEnd = cal.date(byAdding: .day, value: 1, to: start)
                        .map { Int($0.timeIntervalSince1970) } ?? windowStart + 86_400
                    windowDay = DayKey.local(d)
                }
                if daysNeedingStrainEstimate.contains(windowDay) {
                    hrByDayApple[windowDay, default: []].append(s)
                }
            }
        }
        var restingHRByDayApple: [String: Double] = [:]
        for row in inputs.apple {
            if let rhr = row.restingHr { restingHRByDayApple[row.day] = Double(rhr) }
        }
        let strainEstimates = Self.appleStrainEstimates(hrByDay: hrByDayApple,
                                                        eligibleDays: daysNeedingStrainEstimate,
                                                        restingHRByDay: restingHRByDayApple,
                                                        maxHR: inputs.strainHRmax, sex: inputs.strainSex)
        // Ola 1 · E2: the Cénit strength sessions enter the daily series IN READING — `dailyMetric`
        // is never written. Applied AFTER `daysNeedingStrainEstimate` (so Apple's live estimate for
        // band-less days is still decided on the untouched merge) and BEFORE `days`/`displayDays` are
        // published, so the four consumers of the series read the same numbers.
        let strengthLoads: [SourceFusion.StrengthDayLoad] = inputs.strengthLoads.map {
            SourceFusion.StrengthDayLoad(
                day: DayKey.local(Date(timeIntervalSince1970: TimeInterval($0.startTs))),
                startTs: $0.startTs, endTs: $0.endTs, strain: $0.strain,
                estimated: $0.strainSource == .rpe)
        }
        let appleWorkouts = inputs.appleWorkouts.map {
            SourceFusion.WorkoutInterval(startTs: $0.startTs, endTs: $0.endTs)
        }
        let overlaid = Self.overlayStrengthLoad(days: merged.days, loads: strengthLoads,
                                                workouts: appleWorkouts, today: inputs.asOf)
        let overlaidDisplay = Self.overlayStrengthLoad(days: merged.displayDays, loads: strengthLoads,
                                                       workouts: appleWorkouts, today: inputs.asOf).days
        // FER-485: stored per-source coverage from the UNFILTERED raws (the always-Combined truth), so the
        // diagnostic coverage shows what's stored even when the mode hides a source from the dashboard.
        let storedStrap = Set(inputs.importedRaw.map(\.day)).union(inputs.computedRaw.map(\.day))
        let storedAppleOnly = Set(inputs.appleRaw.map(\.day)).subtracting(storedStrap)
        let storedSleeps = Self.mergeSleep(imported: inputs.impSleepRaw, computed: inputs.compSleepRaw).count
        return DashboardData(
            days: overlaid.days,
            displayDays: overlaidDisplay,
            sleeps: onDeviceSleeps,
            appleSleeps: appleSleeps,
            importedSleep: fig,
            appleHealthDays: merged.appleDays,
            storedStrapDays: storedStrap,
            storedAppleOnlyDays: storedAppleOnly,
            storedSleepsCount: storedSleeps,
            strainEstimates: strainEstimates,
            strengthEstimatedDays: overlaid.estimatedDays
        )
    }

    /// Seed the dashboard with pre-built rows in a single publish — for SwiftUI previews, which have
    /// no store to `refresh()` from. `refresh()` is the production path.
    func setDashboard(days: [DailyMetric] = [],
                      sleeps: [CachedSleepSession] = [],
                      importedSleep: [String: ImportedSleepFigures] = [:],
                      appleHealthDays: Set<String> = [],
                      loaded: Bool = true,
                      fullyLoaded: Bool = true) {
        dashboard = DashboardData(days: days, displayDays: days, sleeps: sleeps, importedSleep: importedSleep,
                                  appleHealthDays: appleHealthDays,
                                  loaded: loaded, fullyLoaded: fullyLoaded, seq: dashboard.seq + 1)
    }

    /// Layered precedence (FER-62): Apple Health rows are the base, on-device computed rows fill the
    /// days they don't cover, and imported legacy rows win over everything — so the legacy row always beats
    /// Apple Health. Also returns the days whose surfaced row stayed Apple Health (legacy-uncovered),
    /// for source badging.
    ///
    /// `days` includes Apple-only rows (the base layer below): a band-less night surfaces Apple's
    /// HRV/sleep, and `appleDays` is the SET of those days. The recovery baseline reads `repo.days` but
    /// EXCLUDES `appleHealthDays` before folding HRV/RHR/resp (FER-519, `SourceLens.clearBandColumns`),
    /// so Apple's SDNN never enters the band's RMSSD baseline — only the capped `foldApplePrior` seeds
    /// resp (breaths/min during sleep — same metric; RHR is band sleep-nadir vs Apple awake, no longer
    /// seeded, FER-634). `displayDays` (FER-149) is a display-only twin of `days`: a
    /// legacy-covered day whose measured fields are nil (a partial-connection day) back-fills those nils
    /// from the Apple Health row this merge overwrote, so the HRV sparkline/trend shows Apple's value
    /// instead of a gap. The legacy value always wins when present — only genuine gaps fill.
    /// FER-970 (R-01): the days whose MERGED strain is nil — the only days Apple workout-HR can
    /// serve (the estimated-strain path). A pure pre-pass over rows performRefresh has already
    /// read, so the HR read can be skipped outright when this comes back empty. Reuses the very
    /// same `mergeDaily` the assembler runs — eligibility cannot drift from it.
    /// Forwards to `SourceFusion` (single policy copy; plan 2026-07-20).
    nonisolated static func strainEstimateEligibleDays(imported: [DailyMetric], computed: [DailyMetric],
                                                       apple: [DailyMetric]) -> Set<String> {
        SourceFusion.strainEstimateEligibleDays(imported: imported, computed: computed, apple: apple)
    }

    /// Inclusive read window for Apple workout-HR used by the estimated «Carga del día»: local
    /// midnight of the civil day containing `now` → `now` (the only day the UI shows an estimate).
    /// Pure + static so CenitUnitTests can pin the bounds without a store.
    nonisolated static func appleHrWindow(now: Date, tzOffsetSeconds: Int) -> (from: Date, to: Date) {
        let nowTs = Int(now.timeIntervalSince1970)
        let fromTs = AnalyticsEngine.localMidnight(nowTs, tzOffsetSeconds: tzOffsetSeconds)
        return (Date(timeIntervalSince1970: TimeInterval(fromTs)), now)
    }

    nonisolated static func mergeDaily(imported: [DailyMetric], computed: [DailyMetric],
                           apple: [DailyMetric]) -> (days: [DailyMetric], appleDays: Set<String>,
                                                     displayDays: [DailyMetric]) {
        SourceFusion.mergeDaily(imported: imported, computed: computed, apple: apple)
    }

    /// Ola 1 · E2: fold the Cénit strength sessions into the daily strain series (read-only overlay).
    /// Forwards to `SourceFusion` — single policy copy, like `mergeDaily`.
    nonisolated static func overlayStrengthLoad(days: [DailyMetric],
                                                loads: [SourceFusion.StrengthDayLoad],
                                                workouts: [SourceFusion.WorkoutInterval],
                                                today: String) -> (days: [DailyMetric], estimatedDays: Set<String>) {
        SourceFusion.overlayStrengthLoad(days: days, loads: loads, workouts: workouts, today: today)
    }

    /// FER-883: per-day cardiovascular-load estimate from Apple workout HR, for days whose MEASURED
    /// strain is nil (band-less day in Apple/Combined mode). Pure + static (RepositoryMergeTests pins it),
    /// NEVER folded into `days`/`displayDays`, surfaced only via `repo.today`/`estimatedStrain`/
    /// `isStrainEstimated`. Forwards to `SourceFusion` (single policy copy; plan 2026-07-20).
    nonisolated static func appleStrainEstimates(hrByDay: [String: [HRSample]], eligibleDays: Set<String>,
                                                 restingHRByDay: [String: Double] = [:],
                                                 maxHR: Double? = nil, sex: String = "male")
        -> [String: Double] {
        SourceFusion.appleStrainEstimates(hrByDay: hrByDay, eligibleDays: eligibleDays,
                                          restingHRByDay: restingHRByDay, maxHR: maxHR, sex: sex)
    }

    /// La misma precedencia, ahora para las noches, con la llave del día en que la noche termina.
    /// Forwards to `SourceFusion` (single policy copy; plan 2026-07-20).
    nonisolated private static func mergeSleep(imported: [CachedSleepSession], computed: [CachedSleepSession]) -> [CachedSleepSession] {
        SourceFusion.mergeSleep(imported: imported, computed: computed)
    }

    // MARK: - Lecturas de detalle (pasan derecho a la base)

    func dailyMetrics(fromDay: String, toDay: String) async -> [DailyMetric] {
        // FER-484 / FER-1003: appleHealthOnly excludes the legacy device — method kept for callers, always empty.
        return []
    }

    func hrSamples(from: Int, to: Int, limit: Int = 8000) async -> [HRSample] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// Beat-to-beat R-R intervals for the legacy device in `[from, to]`. Feeds the intraday stress engine
    /// (`StressEngine`), which derives RMSSD per window. Recomputed on the fly like `hrSamples`; the
    /// `rrInterval` table is index-covered by `(deviceId, ts)` so a multi-day read is a range scan. (FER-377)
    func rrIntervals(from: Int, to: Int, limit: Int = 200_000) async -> [RRInterval] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.rrIntervals(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// FER-972 (P-05): day-keys (per scalar key) already attempted this app session whose night read
    /// unreadable/too-thin — don't re-read their raw samples on every sheet open. In-memory only:
    /// a relaunch (or the nightly pass re-scoring the night) retries naturally.
    private var nocturnalScalarAttempted: Set<String> = []

    /// Per-night distal warming magnitudes (°C, sleep-onset → nocturnal plateau) over the last `nights`
    /// legacy nights, oldest → newest, for the thermal-stability read (FER-850). `nil` for a night with too
    /// little temp. FER-972 (P-05): reads the `night_warming_c` scalar the nightly pass persists next to
    /// `hrv_lf`; only nights the engine window didn't cover are computed here once (write-through), so a
    /// sheet open stops re-reading ~28 nights × raw samples. The math lives in
    /// `ThermalStabilityEngine.warmingMagnitudeC` (same body, moved to the package with its test).
    func nocturnalWarmingMagnitudes(nights: Int = 28) async -> [Double?] {
        // FER-1003: the legacy thermal-stability path is dormant under Apple-only.
        return []
    }

    /// El pulso del aparato heredado, promediado en cubos de `bucketSeconds`, para la gráfica de las
    /// últimas 24 horas. La suma se hace en SQL: un día entero nunca carga las filas crudas de ~1 Hz.
    func hrBuckets(from: Int, to: Int, bucketSeconds: Int = 300) async -> [HRBucket] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.hrBuckets(deviceId: deviceId, from: from, to: to, bucketSeconds: bucketSeconds)) ?? []
    }

    /// Sleep sessions overlapping `[from, to]`, MERGED across the imported (raw `deviceId`) and on-device
    /// COMPUTED (`computedDeviceId`) sources — a live legacy user's nightly sleep was written by the
    /// retired on-device pass under the computed suffix, an import user's under the raw id. Reading only
    /// the raw id missed a
    /// BLE user's sleep entirely, so the intraday-stress exclusion never fired and the night read as waking
    /// (FER-451). Mirrors the dashboard's own sleep merge. Deduped by startTs (imported/export wins on a
    /// collision), oldest first.
    func sleepSessions(from: Int, to: Int, limit: Int = 100) async -> [CachedSleepSession] {
        guard let store = await ensureStore() else { return [] }
        // FER-484/486 / FER-1003: Apple-only — the legacy partitions stay empty; Apple Health sessions only.
        let imported: [CachedSleepSession] = []
        let computed: [CachedSleepSession] = []
        let apple = (try? await store.sleepSessions(deviceId: "apple-health", from: from, to: to, limit: limit)) ?? []
        return Self.mergeSleepSessions(imported: imported, computed: computed, apple: apple)
    }

    /// Merge sleep sessions across sources. The legacy device is the base — imported (real export) wins
    /// over the on-device computed row on the same `startTs`. An Apple Health session is added ONLY if no legacy
    /// session overlaps its `[startTs, endTs]` span: the band wins PER NIGHT (FER-486).
    /// Forwards to `SourceFusion` (single policy copy; plan 2026-07-20).
    static func mergeSleepSessions(imported: [CachedSleepSession], computed: [CachedSleepSession],
                                   apple: [CachedSleepSession]) -> [CachedSleepSession] {
        SourceFusion.mergeSleepSessions(imported: imported, computed: computed, apple: apple)
    }

    /// Apple Health sleep sessions to surface in the Detalle when nothing on-device covered that night —
    /// the on-device night wins, so an Apple session overlapping ANY on-device span is dropped (FER-486).
    /// Forwards to `SourceFusion` (single policy copy; plan 2026-07-20).
    nonisolated static func appleSleepsNotCoveredOnDevice(apple: [CachedSleepSession],
                                                          onDevice: [CachedSleepSession]) -> [CachedSleepSession] {
        SourceFusion.appleSleepsNotCoveredOnDevice(apple: apple, onDevice: onDevice)
    }

    /// Todos los entrenamientos —importados, de Apple Salud y los ratos que el aparato detectó solo—,
    /// del más nuevo al más viejo.
    ///
    /// Lo detectado se enseña con su sello honesto de «Detectado», para que el usuario vea, y pueda
    /// descartar o renombrar, el duplicado que creó el detector automático (#107). El filtro de lo
    /// descartado se aplica AQUÍ, para que todas las pantallas coincidan: el motor vuelve a derivar
    /// esas filas en cada corrida, así que un borrado simple las resucitaría; la lista de tramos
    /// descartados es el registro durable de «esto no fue un entrenamiento».
    /// `respectingMode`: dashboard callers (Today/Cuerpo/Workouts/Coach) leave it `true` so the list
    /// honors the data-source mode; the diagnostic screens (Datos y fuentes / Apple Health coverage) pass
    /// `false` to show everything STORED regardless of mode (FER-485).
    func workoutRows(days: Int = 4000, respectingMode: Bool = true) async -> [WorkoutRow] {
        guard let store = await ensureStore() else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        let lo = now - days * 86_400, hi = now + 86_400
        // FER-1003: el producto quedó anclado a Apple Salud — la fuente heredada nunca alimenta al
        // tablero, Apple siempre sí. El modo diagnóstico (`respectingMode == false`) sigue enseñando
        // las filas heredadas que están guardadas.
        let useLegacy = !respectingMode
        let useApple = true
        var rows: [WorkoutRow] = []
        if useLegacy {
            rows += (try? await store.workouts(deviceId: deviceId, from: lo, to: hi, limit: 5000)) ?? []
            rows += (try? await store.workouts(deviceId: computedDeviceId, from: lo, to: hi, limit: 5000)) ?? []
        }
        if useApple {
            rows += (try? await store.workouts(deviceId: "apple-health", from: lo, to: hi, limit: 5000)) ?? []
        }
        let spans = WorkoutSource.parseDismissedSpans(dismissedDetectedSpans)
        return rows.filter { !WorkoutSource.isDismissed($0, spans: spans) }
            .sorted { $0.startTs > $1.startTs }
    }

    // MARK: - Editar entrenamientos (agregar y editar a mano · renombrar · descartar · borrar)
    //
    // Un entrenamiento escrito a mano vive bajo la fuente heredada (`deviceId`, origen "manual"), en el
    // mismo lugar donde ya caen las sesiones que el app cronometra en vivo. Lo detectado vive bajo la
    // fuente calculada con el deporte "detected", y el motor lo borra y lo vuelve a derivar en cada
    // corrida: por eso la única forma durable de mantener uno oculto es la lista de tramos de abajo.

    /// Los tramos descartados que quedan guardados, como `"inicio:fin"`.
    ///
    /// Se leen y se escriben directo en `UserDefaults`, para que el camino de lectura y el de escritura
    /// compartan una sola fuente de verdad. El motor nunca los ve —siempre vuelve a derivar—; solo los
    /// consultan el filtro de lectura y estos métodos.
    private var dismissedDetectedSpans: [String] {
        get { UserDefaults.standard.stringArray(forKey: WorkoutSource.dismissedDefaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: WorkoutSource.dismissedDefaultsKey) }
    }

    /// Guarda un entrenamiento escrito a mano —nuevo o editado— bajo la fuente heredada. `replacing`
    /// es la fila desde la que empezó la edición:
    ///  - editar un rato DETECTADO lo reemplaza con esta fila a mano, y el detectado original queda
    ///    descartado de forma durable para que el detector no lo traiga de vuelta (si no, se verían
    ///    los dos);
    ///  - editar una fila A MANO cuya llave natural (inicio o deporte) cambió borra la fila vieja
    ///    después de guardar la nueva;
    ///  - una fila IMPORTADA nunca llega aquí como `replacing` —duplicarla es solo agregar—, así que
    ///    su historial no se toca.
    ///
    /// El orden es guardar y luego borrar, nunca al revés: no se borra la única copia antes de que
    /// aterrice la nueva. Si el borrado falla después de guardar bien, se anota en la bitácora del
    /// sistema; un duplicado visible es mejor que perder la sesión.
    func saveManualWorkout(_ row: WorkoutRow, replacing old: WorkoutRow? = nil) async throws {
        guard let store = await ensureStore() else { return }
        _ = try await store.upsertWorkouts([row], deviceId: deviceId)
        if let old, WorkoutSource.classify(old.source) == .detected {
            // Durable dismiss so re-detect doesn't resurrect the bout; delete is best-effort after upsert.
            let token = WorkoutSource.dismissedToken(for: old)
            var spans = dismissedDetectedSpans
            if !spans.contains(token) { spans.append(token); dismissedDetectedSpans = spans }
            do {
                _ = try await store.deleteWorkouts(deviceId: computedDeviceId, sport: old.sport,
                                                   from: old.startTs, to: old.startTs)
            } catch {
                print("[saveManualWorkout] delete of detected original failed after upsert: \(error)")
            }
        } else if let old, old.startTs != row.startTs || old.sport != row.sport {
            do {
                _ = try await store.deleteWorkouts(deviceId: deviceId, sport: old.sport,
                                                   from: old.startTs, to: old.startTs)
            } catch {
                print("[saveManualWorkout] delete of replaced row failed after upsert: \(error)")
            }
        }
    }

    /// Renombra un rato detectado: lo copia a una fila a mano con el deporte elegido y luego borra el
    /// detectado original.
    ///
    /// Sobrevive a la siguiente corrida del motor por dos razones: el motor solo borra y vuelve a
    /// derivar las filas con deporte "detected" bajo la fuente calculada, y además se salta cualquier
    /// rato que se traslape con un entrenamiento de verdad — que es justo en lo que esta copia acaba
    /// de convertirse. Así la misma sesión nunca reaparece duplicada (#107).
    ///
    /// Primero guardar, luego borrar. Si el borrado falla, se anota: un duplicado pesa menos que una
    /// pérdida.
    func relabelDetected(_ row: WorkoutRow, sport: String) async throws {
        guard let store = await ensureStore() else { return }
        let trimmed = sport.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let manual = WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: trimmed, source: "manual",
                                durationS: row.durationS, energyKcal: row.energyKcal,
                                avgHr: row.avgHr, maxHr: row.maxHr, strain: row.strain,
                                distanceM: row.distanceM, zonesJSON: row.zonesJSON, notes: row.notes)
        _ = try await store.upsertWorkouts([manual], deviceId: deviceId)
        do {
            _ = try await store.deleteWorkouts(deviceId: computedDeviceId, sport: "detected",
                                               from: row.startTs, to: row.startTs)
        } catch {
            print("[relabelDetected] delete of detected bout failed after upsert: \(error)")
        }
    }

    /// Descarta un rato DETECTADO que el usuario dice que no fue un entrenamiento. Anota su tramo en
    /// la lista durable —para que una nueva detección del mismo tramo siga oculta— y además borra la
    /// fila actual, para que desaparezca de inmediato. Repetirlo no hace daño: un tramo que ya está
    /// no se duplica (#107).
    func dismissDetected(_ row: WorkoutRow) async throws {
        guard WorkoutSource.classify(row.source) == .detected else { return }
        let token = WorkoutSource.dismissedToken(for: row)
        var spans = dismissedDetectedSpans
        if !spans.contains(token) { spans.append(token); dismissedDetectedSpans = spans }
        guard let store = await ensureStore() else { return }
        _ = try await store.deleteWorkouts(deviceId: computedDeviceId, sport: row.sport,
                                           from: row.startTs, to: row.startTs)
    }

    /// Borra UN entrenamiento por su llave natural. El modelo que lee la pantalla no carga la fuente,
    /// así que hay que reconstruirla del origen: lo detectado vive bajo la fuente calculada —y de paso
    /// se descarta su tramo, para que no regrese—; todo lo demás que la pantalla puede borrar, que es
    /// lo escrito a mano, vive bajo la fuente heredada.
    func deleteWorkout(_ row: WorkoutRow) async throws {
        if WorkoutSource.classify(row.source) == .detected { try await dismissDetected(row); return }
        guard let store = await ensureStore() else { return }
        _ = try await store.deleteWorkouts(deviceId: deviceId, sport: row.sport,
                                           from: row.startTs, to: row.startTs)
    }

    /// Test seam: attach an already-open store so unit tests drive writes against a tmp/in-memory DB
    /// without opening the default App Support path.
    func attachStoreForTesting(_ store: CenitStore) {
        self.store = store
    }

    /// Los agregados diarios de Apple Salud: pasos, energía, VO₂ máx. y pulso.
    /// `respectingMode`: dashboard callers (Today/Cuerpo) leave it `true` so Apple is hidden in `.legacyOnly`;
    /// the Apple Health diagnostic screen passes `false` to show what's STORED regardless of mode (FER-485).
    func appleDailyRows(days: Int = 4000, respectingMode: Bool = true) async -> [AppleDaily] {
        // FER-1003: Apple is always included under the product pin (`usesAppleHealth` is constant true).
        _ = respectingMode
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        return (try? await store.appleDaily(deviceId: "apple-health", from: from, to: to)) ?? []
    }

    /// Apple-Health `dailyMetric` rows (sleep / HRV / resting HR / SpO₂ / resp rate) read straight from
    /// the apple-health source — NOT the merged dashboard. `mergeDaily` replaces a day's Apple row
    /// wholesale when the legacy source also has that day, so a legacy day with nil fields (e.g. a device that
    /// didn't decode HRV/sleep) hides the value Apple Health does have; Today's Key Metrics falls back
    /// to these to fill that gap without disturbing the dashboard merge or the recovery baseline. (FER-98)
    func appleDailyMetricRows(days: Int = 4000) async -> [DailyMetric] {
        // FER-484 / FER-1003: dashboard-only Apple Key-Metrics fall-back (TodayView/CuerpoView).
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        return (try? await store.dailyMetrics(deviceId: "apple-health", from: from, to: to)) ?? []
    }

    /// `yyyy-MM-dd` (local zone, en_US_POSIX) — same contract as `localDayKey`; both share the one
    /// `dayKeyFormatter` (was two byte-identical formatters, FER-328). Hot read path, so it's a single
    /// cached formatter; read-only use is thread-safe.
    static func dayString(_ d: Date) -> String { dayKeyFormatter.string(from: d) }

    /// The (from, to) `yyyy-MM-dd` window spanning the trailing `days` up to tomorrow — the shared
    /// date window every dashboard/series read derives the same way (FER-328). `now` is injectable so
    /// a caller that already sampled the clock (refresh) reuses it instead of reading `Date()` twice.
    private static func dayWindow(days: Int, now: Date = Date()) -> (from: String, to: String) {
        (dayString(now.addingTimeInterval(-Double(days) * 86_400)),
         dayString(now.addingTimeInterval(86_400)))
    }
}


