import Foundation
import ZIPFoundation

// MARK: - Apple Health export import (FER-382)
//
// The user exports their whole Health database from the Salud app and hands Cénit the
// resulting archive. What comes back is one row per civil day plus the workout list —
// never the raw samples, of which a long-lived account has tens of millions.
//
// The whole path is streaming, from end to end: the zip entry is inflated to a temporary
// file a megabyte at a time, that file is read through the UTF-8 sanitiser, and the parser
// folds each element into its day and drops it. Peak memory is a function of how many DAYS
// the export covers, not of how many records it holds.

// MARK: - Naming the export

/// Apple TRANSLATES the export file name to the phone's language — `export.xml`,
/// `exportación.xml`, `exportation.xml`. Its clinical-records twin does not translate its
/// `_cda` suffix, which is the one stable thing to match on.
enum ExportFileName {

    /// Whether a lower-cased base name could be the health export itself.
    static func isCandidate(_ lowercasedBaseName: String) -> Bool {
        lowercasedBaseName.hasSuffix(".xml") && !lowercasedBaseName.hasSuffix("_cda.xml")
    }

    /// The canonical English name, taken as soon as it appears.
    static let canonical = "export.xml"
}

// MARK: - Collector

/// Accumulates one import while the document streams past. Single-threaded by construction.
private final class HealthExportCollector: NSObject, XMLParserDelegate {

    private let progress: AppleHealthImporter.ProgressHandler?
    private let isCancelled: (@Sendable () -> Bool)?
    private let clock = HealthTimestampReader()
    private let engine = AppleHealthDayAggregator()

    private(set) var workouts: [HealthWorkout] = []
    private(set) var acceptedRecords = 0
    private var countsByType: [String: Int] = [:]
    private var earliest: Date?
    private var latest: Date?

    /// Depth of `<Correlation>` nesting. Apple repeats a correlation's children at the top
    /// level of the document, so the nested copies are the duplicates — ignoring them by
    /// STRUCTURE is what lets the importer de-duplicate without a key set that would grow
    /// one entry per record.
    private var correlationDepth = 0

    private var elementsSeen = 0
    private(set) var wasCancelled = false

    /// Progress and cancellation are sampled on this exact boundary; 50 001 records give the
    /// caller exactly one chance to cancel.
    private static let checkpointEvery = 50_000

    /// Beyond this magnitude a "number" is corruption, not a measurement. A single
    /// `value="nan"` would otherwise poison a day's mean and, downstream, trap the app when
    /// the aggregate is narrowed to an integer.
    private static let implausibleMagnitude = 1e12

