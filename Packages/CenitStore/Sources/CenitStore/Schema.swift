import Foundation
import GRDB

// Schema.swift — la forma del archivo local y la ÚNICA migración que la instala.
//
// Cénit no tiene servidor: el archivo SQLite del teléfono es el único ejemplar de los datos de quien
// usa la app. Por eso el migrador aquí es deliberadamente aburrido: una sola migración, todo el DDL
// pegado tal cual sale de `sqlite3 .schema`, y ni una sentencia que corra dos veces.

extension CenitStore {

    /// El migrador del paquete: **una** migración registrada.
    ///
    /// El identificador `"v43"` no es arbitrario. La base que ya está instalada trae en su ledger
    /// `grdb_migrations` los identificadores `v1`…`v43` de la historia anterior, y GRDB ignora en
    /// silencio los que el migrador no conoce: al registrar sólo `"v43"`, esa base lo lee como
    /// aplicado, no encuentra nada pendiente y **no ejecuta una sola sentencia de esquema**. Una
    /// instalación nueva llega con el ledger vacío, corre `"v43"` y obtiene el esquema completo.
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // La SIGUIENTE migración es "v44"; NUNCA reusar "v1"…"v42": la base del dueño ya los tiene en
        // su ledger y los saltaría en silencio, dejando su esquema atrás sin ningún error visible.
        migrator.registerMigration("v43") { db in
            for object in schema { try install(object, in: db) }
        }
        return migrator
    }

    /// Agrega una columna sólo si el esquema vivo todavía no la tiene.
    ///
    /// Toda migración futura que amplíe una tabla pasa por aquí. Una migración se itera varias veces
    /// durante el desarrollo y se reinstala sobre la MISMA base del teléfono; sin esta guarda, el
    /// segundo intento choca con «duplicate column» y deja la app sin poder abrir sus datos.
    static func addColumnIfMissing(_ db: Database, _ column: String, on table: String,
                                   _ body: (TableAlteration) -> Void) throws {
        guard try !db.columns(in: table).contains(where: { $0.name == column }) else { return }
        try db.alter(table: table, body: body)
    }

    // MARK: - El esquema, objeto por objeto

    /// Una tabla o un índice: su nombre en `sqlite_master` y el texto exacto que lo crea.
    struct SchemaObject {
        let name: String
        let sql: String
    }

    /// Crea el objeto sólo si `sqlite_master` todavía no lo lista.
    ///
    /// El cinturón vive aquí, en Swift, y no como `IF NOT EXISTS` dentro del texto: `sqlite_master`
    /// guarda el `CREATE` **literal** que se ejecutó, y la prueba de forma compara ese texto carácter
    /// por carácter contra el volcado de referencia. Tocar el texto para agregarle una cláusula
    /// rompería esa igualdad justo donde más se necesita. Guardando en Swift, el texto queda intacto
    /// y cualquier ejecución inesperada sigue siendo un no-op en vez de una excepción que impediría
    /// abrir la base.
    private static func install(_ object: SchemaObject, in db: Database) throws {
        let exists = try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM sqlite_master WHERE name = ?)",
            arguments: [object.name]) ?? false
        guard !exists else { return }
        try db.execute(sql: object.sql)
    }

    /// El esquema completo, en el orden en que se instala. No hay llaves foráneas entre estas tablas,
    /// así que el orden sólo importa para leerlo.
    ///
    /// El texto de cada `CREATE` está pegado **verbatim** del volcado de la base de referencia
    /// (`Tests/CenitStoreTests/Resources/legacy-schema.sql`), comillas, saltos de línea y todo. Eso
    /// vuelve la prueba de forma una igualdad exacta contra `sqlite_master`, capaz de cazar un
    /// `STRICT` perdido, un `WITHOUT ROWID` olvidado o un `DEFAULT` que cambió de valor. Si hay que
    /// modificar una tabla, no se edita aquí: se agrega la migración `"v44"`.
    ///
    /// `grdb_migrations` NO está en la lista: GRDB la crea por su cuenta, de forma idempotente.
    static let schema: [SchemaObject] = [
        // Marcas de agua y banderas de una sola vez.
        SchemaObject(name: "cursors", sql: #"CREATE TABLE IF NOT EXISTS "cursors" ("name" TEXT PRIMARY KEY, "value" INTEGER)"#),

        // Cachés de métrica: valores ya calculados, por partición y por día.
        SchemaObject(name: "sleepSession", sql: #"CREATE TABLE IF NOT EXISTS "sleepSession" ("deviceId" TEXT NOT NULL, "startTs" INTEGER NOT NULL, "endTs" INTEGER NOT NULL, "efficiency" DOUBLE, "restingHr" INTEGER, "avgHrv" DOUBLE, "stagesJSON" TEXT, PRIMARY KEY ("deviceId", "startTs"))"#),
        SchemaObject(name: "dailyMetric", sql: #"CREATE TABLE IF NOT EXISTS "dailyMetric" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "totalSleepMin" DOUBLE, "efficiency" DOUBLE, "deepMin" DOUBLE, "remMin" DOUBLE, "lightMin" DOUBLE, "disturbances" INTEGER, "restingHr" INTEGER, "avgHrv" DOUBLE, "recovery" DOUBLE, "strain" DOUBLE, "exerciseCount" INTEGER, "spo2Pct" DOUBLE, "skinTempDevC" DOUBLE, "respRateBpm" DOUBLE, "steps" INTEGER, "activeKcalEst" DOUBLE, "effortConfidence" TEXT, "restConfidence" TEXT, PRIMARY KEY ("deviceId", "day"))"#),
        SchemaObject(name: "journal", sql: #"CREATE TABLE IF NOT EXISTS "journal" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "question" TEXT NOT NULL, "answeredYes" INTEGER NOT NULL, "notes" TEXT, PRIMARY KEY ("deviceId", "day", "question"))"#),
        SchemaObject(name: "workout", sql: #"CREATE TABLE IF NOT EXISTS "workout" ("deviceId" TEXT NOT NULL, "startTs" INTEGER NOT NULL, "endTs" INTEGER NOT NULL, "sport" TEXT NOT NULL, "source" TEXT NOT NULL, "durationS" DOUBLE, "energyKcal" DOUBLE, "avgHr" INTEGER, "maxHr" INTEGER, "strain" DOUBLE, "distanceM" DOUBLE, "zonesJSON" TEXT, "notes" TEXT, PRIMARY KEY ("deviceId", "startTs", "sport"))"#),
        SchemaObject(name: "appleDaily", sql: #"CREATE TABLE IF NOT EXISTS "appleDaily" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "steps" INTEGER, "activeKcal" DOUBLE, "basalKcal" DOUBLE, "vo2max" DOUBLE, "avgHr" INTEGER, "maxHr" INTEGER, "walkingHr" INTEGER, "weightKg" DOUBLE, PRIMARY KEY ("deviceId", "day"))"#),

        // Serie métrica larga (EAV): cualquier escalar de cualquier fuente, leído por clave.
        SchemaObject(name: "metricSeries", sql: #"CREATE TABLE IF NOT EXISTS "metricSeries" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "key" TEXT NOT NULL, "value" DOUBLE NOT NULL, PRIMARY KEY ("deviceId", "day", "key"))"#),
        SchemaObject(name: "idx_metricSeries_device_key_day", sql: #"CREATE INDEX "idx_metricSeries_device_key_day" ON "metricSeries"("deviceId", "key", "day")"#),

        // Experimentos N-of-1 y dieta.
        SchemaObject(name: "experiment", sql: #"CREATE TABLE IF NOT EXISTS "experiment" ("id" TEXT PRIMARY KEY, "deviceId" TEXT NOT NULL, "behavior" TEXT NOT NULL, "outcome" TEXT NOT NULL, "expectedSign" INTEGER NOT NULL, "startDay" TEXT NOT NULL, "windowDays" INTEGER NOT NULL, "status" TEXT NOT NULL, "result" TEXT, "effectDelta" DOUBLE, "effectSize" DOUBLE, "pValue" DOUBLE, "nWith" INTEGER, "nWithout" INTEGER, "createdAt" INTEGER NOT NULL, "decidedAt" INTEGER)"#),
        SchemaObject(name: "dietPlan", sql: #"CREATE TABLE IF NOT EXISTS "dietPlan" ("id" TEXT PRIMARY KEY, "deviceId" TEXT NOT NULL, "nombre" TEXT NOT NULL, "idioma" TEXT NOT NULL, "ciclo" TEXT NOT NULL, "payloadJSON" TEXT NOT NULL, "createdAt" INTEGER NOT NULL)"#),
        SchemaObject(name: "dietAdherence", sql: #"CREATE TABLE IF NOT EXISTS "dietAdherence" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "mealId" TEXT NOT NULL, "status" TEXT NOT NULL, "note" TEXT, "optionIndex" INTEGER, PRIMARY KEY ("deviceId", "day", "mealId"))"#),

        // Fuerza: catálogo propio, rutinas, sesiones y su historia.
        SchemaObject(name: "customExercise", sql: #"CREATE TABLE IF NOT EXISTS "customExercise" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "type" TEXT NOT NULL, "equipment" TEXT, "primaryMuscles" TEXT NOT NULL, "secondaryMuscles" TEXT NOT NULL, "cues" TEXT NOT NULL, "bodyParts" TEXT NOT NULL DEFAULT '[]', "gifUrl" TEXT)"#),
        SchemaObject(name: "learnedExerciseAlias", sql: #"CREATE TABLE IF NOT EXISTS "learnedExerciseAlias" ("name" TEXT PRIMARY KEY, "exerciseId" TEXT NOT NULL, "ts" INTEGER NOT NULL)"#),
        SchemaObject(name: "exerciseTypeOverride", sql: #"CREATE TABLE IF NOT EXISTS "exerciseTypeOverride" ("exerciseId" TEXT PRIMARY KEY, "type" TEXT NOT NULL, "ts" INTEGER NOT NULL)"#),
        SchemaObject(name: "routineFolder", sql: #"CREATE TABLE IF NOT EXISTS "routineFolder" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0)"#),
        SchemaObject(name: "routine", sql: #"CREATE TABLE IF NOT EXISTS "routine" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "tag" TEXT, "createdTs" INTEGER NOT NULL, "updatedTs" INTEGER NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0, "folderId" TEXT)"#),
        SchemaObject(name: "routineExercise", sql: #"CREATE TABLE IF NOT EXISTS "routineExercise" ("id" TEXT PRIMARY KEY, "routineId" TEXT NOT NULL, "exerciseId" TEXT NOT NULL, "position" INTEGER NOT NULL, "targetSets" INTEGER NOT NULL, "targetReps" INTEGER, "targetWeightKg" DOUBLE, "warmupPercents" TEXT NOT NULL, "restMode" TEXT NOT NULL, "restSeconds" INTEGER NOT NULL, "supersetGroup" INTEGER, "hrRestReference" TEXT NOT NULL DEFAULT 'restingMargin', "hrRestValue" DOUBLE NOT NULL DEFAULT 0, "progressionEnabled" INTEGER NOT NULL DEFAULT 0, "progressionSessions" INTEGER NOT NULL DEFAULT 2, "progressionIncrementKg" DOUBLE, "progressionDeload" TEXT NOT NULL DEFAULT 'propose', "progressionIgnoreRecovery" INTEGER NOT NULL DEFAULT 0, "note" TEXT, "progressionUseRPE" INTEGER NOT NULL DEFAULT 0)"#),
        SchemaObject(name: "idx_routineExercise_routine_pos", sql: #"CREATE INDEX "idx_routineExercise_routine_pos" ON "routineExercise"("routineId", "position")"#),
        SchemaObject(name: "routineSet", sql: #"CREATE TABLE IF NOT EXISTS "routineSet" ("id" TEXT PRIMARY KEY, "routineExerciseId" TEXT NOT NULL, "position" INTEGER NOT NULL, "kind" TEXT NOT NULL, "reps" INTEGER, "weightKg" DOUBLE, "restMode" TEXT, "restSeconds" INTEGER, "hrRestReference" TEXT, "hrRestValue" DOUBLE, "repsRangeTop" INTEGER, "mode" TEXT)"#),
        SchemaObject(name: "idx_routineSet_re_pos", sql: #"CREATE INDEX "idx_routineSet_re_pos" ON "routineSet"("routineExerciseId", "position")"#),
        SchemaObject(name: "routineSchedule", sql: #"CREATE TABLE IF NOT EXISTS "routineSchedule" ("weekday" INTEGER PRIMARY KEY, "routineId" TEXT NOT NULL)"#),
        SchemaObject(name: "program", sql: #"CREATE TABLE IF NOT EXISTS "program" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "weeks" INTEGER NOT NULL, "startTs" INTEGER NOT NULL, "deloadRule" TEXT NOT NULL, "endMode" TEXT NOT NULL, "templateId" TEXT, "createdTs" INTEGER NOT NULL)"#),
        SchemaObject(name: "strengthSession", sql: #"CREATE TABLE IF NOT EXISTS "strengthSession" ("id" TEXT PRIMARY KEY, "routineId" TEXT, "startTs" INTEGER NOT NULL, "endTs" INTEGER, "deviceId" TEXT, "strain" DOUBLE, "avgHr" INTEGER, "notes" TEXT, "energyKcal" DOUBLE, "energySource" TEXT, "strainSource" TEXT, "sessionRpe" DOUBLE, "sessionRpeSource" TEXT, "trimpPerAU" DOUBLE, "source" TEXT, "title" TEXT, "programWeek" INTEGER, "deload" INTEGER)"#),
        SchemaObject(name: "setEntry", sql: #"CREATE TABLE IF NOT EXISTS "setEntry" ("id" TEXT PRIMARY KEY, "sessionId" TEXT NOT NULL, "exerciseId" TEXT NOT NULL, "position" INTEGER NOT NULL, "kind" TEXT NOT NULL, "weightKg" DOUBLE, "reps" INTEGER, "timeS" DOUBLE, "distanceM" DOUBLE, "done" BOOLEAN NOT NULL DEFAULT 0, "ts" INTEGER NOT NULL, "rpe" DOUBLE, "restTakenS" INTEGER, "mode" TEXT)"#),
        SchemaObject(name: "idx_setEntry_session_pos", sql: #"CREATE INDEX "idx_setEntry_session_pos" ON "setEntry"("sessionId", "position")"#),
        SchemaObject(name: "idx_setEntry_exercise_ts", sql: #"CREATE INDEX "idx_setEntry_exercise_ts" ON "setEntry"("exerciseId", "ts")"#),
        SchemaObject(name: "personalRecord", sql: #"CREATE TABLE IF NOT EXISTS "personalRecord" ("id" TEXT PRIMARY KEY, "exerciseId" TEXT NOT NULL, "metric" TEXT NOT NULL, "valueKg" DOUBLE, "reps" INTEGER, "ts" INTEGER NOT NULL)"#),
        SchemaObject(name: "idx_personalRecord_exercise", sql: #"CREATE INDEX "idx_personalRecord_exercise" ON "personalRecord"("exerciseId")"#),
        SchemaObject(name: "progressionOptOut", sql: #"CREATE TABLE IF NOT EXISTS "progressionOptOut" ("sessionId" TEXT NOT NULL, "exerciseId" TEXT NOT NULL, PRIMARY KEY ("sessionId", "exerciseId"))"#),
        SchemaObject(name: "strengthExerciseNote", sql: """
            CREATE TABLE strengthExerciseNote (
                id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL,
                setPosition INTEGER, text TEXT NOT NULL, ts INTEGER NOT NULL)
            """),
        SchemaObject(name: "idx_exNote_ex", sql: "CREATE INDEX idx_exNote_ex ON strengthExerciseNote(exerciseId, ts)"),
        SchemaObject(name: "idx_exNote_sess", sql: "CREATE INDEX idx_exNote_sess ON strengthExerciseNote(sessionId)"),
        SchemaObject(name: "strengthHrSample", sql: #"CREATE TABLE IF NOT EXISTS "strengthHrSample" ("sessionId" TEXT NOT NULL, "ts" INTEGER NOT NULL, "bpm" INTEGER NOT NULL, PRIMARY KEY ("sessionId", "ts"))"#),
        SchemaObject(name: "inProgressStrengthSession", sql: #"CREATE TABLE IF NOT EXISTS "inProgressStrengthSession" ("id" TEXT PRIMARY KEY, "snapshot" TEXT NOT NULL, "updatedTs" INTEGER NOT NULL)"#),

        // Mapa de partición: el texto de cada fuente vive UNA vez aquí; las tablas de latido guardan
        // el entero. Sin él, la clave compuesta repetiría el mismo texto en cada una de los millones
        // de filas de 1 Hz.
        SchemaObject(name: "deviceIdMap", sql: """
            CREATE TABLE deviceIdMap (
                deviceId TEXT PRIMARY KEY NOT NULL,
                intId INTEGER NOT NULL UNIQUE
            )
            """),
        SchemaObject(name: "hrSample", sql: """
            CREATE TABLE IF NOT EXISTS "hrSample" (
                deviceId INTEGER NOT NULL, ts INTEGER NOT NULL, bpm INTEGER NOT NULL,
                PRIMARY KEY (deviceId, ts)
            ) STRICT, WITHOUT ROWID
            """),
        SchemaObject(name: "rrInterval", sql: """
            CREATE TABLE IF NOT EXISTS "rrInterval" (
                deviceId INTEGER NOT NULL, ts INTEGER NOT NULL, rrMs INTEGER NOT NULL,
                PRIMARY KEY (deviceId, ts, rrMs)
            ) STRICT, WITHOUT ROWID
            """),
    ]
}
