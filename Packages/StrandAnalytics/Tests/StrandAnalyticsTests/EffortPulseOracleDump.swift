import XCTest
import Foundation
import BiometricStreams
@testable import StrandAnalytics

// EffortPulseOracleDump.swift — TEMPORARY. Writes `Resources/effort-pulse-oracle.json` by running
// the effort/pulse engines over `OracleInputs` and recording what they answer.
//
// It exists for one run: it captures the answers BEFORE the engines are re-authored, so the new
// implementation can be held to them. Delete this file once the fixture is committed; the fixture
// itself, and `EffortPulseOracleTests`, are what stay.
//
// Run with:  swift test --filter EffortPulseOracleDump

final class EffortPulseOracleDump: XCTestCase {

    /// Set to `true` to regenerate the fixture. Off by default so a normal `swift test` never
    /// rewrites the very file it is supposed to be checked against.
    private let enabled = ProcessInfo.processInfo.environment["ORACLE_DUMP"] == "1"

    func testWriteFixture() throws {
        try XCTSkipUnless(enabled, "set ORACLE_DUMP=1 to regenerate the fixture")

        var rows: [String: [String]] = [:]
        func put(_ key: String, _ values: [String]) {
            XCTAssertNil(rows[key], "duplicate oracle key \(key)")
            rows[key] = values
        }

        // MARK: Zones

        for p in OracleInputs.profiles {
            let set = p.maxHROverride.map { HRZones.zones(maxHR: $0) }
                ?? HRZones.zones(age: p.age)
            put("zones.\(p.name).maxHR", [OracleText.of(set.maxHR)])
            put("zones.\(p.name).source", [set.source])
            put("zones.\(p.name).bounds", set.zones.flatMap {
                [OracleText.of($0.lower), OracleText.of($0.upper),
                 OracleText.of($0.lowerPct), OracleText.of($0.upperPct)]
            })
            put("zones.\(p.name).zoneNumber", [40, 90, 100, 120, 140, 160, 180, 200, 260]
                .map { OracleText.of(set.zoneNumber(forBPM: Double($0))) })
            put("zones.\(p.name).tanaka", [OracleText.of(HRZones.tanakaMaxHR(age: p.age))])
        }

        // MARK: Time in zone + median spacing

        let sessions: [(String, [HRSample])] = [
            ("sessionA", OracleInputs.sessionA()),
            ("sessionB", OracleInputs.sessionB()),
            ("sessionC", OracleInputs.sessionC()),
        ]
        let zoneSet = HRZones.zones(maxHR: 190)
        for (name, hr) in sessions {
            let tiz = HRZones.timeInZone(hr, zoneSet: zoneSet)
            put("timeInZone.\(name).seconds", tiz.seconds.map(OracleText.of))
            put("timeInZone.\(name).belowZone1", [OracleText.of(tiz.belowZone1)])
            put("timeInZone.\(name).total", [OracleText.of(tiz.total)])
            put("medianInterval.\(name)", [OracleText.of(HRZones.medianInterval(hr.sorted { $0.ts < $1.ts }))])
        }

        // MARK: Strain, TRIMP and the cumulative curve

        for (name, hr) in sessions {
            put("strain.\(name).hasEnoughData", [OracleText.of(StrainScorer.hasEnoughData(hr))])
            for method in [("edwards", StrainScorer.Method.edwards), ("banister", .banister)] {
                for sex in ["male", "female"] {
                    let s = StrainScorer.strain(hr, maxHR: 190, restingHR: 58,
                                                method: method.1, sex: sex)
                    put("strain.\(name).\(method.0).\(sex)", [OracleText.of(s)])
                    put("trimp.\(name).\(method.0).\(sex)",
                        [OracleText.of(s.map { StrainScorer.strainToTrimp($0) })])
                }
            }
            // The default-parameter call is the one `AppleLoadEstimator` and `SourceFusion` make.
            put("strain.\(name).default",
                [OracleText.of(StrainScorer.strain(hr, maxHR: 190))])
            put("strain.\(name).noMaxHR", [OracleText.of(StrainScorer.strain(hr))])
            let curve = StrainScorer.cumulativeStrain(hr, bucketSeconds: 900, maxHR: 190, restingHR: 58)
            put("curve.\(name).count", [OracleText.of(curve.count)])
            put("curve.\(name).last", [OracleText.of(curve.last?.strain)])
            put("curve.\(name).strains", curve.map { OracleText.of($0.strain) })
        }

        // A strength session: the shape `AppModel+Strength.resolveStrengthLoad` scores.
        let strengthHR = Array(OracleInputs.sessionA().prefix(1200))
        put("strengthSession.strain",
            [OracleText.of(StrainScorer.strain(strengthHR, maxHR: 187, sex: "male"))])

        // MARK: The strain scale itself

        put("trimpToStrain", [0, -5, 1, 50, 100, 500, 3600, 7200, 20000]
            .map { OracleText.of(StrainScorer.trimpToStrain(Double($0))) })
        put("strainToTrimp", [0, -1, 1, 5, 10.91, 15, 21]
            .map { OracleText.of(StrainScorer.strainToTrimp($0)) })
        put("tanakaHRmax", [20, 28, 33, 40, 45, 60]
            .map { OracleText.of(StrainScorer.tanakaHRmax(age: Double($0))) })
        put("defaultMaxHR", [20, 30, 45].map { OracleText.of(StrainScorer.defaultMaxHR(age: $0)) })
        put("constants", [
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

        // MARK: The internal primitives that `StrainScorerIncremental` reproduces

        put("pctHRR", [40, 58, 60, 100, 150, 190, 220]
            .map { OracleText.of(StrainScorer.pctHRR(Double($0), restingHR: 58, hrReserve: 132)) })
        put("zoneWeight", [40, 58, 60, 100, 124, 150, 176, 190, 220]
            .map { OracleText.of(Double(StrainScorer.zoneWeight(Double($0), restingHR: 58, hrReserve: 132))) })
        put("pctHRR.degenerate", [
            OracleText.of(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: 0)),
            OracleText.of(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: -10)),
        ])
        put("zoneWeight.degenerate", [
            OracleText.of(Double(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: 0))),
            OracleText.of(Double(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: -10))),
        ])
        let sorted = [10.0, 20, 30, 40, 55, 55, 70, 91]
        put("percentile", [0, 25, 50, 75, 99.5, 100]
            .map { OracleText.of(StrainScorer.percentile(sorted, $0)) })

        // MARK: Estimated max HR

        let history = Array(repeating: 120.0, count: 690) + Array(repeating: 195.0, count: 10)
        let est = StrainScorer.estimateHRmax(history, age: 30)
        put("estimateHRmax.long", [OracleText.of(est.0), est.1])
        let short = StrainScorer.estimateHRmax([150, 160, 170], age: 30)
        put("estimateHRmax.short", [OracleText.of(short.0), short.1])
        let bare = StrainScorer.estimateHRmax([150], age: nil)
        put("estimateHRmax.bare", [OracleText.of(bare.0), bare.1])

        // MARK: Beat-to-beat indices

        for night in OracleInputs.allNights() {
            let raw = night.rr.map(Double.init)
            let r = HRVAnalyzer.analyze(rawRR: raw)
            put("hrv.\(night.name).analyze", [
                OracleText.of(r.rmssd), OracleText.of(r.sdnn), OracleText.of(r.meanNN),
                OracleText.of(r.pnn50), OracleText.of(Double(r.nInput)), OracleText.of(Double(r.nClean)),
            ])
            put("hrv.\(night.name).raw", [
                OracleText.of(HRVAnalyzer.rmssdRaw(raw)), OracleText.of(HRVAnalyzer.sdnnRaw(raw)),
            ])
            put("hrv.\(night.name).cleanCount", [
                OracleText.of(Double(HRVAnalyzer.rangeFilter(raw).count)),
                OracleText.of(Double(HRVAnalyzer.cleanRR(raw).count)),
            ])
            put("hrv.\(night.name).clean", HRVAnalyzer.cleanRR(raw).map(OracleText.of))
            put("hrv.\(night.name).median", [OracleText.of(HRVAnalyzer.median(raw))])

            // The persisted nocturnal value: segmented RMSSD over stamped beats.
            let seg = HRVAnalyzer.rmssdSegmented(OracleInputs.timedNight(night.rr))
            put("hrv.\(night.name).segmented",
                [OracleText.of(seg.rmssd), OracleText.of(Double(seg.nPairs))])
            let seg5 = HRVAnalyzer.rmssdSegmented(OracleInputs.timedNight(night.rr),
                                                  gapSeconds: 5, deltaFraction: 0.30)
            put("hrv.\(night.name).segmentedLoose",
                [OracleText.of(seg5.rmssd), OracleText.of(Double(seg5.nPairs))])
        }

        // The windowed entry point, over rows that carry their own stamps.
        let rows1 = OracleInputs.night1().enumerated().map { RRInterval(ts: 1_000 + $0.offset, rrMs: $0.element) }
        let rows2 = OracleInputs.night2().enumerated().map { RRInterval(ts: 9_000 + $0.offset, rrMs: $0.element) }
        let windowed = HRVAnalyzer.analyze(rows1 + rows2, windowStart: 1_000, windowEnd: 1_200)
        put("hrv.windowed", [
            OracleText.of(windowed.rmssd), OracleText.of(windowed.sdnn), OracleText.of(windowed.meanNN),
            OracleText.of(windowed.pnn50), OracleText.of(Double(windowed.nInput)),
            OracleText.of(Double(windowed.nClean)),
        ])
        put("hrv.constants", [
            OracleText.of(HRVAnalyzer.rrMinMs), OracleText.of(HRVAnalyzer.rrMaxMs),
            OracleText.of(Double(HRVAnalyzer.minBeats)), OracleText.of(HRVAnalyzer.ectopicThreshold),
            OracleText.of(Double(HRVAnalyzer.ectopicWindowRadius)),
            OracleText.of(HRVAnalyzer.maxSuccessiveDeltaFraction),
        ])

        // MARK: Nocturnal resting heart rate and its bands

        let night = OracleInputs.restingNight()
        put("restingHR.full", [OracleText.of(RecoveryScorer.restingHR(night, start: night[0].ts,
                                                                     end: night[night.count - 1].ts))])
        put("restingHR.firstHalf", [OracleText.of(RecoveryScorer.restingHR(night, start: night[0].ts,
                                                                          end: night[0].ts + 5399))])
        put("restingHR.empty", [OracleText.of(RecoveryScorer.restingHR([], start: 0, end: 1000))])
        put("restingHR.constants", [
            OracleText.of(Double(RecoveryScorer.restingHRWindowS)),
            OracleText.of(Double(RecoveryScorer.restingHRMinBinSamples)),
            OracleText.of(RecoveryScorer.restingHRMinBpm),
        ])
        put("band", [0, 20, 33.9, 34, 50, 66.9, 67, 90, 100].map { RecoveryScorer.band($0) })
        put("band.cuts", [OracleText.of(RecoveryScorer.bandRedMax),
                          OracleText.of(RecoveryScorer.bandYellowMax)])

        // MARK: Energy

        for body in OracleInputs.bodies {
            for (name, hr) in sessions {
                let bout = Calories.estimateBoutCalories(hr, profile: body.profile,
                                                         hrmax: 190, restingHR: 58)
                put("energy.\(body.name).\(name).bout",
                    [OracleText.of(bout.0), OracleText.of(bout.1)])
                put("energy.\(body.name).\(name).day",
                    [OracleText.of(Calories.estimateDayCalories(hr, profile: body.profile,
                                                                hrmax: 190, restingHR: 58))])
            }
            put("energy.\(body.name).met", [600.0, 2700, 3600, 0, -500, 36_000]
                .map { OracleText.of(Calories.estimateStrengthCalories(durationSeconds: $0,
                                                                       profile: body.profile)) })
            put("energy.\(body.name).selector", [
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
        put("energy.empty", [
            OracleText.of(Calories.estimateDayCalories([], profile: OracleInputs.bodies[0].profile,
                                                       hrmax: 190, restingHR: 58)),
            OracleText.of(Double(Calories.strengthEnergyMinSamples)),
        ])

        // MARK: The stage-segment JSON on disk

        let stages = [StageSegment(start: 100, end: 200, stage: "light"),
                      StageSegment(start: 200, end: 260, stage: "deep"),
                      StageSegment(start: 260, end: 300, stage: "rem"),
                      StageSegment(start: 300, end: 320, stage: "wake")]
        put("stagesJSON", [OracleText.of(AnalyticsEngine.encodeStages(stages))])

        // MARK: Write

        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(rows)
        try data.write(to: dir.appendingPathComponent("effort-pulse-oracle.json"))
        print("oracle rows: \(rows.count)")
    }
}
