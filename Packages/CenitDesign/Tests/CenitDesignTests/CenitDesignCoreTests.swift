import XCTest
import SwiftUI
@testable import CenitDesign

/// Coverage for the reimplemented core tokens/toolkit (FER-395): `Color(hex:)`, `StrandPalette`'s
/// gradient sampling, `SleepInterval`, the chart-scrub geometry toolkit, and the small pure statics on
/// `TrendChart`/`Sparkline`.
final class CenitDesignCoreTests: XCTestCase {

    // MARK: - CenitDesign

    func testVersionStringIsSet() {
        XCTAssertFalse(CenitDesign.version.isEmpty)
    }

    // MARK: - Color(hex:)

    func testSixDigitHexReadsAsOpaqueRGB() {
        let parsed = Color(hex: "#7F3C99").rgbaComponents
        XCTAssertEqual(parsed.r, 0x7F / 255.0, accuracy: 0.01)
        XCTAssertEqual(parsed.g, 0x3C / 255.0, accuracy: 0.01)
        XCTAssertEqual(parsed.b, 0x99 / 255.0, accuracy: 0.01)
        XCTAssertEqual(parsed.a, 1.0, accuracy: 0.001)
    }

    func testEightDigitHexTrailingByteIsAlpha() {
        let parsed = Color(hex: "AABBCC80").rgbaComponents
        XCTAssertEqual(parsed.r, 0xAA / 255.0, accuracy: 0.01)
        XCTAssertEqual(parsed.g, 0xBB / 255.0, accuracy: 0.01)
        XCTAssertEqual(parsed.b, 0xCC / 255.0, accuracy: 0.01)
        XCTAssertEqual(parsed.a, 0x80 / 255.0, accuracy: 0.01)
    }

    /// Leading/trailing punctuation (a "#", surrounding whitespace) is trimmed before parsing, so a
    /// literal with or without the hash reads identically.
    func testLeadingHashDoesNotChangeTheParsedColor() {
        let withHash = Color(hex: "#00FF00").rgbaComponents
        let bare = Color(hex: "00FF00").rgbaComponents
        XCTAssertEqual(withHash.g, bare.g, accuracy: 0.001)
        XCTAssertEqual(withHash.r, bare.r, accuracy: 0.001)
    }

    // MARK: - StrandPalette gradients

    func testRecoveryGradientHasFiveOrderedStops() {
        let stops = StrandPalette.recoveryStops
        XCTAssertEqual(stops.count, 5)
        XCTAssertEqual(stops.map(\.location), stops.map(\.location).sorted())
        XCTAssertEqual(stops.first?.location, 0.0)
        XCTAssertEqual(stops.last?.location, 1.0)
    }

    func testRecoveryColorMatchesRampEndpointsExactly() {
        let atZero = StrandPalette.recoveryColor(0).rgbaComponents
        let rampStart = StrandPalette.recovery000.rgbaComponents
        XCTAssertEqual(atZero.r, rampStart.r, accuracy: 0.02)
        XCTAssertEqual(atZero.g, rampStart.g, accuracy: 0.02)

        let atHundred = StrandPalette.recoveryColor(100).rgbaComponents
        let rampEnd = StrandPalette.recovery100.rgbaComponents
        XCTAssertEqual(atHundred.b, rampEnd.b, accuracy: 0.02)
    }

    func testRecoveryColorOutOfDomainClampsRatherThanExtrapolates() {
        let farBelow = StrandPalette.recoveryColor(-1_000).rgbaComponents
        let atFloor = StrandPalette.recoveryColor(0).rgbaComponents
        XCTAssertEqual(farBelow.r, atFloor.r, accuracy: 0.001)

        let farAbove = StrandPalette.recoveryColor(9_999).rgbaComponents
        let atCeiling = StrandPalette.recoveryColor(100).rgbaComponents
        XCTAssertEqual(farAbove.g, atCeiling.g, accuracy: 0.001)
    }

    /// Each threshold checked one below its upper bound, since the mapping is a half-open ladder.
    func testRecoveryStateLadderThresholds() {
        XCTAssertEqual(StrandPalette.recoveryState(24.9), "DEPLETED")
        XCTAssertEqual(StrandPalette.recoveryState(49.9), "LOW")
        XCTAssertEqual(StrandPalette.recoveryState(69.9), "MODERATE")
        XCTAssertEqual(StrandPalette.recoveryState(87.9), "PRIMED")
        XCTAssertEqual(StrandPalette.recoveryState(88.0), "PEAK")
    }

