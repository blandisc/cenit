import Foundation

/// A single heart-rate reading: beats per minute at a point in time.
///
/// `ts` is Unix wall-clock seconds. This is the live, high-volume vocabulary type in the
/// package — Apple Health feeds it through `CenitStore` (the `hrSample` table) into every
/// `CenitAnalytics` engine that reads heart rate.
///
/// Callers are expected to keep arrays of samples ordered by `ts` ascending — `CenitStore`
/// persists and reads them that way, and downstream algorithms assume it — but nothing in
/// this type enforces or validates that ordering.
public struct HRSample: Equatable, Codable, Sendable {
    public let ts: Int
    public let bpm: Int

    public init(ts: Int, bpm: Int) {
        self.ts = ts
        self.bpm = bpm
    }
}

/// A single R-R interval: the time between two consecutive heartbeats, in milliseconds.
///
/// Same `ts` convention as `HRSample`. HRV analysis (`HRVAnalyzer`, `HRVFreqDomain`,
/// `StressEngine`) and the `rrInterval` table are built on sequences of these.
public struct RRInterval: Equatable, Codable, Sendable {
    public let ts: Int
    public let rrMs: Int

    public init(ts: Int, rrMs: Int) {
        self.ts = ts
        self.rrMs = rrMs
    }
}

/// A raw skin-temperature reading. `raw` is sensor output, not a physiological unit — any
/// conversion to a real temperature happens downstream, not in this type.
///
/// Dormant: nothing in the app currently feeds real data through the tables/engines that
/// would consume this end to end, but the type still has live call sites, so it stays.
public struct SkinTempSample: Equatable, Codable, Sendable {
    public let ts: Int
    public let raw: Int
    public let unit: String

    public init(ts: Int, raw: Int, unit: String = "raw_adc") {
        self.ts = ts
        self.raw = raw
        self.unit = unit
    }
}

/// A raw respiration reading. Same shape and same dormant status as `SkinTempSample` — its
/// one caller is an accelerometer-based sleep-staging path nothing in production drives yet.
public struct RespSample: Equatable, Codable, Sendable {
    public let ts: Int
    public let raw: Int
    public let unit: String

    public init(ts: Int, raw: Int, unit: String = "raw_adc") {
        self.ts = ts
        self.raw = raw
        self.unit = unit
    }
}

/// A single accelerometer/gravity-vector sample, in g (`unit: "g"`).
///
/// Dormant like `SkinTempSample`/`RespSample`: workout detection and sleep staging both
/// accept `[GravitySample]`, but no production path constructs one with real data today.
public struct GravitySample: Equatable, Codable, Sendable {
    public let ts: Int
    public let x: Double
    public let y: Double
    public let z: Double
    public let unit: String

    public init(ts: Int, x: Double, y: Double, z: Double, unit: String = "g") {
        self.ts = ts
        self.x = x
        self.y = y
        self.z = z
        self.unit = unit
    }
}

/// A batch of decoded biometric rows in transit: HealthKit → `Streams` → `CenitStore`
/// (persistence) / `CenitAnalytics` (computation).
///
/// Only `hr` and `rr` have a live write path today — `CenitStore.insert` maps them onto the
/// `hrSample`/`rrInterval` tables. `skinTemp`/`resp`/`gravity` are carried for the dormant
/// accelerometer/thermal engines (see the type docs above); they are not written or read by
/// any live table.
///
/// `Codable` is the compiler-synthesized default: nothing in this repo decodes or encodes a
/// `Streams` value as JSON (no fixture depends on a specific key layout), so there is no
/// contract to preserve beyond "round-trips with itself".
public struct Streams: Equatable, Codable, Sendable {
    public var hr: [HRSample]
    public var rr: [RRInterval]
    public var skinTemp: [SkinTempSample]
    public var resp: [RespSample]
    public var gravity: [GravitySample]

    public init(hr: [HRSample] = [], rr: [RRInterval] = [],
                skinTemp: [SkinTempSample] = [], resp: [RespSample] = [],
                gravity: [GravitySample] = []) {
        self.hr = hr
        self.rr = rr
        self.skinTemp = skinTemp
        self.resp = resp
        self.gravity = gravity
    }

    /// True only when every stream is empty.
    public var isEmpty: Bool {
        hr.isEmpty && rr.isEmpty && skinTemp.isEmpty && resp.isEmpty && gravity.isEmpty
    }
}
