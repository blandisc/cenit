import XCTest
import Foundation
@testable import CenitAnalytics

final class TrainingRegulationTests: XCTestCase {

    // MARK: - Honest gate (no signal → nil, UI hides the band)

    func testNilWhenThereIsNoSignal() {
        XCTAssertNil(TrainingRegulation.suggest(recoveryZ: nil))
    }

    // MARK: - By z (preferred path)

    func testZHighDialsUp() {
        let s = TrainingRegulation.suggest(recoveryZ: 0.6)
        XCTAssertEqual(s?.adjustment, .dialUp)
        XCTAssertEqual(s?.reason, .recoveryHigh)
    }

    func testZLowDialsBack() {
        let s = TrainingRegulation.suggest(recoveryZ: -0.6)
        XCTAssertEqual(s?.adjustment, .dialBack)
        XCTAssertEqual(s?.reason, .recoveryLow)
    }

    func testZNeutralHolds() {
        let s = TrainingRegulation.suggest(recoveryZ: 0.0)
        XCTAssertEqual(s?.adjustment, .hold)
        XCTAssertEqual(s?.reason, .withinNormal)
    }

    func testZBoundaries() {
        // z == +zHigh → dial up (inclusive); z == -zLow → dial back (inclusive).
        XCTAssertEqual(TrainingRegulation.suggest(recoveryZ: TrainingRegulation.zHigh)?.adjustment, .dialUp)
        XCTAssertEqual(TrainingRegulation.suggest(recoveryZ: -TrainingRegulation.zLow)?.adjustment, .dialBack)
        // Just inside the band → hold.
        XCTAssertEqual(TrainingRegulation.suggest(recoveryZ: 0.49)?.adjustment, .hold)
        XCTAssertEqual(TrainingRegulation.suggest(recoveryZ: -0.49)?.adjustment, .hold)
    }

    // MARK: - Invariants

    func testAlwaysAdvisory() {
        XCTAssertTrue(TrainingRegulation.suggest(recoveryZ: 2.0)!.isAdvisory)
        XCTAssertTrue(TrainingRegulation.suggest(recoveryZ: -2.0)!.isAdvisory)
    }

    // MARK: - Light alternative (FER-532) — the planner's «Sugerencia» row

    // MARK: - The systemic gate (FER-91 · E10 «Tu cuerpo») — regression

    /// The bug the code comment at `gatesTraining` documents, pinned so it can't come back: the
    /// muscle map used to read `!allowsRaise` as its gate, which is TRUE for `.lighter` too, and
    /// ended up shouting «hoy toca descanso» on a morning whose own bullet said «hoy ve leve» ten
    /// points below — a second oracle, in a different tone. Only `.recover` may close the screen.
    func testOnlyRecoverGatesTraining() {
        XCTAssertTrue(TrainingRegulation.gatesTraining(.recover))
        for advice in allAdvice where advice != .recover {
            XCTAssertFalse(TrainingRegulation.gatesTraining(advice),
                           "\(advice) must NOT gate «Tu cuerpo» — only .recover does")
        }
    }

    /// `.lighter` holds the WEIGHT (`allowsRaise` is false), never the training itself: the two
    /// predicates answer different questions, and the fix this test protects is exactly that a gate
    /// must not be derived from `!allowsRaise`.
    func testLighterHoldsTheRaiseButNeverGatesTraining() {
        XCTAssertFalse(TrainingRegulation.allowsRaise(.lighter))
        XCTAssertFalse(TrainingRegulation.gatesTraining(.lighter))
    }

    private let allAdvice: [TrainingRegulation.Advice] = [.planAsIs, .lighter, .recover, .silent, .pending]


}
