import XCTest
import SwiftUI
@testable import CenitDesign

/// B1/FER-349 — el vidrio se re-ilumina para negro: los tokens `vidrio*` (relleno, borde, canto,
/// highlight) resuelven DISTINTO en oscuro (superficie lit casi-negra + canto de luz), no el blanco
/// translúcido que sobre negro se ve gris. Con el flag apagado siguen byte-idénticos en claro.
/// XCTest → hilo principal (resolver dinámico off-main deadlockea en macOS).
final class LiquidVidrioOscuroTests: XCTestCase {

    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    private func difiere(_ c: Color) -> Bool {
        let l = c.resolved(at: .light).rgbaComponents, d = c.resolved(at: .dark).rgbaComponents
        return abs(l.r - d.r) > 0.02 || abs(l.g - d.g) > 0.02 || abs(l.b - d.b) > 0.02 || abs(l.a - d.a) > 0.02
    }

    func testVidrioResuelveDistintoEnOscuro() {
        LiquidTheme.oscuroHabilitado = true
        for (n, c) in [("vidrioSuperficie", LiquidColor.vidrioSuperficie),
                       ("vidrioBordeSuperficie", LiquidColor.vidrioBordeSuperficie),
                       ("vidrioPastilla", LiquidColor.vidrioPastilla),
                       ("vidrioCanto", LiquidColor.vidrioCanto),
                       ("vidrioAtmosfera", LiquidColor.vidrioAtmosfera),
                       ("vidrioHighlight(0.8)", LiquidColor.vidrioHighlight(0.8))] {
            XCTAssertTrue(difiere(c), "\(n) debe re-iluminarse en oscuro (no quedar igual al claro)")
        }
    }

    func testVidrioClaroByteIdentico() {
        LiquidTheme.oscuroHabilitado = false
        // Con el flag apagado, el relleno de superficie sigue siendo blanco ~46 % (cero cambio hoy).
        let d = LiquidColor.vidrioSuperficie.resolved(at: .light).rgbaComponents
        XCTAssertEqual(d.r, 1, accuracy: 0.01); XCTAssertEqual(d.g, 1, accuracy: 0.01); XCTAssertEqual(d.b, 1, accuracy: 0.01)
        XCTAssertEqual(d.a, 0.46, accuracy: 0.02)
    }

    /// El relleno oscuro es carbón casi opaco, no el velo crema que sobre negro se ve gris
    /// y deja la tinta clara sin suelo.
    func testRellenoOscuroEsCarbonNoLeche() {
        LiquidTheme.oscuroHabilitado = true
        for (n, c) in [("vidrioSuperficie", LiquidColor.vidrioSuperficie),
                       ("vidrioPastilla", LiquidColor.vidrioPastilla),
                       ("vidrioAtmosfera", LiquidColor.vidrioAtmosfera),
                       ("densidad0", LiquidColor.vidrioSuperficieDensidad(0)),
                       ("papelDock", LiquidColor.papelDock)] {
            let p = c.resolved(at: .dark).rgbaComponents
            let y = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
            XCTAssertLessThan(y, 0.25, "\(n) tiene que ser carbón, no un velo claro")
            XCTAssertGreaterThan(p.a, 0.75, "\(n) tiene que cubrir el suelo")
        }
    }

    /// Un borde que en claro es blanco alto no puede seguir siéndolo en oscuro: se lee como anillo.
    func testFiloOscuroNoEsAnilloBlanco() {
        LiquidTheme.oscuroHabilitado = true
        let borde = LiquidColor.vidrioBorde.resolved(at: .dark).rgbaComponents
        XCTAssertLessThan(borde.a, 0.35, "vidrioBorde oscuro no puede ser un blanco casi opaco")
        let claro = LiquidColor.vidrioBorde.resolved(at: .light).rgbaComponents
        XCTAssertEqual(claro.r, 1, accuracy: 0.01)
        XCTAssertEqual(claro.a, 0.85, accuracy: 0.02)
    }

    /// El régimen sobrio (Hoy, detalles) no puede quedarse en blanco al 50 % cuando la tinta ya es clara.
    func testSobrioOscuroNoEsBlanco() {
        LiquidTheme.oscuroHabilitado = true
        let oscuro = LiquidTonoSuperficie.rellenoResuelto(
            tono: .neutro, regimen: .sobrio, intensidad: LiquidTono.intensidadDefault)
            .resolved(at: .dark).rgbaComponents
        let y = 0.2126 * oscuro.r + 0.7152 * oscuro.g + 0.0722 * oscuro.b
        XCTAssertLessThan(y, 0.25)
        XCTAssertGreaterThan(oscuro.a, 0.75)
        let claro = LiquidTonoSuperficie.rellenoResuelto(
            tono: .neutro, regimen: .sobrio, intensidad: LiquidTono.intensidadDefault)
            .resolved(at: .light).rgbaComponents
        XCTAssertEqual(claro.r, 1, accuracy: 0.01)
        XCTAssertEqual(claro.a, 0.50, accuracy: 0.02)
    }

    /// Las motas del héroe y del polvo tienen que ser más luminosas en oscuro que la tinta
    /// pensada para papel claro; el ramo claro sigue siendo el hex de `ParticulaRGB`.
    func testParticulasLeenSobreNegroYElClaroNoCambia() {
        LiquidTheme.oscuroHabilitado = true
        let pares: [(String, Color, (r: Double, g: Double, b: Double))] = [
            ("verde", LiquidColor.particulaVerde, LiquidColor.ParticulaRGB.verde),
            ("roja", LiquidColor.particulaRoja, LiquidColor.ParticulaRGB.roja),
            ("ambar", LiquidColor.particulaAmbar, LiquidColor.ParticulaRGB.ambar),
            ("neutra", LiquidColor.particulaNeutra, LiquidColor.ParticulaRGB.neutra),
        ]
        func y(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Double {
            0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
        }
        for (n, color, rgb) in pares {
            let claro = color.resolved(at: .light).rgbaComponents
            let oscuro = color.resolved(at: .dark).rgbaComponents
            XCTAssertEqual(claro.r, rgb.r, accuracy: 0.004, "\(n) claro")
            XCTAssertEqual(claro.g, rgb.g, accuracy: 0.004, "\(n) claro")
            XCTAssertEqual(claro.b, rgb.b, accuracy: 0.004, "\(n) claro")
            XCTAssertGreaterThan(y(oscuro), y(claro) + 0.15, "\(n) tiene que leerse sobre negro")
        }
    }
}
