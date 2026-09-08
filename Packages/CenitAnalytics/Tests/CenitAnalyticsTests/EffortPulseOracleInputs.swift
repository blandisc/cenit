import Foundation
import BiometricStreams
@testable import CenitAnalytics

// EffortPulseOracleInputs.swift — the synthetic inputs behind `effort-pulse-oracle.json`.
//
// The fixture is a NO-MOVEMENT harness: it pins what the effort/pulse engines answered for a fixed
// set of inputs, so a re-authored implementation can prove it did not shift a single persisted
// number (`dailyMetric.strain`, `strengthSession.strain`, `apple_rmssd_night`, session energy).
//
// Every series here is built from INTEGER arithmetic with a deterministic linear congruential
// generator, so the inputs are byte-identical on every machine and every run: no `Date()`, no
// `random()`, no floating-point accumulation on the input side. The generator that first wrote the
// fixture and the test that now reads it build their inputs through THIS file, so a drift in the
// inputs is impossible by construction.

// MARK: - Deterministic integer noise

/// Linear congruential generator (Numerical Recipes parameters). Integer-only, so the series it
/// builds are exactly reproducible across platforms and Swift versions.
struct OracleLCG {
    private var state: UInt32
    init(seed: UInt32) { state = seed }

    /// Next value in `0..<bound`.
    mutating func next(_ bound: Int) -> Int {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Int(state >> 16) % bound
    }
}

// MARK: - Heart-rate series

enum OracleInputs {

    /// Session A — interval work: three 300 s blocks at an easy pulse alternating with three at a
    /// hard one, sampled once a second. Crosses every zone edge and both sufficiency branches.
    static func sessionA() -> [HRSample] {
        var out: [HRSample] = []
        var ts = 1_700_000_000
        for block in 0..<6 {
            let bpm = block % 2 == 0 ? 95 : 165
            for _ in 0..<300 {
                out.append(HRSample(ts: ts, bpm: bpm))
                ts += 1
            }
        }
        return out
    }

    /// Session B — a low-cadence source: 60 readings 30 s apart, ramping 130 → 159 bpm. Exercises
    /// the sparse sufficiency branch and a median spacing that is not one second.
    static func sessionB() -> [HRSample] {
        var out: [HRSample] = []
        var ts = 1_700_100_000
        for i in 0..<60 {
            out.append(HRSample(ts: ts, bpm: 130 + i / 2))
            ts += 30
        }
        return out
    }

    /// Session C — a whole day at one reading a minute, an integer triangle wave between 55 and
    /// 135 bpm plus bounded integer noise. The shape a fused Apple day has.
    static func sessionC() -> [HRSample] {
        var rng = OracleLCG(seed: 20_260_387)
        var out: [HRSample] = []
        var ts = 1_700_200_000
        for i in 0..<1440 {
            let phase = i % 240
            let triangle = phase < 120 ? phase : 240 - phase
            let bpm = 55 + (triangle * 80) / 120 + rng.next(5) - 2
            out.append(HRSample(ts: ts, bpm: bpm))
            ts += 60
        }
        return out
    }

    /// A night of heart rate for the resting-HR estimator: 90 min at 62 bpm, then 90 min at 51,
    /// then 30 min of a sensor dropout (three lone samples), at one reading a second.
    static func restingNight() -> [HRSample] {
        var out: [HRSample] = []
        var ts = 1_700_300_000
        for _ in 0..<5400 { out.append(HRSample(ts: ts, bpm: 62)); ts += 1 }
        for _ in 0..<5400 { out.append(HRSample(ts: ts, bpm: 51)); ts += 1 }
        for _ in 0..<3 { out.append(HRSample(ts: ts, bpm: 38)); ts += 600 }
        return out
    }

    // MARK: - Beat-to-beat series

    /// Night 1 — clean, ~60 bpm with a respiratory modulation of ±40 ms over a 12-beat cycle.
    static func night1() -> [Int] {
        (0..<400).map { i in
            let cycle = i % 12
            let swing = cycle < 6 ? cycle : 12 - cycle
            return 980 + swing * 8
        }
    }

    /// Night 2 — clean and bradycardic (~50 bpm), the case a relative artifact rule must not punish.
    static func night2() -> [Int] {
        (0..<400).map { i in
            let cycle = i % 10
            let swing = cycle < 5 ? cycle : 10 - cycle
            return 1180 + swing * 12
        }
    }

