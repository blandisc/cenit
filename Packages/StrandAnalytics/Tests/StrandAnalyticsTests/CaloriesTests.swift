import XCTest
import BiometricStreams
@testable import StrandAnalytics

/// Energy against the three published equations, with the coefficient checks first: if C18 or C19
/// below fail, a coefficient has been mistyped and every stored session energy is wrong.
///
/// Roza & Shizgal (1984) for resting, Keytel et al. (2005) for active, Ainsworth et al. (2011) for
/// strength without a pulse.
final class CaloriesTests: XCTestCase {

    private let man = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")

    private func series(_ n: Int, bpm: Int, every: Int = 1) -> [HRSample] {
        (0..<n).map { HRSample(ts: $0 * every, bpm: bpm) }
    }

    // MARK: - The published equations, anchored

    /// Keytel for a man of 80 kg at 30, at 150 bpm:
    /// 0.6309×150 + 0.1988×80 + 0.2017×30 − 55.0969 = 61.4931 kJ/min → ÷251.04 = 0.244953 kcal/s,
    /// over 600 s = 146.97 kcal.
    func testActiveEnergyMatchesKeytel() {
        let (kcal, kJ) = Calories.estimateBoutCalories(series(600, bpm: 150), profile: man,
                                                       hrmax: 190, restingHR: 60)
        XCTAssertEqual(kcal, 146.97, accuracy: 0.1)
        XCTAssertEqual(kJ, kcal * 4.184, accuracy: 1e-9)
    }

    /// Below the activity gate everything is basal, so a whole day at 80 bpm is exactly the Harris-
    /// Benedict figure: 88.362 + 13.397×80 + 4.799×180 − 5.677×30 = 1853.63 kcal.
    func testRestingEnergyMatchesHarrisBenedictAsRevised() {
        let kcal = Calories.estimateBoutCalories(series(86_400, bpm: 80), profile: man,
                                                 hrmax: 190, restingHR: 60).0
        XCTAssertEqual(kcal, 1853.6, accuracy: 1.0)
    }

    /// The height coefficients are applied to CENTIMETRES, as published. A profile in metres would
    /// land far from the anchor above.
    func testHeightIsInCentimetres() {
        let inMetres = UserProfile(weightKg: 80, heightCm: 1.8, age: 30, sex: "male")
        XCTAssertNotEqual(Calories.restingKcalPerDay(inMetres), Calories.restingKcalPerDay(man),
                          accuracy: 100)
    }

