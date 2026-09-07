import XCTest
import Foundation
import BiometricStreams
@testable import StrandAnalytics

// EffortPulseOracleTests.swift — the no-movement gate for the effort/pulse engines.
//
// WHY THIS EXISTS. Several numbers these engines produce are PERSISTED: the day's load, a strength
// session's load, the nightly RMSSD, a session's energy. They are also read back and compared against
// each other for weeks — moving averages, an acute:chronic ratio, personal baselines. A change that
// shifts them by half a percent does not «improve» anything: it silently rewrites what the person
// already saw, and bends every trend built on top.
//
// So `Resources/effort-pulse-oracle.json` records, for a fixed set of synthetic inputs, what these
// engines answered. This suite holds the current implementation to those answers.
//
// TOLERANCE. Every value is compared BIT FOR BIT: the fixture stores each `Double` as its shortest
// round-trippable decimal text, so a reload is exact and any difference at all is a real difference.
// If a future change legitimately needs a looser comparison, that is a decision to state out loud
// here — not a tolerance to widen quietly.
//
// The inputs live in `EffortPulseOracleInputs`, shared with the generator that first wrote the file,
// so the inputs cannot drift away from what was recorded.
final class EffortPulseOracleTests: XCTestCase {

    private var oracle: OracleTable!

    override func setUpWithError() throws {
        oracle = try OracleTable.load()
    }

    /// Compare one case against the fixture, bit for bit.
    private func expect(_ key: String, _ values: [String],
                        file: StaticString = #filePath, line: UInt = #line) {
        do {
            let recorded = try oracle.tokens(key)
            XCTAssertEqual(values, recorded, "oracle case \(key) moved", file: file, line: line)
        } catch {
            XCTFail("oracle case \(key) missing: \(error)", file: file, line: line)
        }
    }

    // MARK: - Zones

    func testZonesDidNotMove() {
        for p in OracleInputs.profiles {
            let set = p.maxHROverride.map { HRZones.zones(maxHR: $0) } ?? HRZones.zones(age: p.age)
            expect("zones.\(p.name).maxHR", [OracleText.of(set.maxHR)])
            expect("zones.\(p.name).source", [set.source])
            expect("zones.\(p.name).bounds", set.zones.flatMap {
                [OracleText.of($0.lower), OracleText.of($0.upper),
                 OracleText.of($0.lowerPct), OracleText.of($0.upperPct)]
            })
            expect("zones.\(p.name).zoneNumber", [40, 90, 100, 120, 140, 160, 180, 200, 260]
                .map { OracleText.of(set.zoneNumber(forBPM: Double($0))) })
            expect("zones.\(p.name).tanaka", [OracleText.of(HRZones.tanakaMaxHR(age: p.age))])
        }
    }

    func testTimeInZoneAndMedianSpacingDidNotMove() {
        let zoneSet = HRZones.zones(maxHR: 190)
        for (name, hr) in Self.sessions {
            let tiz = HRZones.timeInZone(hr, zoneSet: zoneSet)
            expect("timeInZone.\(name).seconds", tiz.seconds.map(OracleText.of))
            expect("timeInZone.\(name).belowZone1", [OracleText.of(tiz.belowZone1)])
            expect("timeInZone.\(name).total", [OracleText.of(tiz.total)])
            expect("medianInterval.\(name)",
                   [OracleText.of(HRZones.medianInterval(hr.sorted { $0.ts < $1.ts }))])
        }
    }

    // MARK: - Load
    //
    // `dailyMetric.strain` and `strengthSession.strain` are the two highest-risk stored numbers in
    // the package: they feed the acute and chronic moving averages, the ratio, the load band and
    // monotony. A drift here is not one wrong figure, it is a wrong history.

