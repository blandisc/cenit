import Foundation

/// Lee el `docs/design-system/CATALOGO.md` YA GENERADO (`swift run CenitDesignTokens`) desde los
/// tests, y parte su índice de componentes en columnas (FER-267, FER-430).
enum CatalogoIndice {
    /// `Tests/CenitDesignTests/<esteArchivo>.swift` → sube a la raíz del repo.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../Tests/CenitDesignTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../CenitDesign (raíz del paquete)
            .deletingLastPathComponent() // .../Packages
            .deletingLastPathComponent() // raíz del repo
    }

    static var url: URL { repoRoot.appendingPathComponent("docs/design-system/CATALOGO.md") }

    static func texto() throws -> String { try String(contentsOf: url, encoding: .utf8) }

    /// Filas de datos del índice, como columnas ya recortadas:
    /// `["", rol, "`símbolo`", "`archivo`", cuándo usarlo, cuándo no, ""]`. El separador visual
    /// `|---|---|` no trae backticks, así que no cuela como falso positivo.
    static func filas(_ catalogo: String) -> [[String]] {
        catalogo.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard cols.count == 7, cols[2].hasPrefix("`"), cols[3].hasPrefix("`") else { return nil }
            return cols
        }
    }

    static func sinBackticks(_ celda: String) -> String {
        celda.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
    }
}
