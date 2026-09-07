import Foundation
import GRDB

// RowBatch.swift — cómo se escriben muchas filas de golpe.
//
// Una importación de Apple Health aplana años de historia a decenas de miles de filas. Con una
// sentencia por fila eso tarda minutos y bloquea el actor; en `INSERT` multi-fila tarda segundos. Lo
// único que hay que respetar es el tope de 999 variables ligadas de SQLite, y una regla que muerde:
// una sola sentencia `INSERT … ON CONFLICT DO UPDATE` **no** puede tocar dos veces la misma clave de
// conflicto. De ahí las dos utilidades de este archivo.

enum RowBatch {

    /// Cuántas filas caben en una sentencia con `columns` variables por fila.
    static func chunkSize(columnsPerRow: Int) -> Int {
        max(1, 999 / max(1, columnsPerRow))
    }

    /// La lista de `(?, ?, …)` de un `INSERT` multi-fila.
    static func placeholders(rows: Int, columnsPerRow: Int) -> String {
        let one = "(" + Array(repeating: "?", count: columnsPerRow).joined(separator: ", ") + ")"
        return Array(repeating: one, count: rows).joined(separator: ", ")
    }

    /// Se queda con la ÚLTIMA aparición de cada clave natural, en el orden de la PRIMERA.
    ///
    /// Es la traducción de «fila por fila, el último gana» a una sola sentencia: si el mismo día
    /// llega dos veces en el mismo lote, SQLite se negaría a resolver el conflicto dos veces, así que
    /// se resuelve antes, en memoria, con el mismo resultado que tendría escribirlas en orden.
    static func lastPerKey<Row, Key: Hashable>(_ rows: [Row], by key: (Row) -> Key) -> [Row] {
        var order: [Key] = []
        var latest: [Key: Row] = [:]
        for row in rows {
            let k = key(row)
            if latest.updateValue(row, forKey: k) == nil { order.append(k) }
        }
        return order.compactMap { latest[$0] }
    }

    /// Reparte las filas en pasadas donde ninguna clave natural se repite: la primera aparición de
    /// cada clave va a la pasada 1, la segunda a la 2, y así.
    ///
    /// Aplicadas en orden, las pasadas reproducen exactamente la semántica de escribir fila por fila.
    /// Hace falta donde la regla de conflicto NO es un reemplazo —los agregados diarios se funden
    /// columna por columna— y quedarse con la última aparición perdería lo que traía la primera.
    static func passes<Row, Key: Hashable>(_ rows: [Row], by key: (Row) -> Key) -> [[Row]] {
        var seen: [Key: Int] = [:]
        var result: [[Row]] = []
        for row in rows {
            let k = key(row)
            let pass = seen[k, default: 0]
            seen[k] = pass + 1
            if pass == result.count { result.append([]) }
            result[pass].append(row)
        }
        return result
    }

    /// Ejecuta `sql` una vez por trozo de `rows`, sumando las filas que SQLite reporta como
    /// cambiadas. `arguments` aplana cada fila a sus columnas, en el orden del `INSERT`.
    @discardableResult
    static func write<Row>(_ db: Database, rows: [Row], columnsPerRow: Int,
                           sql: (_ values: String) -> String,
                           arguments: (Row) -> [DatabaseValueConvertible?]) throws -> Int {
        var changed = 0
        for chunk in rows.chunked(into: chunkSize(columnsPerRow: columnsPerRow)) {
            var bound: [DatabaseValueConvertible?] = []
            bound.reserveCapacity(chunk.count * columnsPerRow)
            for row in chunk { bound.append(contentsOf: arguments(row)) }
            try db.execute(sql: sql(placeholders(rows: chunk.count, columnsPerRow: columnsPerRow)),
                           arguments: StatementArguments(bound))
            changed += db.changesCount
        }
        return changed
    }
}

extension Array {
    /// Trozos consecutivos de a lo más `size` elementos. `size` siempre llega ≥ 1.
    func chunked(into size: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