    func testStrainColorAtRampEndpoints() {
        let floor = StrandPalette.strainColor(0).rgbaComponents
        let ramp0 = StrandPalette.strain000.rgbaComponents
        XCTAssertEqual(floor.r, ramp0.r, accuracy: 0.02)

        let ceiling = StrandPalette.strainColor(21).rgbaComponents
        let ramp100 = StrandPalette.strain100.rgbaComponents
        XCTAssertEqual(ceiling.b, ramp100.b, accuracy: 0.02)
    }

    func testHRZoneColorIndexingAndClamp() {
        let zone2 = StrandPalette.hrZoneColor(2).rgbaComponents
        let expected2 = StrandPalette.zone2.rgbaComponents
        XCTAssertEqual(zone2.g, expected2.g, accuracy: 0.001)

        let clampedHigh = StrandPalette.hrZoneColor(42).rgbaComponents
        let zone5 = StrandPalette.zone5.rgbaComponents
        XCTAssertEqual(clampedHigh.r, zone5.r, accuracy: 0.001)

        let clampedLow = StrandPalette.hrZoneColor(-3).rgbaComponents
        let zone1 = StrandPalette.zone1.rgbaComponents
        XCTAssertEqual(clampedLow.b, zone1.b, accuracy: 0.001)
    }

    func testSleepStageColorRoutesEachCase() {
        for stage in SleepStage.allCases {
            let mapped = StrandPalette.sleepStageColor(stage).rgbaComponents
            let direct: (r: Double, g: Double, b: Double, a: Double)
            switch stage {
            case .awake: direct = StrandPalette.sleepAwake.rgbaComponents
            case .light: direct = StrandPalette.sleepLight.rgbaComponents
            case .deep:  direct = StrandPalette.sleepDeep.rgbaComponents
            case .rem:   direct = StrandPalette.sleepREM.rgbaComponents
            }
            XCTAssertEqual(mapped.r, direct.r, accuracy: 0.001, "\(stage)")
        }
    }

    func testGradientSampleInterpolatesLinearly() {
        let twoToneRamp: [Gradient.Stop] = [
            .init(color: Color(hex: "#101010"), location: 0),
            .init(color: Color(hex: "#F0F0F0"), location: 1),
        ]
        let lowEnd = 0x10 / 255.0, highEnd = 0xF0 / 255.0
        let quarter = StrandPalette.sample(stops: twoToneRamp, at: 0.25).rgbaComponents
        XCTAssertEqual(quarter.r, lowEnd + (highEnd - lowEnd) * 0.25, accuracy: 0.03)
        let threeQuarters = StrandPalette.sample(stops: twoToneRamp, at: 0.75).rgbaComponents
        XCTAssertEqual(threeQuarters.r, lowEnd + (highEnd - lowEnd) * 0.75, accuracy: 0.03)
    }

    func testGradientSampleDegenerateCases() {
        XCTAssertEqual(StrandPalette.sample(stops: [], at: 0.5).rgbaComponents.a, 0, accuracy: 0.001)
        let singleStop: [Gradient.Stop] = [.init(color: Color(hex: "#334455"), location: 0.5)]
        let sampled = StrandPalette.sample(stops: singleStop, at: 0.1).rgbaComponents
        let literal = Color(hex: "#334455").rgbaComponents
        XCTAssertEqual(sampled.g, literal.g, accuracy: 0.001)
    }

    // MARK: - SleepInterval

    func testSleepIntervalDurationIsElapsedSeconds() {
        let interval = SleepInterval(stage: .light, start: 200, end: 950)
        XCTAssertEqual(interval.duration, 750, accuracy: 0.001)
    }

    func testSleepIntervalDurationFloorsAtZeroForAReversedPair() {
        let backwards = SleepInterval(stage: .rem, start: 900, end: 300)
        XCTAssertEqual(backwards.duration, 0, accuracy: 0.001)
    }

    // MARK: - StrandTone

    func testStrandToneColorsMatchTheirPaletteSource() {
        XCTAssertEqual(StrandTone.warning.color.rgbaComponents.r,
                       StrandPalette.statusWarning.rgbaComponents.r, accuracy: 0.001)
        XCTAssertEqual(StrandTone.accent.color.rgbaComponents.g,
                       StrandPalette.accent.rgbaComponents.g, accuracy: 0.001)
    }

    // MARK: - Chart scrub toolkit — nearest-index

