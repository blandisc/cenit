import XCTest
import CenitStore
@testable import Cenit

/// Fija la lógica pura de una fila de entrenamiento: de dónde viene (el modelo de lectura no trae
/// `deviceId`, así que el origen se deduce de la columna `source`), el filtro durable que mantiene
/// oculto un bout ya descartado aunque el motor lo vuelva a derivar (#107), la validación de un alta
/// manual y qué se conserva al editar.
final class WorkoutSourceTests: XCTestCase {

    // MARK: - De dónde viene la fila

    func testDerivedSuffixWinsOverTheLegacyBrandSubstring() {
        XCTAssertEqual(WorkoutSource.classify("strap-noop"), .detected)
        // Un id derivado que ADEMÁS contiene el nombre de la marca heredada tiene que seguir siendo
        // derivado: si cayera a la rama de importación, el bout quedaría imposible de descartar.
        XCTAssertEqual(WorkoutSource.classify("my-whoop-noop"), .detected)
    }

    func testClassifiesTheStoredSourceStrings() {
        XCTAssertEqual(WorkoutSource.classify("whoop"), .legacyWearable)
        XCTAssertEqual(WorkoutSource.classify("manual"), .manual)
        XCTAssertEqual(WorkoutSource.classify("apple_health"), .apple)
        XCTAssertEqual(WorkoutSource.classify("apple-health"), .apple)
        XCTAssertEqual(WorkoutSource.classify("APPLE-HEALTH"), .apple)      // se compara en minúsculas
        XCTAssertEqual(WorkoutSource.classify("cualquier-otra-cosa"), .apple)   // caída por omisión
    }

    /// La sincronización viva escribe el nombre real de la app que grabó después de «apple-health:».
    /// Ese nombre puede ser justo el de la otra marca; el prefijo de Apple tiene que ganar. Antes de
    /// esa precedencia, una sesión escrita en Apple Health se clasificaba como importación heredada.
    func testApplePrefixWinsOverTheBrandSubstringInsideTheAppName() {
        XCTAssertEqual(WorkoutSource.classify("apple-health:Whoop"), .apple)
        XCTAssertEqual(WorkoutSource.classify("apple-health:Strong"), .apple)
        XCTAssertEqual(WorkoutSource.classify("apple-health:Apple Fitness"), .apple)
        XCTAssertEqual(WorkoutSource.classify("apple-health:"), .apple)      // cualquier sufijo, aun vacío
        XCTAssertEqual(WorkoutSource.classify("apple_health:Whoop"), .apple) // prefijo viejo con guion bajo
    }

    func testAppleAppNameIsTheSuffixOrNothing() {
        XCTAssertEqual(WorkoutSource.appleAppName("apple-health:Strong"), "Strong")
        XCTAssertEqual(WorkoutSource.appleAppName("apple-health:Apple Fitness"), "Apple Fitness")
        XCTAssertNil(WorkoutSource.appleAppName("apple-health"))    // sin nombre
        XCTAssertNil(WorkoutSource.appleAppName("apple-health:"))   // nombre vacío = sin nombre
        XCTAssertNil(WorkoutSource.appleAppName("apple_health"))    // el importador viejo nunca trajo nombre
        XCTAssertNil(WorkoutSource.appleAppName("whoop"))
        XCTAssertNil(WorkoutSource.appleAppName("manual"))
    }

    // MARK: - Nombre y glifo del deporte

    func testDetectedTokenBecomesANeutralActivity() {
        XCTAssertEqual(WorkoutSource.displaySport("detected"), "Activity")
        XCTAssertEqual(WorkoutSource.displaySport("Running"), "Running")
    }

