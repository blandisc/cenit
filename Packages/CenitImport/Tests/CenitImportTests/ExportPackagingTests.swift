import XCTest
@testable import CenitImport

/// FER-382 — how the export is packaged, and how Cénit finds the right file inside it.
///
/// Apple TRANSLATES the export's file name to the phone's language, so looking for the
/// literal `export.xml` breaks every user whose phone is not in English — the owner's
/// included. The `_cda` clinical twin, on the other hand, keeps its suffix in every
/// language, and it is often the bigger of the two: picking by size alone would import the
/// wrong file.
final class ExportPackagingTests: XCTestCase {

    private let coordinator = ImportCoordinator()
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("cenit-import-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Building archives

    private func sampleXML() throws -> Data {
        try Data(contentsOf: try bundledResource("health_export_sample", "xml"))
    }

    /// Filler for the clinical twin: NOT health XML, and deliberately BIGGER than the real
    /// export, so "pick the largest candidate" alone would choose it and the `_cda` rule is
    /// the only thing that can get this right.
    private func clinicalTwinFiller(largerThan sample: Data) -> Data {
        var text = "record_id,issued_at,note\n"
        var index = 0
        while text.utf8.count <= sample.count {
            text += "\(index),2024-01-0\(index % 9 + 1),lorem ipsum clinical filler row\n"
            index += 1
        }
        return Data(text.utf8)
    }

    /// Builds a zip out of `entries` (path inside the archive → contents) using the system
    /// zipper, so the archive under test is a real one and not one this package wrote itself.
    private func makeZip(named name: String, entries: [String: Data]) throws -> URL {
        let staging = scratch.appendingPathComponent("staging-\(UUID().uuidString)")
        for (path, contents) in entries {
            let file = staging.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try contents.write(to: file)
        }
        let archive = scratch.appendingPathComponent(name)
        let zipper = Process()
        zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipper.currentDirectoryURL = staging
        zipper.arguments = ["-q", "-r", archive.path, "."]
        try zipper.run()
        zipper.waitUntilExit()
        XCTAssertEqual(zipper.terminationStatus, 0, "could not build \(name)")
        return archive
    }

    // MARK: - Zip

    func testImportsAZipHoldingTheEnglishExport() throws {
        let zip = try makeZip(named: "export.zip",
                              entries: ["apple_health_export/export.xml": try sampleXML()])
        let result = try coordinator.importAppleHealth(from: zip)
        XCTAssertGreaterThanOrEqual(result.daily.count, 1)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(try onlyRow(result.daily).deepMin, 60)
        XCTAssertEqual(try onlyRow(result.daily).spo2Pct, 97.0)
    }

    /// A phone in Spanish names the file `exportación.xml`.
    func testImportsAZipWhoseExportIsNamedInSpanish() throws {
        let zip = try makeZip(named: "exportación.zip",
                              entries: ["apple_health_export/exportación.xml": try sampleXML()])
        let result = try coordinator.importAppleHealth(from: zip)
        XCTAssertGreaterThanOrEqual(result.daily.count, 1)
        XCTAssertEqual(result.workouts.count, 1)
    }

    func testTheClinicalTwinIsNeverMistakenForTheExportEvenWhenItIsBigger() throws {
        let sample = try sampleXML()
        let filler = clinicalTwinFiller(largerThan: sample)
        XCTAssertGreaterThan(filler.count, sample.count, "the twin has to be the bigger file")

        let zip = try makeZip(named: "exportación.zip", entries: [
            "apple_health_export/exportación_cda.xml": filler,
            "apple_health_export/exportación.xml": sample,
        ])
        let result = try coordinator.importAppleHealth(from: zip)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.summary.recordCount, 10)
    }

    // MARK: - Folder

    func testImportsAnUnpackedFolder() throws {
        let folder = scratch.appendingPathComponent("unpacked")
        let nested = folder.appendingPathComponent("apple_health_export")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try sampleXML().write(to: nested.appendingPathComponent("exportación.xml"))

        let result = try coordinator.importAppleHealth(from: folder)
        XCTAssertGreaterThanOrEqual(result.daily.count, 1)
        XCTAssertEqual(result.workouts.count, 1)
    }

    // MARK: - Detection

    func testDetectsAPlainXML() throws {
        let url = try bundledResource("health_export_sample", "xml")
        XCTAssertEqual(try coordinator.detectKind(of: url), .appleHealth)

        let detected = try coordinator.detectAndImport(from: url)
        XCTAssertEqual(detected.kind, .appleHealth)
        XCTAssertEqual(detected.summary.recordCount, 10)
        guard case .appleHealth(let result) = detected else { return XCTFail("wrong case") }
        XCTAssertGreaterThanOrEqual(result.daily.count, 1)
    }

    /// Detection reads the zip's central directory only — nothing is inflated to answer this.
    func testDetectsAZipInEitherLanguage() throws {
        let english = try makeZip(named: "export.zip",
                                  entries: ["apple_health_export/export.xml": try sampleXML()])
        XCTAssertEqual(try coordinator.detectKind(of: english), .appleHealth)

        let spanish = try makeZip(named: "exportación.zip",
                                  entries: ["apple_health_export/exportación.xml": try sampleXML()])
        XCTAssertEqual(try coordinator.detectKind(of: spanish), .appleHealth)
    }

    func testDetectingAMissingPathThrows() {
        let missing = scratch.appendingPathComponent("nothing-here-\(UUID().uuidString).zip")
        XCTAssertThrowsError(try coordinator.detectKind(of: missing)) { error in
            guard case ImportError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    func testDetectingAnEmptyFolderThrows() throws {
        let empty = scratch.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try coordinator.detectKind(of: empty)) { error in
            guard case ImportError.notAZipOrFolder = error else {
                return XCTFail("expected notAZipOrFolder, got \(error)")
            }
        }
    }

    func testAZipWithNoExportInsideIsReported() throws {
        let zip = try makeZip(named: "wrong.zip", entries: ["readme.txt": Data("nothing".utf8)])
        XCTAssertThrowsError(try coordinator.importAppleHealth(from: zip)) { error in
            guard case ImportError.missingEntry(let name) = error else {
                return XCTFail("expected missingEntry, got \(error)")
            }
            XCTAssertEqual(name, "export.xml")
        }
    }

    // MARK: - Error text

    /// These strings reach the user verbatim on the import screen.
    func testErrorDescriptionsAreTheOnesTheAppShows() {
        XCTAssertEqual(ImportError.fileNotFound("/tmp/x").description, "File not found: /tmp/x")
        XCTAssertEqual(ImportError.notAZipOrFolder("/tmp/x").description,
                       "Expected a folder or .zip: /tmp/x")
        XCTAssertEqual(ImportError.missingEntry("export.xml").description,
                       "Required entry not found: export.xml")
        XCTAssertEqual(ImportError.xmlParseFailed("boom").description, "XML parse failed: boom")
        XCTAssertEqual(ImportError.emptyExport("nothing").description,
                       "Export contained no usable data: nothing")
    }
}
