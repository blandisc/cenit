import Foundation
import GRDB

// MarkStore.swift — las marcas con nombre: hasta dónde llegó un proceso, y qué ya se hizo una vez.
//
// Es la tabla más pequeña y la más terca: una bandera mal leída hace que una compactación única se
// repita en cada arranque, o que no se corra nunca.

extension CenitStore {

    /// Guarda `value` bajo `name`. Idempotente: el último gana, jamás se duplica el nombre.
    public func setCursor(_ name: String, _ value: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO cursors (name, value) VALUES (?, ?)
                ON CONFLICT (name) DO UPDATE SET value = excluded.value
                """, arguments: [name, value])
        }
    }

    /// El valor guardado bajo `name`, o `nil` si nunca se escribió.
    public func cursor(_ name: String) async throws -> Int? {
        try syncRead { db in
            try Int.fetchOne(db, sql: "SELECT value FROM cursors WHERE name = ?", arguments: [name])
        }
    }

    // Las cuatro de abajo son azúcar sobre dos prefijos de nombre. Los prefijos son contrato: tienen
    // que ser distintos para que la marca de subida y la de lectura del MISMO flujo no se pisen.

    private static func uploadMark(_ stream: String) -> String { "highwater:" + stream }
    private static func readMark(_ stream: String) -> String { "read:" + stream }

    /// Hasta qué instante se subió el flujo `stream`.
    public func setHighwater(_ stream: String, _ ts: Int) async throws {
        try await setCursor(Self.uploadMark(stream), ts)
    }

    public func highwater(_ stream: String) async throws -> Int? {
        try await cursor(Self.uploadMark(stream))
    }

    /// Hasta qué instante se leyó el flujo `stream`.
    public func setReadHighwater(_ stream: String, _ ts: Int) async throws {
        try await setCursor(Self.readMark(stream), ts)
    }

    public func readHighwater(_ stream: String) async throws -> Int? {
        try await cursor(Self.readMark(stream))
    }
}