    func testTheTwoPublishedSexesDisagreeAndTheThirdSitsBetweenThem() {
        let hr = series(600, bpm: 150)
        let m = Calories.estimateBoutCalories(hr, profile: man, hrmax: 190, restingHR: 60).0
        let f = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "female"),
            hrmax: 190, restingHR: 60).0
        let x = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "nonbinary"),
            hrmax: 190, restingHR: 60).0
        XCTAssertNotEqual(m, f, accuracy: 1.0)
        // The third set is the arithmetic mean of the two published ones — an interpolation, not a
        // result, and it must be exactly halfway or it is neither.
        XCTAssertEqual(x, (m + f) / 2, accuracy: 1e-9)
        // An unrecognised value takes the same interpolated set rather than refusing to estimate.
        let unknown = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "unspecified"),
            hrmax: 190, restingHR: 60).0
        XCTAssertEqual(unknown, x, accuracy: 1e-12)
    }

    // MARK: - Strength without a pulse (Ainsworth 2011)

    func testMETRouteIsMETTimesMassTimesHours() {
        let eighty = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let seventy = UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "male")
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: 2700, profile: eighty),
                       210.0, accuracy: 1e-9)   // 3.5 × 80 × 0.75
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: 3600, profile: seventy),
                       245.0, accuracy: 1e-9)   // 3.5 × 70 × 1.0
    }

    func testMETRouteClampsBothEndsOfTheDuration() {
        let eighty = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: 0, profile: eighty),
                       0.0, accuracy: 1e-12)
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: -500, profile: eighty),
                       0.0, accuracy: 1e-12)
        // A corrupt end stamp is bounded, not absurd: 10 h is priced as 6.
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: 36_000,
                                                         profile: UserProfile(weightKg: 70)),
                       1470.0, accuracy: 1e-9)  // 3.5 × 70 × 6
    }

    func testMETRouteFallsBackToASeventyKilogramBody() {
        XCTAssertEqual(Calories.estimateStrengthCalories(
            durationSeconds: 1800, profile: UserProfile(weightKg: 0)), 122.5, accuracy: 1e-9)
    }

    /// One entry point, branching on the same constant the caller labels the origin with — so the
    /// stored label can never claim one method while the number came from the other.
    func testStrengthSelectorBranchesOnTheSharedThreshold() {
        let eighty = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        XCTAssertEqual(Calories.strengthEnergyMinSamples, 2)
        XCTAssertEqual(Calories.estimateStrengthEnergy(hrSamples: [], durationSeconds: 2700,
                                                       profile: eighty), 210.0, accuracy: 1e-9)
        XCTAssertEqual(Calories.estimateStrengthEnergy(hrSamples: [HRSample(ts: 0, bpm: 130)],
                                                       durationSeconds: 2700, profile: eighty),
                       210.0, accuracy: 1e-9, "one reading is under the threshold → the MET route")
        let withHR = Calories.estimateStrengthEnergy(hrSamples: series(120, bpm: 140),
                                                     durationSeconds: 2700, profile: eighty,
                                                     hrMax: 190, restingHR: 60)
        XCTAssertGreaterThan(withHR, 0)
        XCTAssertNotEqual(withHR, 210.0, accuracy: 1e-6, "two readings or more → the pulse route")
    }

    // MARK: - The two integration rules

    func testNoReadingsIsNoEnergy() {
        XCTAssertEqual(Calories.estimateDayCalories([], profile: man, hrmax: 190, restingHR: 60),
                       0.0, accuracy: 1e-12)
    }

    /// At exactly 1 Hz, and above BOTH gates, the two rules must agree — that is the only sampling
    /// rate at which one figure per reading is the same thing as integrating over time.
    func testAtOneHertzAndClearlyActiveTheTwoRoutesAgree() {
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")
        let hr = series(600, bpm: 130)
        let bout = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 185, restingHR: 55).0
        let day = Calories.estimateDayCalories(hr, profile: profile, hrmax: 185, restingHR: 55)
        XCTAssertEqual(bout, day, accuracy: 1e-9)
    }

    /// The gates differ ON PURPOSE. At 110 bpm the pulse clears the session gate but not the day
    /// gate, so the day counts that hour as basal — applying the raw exercise rate to the ordinary
    /// pulse of walking and stairs would overcount massively.
    func testTheDayGateSitsAboveEverydayLife() {
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")
        let hr = series(3600, bpm: 110)
        let bout = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 185, restingHR: 55).0
        let day = Calories.estimateDayCalories(hr, profile: profile, hrmax: 185, restingHR: 55)
        XCTAssertLessThan(day, bout)
        let atRest = Calories.estimateDayCalories(series(3600, bpm: 55), profile: profile,
                                                  hrmax: 185, restingHR: 55)
        XCTAssertEqual(day, atRest, accuracy: 1e-9, "an hour priced as basal, exactly")
    }

    /// The day total cannot exceed a day.
    func testTheDayTotalIsCappedAtTwentyFourHours() {
        let a = Calories.estimateDayCalories(series(86_400, bpm: 150), profile: man,
                                             hrmax: 190, restingHR: 60)
        let b = Calories.estimateDayCalories(series(90_000, bpm: 150), profile: man,
                                             hrmax: 190, restingHR: 60)
        XCTAssertEqual(a, b, accuracy: 1e-6)
    }

    /// A resting day still burns; an active one burns more. Nothing is ever below basal.
    func testEveryDayBurnsAtLeastBasal() {
        let p = UserProfile(weightKg: 70, heightCm: 170, age: 30, sex: "male")
        let rest = Calories.estimateDayCalories(series(3600, bpm: 60), profile: p,
                                                hrmax: 190, restingHR: 55)
        let active = Calories.estimateDayCalories(series(3600, bpm: 150), profile: p,
                                                  hrmax: 190, restingHR: 55)
        XCTAssertGreaterThan(rest, 0)
        XCTAssertGreaterThan(active, rest)
    }

    /// A sparsely sampled session must not report less energy just because it was sampled less: each
    /// reading carries the time until the next.
    func testASparseSessionIsNotPenalisedForItsSampling() {
        let dense = Calories.estimateBoutCalories(series(1201, bpm: 150), profile: man,
                                                  hrmax: 190, restingHR: 60).0
        let sparse = Calories.estimateBoutCalories(series(41, bpm: 150, every: 30), profile: man,
                                                   hrmax: 190, restingHR: 60).0
        XCTAssertEqual(sparse / dense, 1.0, accuracy: 0.02)
    }

    /// …but a long hole inside a session is capped, so an interruption in recording is not paid out
    /// in full.
    func testALongHoleInsideASessionIsCapped() {
        let two = Calories.estimateBoutCalories(
            [HRSample(ts: 0, bpm: 150), HRSample(ts: 300, bpm: 150)],
            profile: man, hrmax: 190, restingHR: 60).0
        let capped = Calories.estimateBoutCalories(series(151, bpm: 150), profile: man,
                                                   hrmax: 190, restingHR: 60).0
        XCTAssertEqual(two / capped, 1.0, accuracy: 0.01)
    }

    /// Keytel was fitted inside the exercise range, so the pulse entering it is clamped to the
    /// person's maximum first.
    func testPulseAboveTheMaximumIsClampedBeforeEnteringKeytel() {
        let atMax = Calories.estimateBoutCalories(series(600, bpm: 190), profile: man,
                                                  hrmax: 190, restingHR: 60).0
        let beyond = Calories.estimateBoutCalories(series(600, bpm: 240), profile: man,
                                                   hrmax: 190, restingHR: 60).0
        XCTAssertEqual(atMax, beyond, accuracy: 1e-9)
    }

    /// Readings arriving out of order give the same answer as ordered ones.
    func testOutOfOrderReadingsGiveTheSameAnswer() {
        let hr = series(600, bpm: 150)
        XCTAssertEqual(Calories.estimateBoutCalories(hr.reversed(), profile: man,
                                                     hrmax: 190, restingHR: 60).0,
                       Calories.estimateBoutCalories(hr, profile: man, hrmax: 190, restingHR: 60).0,
                       accuracy: 1e-9)
    }
}
