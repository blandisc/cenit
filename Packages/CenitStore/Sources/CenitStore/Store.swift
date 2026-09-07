import Foundation
import GRDB

// Store.swift — la puerta del archivo local.
//
// Cénit calcula todo en el teléfono y no habla con ningún servidor: este actor es la única capa
// durable que existe. Serializa cada escritura, traduce la clave de partición a su entero suplente y
// corre la migración al abrir. Nada de lo que hay aquí sale del dispositivo.

/// Datos del esquema instalado. Se derivan del migrador, nunca se escriben a mano: una constante
/// suelta se desincroniza en cuanto alguien agrega una migración y se olvida de subirla.
public enum CenitStoreInfo {
    /// Cuántas migraciones registra el paquete.
    public static var schemaVersion: Int { CenitStore.makeMigrator().migrations.count }
    /// El identificador de la última migración registrada.
    public static var latestMigration: String { CenitStore.makeMigrator().migrations.last ?? "" }
}

public actor CenitStore {

    /// Cómo se abre la conexión.
    public enum Backend: Sendable {
        /// Una sola conexión. Es el default y el único modo posible en memoria.
        case queue
        /// Pool WAL: las lecturas se sirven por conexiones de sólo lectura y no esperan detrás de una
        /// escritura larga. La app lo usa para que el barrido del tablero no se forme detrás del
        /// pase nocturno.
        case pool(maxReaders: Int)
    }

    /// El escritor real. Es un `let` para que la instantánea del tablero pueda leerlo `nonisolated`.
    let dbWriter: any DatabaseWriter

    /// Texto de partición → entero suplente. Vive en el actor, así que no necesita candado: el actor
    /// serializa el consultar-luego-insertar y dos llamadas no pueden asignar dos enteros al mismo
    /// texto.
    private var partitionIds: [String: Int64] = [:]

    // MARK: - Apertura

    /// Abre (creando si hace falta) el archivo en `path`, lo configura y **corre la migración** antes
    /// de devolver. Si la migración lanza, esto lanza: una base a medio migrar no se entrega.
    public init(path: String, backend: Backend = .queue) async throws {
        var config = Self.connectionConfiguration()
        switch backend {
        case .queue:
            dbWriter = try DatabaseQueue(path: path, configuration: config)
        case .pool(let maxReaders):
            config.maximumReaderCount = max(1, maxReaders)
            dbWriter = try DatabasePool(path: path, configuration: config)
        }
        try Self.makeMigrator().migrate(dbWriter)
    }

    private init(writer: any DatabaseWriter) throws {
        dbWriter = writer
        try Self.makeMigrator().migrate(writer)
    }

    /// Una base efímera, migrada, para pruebas. Siempre en cola: el pool de GRDB no tiene modo en
    /// memoria.
    public static func inMemory() async throws -> CenitStore {
        try CenitStore(writer: try DatabaseQueue(configuration: connectionConfiguration()))
    }

    /// Los PRAGMAs que se aplican a **cada** conexión nueva.
    ///
    /// En un pool este preparador corre también en las conexiones de sólo lectura, donde los PRAGMAs
    /// de escritura lanzan. Por eso van tras la guarda de `readonly`: sin ella, abrir un lector falla
    /// y se cae toda la lectura del tablero — un modo de falla que la cola nunca muestra.
    private static func connectionConfiguration() -> Configuration {
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            if !db.configuration.readonly {
                // El orden importa: `auto_vacuum` sólo surte efecto en una base donde todavía no hay
                // ninguna tabla, así que va antes que nada.
                try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            try db.execute(sql: "PRAGMA cache_size = -16000")
            try db.execute(sql: "PRAGMA mmap_size = 268435456")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        return config
    }

    // MARK: - Acceso síncrono compartido

    /// Una lectura, síncrona, en el ejecutor del actor.
    ///
    /// Deliberadamente NO es `async`: GRDB 6 marca sus variantes síncronas como sobrecarga
    /// desfavorecida, así que un envoltorio `async` elegiría la asíncrona y cambiaría el
    /// comportamiento bajo los pies de quien la llama.
    func syncRead<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.read(block)
    }

    /// Una escritura, síncrona, en el ejecutor del actor. Misma razón que `syncRead` para no ser `async`.
    func syncWrite<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.write(block)
    }

    /// Una escritura fuera de transacción y con barrera: sin lectores vivos, ni siquiera en el pool.
    /// Tampoco es `async`, por la misma razón que las dos de arriba.
    private func syncBarrier<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.barrierWriteWithoutTransaction(block)
    }

    // MARK: - Traducción de partición

    /// El entero suplente de una partición.
    ///
    /// LECTURA (`creating: false`): una partición que nunca se escribió devuelve `nil`, y quien lee
    /// responde vacío en vez de lanzar — preguntar por una fuente que aún no existe no es un error.
    /// ESCRITURA (`creating: true`): si falta, se asigna el siguiente entero libre y jamás devuelve
    /// `nil`, para que ninguna escritura pueda fracasar por un mapeo ausente.
    func partitionId(_ deviceId: String, creating: Bool) throws -> Int64? {
        if let known = partitionIds[deviceId] { return known }
        let sql = "SELECT intId FROM deviceIdMap WHERE deviceId = ?"

        if let stored = try syncRead({ try Int64.fetchOne($0, sql: sql, arguments: [deviceId]) }) {
            partitionIds[deviceId] = stored
            return stored
        }
        guard creating else { return nil }

        let assigned = try syncWrite { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO deviceIdMap (deviceId, intId)
                VALUES (?, (SELECT COALESCE(MAX(intId), 0) + 1 FROM deviceIdMap))
                ON CONFLICT (deviceId) DO NOTHING
                """, arguments: [deviceId])
            // Se relee en la misma transacción: si otro proceso ganó la carrera, el `DO NOTHING`
            // dejó su entero y éste es el que hay que usar.
            return try Int64.fetchOne(db, sql: sql, arguments: [deviceId])!
        }
        partitionIds[deviceId] = assigned
        return assigned
    }

    // MARK: - Mantenimiento

    /// Funde el WAL en el archivo principal y lo trunca. Se llama antes de copiar el archivo a un
    /// respaldo; lanza ante un error duro de SQLite para que quien llama caiga a una copia simple en
    /// vez de guardar un respaldo incompleto.
    public func checkpointWAL() async throws {
        // Fuera de transacción y con barrera: un checkpoint no puede correr con lectores vivos.
        try syncBarrier { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// Reescribe el archivo compactándolo. También es la única forma de que una base creada antes
    /// del modo incremental adopte `auto_vacuum`.
    public func vacuum() async throws {
        try syncBarrier { db in
            try db.execute(sql: "VACUUM")
        }
    }

    // MARK: - Introspección (pruebas)

    public func pageCountForTest() async throws -> Int {
        try syncRead { try Int.fetchOne($0, sql: "PRAGMA page_count") ?? 0 }
    }

    /// Los nombres de tabla de `sqlite_master`, incluidas las internas de GRDB. Quien compara lo hace
    /// por pertenencia, no por igualdad de conjunto.
    public func tableNames() async throws -> Set<String> {
        try syncRead { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    public func primaryKeyColumns(_ table: String) async throws -> [String] {
        try syncRead { try $0.primaryKey(table).columns }
    }

    public func columnNamesForTest(table: String) async throws -> [String] {
        try syncRead { try $0.columns(in: table).map(\.name) }
    }

    public func indexNamesForTest(table: String) async throws -> Set<String> {
        try syncRead { Set(try $0.indexes(on: table).map(\.name)) }
    }

    /// Las líneas `detail` de `EXPLAIN QUERY PLAN`. Los valores ligados no cambian el plan, pero el
    /// número de marcadores sí tiene que coincidir con el de la consulta real.
    public func queryPlanForTest(_ sql: String,
                                 arguments: StatementArguments = StatementArguments()) async throws -> [String] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(sql)", arguments: arguments)
                .map { $0["detail"] ?? "" }
        }
    }
}
