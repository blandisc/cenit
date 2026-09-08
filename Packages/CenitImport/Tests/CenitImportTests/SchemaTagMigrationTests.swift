import XCTest
@testable import CenitImport

/// FER-382 — the interchange formats were renamed with the app. Both importers now READ the
/// old tag and the new one, and WRITE only the new one.
///
/// Accepting the old tag is not politeness: the plans and programs already on the user's
/// phone — and the payloads already stored inside the database as opaque JSON — spell it the
/// old way. Rejecting them would look like the file broke.
final class SchemaTagMigrationTests: XCTestCase {

    private let diet = DietPlanImporter()
    private let workout = WorkoutProgramImporter()

    private func dietPayload(schema: String) -> String {
        """
        { "schema":"\(schema)", "idioma":"es", "nombre":"Plan",
          "comidas":[ {"id":"d","nombre":"Desayuno","opciones":[{"alimentos":["huevo"]}]} ] }
        """
    }

    private func workoutPayload(schema: String) -> String {
        """
        { "schema":"\(schema)", "idioma":"es", "programa":"Fuerza", "rutinas":[
          { "nombre":"Empuje", "ejercicios":[ { "nombre":"Press banca", "series":4, "reps":8 } ] } ] }
        """
    }

    // MARK: - Reading

    func testTheCurrentTagsAreTheRenamedOnes() {
        XCTAssertEqual(DietPlan.currentSchema, "cenit.diet.v1")
        XCTAssertEqual(WorkoutProgram.currentSchema, "cenit.workout.v1")
        XCTAssertEqual(DietPlan.legacySchema, "noop.diet.v1")
        XCTAssertEqual(WorkoutProgram.legacySchema, "noop.workout.v1")
    }

    func testAPlanWrittenWithTheOldTagStillParses() throws {
        let plan = try diet.parse(text: dietPayload(schema: DietPlan.legacySchema))
        XCTAssertEqual(plan.name, "Plan")
        XCTAssertEqual(plan.meals.count, 1)
    }

    func testAProgramWrittenWithTheOldTagStillParses() throws {
        let program = try workout.parse(text: workoutPayload(schema: WorkoutProgram.legacySchema))
        XCTAssertEqual(program.name, "Fuerza")
        XCTAssertEqual(program.routines.count, 1)
    }

    // MARK: - Writing

    /// Whatever tag came in, what gets persisted carries today's.
    func testTheOldTagIsNormalisedOnTheWayIn() throws {
        let fromLegacy = try diet.parse(text: dietPayload(schema: DietPlan.legacySchema))
        XCTAssertEqual(fromLegacy.schema, DietPlan.currentSchema)

        let program = try workout.parse(text: workoutPayload(schema: WorkoutProgram.legacySchema))
        XCTAssertEqual(program.schema, WorkoutProgram.currentSchema)
    }

    func testTheCanonicalJSONEmitsOnlyTheNewTag() throws {
        let plan = try diet.parse(text: dietPayload(schema: DietPlan.legacySchema))
        let json = try DietPlanImporter.canonicalJSON(plan)
        XCTAssertTrue(json.contains("\"\(DietPlan.currentSchema)\""), json)
        XCTAssertFalse(json.contains(DietPlan.legacySchema), json)
        // …and what was written can be read back.
        XCTAssertEqual(try diet.parse(text: json), plan)
    }

    // MARK: - Still rejected

    func testAnUnrelatedSchemaIsStillRejected() {
        XCTAssertThrowsError(try diet.parse(text: dietPayload(schema: "acme.diet.v1"))) {
            XCTAssertEqual($0 as? DietPlanParseError, .unsupportedSchema(found: "acme.diet.v1"))
        }
        XCTAssertThrowsError(try workout.parse(text: workoutPayload(schema: "cenit.workout.v2"))) {
            XCTAssertEqual($0 as? WorkoutProgramParseError,
                           .unsupportedSchema(found: "cenit.workout.v2"))
        }
    }

    /// A diet payload is not a program, whichever generation of tag it carries.
    func testTheTwoFormatsDoNotAcceptEachOther() {
        XCTAssertThrowsError(try workout.parse(text: workoutPayload(schema: DietPlan.legacySchema))) {
            XCTAssertEqual($0 as? WorkoutProgramParseError,
                           .unsupportedSchema(found: DietPlan.legacySchema))
        }
    }
}