    func testStrainAndTrimpDidNotMove() {
        for (name, hr) in Self.sessions {
            expect("strain.\(name).hasEnoughData", [OracleText.of(StrainScorer.hasEnoughData(hr))])
            for method in [("edwards", StrainScorer.Method.edwards), ("banister", .banister)] {
                for sex in ["male", "female"] {
                    let s = StrainScorer.strain(hr, maxHR: 190, restingHR: 58,
                                                method: method.1, sex: sex)
                    expect("strain.\(name).\(method.0).\(sex)", [OracleText.of(s)])
                    expect("trimp.\(name).\(method.0).\(sex)",
                           [OracleText.of(s.map { StrainScorer.strainToTrimp($0) })])
                }
            }
            expect("strain.\(name).default", [OracleText.of(StrainScorer.strain(hr, maxHR: 190))])
            expect("strain.\(name).noMaxHR", [OracleText.of(StrainScorer.strain(hr))])
        }
    }

    func testStrengthSessionStrainDidNotMove() {
        let hr = Array(OracleInputs.sessionA().prefix(1200))
        expect("strengthSession.strain",
               [OracleText.of(StrainScorer.strain(hr, maxHR: 187, sex: "male"))])
    }

    func testCumulativeCurveDidNotMove() {
        for (name, hr) in Self.sessions {
            let curve = StrainScorer.cumulativeStrain(hr, bucketSeconds: 900, maxHR: 190, restingHR: 58)
            expect("curve.\(name).count", [OracleText.of(curve.count)])
            expect("curve.\(name).last", [OracleText.of(curve.last?.strain)])
            expect("curve.\(name).strains", curve.map { OracleText.of($0.strain) })
        }
    }

    func testScaleAndConstantsDidNotMove() {
        expect("trimpToStrain", [0, -5, 1, 50, 100, 500, 3600, 7200, 20000]
            .map { OracleText.of(StrainScorer.trimpToStrain(Double($0))) })
        expect("strainToTrimp", [0, -1, 1, 5, 10.91, 15, 21]
            .map { OracleText.of(StrainScorer.strainToTrimp($0)) })
        expect("tanakaHRmax", [20, 28, 33, 40, 45, 60]
            .map { OracleText.of(StrainScorer.tanakaHRmax(age: Double($0))) })
        expect("defaultMaxHR", [20, 30, 45].map { OracleText.of(StrainScorer.defaultMaxHR(age: $0)) })
        expect("constants", [
            OracleText.of(Double(StrainScorer.minReadings)),
            OracleText.of(Double(StrainScorer.minSparseReadings)),
            OracleText.of(Double(StrainScorer.minSpanSeconds)),
            OracleText.of(StrainScorer.maxStrain),
            OracleText.of(StrainScorer.strainDenominator),
            OracleText.of(Double(StrainScorer.defaultAge)),
            OracleText.of(StrainScorer.defaultRestingHR),
            OracleText.of(Double(StrainScorer.hrmaxMinSamples)),
            OracleText.of(StrainScorer.hrmaxPercentile),
            OracleText.of(StrainScorer.banisterScale),
            OracleText.of(StrainScorer.banisterBMen),
            OracleText.of(StrainScorer.banisterBWomen),
        ])
    }