    /// Night 3 — night 1 with an ectopic beat every 37 intervals (a compensatory long beat).
    static func night3() -> [Int] {
        var v = night1()
        for i in stride(from: 37, to: v.count, by: 37) { v[i] = 1520 }
        return v
    }

    /// Night 4 — night 1 with dropouts: implausibly short and implausibly long intervals that the
    /// range filter must remove before any index is computed.
    static func night4() -> [Int] {
        var v = night1()
        for i in stride(from: 23, to: v.count, by: 23) { v[i] = i % 46 == 0 ? 250 : 2400 }
        return v
    }

    /// Night 5 — a sparse, dirty tail: 60 intervals with bounded noise, right at the density floor.
    static func night5() -> [Int] {
        var rng = OracleLCG(seed: 385_385)
        return (0..<60).map { _ in 900 + rng.next(200) }
    }

    static func allNights() -> [(name: String, rr: [Int])] {
        [("night1", night1()), ("night2", night2()), ("night3", night3()),
         ("night4", night4()), ("night5", night5())]
    }

    /// A night's intervals carried with their own wall-clock stamps, the shape the segmented RMSSD
    /// consumes: each beat lands one interval after the previous one, and every 50th beat opens a
    /// 30 s recording gap that the pairing rule must refuse to bridge.
    static func timedNight(_ rr: [Int], start: Double = 1_700_400_000) -> [TimedNN] {
        var out: [TimedNN] = []
        var t = start
        for (i, ms) in rr.enumerated() {
            if i > 0 && i % 50 == 0 { t += 30 }
            t += Double(ms) / 1000.0
            out.append(TimedNN(ts: t, nnMs: Double(ms)))
        }
        return out
    }

    // MARK: - Profiles

    /// Three bodies: a young one, an older one, and one whose max HR was measured, not estimated.
    static let profiles: [(name: String, age: Double, maxHROverride: Double?)] = [
        ("age28", 28, nil), ("age45", 45, nil), ("measured195", 33, 195),
    ]

    /// Three bodies for the energy equations, one per coefficient set.
    static let bodies: [(name: String, profile: UserProfile)] = [
        ("male80", UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")),
        ("female62", UserProfile(weightKg: 62, heightCm: 165, age: 29, sex: "female")),
        ("unspecified70", UserProfile(weightKg: 70, heightCm: 172, age: 41, sex: "nonbinary")),
    ]
}

// MARK: - The fixture table

/// The recorded answers, keyed by case name. Values are kept as the shortest round-trippable
/// decimal text of each `Double`, so a reload is bit-identical to what was written — a JSON number
/// would go through a formatter and could lose the last bits.
struct OracleTable {
    private let rows: [String: [String]]

    /// Marker for an engine that honestly answered "no measurement".
    static let none = "nil"

    init(rows: [String: [String]]) { self.rows = rows }

    /// Loads the fixture that ships with the test bundle.
    static func load() throws -> OracleTable {
        guard let url = Bundle.module.url(forResource: "effort-pulse-oracle", withExtension: "json") else {
            throw OracleError.missingFixture
        }
        let data = try Data(contentsOf: url)
        let rows = try JSONDecoder().decode([String: [String]].self, from: data)
        return OracleTable(rows: rows)
    }

    enum OracleError: Error { case missingFixture, missingKey(String) }

    var keys: [String] { rows.keys.sorted() }

    func tokens(_ key: String) throws -> [String] {
        guard let v = rows[key] else { throw OracleError.missingKey(key) }
        return v
    }

    /// The recorded doubles for a case; `nil` entries come back as `nil`.
    func doubles(_ key: String) throws -> [Double?] {
        try tokens(key).map { $0 == Self.none ? nil : Double($0) }
    }

    /// The single recorded double for a case.
    func double(_ key: String) throws -> Double? {
        try doubles(key).first ?? nil
    }
}

/// Renders a value the way the fixture stores it.
enum OracleText {
    static func of(_ v: Double?) -> String { v.map { String($0) } ?? OracleTable.none }
    static func of(_ v: Int?) -> String { v.map { String($0) } ?? OracleTable.none }
    static func of(_ v: String?) -> String { v ?? OracleTable.none }
    static func of(_ v: Bool) -> String { v ? "true" : "false" }
}
