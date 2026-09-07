import XCTest
@testable import CenitEnsenanza

// MARK: - Tests del registro (épico FER-428, L4/FER-430, diseño /arquitecto §4)
//
// Foundation-only: ningún test importa SwiftUI/TipKit — el paquete es puro y corre en el fast
// loop y en la matriz de ubuntu de `swift-packages.yml`.

final class RegistroTests: XCTestCase {
    // MARK: 1. ids únicos y con formato

    func test_idsUnicosYConFormato() throws {
        let formato = try NSRegularExpression(pattern: #"^[a-z]+(\.[a-z0-9-]+)+$"#)
        for id in FuncionalidadID.allCases {
            let raw = id.rawValue
            let rango = NSRange(raw.startIndex..., in: raw)
            XCTAssertNotNil(
                formato.firstMatch(in: raw, range: rango),
                "\(raw) no cumple el formato pestana.slug"
            )
        }
        XCTAssertEqual(
            Set(Registro.todas.map(\.id)),
            Set(FuncionalidadID.allCases),
            "el registro no cubre exactamente los ids de FuncionalidadID (falta uno)"
        )
        // Un `Set` colapsa duplicados: el conteo es lo que caza una entrada repetida (qa FER-430, D1).
        XCTAssertEqual(
            Registro.todas.count, FuncionalidadID.allCases.count,
            "hay una entrada repetida en el registro (Registro.todas la listaría dos veces)"
        )
    }

    // MARK: 2. toda entrada tiene al menos una pieza

    func test_todaEntradaTienePieza() {
        for funcionalidad in Registro.todas {
            XCTAssertFalse(
                funcionalidad.piezas.isEmpty,
                "\(funcionalidad.id.rawValue) no tiene ninguna pieza de enseñanza"
            )
        }
    }

    // MARK: 3. toda .novedad tiene su línea en CHANGELOG.md

    func test_novedadTieneLineaEnChangelog() throws {
        let changelog = try RepoFiles.read("CHANGELOG.md")
        for funcionalidad in Registro.todas {
            for pieza in funcionalidad.piezas {
                guard case .novedad(let version, _) = pieza else { continue }
                let patron = "^## " + NSRegularExpression.escapedPattern(for: version) + #"\b"#
                let regex = try NSRegularExpression(pattern: patron, options: [.anchorsMatchLines])
                let rango = NSRange(changelog.startIndex..., in: changelog)
                XCTAssertNotNil(
                    regex.firstMatch(in: changelog, range: rango),
                    "\(funcionalidad.id.rawValue) declara .novedad(\(version)) sin encabezado `## \(version)` en CHANGELOG.md"
                )
            }
        }
    }

    // MARK: 4. .gestoConBoton nombra dos claves no vacías y distintas (existencia → test 5)

    func test_gestoConBotonNombraDosClaves() {
        for funcionalidad in Registro.todas {
            for pieza in funcionalidad.piezas {
                guard case .gestoConBoton(let gesto, let boton) = pieza else { continue }
                XCTAssertFalse(gesto.isEmpty, "\(funcionalidad.id.rawValue): clave de gesto vacía")
                XCTAssertFalse(boton.isEmpty, "\(funcionalidad.id.rawValue): clave de botón vacía")
                XCTAssertNotEqual(
                    gesto, boton,
                    "\(funcionalidad.id.rawValue): gesto y botón usan la misma clave"
                )
            }
        }
    }

    // MARK: 5. toda clave referida existe en el catálogo, con valor `es`

    func test_todaClaveExisteEnCatalogoBajoEs() throws {
        let catalogoTexto = try RepoFiles.read("Cenit/Resources/Localizable.xcstrings")
        guard
            let json = try JSONSerialization.jsonObject(with: Data(catalogoTexto.utf8)) as? [String: Any],
            let strings = json["strings"] as? [String: Any]
        else {
            XCTFail("no pude parsear Cenit/Resources/Localizable.xcstrings como JSON")
            return
        }

        func valorEs(_ clave: String) -> String? {
            guard
                let entrada = strings[clave] as? [String: Any],
                let localizations = entrada["localizations"] as? [String: Any],
                let es = localizations["es"] as? [String: Any],
                let stringUnit = es["stringUnit"] as? [String: Any],
                let value = stringUnit["value"] as? String
            else { return nil }
            return value
        }

        func assertClaveViva(_ clave: String, contexto: String) {
            let valor = valorEs(clave)
            XCTAssertNotNil(valor, "\(contexto): falta la clave `\(clave)` en el catálogo bajo `es`")
            XCTAssertFalse(
                (valor ?? "").isEmpty,
                "\(contexto): la clave `\(clave)` existe pero su valor `es` está vacío"
            )
        }

        for funcionalidad in Registro.todas {
            let contexto = funcionalidad.id.rawValue
            assertClaveViva(funcionalidad.nombreKey, contexto: contexto)
            assertClaveViva(funcionalidad.paraQueKey, contexto: contexto)
            assertClaveViva(funcionalidad.dondeViveKey, contexto: contexto)
            for pieza in funcionalidad.piezas {
                switch pieza {
                case .vacio(let clave):
                    assertClaveViva(clave, contexto: contexto)
                case .gestoConBoton(let gesto, let boton):
                    assertClaveViva(gesto, contexto: contexto)
                    assertClaveViva(boton, contexto: contexto)
                case .tip, .hito, .ayuda, .novedad:
                    continue
                }
            }
        }
    }

    // MARK: 6. los ids de tip/hito llevan el prefijo de su funcionalidad

    func test_tipIdsLlevanPrefijoDeSuFuncionalidad() {
        for funcionalidad in Registro.todas {
            let raiz = funcionalidad.id.rawValue
            for pieza in funcionalidad.piezas {
                let id: String
                switch pieza {
                case .tip(let tipId): id = tipId
                case .hito(let hitoId): id = hitoId
                default: continue
                }
                XCTAssertTrue(
                    id == raiz || id.hasPrefix(raiz + "."),
                    "\(id) no es \(raiz) ni empieza con \(raiz). — no es un id derivado de su funcionalidad"
                )
            }
        }
    }

    // MARK: 7. los 6 tips de Entrenar (FER-430 §3c) están en el registro

    func test_tipsDeEntrenarEstanEnElRegistro() {
        let idsDeTips: Set<String> = [
            FuncionalidadID.entrenarAmrapDrop.rawValue + ".amrap",
            FuncionalidadID.entrenarAmrapDrop.rawValue + ".drop",
            FuncionalidadID.entrenarRir.rawValue,
            FuncionalidadID.entrenarEsfuerzoEstimado.rawValue,
            FuncionalidadID.entrenarPlan.rawValue + ".semana-ligera",
            FuncionalidadID.entrenarProgresion.rawValue + ".ritmo",
        ]
        for id in idsDeTips {
            XCTAssertTrue(
                Registro.tipIDs.contains(id),
                "\(id) no está en Registro.tipIDs — falta la pieza .tip/.hito correspondiente"
            )
        }
    }
}