    /// The three primitives `StrainScorerIncremental` reproduces from a bounded histogram. If any of
    /// them moves, the live fold and the batch curve start disagreeing without anything failing to
    /// compile.
    func testSharedPrimitivesDidNotMove() {
        expect("pctHRR", [40, 58, 60, 100, 150, 190, 220]
            .map { OracleText.of(StrainScorer.pctHRR(Double($0), restingHR: 58, hrReserve: 132)) })
        expect("zoneWeight", [40, 58, 60, 100, 124, 150, 176, 190, 220]
            .map { OracleText.of(Double(StrainScorer.zoneWeight(Double($0), restingHR: 58, hrReserve: 132))) })
        expect("pctHRR.degenerate", [
            OracleText.of(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: 0)),
            OracleText.of(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: -10)),
        ])
        expect("zoneWeight.degenerate", [
            OracleText.of(Double(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: 0))),
            OracleText.of(Double(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: -10))),
        ])
        expect("percentile", [0, 25, 50, 75, 99.5, 100]
            .map { OracleText.of(StrainScorer.percentile([10.0, 20, 30, 40, 55, 55, 70, 91], $0)) })
    }

    func testEstimatedMaxHRDidNotMove() {
        let history = Array(repeating: 120.0, count: 690) + Array(repeating: 195.0, count: 10)
        let long = StrainScorer.estimateHRmax(history, age: 30)
        expect("estimateHRmax.long", [OracleText.of(long.0), long.1])
        let short = StrainScorer.estimateHRmax([150, 160, 170], age: 30)
        expect("estimateHRmax.short", [OracleText.of(short.0), short.1])
        let bare = StrainScorer.estimateHRmax([150], age: nil)
        expect("estimateHRmax.bare", [OracleText.of(bare.0), bare.1])
    }

    // MARK: - Beat-to-beat
    //
    // `apple_rmssd_night` is produced from `rmssdSegmented`. Which pairs count decides which nights
    // exist at all, so a change here can reverse the direction of a trend already on screen.

    func testNightlyHRVDidNotMove() {
        for night in OracleInputs.allNights() {
            let raw = night.rr.map(Double.init)
            let r = HRVAnalyzer.analyze(rawRR: raw)
            expect("hrv.\(night.name).analyze", [
                OracleText.of(r.rmssd), OracleText.of(r.sdnn), OracleText.of(r.meanNN),
                OracleText.of(r.pnn50), OracleText.of(Double(r.nInput)), OracleText.of(Double(r.nClean)),
            ])
            expect("hrv.\(night.name).raw", [
                OracleText.of(HRVAnalyzer.rmssdRaw(raw)), OracleText.of(HRVAnalyzer.sdnnRaw(raw)),
            ])
            expect("hrv.\(night.name).cleanCount", [
                OracleText.of(Double(HRVAnalyzer.rangeFilter(raw).count)),
                OracleText.of(Double(HRVAnalyzer.cleanRR(raw).count)),
            ])
            expect("hrv.\(night.name).clean", HRVAnalyzer.cleanRR(raw).map(OracleText.of))
            expect("hrv.\(night.name).median", [OracleText.of(HRVAnalyzer.median(raw))])

            let seg = HRVAnalyzer.rmssdSegmented(OracleInputs.timedNight(night.rr))
            expect("hrv.\(night.name).segmented",
                   [OracleText.of(seg.rmssd), OracleText.of(Double(seg.nPairs))])
            let loose = HRVAnalyzer.rmssdSegmented(OracleInputs.timedNight(night.rr),
                                                   gapSeconds: 5, deltaFraction: 0.30)
            expect("hrv.\(night.name).segmentedLoose",
                   [OracleText.of(loose.rmssd), OracleText.of(Double(loose.nPairs))])
        }
    }

    func testWindowedHRVAndConstantsDidNotMove() {
        let rows1 = OracleInputs.night1().enumerated()
            .map { RRInterval(ts: 1_000 + $0.offset, rrMs: $0.element) }
        let rows2 = OracleInputs.night2().enumerated()
            .map { RRInterval(ts: 9_000 + $0.offset, rrMs: $0.element) }
        let w = HRVAnalyzer.analyze(rows1 + rows2, windowStart: 1_000, windowEnd: 1_200)
        expect("hrv.windowed", [
            OracleText.of(w.rmssd), OracleText.of(w.sdnn), OracleText.of(w.meanNN),
            OracleText.of(w.pnn50), OracleText.of(Double(w.nInput)), OracleText.of(Double(w.nClean)),
        ])
        expect("hrv.constants", [
            OracleText.of(HRVAnalyzer.rrMinMs), OracleText.of(HRVAnalyzer.rrMaxMs),
            OracleText.of(Double(HRVAnalyzer.minBeats)), OracleText.of(HRVAnalyzer.ectopicThreshold),
            OracleText.of(Double(HRVAnalyzer.ectopicWindowRadius)),
            OracleText.of(HRVAnalyzer.maxSuccessiveDeltaFraction),
        ])
    }

    // MARK: - Nocturnal resting heart rate

    func testRestingHeartRateDidNotMove() {
        let night = OracleInputs.restingNight()
        expect("restingHR.full", [OracleText.of(RecoveryScorer.restingHR(
            night, start: night[0].ts, end: night[night.count - 1].ts))])
        expect("restingHR.firstHalf", [OracleText.of(RecoveryScorer.restingHR(
            night, start: night[0].ts, end: night[0].ts + 5399))])
        expect("restingHR.empty", [OracleText.of(RecoveryScorer.restingHR([], start: 0, end: 1000))])
        expect("restingHR.constants", [
            OracleText.of(Double(RecoveryScorer.restingHRWindowS)),
            OracleText.of(Double(RecoveryScorer.restingHRMinBinSamples)),
            OracleText.of(RecoveryScorer.restingHRMinBpm),
        ])
    }

    // MARK: - Energy
    //
    // A strength session's energy is mirrored into Apple Health as active energy, so it is what the
    // move ring credits. Moving it changes a figure the person's own health data already carries.

    func testEnergyDidNotMove() {
        for body in OracleInputs.bodies {
            for (name, hr) in Self.sessions {
                let bout = Calories.estimateBoutCalories(hr, profile: body.profile,
                                                         hrmax: 190, restingHR: 58)
                expect("energy.\(body.name).\(name).bout",
                       [OracleText.of(bout.0), OracleText.of(bout.1)])
                expect("energy.\(body.name).\(name).day",
                       [OracleText.of(Calories.estimateDayCalories(hr, profile: body.profile,
                                                                   hrmax: 190, restingHR: 58))])
            }
            expect("energy.\(body.name).met", [600.0, 2700, 3600, 0, -500, 36_000]
                .map { OracleText.of(Calories.estimateStrengthCalories(durationSeconds: $0,
                                                                       profile: body.profile)) })
            expect("energy.\(body.name).selector", [
                OracleText.of(Calories.estimateStrengthEnergy(hrSamples: [], durationSeconds: 2700,
                                                              profile: body.profile, hrMax: 190)),
                OracleText.of(Calories.estimateStrengthEnergy(
                    hrSamples: [HRSample(ts: 0, bpm: 120)], durationSeconds: 2700,
                    profile: body.profile, hrMax: 190)),
                OracleText.of(Calories.estimateStrengthEnergy(
                    hrSamples: Array(OracleInputs.sessionA().prefix(2700)), durationSeconds: 2700,
                    profile: body.profile, hrMax: 190, restingHR: 58)),
            ])
        }
        expect("energy.empty", [
            OracleText.of(Calories.estimateDayCalories([], profile: OracleInputs.bodies[0].profile,
                                                       hrmax: 190, restingHR: 58)),
            OracleText.of(Double(Calories.strengthEnergyMinSamples)),
        ])
    }

    // MARK: - The stage JSON on disk

    /// The stored text must stay READABLE, which is the property that actually matters — key ORDER
    /// inside each object is not stable run to run (the encoder does not promise one), so the fixture's
    /// recorded string is compared by what it decodes to, not by its bytes.
    func testStageJSONStillDecodesToTheRecordedTimeline() throws {
        let stages = [StageSegment(start: 100, end: 200, stage: "light"),
                      StageSegment(start: 200, end: 260, stage: "deep"),
                      StageSegment(start: 260, end: 300, stage: "rem"),
                      StageSegment(start: 300, end: 320, stage: "wake")]
        let recorded = try XCTUnwrap(oracle.tokens("stagesJSON").first)
        XCTAssertEqual(AnalyticsEngine.decodeStages(recorded), stages,
                       "the text recorded before the rewrite must still decode")
        let now = try XCTUnwrap(AnalyticsEngine.encodeStages(stages))
        XCTAssertEqual(AnalyticsEngine.decodeStages(now), AnalyticsEngine.decodeStages(recorded),
                       "what is written now must mean the same as what was written then")
    }

    // MARK: - Shared inputs

    private static let sessions: [(String, [HRSample])] = [
        ("sessionA", OracleInputs.sessionA()),
        ("sessionB", OracleInputs.sessionB()),
        ("sessionC", OracleInputs.sessionC()),
    ]
}