    func testGluedHealthKitNamesAreOpenedIntoWords() {
        // Apple Health guarda el nombre crudo, sin espacios; tiene que leerse como palabras (FER-76).
        XCTAssertEqual(WorkoutSource.displaySport("TraditionalStrengthTraining"), "Traditional Strength Training")
        XCTAssertEqual(WorkoutSource.displaySport("HighIntensityIntervalTraining"), "High Intensity Interval Training")
        XCTAssertEqual(WorkoutSource.displaySport("CoreTraining"), "Core Training")
        // Una sola palabra, o un nombre que ya trae espacio, se queda intacto.
        XCTAssertEqual(WorkoutSource.displaySport("Hiking"), "Hiking")
        XCTAssertEqual(WorkoutSource.displaySport("Weight Training"), "Weight Training")
    }

    func testSymbolPerSport() {
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Running"), "figure.run")
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Walking"), "figure.walk")
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Cycling"), "figure.outdoor.cycle")
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Swimming"), "figure.pool.swim")
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Rowing"), "figure.rower")
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Strength Training"), "dumbbell.fill")
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "HIIT"), "figure.highintensity.intervaltraining")
        // Un deporte que no conocemos cae en una figura neutra: nunca se inventa la disciplina.
        XCTAssertEqual(WorkoutSource.sfSymbol(for: "Curling"), "figure.mixed.cardio")
    }

    // MARK: - Lapsos descartados

    func testCorruptSpansAreDropped() {
        let spans = WorkoutSource.parseDismissedSpans(["100:200", "bad", "5:5", "9:3", "300:400"])
        // Se caen «bad» (no son dos enteros), «5:5» (ancho cero) y «9:3» (fin antes del inicio).
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].start, 100)
        XCTAssertEqual(spans[0].end, 200)
        XCTAssertEqual(spans[1].start, 300)
        XCTAssertEqual(spans[1].end, 400)
    }

    func testOnlyDerivedRowsAreHiddenAndOnlyWhenTheyOverlap() {
        let spans = WorkoutSource.parseDismissedSpans(["1000:2000"])
        XCTAssertTrue(WorkoutSource.isDismissed(row(1500, 2500, source: "strap-noop"), spans: spans))
        XCTAssertFalse(WorkoutSource.isDismissed(row(3000, 4000, source: "strap-noop"), spans: spans))
        // Pegar justo al final no es traslapar: el intervalo es medio abierto.
        XCTAssertFalse(WorkoutSource.isDismissed(row(2000, 3000, source: "strap-noop"), spans: spans))
        // Una fila manual (o importada) NUNCA se oculta sola; ésa la borra la persona.
        XCTAssertFalse(WorkoutSource.isDismissed(row(1500, 2500, sport: "Running", source: "manual"),
                                                 spans: spans))
    }

    func testDismissalSurvivesABoundaryThatDrifts() {
        // El motor vuelve a derivar el bout con fronteras un poco distintas; sigue descartado.
        let spans = WorkoutSource.parseDismissedSpans(["1000:2000"])
        XCTAssertTrue(WorkoutSource.isDismissed(row(1040, 2030, source: "strap-noop"), spans: spans))
    }

    func testDismissedTokenRoundTrips() {
        let dismissed = row(1_700_000_000, 1_700_003_600, source: "strap-noop")
        let token = WorkoutSource.dismissedToken(for: dismissed)
        XCTAssertEqual(token, "1700000000:1700003600")
        XCTAssertTrue(WorkoutSource.isDismissed(dismissed,
                                                spans: WorkoutSource.parseDismissedSpans([token])))
    }

    // MARK: - Alta manual

    func testManualRowKeepsWhatWasTypedAndInventsNothing() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let built = WorkoutSource.buildManualRow(start: start, durationMin: 45, sport: "  Running ",
                                                 avgHr: 150, energyKcal: 540,
                                                 now: start.addingTimeInterval(3600))
        XCTAssertNotNil(built)
        XCTAssertEqual(built?.sport, "Running")              // recortado
        XCTAssertEqual(built?.source, "manual")
        XCTAssertEqual(built?.durationS, 45 * 60)
        XCTAssertEqual(built?.endTs, built.map { $0.startTs + 45 * 60 })
        XCTAssertEqual(built?.avgHr, 150)
        XCTAssertNil(built?.strain)                          // sin FC capturada no se fabrica esfuerzo
    }

    func testManualRowRefusesInputItCannotStandBehind() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let now = start.addingTimeInterval(3600)
        func built(durationMin: Int = 30, sport: String = "Run", start: Date = start,
                   avgHr: Int? = nil, energyKcal: Double? = nil) -> WorkoutRow? {
            WorkoutSource.buildManualRow(start: start, durationMin: durationMin, sport: sport,
                                         avgHr: avgHr, energyKcal: energyKcal, now: now)
        }
        XCTAssertNil(built(durationMin: 0))                       // sin duración
        XCTAssertNil(built(durationMin: 25 * 60))                 // más de un día
        XCTAssertNil(built(sport: "   "))                         // sin deporte
        XCTAssertNil(built(start: now.addingTimeInterval(60)))    // empieza en el futuro
        XCTAssertNil(built(avgHr: 10))                            // FC fuera de lo plausible
        XCTAssertNil(built(energyKcal: 99_999))                   // calorías fuera de lo plausible
        // Los extremos válidos sí pasan.
        XCTAssertNotNil(built(durationMin: 24 * 60))
        XCTAssertNotNil(built(avgHr: 25))
        XCTAssertNotNil(built(avgHr: 250))
    }

    // MARK: - Editar sin borrar lo capturado

    func testEditingKeepsTheCapturedFieldsTheSheetNeverShows() {
        let old = row(100, 3700, sport: "Workout", source: "manual", avgHr: 130, maxHr: 175, strain: 13.5)
        let rebuilt = row(100, 3700, sport: "Running", source: "manual", avgHr: 140)
        let merged = WorkoutSource.preservingCaptured(rebuilt, from: old)
        XCTAssertEqual(merged.sport, "Running")   // lo editado manda
        XCTAssertEqual(merged.avgHr, 140)         // lo editado manda
        XCTAssertEqual(merged.maxHr, 175)         // lo capturado se arrastra
        XCTAssertEqual(merged.strain, 13.5)       // lo capturado se arrastra
    }

    func testAFreshAddHasNothingToCarryOver() {
        let rebuilt = row(100, 3700, sport: "Running", source: "manual", avgHr: 140)
        XCTAssertEqual(WorkoutSource.preservingCaptured(rebuilt, from: nil), rebuilt)
    }

    // MARK: - Formato compartido

    func testDurationReadsAsHoursAndMinutes() {
        XCTAssertEqual(WorkoutFormat.duration(0), "0m")
        XCTAssertEqual(WorkoutFormat.duration(2700), "45m")
        XCTAssertEqual(WorkoutFormat.duration(3600), "1h 0m")
        XCTAssertEqual(WorkoutFormat.duration(5400), "1h 30m")
        XCTAssertEqual(WorkoutFormat.duration(90_000), "25h 0m")   // nunca se envuelve en días
    }

    func testDateAndTimeFollowTheDeviceLocale() {
        let noon = 1_700_000_000
        let sameDay = noon + 120
        XCTAssertFalse(WorkoutFormat.date(noon).isEmpty)
        XCTAssertFalse(WorkoutFormat.time(noon).isEmpty)
        XCTAssertEqual(WorkoutFormat.date(noon), WorkoutFormat.date(sameDay))
        XCTAssertNotEqual(WorkoutFormat.time(noon), WorkoutFormat.time(sameDay))
    }

    // MARK: - Fixture

    private func row(_ start: Int, _ end: Int, sport: String = "detected", source: String,
                     avgHr: Int? = nil, maxHr: Int? = nil, strain: Double? = nil) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: end, sport: sport, source: source,
                   durationS: Double(end - start), energyKcal: nil, avgHr: avgHr, maxHr: maxHr,
                   strain: strain, distanceM: nil, zonesJSON: nil, notes: nil)
    }
}
