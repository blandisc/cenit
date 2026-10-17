import XCTest

/// CEN-43 · la raíz es la sesión (antes / durante / después), sin dock.
///
/// Recorre la raíz de Fuerza con los fixtures deterministas de `FuerzaFixtures` (simulador, DEBUG):
/// rutina de hoy → «Empezar» → sesión → serie hecha → «Terminar» → guardar → acta → «Listo» →
/// «Hoy ya entrenaste»; la puerta de plan sin rutina; las tres hojas; y que ninguna pantalla pinte
/// barra de pestañas ni la línea de preparación. Cada paso deja una captura adjunta al resultado.
final class FuerzaRootUITests: XCTestCase {

    private static let baseArgs = [
        "-AppleLanguages", "(es)",
        "-AppleLocale", "es_MX",
        "-cenit.onboarded", "YES",
        "-cenit.acceptedTermsVersion", "2.0",
        "-cenit.didOfferRestore", "YES",
        // CEN-44: cada prueba arranca como si la tarjeta de Apple Salud nunca se hubiera ofrecido.
        "-health.firstSessionPromptShown", "NO",
    ]

    private static let tituloPermisoSalud = "¿Guardar tus entrenamientos en Apple Salud?"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()   // arranque limpio: una instancia viva ignoraría los argumentos y el fixture
        app.launchArguments = Self.baseArgs + ["-cenit.fixture", fixture]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Lo que la raíz de Fuerza nunca debe mostrar: dock ni recuperación.
    private func assertSinDockNiRecuperacion(_ app: XCUIApplication, file: StaticString = #filePath,
                                             line: UInt = #line) {
        XCTAssertEqual(app.tabBars.count, 0, "la raíz no debe montar barra de pestañas", file: file, line: line)
        XCTAssertFalse(app.staticTexts["En rango"].exists, "la línea de preparación no va en la raíz",
                       file: file, line: line)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CONTEXTO'")).firstMatch.exists,
                       "la fila «Contexto · Carga» no va en la raíz", file: file, line: line)
    }

    private func assertTresHojas(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for id in ["fuerza.plan", "fuerza.progreso", "fuerza.ajustes"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "falta la entrada \(id)",
                          file: file, line: line)
        }
    }

    // MARK: Antes → Durante → Después → Antes

    func test_rutinaDeHoy_empezarTerminarYVolver() throws {
        let app = launch("fuerza-hoy")
        let empezar = app.buttons["fuerza.empezar"]
        XCTAssertTrue(empezar.waitForExistence(timeout: 20), "con rutina de hoy, la raíz ofrece «Empezar»")
        XCTAssertTrue(app.staticTexts["Empuje"].exists)
        assertSinDockNiRecuperacion(app)
        assertTresHojas(app)
        // CEN-44: al abrir no se pide Apple Salud (ni tarjeta ni diálogo del sistema).
        XCTAssertFalse(app.staticTexts[Self.tituloPermisoSalud].exists, "el permiso no se pide al abrir")
        snap(app, "01-antes-con-rutina")

        // Durante: la sesión en vivo.
        empezar.tap()
        let terminar = app.buttons["Terminar"]
        XCTAssertTrue(terminar.waitForExistence(timeout: 10), "«Empezar» abre la sesión en vivo")
        snap(app, "02-durante")

        // Una serie hecha para que haya qué guardar.
        let serieHecha = app.buttons["Marcar serie como hecha"]
        XCTAssertTrue(serieHecha.waitForExistence(timeout: 10), "la sesión ofrece marcar la serie")
        serieHecha.tap()
        snap(app, "03-serie-hecha")

        // Terminar → guardar → acta.
        terminar.tap()
        // Con series pendientes la acción primaria es «Terminar y guardar»; sin pendientes, «Guardar
        // entrenamiento» (LiveStrengthSheet.bodyFinishConfirmActions).
        let guardar = app.buttons.matching(NSPredicate(
            format: "label == 'Terminar y guardar' OR label == 'Guardar entrenamiento'")).firstMatch
        XCTAssertTrue(guardar.waitForExistence(timeout: 5), "terminar con series pide guardar")
        guardar.tap()
        let listo = app.buttons["Listo"]
        XCTAssertTrue(listo.waitForExistence(timeout: 10), "al guardar aparece el acta con «Listo»")
        snap(app, "04-despues-acta")

        // «Listo» → Antes con «Hoy ya entrenaste». El globo de ayuda del esfuerzo («Entendido») se
        // come el primer toque fuera de él, como todo popover de iOS: se cierra primero.
        let entendido = app.buttons["Entendido"]
        if entendido.waitForExistence(timeout: 2) { entendido.tap() }
        listo.tap()
        // CEN-44: al cerrar el acta de la primera sesión se ofrece Apple Salud, una vez. «Ahora no» la deja
        // para Ajustes › Fuentes de datos.
        XCTAssertTrue(app.staticTexts[Self.tituloPermisoSalud].waitForExistence(timeout: 10),
                      "al cerrar la primera sesión se ofrece Apple Salud")
        snap(app, "04b-permiso-salud")
        app.buttons["Ahora no"].tap()
        XCTAssertTrue(app.staticTexts["Hoy ya entrenaste"].waitForExistence(timeout: 10),
                      "tras el acta, la raíz dice «Hoy ya entrenaste»")
        // La única rutina está agendada hoy: la que sigue es la misma, dentro de 7 días → «el próximo …».
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'el próximo'")).firstMatch.exists,
                      "a 7 días la siguiente se nombra «el próximo <día>», no solo el día de hoy")
        assertSinDockNiRecuperacion(app)
        assertTresHojas(app)
        snap(app, "05-antes-hoy-ya-entrenaste")
    }

    // MARK: Sin rutina

    func test_sinRutina_puertaDePlanConLasTresHojas() throws {
        let app = launch("fuerza-sin-rutina")
        XCTAssertTrue(app.staticTexts["Arma tu semana"].waitForExistence(timeout: 20),
                      "sin rutina, la raíz cae en la puerta de plan")
        assertSinDockNiRecuperacion(app)
        assertTresHojas(app)
        snap(app, "06-sin-rutina")
    }

    func test_sinRutina_elegirPlantillaLlevaAAntes() throws {
        let app = launch("fuerza-sin-rutina")
        let plantilla = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Cuerpo completo'")).firstMatch
        XCTAssertTrue(plantilla.waitForExistence(timeout: 20), "la puerta de plan ofrece plantillas")
        plantilla.tap()
        // Abre la galería de plantillas; ahí «Cuerpo completo» abre su detalle con «Usar este plan»
        // (modo grupo: crea las rutinas y agenda la semana).
        XCTAssertTrue(app.staticTexts["Empieza con una plantilla"].waitForExistence(timeout: 10),
                      "tocar una plantilla abre la galería")
        snap(app, "07-galeria")
        let fila = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cuerpo completo'")).allElementsBoundByIndex
            .last(where: { $0.isHittable })
        XCTAssertNotNil(fila, "la galería lista «Cuerpo completo»")
        fila?.tap()
        let usar = app.buttons.matching(NSPredicate(
            format: "label == 'Usar este plan' OR label == 'Agregar a mis rutinas'")).firstMatch
        XCTAssertTrue(usar.waitForExistence(timeout: 10), "el detalle ofrece aplicar la plantilla")
        snap(app, "07b-detalle-plantilla")
        usar.tap()
        // Al aplicar la plantilla, la raíz deja la puerta de plan: o hay rutina hoy (Antes con «Empezar»)
        // o hoy toca descanso en esa plantilla; en ambos casos «Arma tu semana» desaparece.
        let salioDeLaPuerta = NSPredicate(format: "exists == false")
        expectation(for: salioDeLaPuerta, evaluatedWith: app.staticTexts["Arma tu semana"])
        waitForExpectations(timeout: 15)
        assertSinDockNiRecuperacion(app)
        assertTresHojas(app)
        snap(app, "08-tras-plantilla")
    }

    // MARK: Descanso (CEN-57)

    func test_diaDeDescanso_hoyDescansasConLaQueSigue() throws {
        let app = launch("fuerza-descanso")
        XCTAssertTrue(app.staticTexts["Hoy descansas"].waitForExistence(timeout: 20),
                      "con plan y sin rutina hoy, la raíz dice «Hoy descansas»")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Empuje' AND label CONTAINS 'mañana'"))
            .firstMatch.exists, "nombra la rutina que sigue: «Sigue: Empuje · mañana»")
        XCTAssertFalse(app.buttons["fuerza.empezar"].exists, "en descanso no hay «Empezar»")
        XCTAssertFalse(app.staticTexts["Arma tu semana"].exists, "con plan no se ofrece armar la semana")
        assertSinDockNiRecuperacion(app)
        assertTresHojas(app)
        snap(app, "11-hoy-descansas")
    }

    // MARK: Hojas

    func test_hojas_abrenYRegresan() throws {
        let app = launch("fuerza-hoy")
        XCTAssertTrue(app.buttons["fuerza.empezar"].waitForExistence(timeout: 20))
        for (id, nombre) in [("fuerza.plan", "plan"), ("fuerza.progreso", "progreso"), ("fuerza.ajustes", "ajustes")] {
            app.buttons[id].tap()
            let listo = app.buttons["Listo"]
            XCTAssertTrue(listo.waitForExistence(timeout: 10), "la hoja \(nombre) abre y se cierra con «Listo»")
            snap(app, "09-hoja-\(nombre)")
            listo.tap()
            XCTAssertTrue(app.buttons["fuerza.empezar"].waitForExistence(timeout: 10),
                          "cerrar la hoja \(nombre) regresa a Antes")
        }
    }

    // MARK: Deep link

    func test_deepLinkSession_regresaALaSesionViva() throws {
        let app = launch("fuerza-hoy")
        let empezar = app.buttons["fuerza.empezar"]
        XCTAssertTrue(empezar.waitForExistence(timeout: 20))
        empezar.tap()
        XCTAssertTrue(app.buttons["Terminar"].waitForExistence(timeout: 10))
        // Minimiza la sesión (sigue viva, la raíz queda detrás) y vuelve por el enlace de la Live
        // Activity. No se sale al Home: `open` podría relanzar la app y el fixture la vaciaría.
        app.buttons["Minimizar sesión"].tap()
        XCTAssertTrue(app.buttons["fuerza.empezar"].waitForExistence(timeout: 10) || app.buttons["fuerza.plan"].exists)
        snap(app, "10a-sesion-minimizada")
        // `XCUIApplication.open` relanza la app sin argumentos; el `open` del sistema la reactiva.
        XCUIDevice.shared.system.open(URL(string: "cenit://session")!)
        XCTAssertTrue(app.buttons["Terminar"].waitForExistence(timeout: 10),
                      "cenit://session regresa a la sesión en vivo")
        snap(app, "10-deep-link-sesion")
    }
}
