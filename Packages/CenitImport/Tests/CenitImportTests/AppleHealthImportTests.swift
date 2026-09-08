import XCTest
@testable import CenitImport

/// FER-382 — the importer over a whole (small) export, and over exports that are damaged in
/// the ways real ones are: a byte the parser refuses, a tag that never closes, a character cut
/// in half. Losing fifteen years of history to one bad byte is the failure this path exists to
/// prevent.
final class AppleHealthImportTests: XCTestCase {

    private let importer = AppleHealthImporter()

    // MARK: - The sample export

    private func importSample() throws -> AppleHealthImportResult {
        try importer.importXML(at: try bundledResource("health_export_sample", "xml"))
    }

    func testTheSampleExportCollapsesToOneDay() throws {
        let result = try importSample()
        XCTAssertEqual(result.daily.map(\.day), ["2024-01-02"])
    }

    func testTheDayCarriesEveryQuantityItShould() throws {
        let day = try onlyRow(try importSample().daily)
        XCTAssertEqual(try XCTUnwrap(day.weightKg), 72.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.restingHr), 58, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.respRate), 15.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.steps), 1200, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.spo2Pct), 97.0, accuracy: 1e-9)
    }

    /// The heart rate appears twice in the file: once at the top level and once inside a
    /// `<Correlation>`. Only the top-level one is real, so the mean and the maximum both stay
    /// at 61 — if the nested copy counted, nothing here would move, which is exactly why the
    /// count is asserted too.
    func testTheRecordNestedInACorrelationIsIgnored() throws {
        let result = try importSample()
        let day = try onlyRow(result.daily)
        XCTAssertEqual(try XCTUnwrap(day.avgHr), 61, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.maxHr), 61, accuracy: 1e-9)
        XCTAssertEqual(result.summary.countsByCategory["HeartRate"], 1)
    }

    func testTheNightIsAttributedToTheMorningItEndedOn() throws {
        let day = try onlyRow(try importSample().daily)
        XCTAssertEqual(try XCTUnwrap(day.coreMin), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.deepMin), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.awakeMin), 15, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.asleepMin), 120, accuracy: 1e-9)
        // The night exists, so the stages it did not have read zero, not nil.
        XCTAssertEqual(try XCTUnwrap(day.remMin), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(day.inBedMin), 0, accuracy: 1e-9)
    }

    /// The number the app puts in front of the user: six quantity readings, three sleep
    /// segments, one workout.
    func testTheSummaryCountsWhatWasImported() throws {
        let summary = try importSample().summary
        XCTAssertEqual(summary.sourceKind, .appleHealth)
        XCTAssertEqual(summary.recordCount, 10)
        XCTAssertEqual(summary.countsByCategory["Workout"], 1)
        XCTAssertEqual(summary.countsByCategory["SleepAnalysis"], 3)
        XCTAssertEqual(summary.skippedSpans, 0)

        let earliest = try XCTUnwrap(summary.earliest)
        let latest = try XCTUnwrap(summary.latest)
        XCTAssertLessThanOrEqual(earliest, latest)
    }

    /// A type outside `relevantTypes` is dropped before any work is done on it, and never
    /// reaches the metric store.
    func testAnIrrelevantTypeIsInvisible() throws {
        let result = try importSample()
        XCTAssertNil(result.summary.countsByCategory["DietaryWater"])
        let values = AppleHealthAggregator.metricPoints(result.daily).map(\.value)
        XCTAssertFalse(values.contains(250))
    }

    func testTheWorkoutIsReadWithItsUnitsConverted() throws {
        let result = try importSample()
        XCTAssertEqual(result.workouts.count, 1)
        let run = try XCTUnwrap(result.workouts.first)
        XCTAssertEqual(run.activityType, "Running")
        XCTAssertEqual(try XCTUnwrap(run.durationS), 2700, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(run.distanceM), 8050, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(run.energyKcal), 540, accuracy: 1e-9)
        XCTAssertEqual(run.start, utcInstant(2024, 1, 2, 16))
        XCTAssertEqual(run.tzOffsetMin, 60)
    }

    /// `import(from:)` on a bare `.xml` takes the same road as `importXML(at:)`.
    func testImportingByPathRecognisesAPlainXML() throws {
        let url = try bundledResource("health_export_sample", "xml")
        let result = try importer.import(from: url)
        XCTAssertEqual(result.summary.recordCount, 10)
    }

    func testAMissingPathIsReported() {
        let missing = URL(fileURLWithPath: "/tmp/there-is-no-such-export-\(UUID().uuidString).xml")
        XCTAssertThrowsError(try importer.import(from: missing)) { error in
            guard case ImportError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    // MARK: - Damaged documents

    private func document(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<HealthData>\n\(body)\n</HealthData>\n"
    }

    private func heartRate(_ value: Int, at minute: Int) -> String {
        """
        <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" \
        startDate="2024-05-01 10:\(String(format: "%02d", minute)):00 +0000" \
        endDate="2024-05-01 10:\(String(format: "%02d", minute)):00 +0000" value="\(value)"/>
        """
    }

    func testControlBytesInTheMiddleAreScrubbedAndTheRestSurvives() throws {
        var data = Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<HealthData>\n".utf8)
        data.append(Data((heartRate(70, at: 0) + "\n").utf8))
        data.append(contentsOf: [0x00, 0x1F])            // illegal in XML 1.0 — one run
        data.append(Data(("\n" + heartRate(80, at: 1) + "\n</HealthData>\n").utf8))

        let result = try importer.importXML(data: data)
        XCTAssertEqual(result.summary.recordCount, 2)
        XCTAssertGreaterThanOrEqual(result.summary.skippedSpans, 1)
    }

    func testInvalidBytesInsideAnAttributeAreReplacedNotFatal() throws {
        var data = Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<HealthData>\n".utf8)
        data.append(Data("<Record type=\"HKQuantityTypeIdentifierHeartRate\" sourceName=\"Reloj".utf8))
        data.append(contentsOf: [0xFF, 0xFE])
        data.append(Data("""
        " unit="count/min" startDate="2024-05-01 10:00:00 +0000" \
        endDate="2024-05-01 10:00:00 +0000" value="70"/>
        """.utf8))
        data.append(Data(("\n" + heartRate(80, at: 1) + "\n</HealthData>\n").utf8))

        let result = try importer.importXML(data: data)
        XCTAssertEqual(result.summary.recordCount, 2)
        XCTAssertGreaterThanOrEqual(result.summary.skippedSpans, 1)
    }

    /// A tag the sanitiser cannot repair costs the tail of the document, not the head.
    func testABrokenTagKeepsWhatWasReadBeforeIt() throws {
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
        \(heartRate(70, at: 0))
        \(heartRate(80, at: 1))
        <Record type="HKQuantityTypeIdentifierHeartR
        """
        let result = try importer.importXML(data: Data(text.utf8))
        XCTAssertEqual(result.summary.recordCount, 2)
        XCTAssertGreaterThanOrEqual(result.summary.skippedSpans, 1)
    }

    func testSomethingThatIsNotXMLAtAllThrows() {
        XCTAssertThrowsError(try importer.importXML(data: Data("plain prose, no markup".utf8))) { error in
            guard case ImportError.xmlParseFailed = error else {
                return XCTFail("expected xmlParseFailed, got \(error)")
            }
        }
    }

    /// A character split across the sanitiser's block boundary must be stitched back
    /// together — no replacement, no scrubbed run, and the record still read.
    func testAMultiByteCharacterSplitAcrossBlocksSurvives() throws {
        let text = document("""
        <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Bàscula" unit="count/min" \
        startDate="2024-05-01 10:00:00 +0000" endDate="2024-05-01 10:00:00 +0000" value="70"/>
        """)
        let result = try importer.importXML(data: Data(text.utf8), chunkSize: 8)
        XCTAssertEqual(result.summary.recordCount, 1)
        XCTAssertEqual(result.summary.skippedSpans, 0)
        XCTAssertEqual(try onlyRow(result.daily).avgHr, 70)
    }

    func testUnknownElementsAndUnknownChildrenAreTolerated() throws {
        let text = document("""
        <SomethingNew version="9"><Inner value="1"/></SomethingNew>
        <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" \
        startDate="2024-05-01 10:00:00 +0000" endDate="2024-05-01 10:00:00 +0000" value="80">
          <UnknownChild key="x" value="y"/>
        </Record>
        """)
        let result = try importer.importXML(data: Data(text.utf8))
        XCTAssertEqual(try onlyRow(result.daily).avgHr, 80)
    }

    /// Two identical TOP-LEVEL readings are two readings. Structural de-duplication only
    /// drops what a correlation repeats; keeping a key per record is what would exhaust
    /// memory on a real export.
    func testTwoIdenticalTopLevelRecordsBothCount() throws {
        let text = document("\(heartRate(70, at: 0))\n\(heartRate(70, at: 0))")
        let result = try importer.importXML(data: Data(text.utf8))
        XCTAssertEqual(result.summary.recordCount, 2)
        XCTAssertEqual(try onlyRow(result.daily).avgHr, 70)
    }

    // MARK: - Values that would poison a day

    func testANonFiniteOrAbsurdValueIsTreatedAsMissingButStillCounted() throws {
        let text = document("""
        <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" \
        startDate="2024-05-01 10:00:00 +0000" endDate="2024-05-01 10:00:00 +0000" value="nan"/>
        <Record type="HKQuantityTypeIdentifierStepCount" unit="count" \
        startDate="2024-05-01 11:00:00 +0000" endDate="2024-05-01 11:00:00 +0000" value="1e30"/>
        """)
        let result = try importer.importXML(data: Data(text.utf8))
        // Both records happened — the user is told two records were imported…
        XCTAssertEqual(result.summary.recordCount, 2)
        // …but neither number is allowed anywhere near an aggregate.
        XCTAssertTrue(result.daily.isEmpty)
    }

    // MARK: - Progress and cancellation

    private func manyRecords(_ count: Int) -> Data {
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<HealthData>\n"
        let record = """
        <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" \
        startDate="2024-05-01 10:00:00 +0000" endDate="2024-05-01 10:00:00 +0000" value="70"/>

        """
        text.reserveCapacity(count * record.utf8.count + 64)
        for _ in 0..<count { text += record }
        text += "</HealthData>\n"
        return Data(text.utf8)
    }

    /// Cancelling is not failing: the app tells the user "cancelled", and it can only do that
    /// if a `CancellationError` — not an `ImportError` — comes back.
    func testCancellingThrowsACancellationError() {
        let data = manyRecords(50_001)
        XCTAssertThrowsError(try importer.importXML(data: data, isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }

    /// The same document with nobody cancelling: one checkpoint, one day, one mean.
    func testTheSameDocumentImportsWholeWhenNobodyCancels() throws {
        let reported = ProgressLog()
        let result = try importer.importXML(data: manyRecords(50_001),
                                            progress: { reported.record($0) })
        XCTAssertEqual(result.summary.recordCount, 50_001)
        XCTAssertEqual(try onlyRow(result.daily).avgHr, 70)
        // 50 001 records cross the checkpoint exactly once: one chance to cancel.
        XCTAssertEqual(reported.counts, [50_000])
    }
}

/// The progress handler is `@Sendable` and is documented as running off the main thread, so
/// the test collects what it reports behind a lock.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Int] = []

    func record(_ count: Int) {
        lock.lock()
        seen.append(count)
        lock.unlock()
    }

    var counts: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}