    func testNearestIndexAcrossEvenlySpacedSamples() {
        // 9 samples across width 80 → pitch 10.
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 0, count: 9, width: 80), 0)
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 14, count: 9, width: 80), 1)
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 44, count: 9, width: 80), 4)
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 80, count: 9, width: 80), 8)
    }

    func testNearestIndexClampsBeyondEitherEdge() {
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: -200, count: 9, width: 80), 0)
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 5_000, count: 9, width: 80), 8)
    }

    func testNearestIndexDegenerateSampleCounts() {
        XCTAssertNil(ChartScrubMath.nearestIndex(toX: 5, count: 0, width: 80))
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 999, count: 1, width: 80), 0)
    }

    func testNearestIndexAmongArbitraryPositions() {
        let xs: [CGFloat] = [-10, 20, 55, 120, 300]
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: -5, xs: xs), 0)     // closest to -10
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 40, xs: xs), 2)    // 15 away from 55 beats 20 away from 20
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 90, xs: xs), 3)    // 30 away from 120 beats 35 away from 55
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 200, xs: xs), 3)
        XCTAssertEqual(ChartScrubMath.nearestIndex(toX: 1_000, xs: xs), 4)
        XCTAssertNil(ChartScrubMath.nearestIndex(toX: 0, xs: []))
    }

    // MARK: - Chart scrub toolkit — tooltip placement

    func testTooltipPositionClampsAtEveryCorner() {
        let box = CGSize(width: 200, height: 120)
        let card = CGSize(width: 70, height: 30)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 0, y: 120), CGPoint(x: 200, y: 120)] {
            let placed = ChartTooltipPlacement.position(anchor: corner, tooltipSize: card, in: box)
            XCTAssertGreaterThanOrEqual(placed.x - card.width / 2, -0.001, "\(corner)")
            XCTAssertLessThanOrEqual(placed.x + card.width / 2, box.width + 0.001, "\(corner)")
            XCTAssertGreaterThanOrEqual(placed.y - card.height / 2, -0.001, "\(corner)")
            XCTAssertLessThanOrEqual(placed.y + card.height / 2, box.height + 0.001, "\(corner)")
        }
    }

    func testTooltipPositionDropsBelowWhenTopEdgeWouldClip() {
        let box = CGSize(width: 300, height: 200)
        let card = CGSize(width: 60, height: 40)
        let placed = ChartTooltipPlacement.position(anchor: CGPoint(x: 150, y: 2), tooltipSize: card, in: box, gap: 10)
        XCTAssertGreaterThan(placed.y, 2)
    }

    /// The side-placed tooltip must never overlap the anchor column it names, at any point on a grid.
    func testTooltipBesideStaysOffTheAnchorColumn() {
        let box = CGSize(width: 260, height: 150)
        let card = CGSize(width: 84, height: 36)
        let gap: CGFloat = 6
        for x in stride(from: CGFloat(0), through: 260, by: 20) {
            for y in stride(from: CGFloat(0), through: 150, by: 25) {
                let placed = ChartTooltipPlacement.positionBeside(anchor: CGPoint(x: x, y: y), tooltipSize: card, in: box, gap: gap)
                XCTAssertGreaterThanOrEqual(abs(placed.x - x), card.width / 2 + gap - 0.001)
                XCTAssertGreaterThanOrEqual(placed.x - card.width / 2, -0.001)
                XCTAssertLessThanOrEqual(placed.x + card.width / 2, box.width + 0.001)
            }
        }
    }

    func testTooltipBesideFallsBackToCenteredWhenTooNarrow() {
        let tightBox = CGSize(width: 90, height: 150)
        let card = CGSize(width: 84, height: 36)
        let anchor = CGPoint(x: 45, y: 75)
        let beside = ChartTooltipPlacement.positionBeside(anchor: anchor, tooltipSize: card, in: tightBox, gap: 6)
        let centered = ChartTooltipPlacement.position(anchor: anchor, tooltipSize: card, in: tightBox, gap: 6)
        XCTAssertEqual(beside.x, centered.x, accuracy: 0.001)
        XCTAssertEqual(beside.y, centered.y, accuracy: 0.001)
    }

    // MARK: - TrendChart / Sparkline statics

    func testTrendChartDefaultDateStringProducesNonEmptyOutput() {
        let formatted = TrendChart.defaultDateString(Date(timeIntervalSince1970: 1_735_000_000))
        XCTAssertFalse(formatted.isEmpty)
    }

    func testSparklineDefaultValueStringRoundsOnlyFractionalInputs() {
        XCTAssertEqual(Sparkline.defaultValueString(70), "70")
        XCTAssertEqual(Sparkline.defaultValueString(70.5), "70.5")
    }
}