    init(progress: AppleHealthImporter.ProgressHandler?, isCancelled: (@Sendable () -> Bool)?) {
        self.progress = progress
        self.isCancelled = isCancelled
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch elementName {
        case "Correlation":
            correlationDepth += 1
        case "Record":
            guard correlationDepth == 0 else { return }
            checkpoint(parser)
            absorbRecord(attributes)
        case "Workout":
            checkpoint(parser)
            absorbWorkout(attributes)
        default:
            // Metadata, workout events, activity summaries, clinical records and anything
            // Apple adds in the future: tolerated at any depth, read by nobody.
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "Correlation", correlationDepth > 0 { correlationDepth -= 1 }
    }

    private func checkpoint(_ parser: XMLParser) {
        elementsSeen += 1
        guard elementsSeen % Self.checkpointEvery == 0 else { return }
        progress?(elementsSeen)
        if isCancelled?() == true {
            wasCancelled = true
            parser.abortParsing()
        }
    }

    // MARK: Elements

    private func absorbRecord(_ attributes: [String: String]) {
        guard let rawType = attributes["type"] else { return }
        let type = HealthTypeName.stripped(rawType)
        guard AppleHealthImporter.relevantTypes.contains(type) else { return }
        guard let startText = attributes["startDate"], let endText = attributes["endDate"],
              let start = clock.parse(startText), let end = clock.parse(endText)
        else { return }

        // The offset of `endDate` is the one that files the reading. In a real export both
        // offsets agree except across a daylight-saving change, and the day a sample belongs
        // to is already persisted in the user's database — recomputing it from `startDate`
        // would move rows under data that is already there.
        let offset = end.offsetMinutes

        if type == "SleepAnalysis" {
            let stage = SleepStage.from(rawValue: attributes["value"] ?? "")
            engine.addSleep(stage: stage, start: start.utc, end: end.utc, tzOffsetMin: offset)
        } else {
            var value = attributes["value"].flatMap(Double.init)
            if let raw = value, !raw.isFinite || abs(raw) >= Self.implausibleMagnitude {
                value = nil
            }
            // Apple writes oxygen saturation as a 0–1 fraction.
            if type == "OxygenSaturation", let raw = value { value = raw * 100 }

            engine.addRecord(type: type, value: value, unit: attributes["unit"],
                             source: attributes["sourceName"],
                             start: start.utc, tzOffsetMin: offset, end: end.utc)
        }

        // A record with an unusable value still happened, and the user is told how many
        // records were imported.
        acceptedRecords += 1
        countsByType[type, default: 0] += 1
        widenSpan(with: start.utc)
    }

    private func absorbWorkout(_ attributes: [String: String]) {
        guard let startText = attributes["startDate"], let endText = attributes["endDate"],
              let start = clock.parse(startText), let end = clock.parse(endText)
        else { return }

        let activity = HealthTypeName.stripped(attributes["workoutActivityType"] ?? "Unknown")
        let duration = attributes["duration"].flatMap(Double.init)
            .map { $0 * Self.secondsPerDurationUnit(attributes["durationUnit"]) }
        let distance = attributes["totalDistance"].flatMap(Double.init)
            .map { $0 * Self.metresPerDistanceUnit(attributes["totalDistanceUnit"]) }

        workouts.append(HealthWorkout(
            activityType: activity,
            durationS: duration,
            distanceM: distance,
            // Apple exports workout energy in kilocalories; the declared unit adds nothing.
            energyKcal: attributes["totalEnergyBurned"].flatMap(Double.init),
            start: start.utc,
            end: end.utc,
            tzOffsetMin: end.offsetMinutes,
            sourceName: attributes["sourceName"]))

        widenSpan(with: start.utc)
    }

    /// Minutes unless the export says otherwise — that is what Apple writes, and an
    /// unrecognised unit is likelier to be a spelling of minutes than of anything else.
    private static func secondsPerDurationUnit(_ unit: String?) -> Double {
        switch unit?.lowercased() {
        case "sec", "s": return 1
        case "hr", "h":  return 3600
        default:         return 60
        }
    }

    /// Kilometres unless the export says otherwise, for the same reason.
    private static func metresPerDistanceUnit(_ unit: String?) -> Double {
        switch unit?.lowercased() {
        case "mi": return 1609.344
        case "m":  return 1
        default:   return 1000
        }
    }

    private func widenSpan(with instant: Date) {
        if earliest == nil || instant < earliest! { earliest = instant }
        if latest == nil || instant > latest! { latest = instant }
    }

    // MARK: Result

    var sawAnything: Bool { acceptedRecords > 0 || !workouts.isEmpty }

    func result(skippedSpans: Int) -> AppleHealthImportResult {
        var counts = countsByType
        counts["Workout"] = workouts.count
        return AppleHealthImportResult(
            daily: engine.merged(),
            workouts: workouts,
            summary: ImportSummary(sourceKind: .appleHealth,
                                   recordCount: acceptedRecords + workouts.count,
                                   earliest: earliest,
                                   latest: latest,
                                   countsByCategory: counts,
                                   skippedSpans: skippedSpans))
    }
}

// MARK: - Importer

/// Reads an Apple Health export — a `.zip`, the unpacked folder, or the XML itself — and
/// reduces it to daily rows plus workouts.
public struct AppleHealthImporter {

    public init() {}

    /// The types worth carrying into the database. Everything else in the export (and there
    /// is a great deal) is dropped before any work is done on it.
    ///
    /// `BodyTemperature` and `AppleSleepingWristTemperature` are imported and counted even
    /// though no field of the daily row holds them yet: their days appear, empty.
    public static let relevantTypes: Set<String> = [
        "HeartRate",
        "RestingHeartRate",
        "HeartRateVariabilitySDNN",
        "WalkingHeartRateAverage",
        "OxygenSaturation",
        "BodyTemperature",
        "AppleSleepingWristTemperature",
        "RespiratoryRate",
        "ActiveEnergyBurned",
        "BasalEnergyBurned",
        "VO2Max",
        "StepCount",
        "SleepAnalysis",
        "BodyMass",
        "BodyFatPercentage",
        "LeanBodyMass",
        "BodyMassIndex",
    ]

    /// Called from the parsing thread — NOT the main one — every 50 000 elements, with the
    /// running count. Hopping to the main actor is the caller's job.
    public typealias ProgressHandler = @Sendable (_ elementsParsed: Int) -> Void

    /// Refuses to inflate more than this. A zip bomb should cost a disk write, not the disk.
    private static let maximumInflatedBytes: UInt64 = 8 * 1024 * 1024 * 1024

    /// Headroom demanded on top of the inflated size before extracting.
    private static let requiredHeadroomBytes: Int64 = 64 * 1024 * 1024

    private static let inflateChunkBytes = 1 << 20

    // MARK: Entry points

    /// Imports whatever the user picked: the `.zip`, the folder they unpacked it into, or a
    /// bare `.xml`. A path with an unfamiliar extension is tried as a zip first and as XML
    /// second, and it is the XML failure that reaches the caller.
    public func `import`(from url: URL, progress: ProgressHandler? = nil,
                         isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ImportError.fileNotFound(url.path)
        }
        if isDirectory.boolValue {
            let xml = try Self.findExport(inFolder: url)
            return try importXML(at: xml, progress: progress, isCancelled: isCancelled)
        }
        switch url.pathExtension.lowercased() {
        case "xml":
            return try importXML(at: url, progress: progress, isCancelled: isCancelled)
        case "zip":
            return try importZip(at: url, progress: progress, isCancelled: isCancelled)
        default:
            do {
                return try importZip(at: url, progress: progress, isCancelled: isCancelled)
            } catch is CancellationError {
                throw CancellationError()   // the user cancelling is not "this wasn't a zip"
            } catch {
                return try importXML(at: url, progress: progress, isCancelled: isCancelled)
            }
        }
    }

    /// Imports an export XML straight off disk.
    public func importXML(at url: URL, progress: ProgressHandler? = nil,
                          isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        guard let stream = InputStream(url: url) else { throw ImportError.fileNotFound(url.path) }
        return try parse(stream: stream, chunkSize: ScrubbedUTF8Stream.defaultChunkSize,
                         progress: progress, isCancelled: isCancelled)
    }

    /// Imports an export XML already in memory. Only for documents small enough to hold —
    /// a real export is read from disk.
    public func importXML(data: Data, progress: ProgressHandler? = nil,
                          isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        try importXML(data: data, chunkSize: ScrubbedUTF8Stream.defaultChunkSize,
                      progress: progress, isCancelled: isCancelled)
    }

    /// Same, with the sanitiser's block size exposed so a test can cut a multi-byte
    /// character in half on purpose.
    func importXML(data: Data, chunkSize: Int, progress: ProgressHandler? = nil,
                   isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        try parse(stream: InputStream(data: data), chunkSize: chunkSize,
                  progress: progress, isCancelled: isCancelled)
    }

    // MARK: Parsing

    private func parse(stream: InputStream, chunkSize: Int,
                       progress: ProgressHandler?,
                       isCancelled: (@Sendable () -> Bool)?) throws -> AppleHealthImportResult {
        let sanitiser = ScrubbedUTF8Stream(source: stream, chunkSize: chunkSize)
        let parser = XMLParser(stream: sanitiser)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let collector = HealthExportCollector(progress: progress, isCancelled: isCancelled)
        parser.delegate = collector

        let completed = parser.parse()

        // A cancellation is never a partial success: the caller asked to stop, and the app
        // tells the user "cancelled", not "failed".
        if collector.wasCancelled { throw CancellationError() }

        let spans = sanitiser.scrubbedRuns
        guard completed else {
            // A tag the sanitiser could not repair. Whatever was read before it is real data
            // and worth keeping; the extra span stands for the tail that was lost.
            if collector.sawAnything { return collector.result(skippedSpans: spans + 1) }
            throw ImportError.xmlParseFailed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return collector.result(skippedSpans: spans)
    }

    // MARK: Zip

    private func importZip(at url: URL, progress: ProgressHandler?,
                           isCancelled: (@Sendable () -> Bool)?) throws -> AppleHealthImportResult {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ImportError.notAZipOrFolder(url.path) }

        guard let entry = Self.findExport(inArchive: archive) else {
            throw ImportError.missingEntry(ExportFileName.canonical)
        }
        let temporary = try Self.inflate(entry, of: archive)
        defer { try? FileManager.default.removeItem(at: temporary) }
        return try importXML(at: temporary, progress: progress, isCancelled: isCancelled)
    }

    private static func findExport(inArchive archive: Archive) -> Entry? {
        var largest: Entry?
        var largestSize: UInt64 = 0
        for entry in archive where entry.type == .file {
            let base = (entry.path as NSString).lastPathComponent.lowercased()
            guard ExportFileName.isCandidate(base) else { continue }
            if base == ExportFileName.canonical { return entry }
            if entry.uncompressedSize >= largestSize {
                largest = entry
                largestSize = entry.uncompressedSize
            }
        }
        return largest
    }

    /// Inflates the entry to a uniquely named temporary file, a megabyte at a time. The
    /// caller deletes it; nothing is held in memory.
    private static func inflate(_ entry: Entry, of archive: Archive) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory

        // Running the volume out of space mid-import corrupts nothing but wastes minutes and
        // leaves the phone unusable, so refuse up front. If the volume will not say, proceed.
        let needed = Int64(clamping: entry.uncompressedSize) + requiredHeadroomBytes
        if let capacity = try? temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage, capacity < needed {
            throw ImportError.xmlParseFailed(
                "Not enough free space to import this export (needs ~\(needed >> 20) MB). Free up space and try again.")
        }

        let temporary = temporaryDirectory
            .appendingPathComponent("cenit-health-\(UUID().uuidString)")
            .appendingPathExtension("xml")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: temporary) else {
            try? FileManager.default.removeItem(at: temporary)
            throw ImportError.xmlParseFailed("could not open a temp file for import")
        }

        do {
            var written: UInt64 = 0
            _ = try archive.extract(entry, bufferSize: inflateChunkBytes, skipCRC32: true) { chunk in
                written += UInt64(chunk.count)
                guard written <= maximumInflatedBytes else {
                    throw ImportError.xmlParseFailed("export.xml too large")
                }
                handle.write(chunk)
            }
            try? handle.close()
            return temporary
        } catch let error as ImportError {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw ImportError.xmlParseFailed(
                "could not read export.xml from zip: \(error.localizedDescription)")
        }
    }

    // MARK: Folder

    private static func findExport(inFolder folder: URL) throws -> URL {
        let manager = FileManager.default

        let direct = folder.appendingPathComponent(ExportFileName.canonical)
        if manager.fileExists(atPath: direct.path) { return direct }
        let nested = folder.appendingPathComponent("apple_health_export")
            .appendingPathComponent(ExportFileName.canonical)
        if manager.fileExists(atPath: nested.path) { return nested }

        var largest: URL?
        var largestSize: Int64 = -1
        if let walker = manager.enumerator(at: folder,
                                           includingPropertiesForKeys: [.fileSizeKey],
                                           options: [.skipsHiddenFiles]) {
            for case let candidate as URL in walker {
                let base = candidate.lastPathComponent.lowercased()
                if base == ExportFileName.canonical { return candidate }
                guard ExportFileName.isCandidate(base) else { continue }
                let size = Int64((try? candidate.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if size >= largestSize {
                    largest = candidate
                    largestSize = size
                }
            }
        }
        guard let found = largest else { throw ImportError.missingEntry(ExportFileName.canonical) }
        return found
    }
}

// MARK: - Coordinator

/// The one door the app knocks on: it works out what the user handed over and imports it.
public struct ImportCoordinator {

    private let appleHealth: AppleHealthImporter

    public init(appleHealth: AppleHealthImporter = AppleHealthImporter()) {
        self.appleHealth = appleHealth
    }

    /// Straight through to the Apple Health importer, cancellation semantics included.
    public func importAppleHealth(from url: URL,
                                  progress: AppleHealthImporter.ProgressHandler? = nil,
                                  isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        try appleHealth.import(from: url, progress: progress, isCancelled: isCancelled)
    }

    /// An import together with the source it was recognised as.
    public enum DetectedImport: Sendable, Equatable {
        case appleHealth(AppleHealthImportResult)

        public var kind: DataSourceKind {
            switch self {
            case .appleHealth: return .appleHealth
            }
        }

        public var summary: ImportSummary {
            switch self {
            case .appleHealth(let result): return result.summary
            }
        }
    }

    /// Recognise, then import. No progress reporting and no cancellation — for callers that
    /// just want the result.
    public func detectAndImport(from url: URL) throws -> DetectedImport {
        switch try detectKind(of: url) {
        case .appleHealth:
            return .appleHealth(try appleHealth.import(from: url))
        }
    }

    /// What kind of export a path holds, WITHOUT unpacking anything: a zip is judged by its
    /// central directory alone.
    public func detectKind(of url: URL) throws -> DataSourceKind {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ImportError.fileNotFound(url.path)
        }
        if url.pathExtension.lowercased() == "xml" { return .appleHealth }

        var names: Set<String> = []
        if isDirectory.boolValue {
            if let walker = manager.enumerator(at: url, includingPropertiesForKeys: nil,
                                               options: [.skipsHiddenFiles]) {
                for case let item as URL in walker {
                    names.insert(item.lastPathComponent.lowercased())
                }
            }
        } else if let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) {
            for entry in archive {
                names.insert((entry.path as NSString).lastPathComponent.lowercased())
            }
        } else {
            names.insert(url.lastPathComponent.lowercased())
        }

        if names.contains(ExportFileName.canonical) { return .appleHealth }
        if names.contains(where: ExportFileName.isCandidate) { return .appleHealth }
        throw ImportError.notAZipOrFolder(url.path)
    }
}
