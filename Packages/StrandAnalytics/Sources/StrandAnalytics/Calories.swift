import Foundation
import BiometricStreams

// Calories.swift — energy for a session and for a day, from heart rate or from duration alone.
//
// THREE PUBLISHED EQUATIONS, and nothing else:
//
//   • RESTING energy — Harris-Benedict as revised by Roza & Shizgal (1984), «The Harris Benedict
//     equation reevaluated», Am J Clin Nutr 40(1):168-182. Basal metabolic rate in kcal/day from
//     weight, height and age. Divided by 86 400 to get the per-second rate everything here works in.
//
//   • ACTIVE energy — Keytel et al. (2005), «Prediction of energy expenditure from heart rate
//     monitoring during submaximal exercise», J Sports Sci 23(3):289-297. Expenditure in kJ/min from
//     heart rate, weight and age. Divided by 60 × 4.184 = 251.04 to reach kcal/s. Heart rate is
//     clamped to the person's maximum first, because Keytel was fitted inside the exercise range.
//
//   • STRENGTH WITHOUT HEART RATE — Ainsworth et al. (2011) Compendium of Physical Activities, Med
//     Sci Sports Exerc 43(8):1575-1581: `kcal = MET × kg × hours`, with MET 3.5 for resistance
//     training at 8–15 reps with varied resistance (the moderate entry, not the vigorous one).
//
// THE THIRD COEFFICIENT SET IS NOT PUBLISHED. Keytel and Harris-Benedict each give one set for men
// and one for women, and Cénit does not require anyone to declare a sex. The third set used here is
// the ARITHMETIC MEAN of the two published sets. That is an interpolation, not a result: no study
// fitted it, and it should never be described as «Keytel». It is kept because the alternatives —
// forcing a declaration, or refusing to estimate — are worse product, and it is also the default when
// the field is unknown or unrecognised.
//
// TWO INTEGRATION RULES, DIFFERENT ON PURPOSE. All three equations give RATES, and a rate only becomes
// energy when multiplied by time. Summing one figure per sample is correct only at exactly 1 Hz, and
// the two routes below resolve that differently for reasons that are not interchangeable:
//
//   • A SESSION is a continuous interval by construction, so its internal holes are real elapsed time
//     inside it: each reading is credited with the time until the next one (capped, so a long dropout
//     is not credited whole), and the last with one second. Without this, a sparsely sampled session
//     would report energy in proportion to how well it happened to be sampled.
//   • A DAY is a raw union of readings with no gap filling, so each reading is credited with exactly
//     ONE SECOND. Crediting elapsed time here would hand the entire cap of active burn to one isolated
//     high reading and overcount by orders of magnitude. The day total is additionally capped at
//     24 hours' worth of seconds.
//
// TWO ACTIVITY GATES, ALSO DIFFERENT ON PURPOSE. Below `rest + fraction × (max − rest)` the resting
// rate applies, above it the active one. The fraction is LOWER for a session — Keytel is fitted on
// real exercise, and inside a session almost any elevated pulse is exercise — and HIGHER for a day,
// because applying the raw exercise rate to the ordinary pulse of walking, stairs and standing up
// overcounts massively. On the day route the active rate additionally cannot fall below the resting
// one: a second spent alive never burns less than basal. These two fractions are RECALIBRATABLE and
// must NOT be unified: the session one has to let real effort through, the day one has to sit above
// everyday life.
//
// APPROXIMATE. Heart-rate-based estimation, not calorimetry, and not an attempt to match any other
// product's figure.

/// The body the equations are applied to.
public struct UserProfile: Equatable, Sendable {
    public var weightKg: Double
    public var heightCm: Double
    public var age: Double
    /// `"male"` / `"female"` select the published coefficient sets; anything else, including
    /// `"nonbinary"` and the unknown, takes the interpolated set.
    public var sex: String

    public init(weightKg: Double = 70.0, heightCm: Double = 170.0,
                age: Double = 30.0, sex: String = "nonbinary") {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
    }
}

public enum Calories {

    // MARK: - Constants

    /// Heart-rate readings a strength session needs before its energy is estimated from pulse rather
    /// than from duration.
    ///
    /// This is INTERFACE, not a private threshold: the caller labels the stored figure's origin by
    /// comparing against this same constant, so the label can never claim one method while the number
    /// came from the other.
    public static let strengthEnergyMinSamples: Int = 2

    /// kJ per kcal.
    private static let kJPerKcal: Double = 4.184
    /// kJ/min → kcal/s: 60 s/min × 4.184 kJ/kcal. Written as the literal rather than the product
    /// because the two differ in the last bit of a `Double`, and this divisor lands on stored energy.
    private static let kJPerMinutePerKcalPerSecond: Double = 251.04
    /// Seconds in a day: the divisor that turns a daily BMR into a rate, and the day route's cap.
    private static let secondsPerDay: Double = 86_400

    /// Fraction of heart-rate reserve above rest at which a SESSION reading counts as effort.
    private static let sessionActiveHRRFraction: Double = 0.30
    /// The same fraction for a DAY. Higher on purpose — see the file header.
    private static let dayActiveHRRFraction: Double = 0.50
    /// Longest stretch (s) one session reading may be credited with, so a recording interruption
    /// inside a session is not paid out in full.
    private static let sessionSampleCapSeconds: Double = 150.0

    /// MET for resistance training, 8–15 reps, varied resistance — Ainsworth et al. (2011).
    private static let resistanceTrainingMET: Double = 3.5
    /// Longest strength session the MET route will price.
    ///
    /// RECALIBRATABLE; the criterion is simply «above any plausible session». It exists so a corrupt
    /// end stamp produces a large-but-bounded number instead of an absurd one.
    private static let maxStrengthSeconds: Double = 6 * 3_600
    /// Body mass assumed when none is known.
    private static let fallbackWeightKg: Double = 70.0

    // MARK: - Public API

    /// Energy for one continuous session, as `(kcal, kJ)`.
    public static func estimateBoutCalories(_ hrSamples: [HRSample], profile: UserProfile,
                                            hrmax: Double?, restingHR: Double?) -> (Double, Double) {
        let kcal = integrate(hrSamples, profile: profile, hrmax: hrmax, restingHR: restingHR,
                             activeFraction: sessionActiveHRRFraction, weighting: .elapsed)
        return (kcal, kcal * kJPerKcal)
    }

    /// Energy for a whole day of readings, in kcal.
    public static func estimateDayCalories(_ hrSamples: [HRSample], profile: UserProfile,
                                           hrmax: Double?, restingHR: Double?) -> Double {
        integrate(hrSamples, profile: profile, hrmax: hrmax, restingHR: restingHR,
                  activeFraction: dayActiveHRRFraction, weighting: .perSecond)
    }

    /// Energy for a strength session from its duration alone — Ainsworth et al. (2011).
    /// Duration is clamped to `[0, maxStrengthSeconds]`; a non-positive mass falls back to 70 kg.
    public static func estimateStrengthCalories(durationSeconds: Double, profile: UserProfile) -> Double {
        let seconds = min(max(0, durationSeconds), maxStrengthSeconds)
        let kg = profile.weightKg > 0 ? profile.weightKg : fallbackWeightKg
        return resistanceTrainingMET * kg * (seconds / 3_600)
    }

    /// The ONE entry point for a strength session's energy: heart rate when there is enough of it,
    /// duration otherwise.
    ///
    /// The caller labels the origin by comparing its sample count against `strengthEnergyMinSamples`,
    /// the same constant this branches on — so the stored label and the stored number always agree.
    public static func estimateStrengthEnergy(hrSamples: [HRSample], durationSeconds: Double,
                                              profile: UserProfile, hrMax: Double? = nil,
                                              restingHR: Double? = nil,
                                              minSamples: Int = strengthEnergyMinSamples) -> Double {
        guard hrSamples.count >= minSamples else {
            return estimateStrengthCalories(durationSeconds: durationSeconds, profile: profile)
        }
        return estimateBoutCalories(hrSamples, profile: profile, hrmax: hrMax,
                                    restingHR: restingHR).0
    }

    // MARK: - Rates

    /// Basal metabolic rate in kcal/day — Roza & Shizgal (1984).
    ///
    /// The height coefficients are stated per CENTIMETRE, exactly as published, and applied to
    /// centimetres. Carrying them scaled and applying them to metres is arithmetically identical and
    /// an invitation to a unit error.
    static func restingKcalPerDay(_ profile: UserProfile) -> Double {
        let c = coefficients(for: profile.sex)
        let kcal = c.bmrIntercept
            + c.bmrWeight * profile.weightKg
            + c.bmrHeight * profile.heightCm
            + c.bmrAge * profile.age
        return max(0, kcal)
    }

    /// Basal rate in kcal per second.
    static func restingKcalPerSecond(_ profile: UserProfile) -> Double {
        restingKcalPerDay(profile) / secondsPerDay
    }

    /// Active expenditure in kcal per second at a given pulse — Keytel et al. (2005).
    static func activeKcalPerSecond(bpm: Double, profile: UserProfile) -> Double {
        let c = coefficients(for: profile.sex)
        let kJPerMin = c.eeHR * bpm
            + c.eeWeight * profile.weightKg
            + c.eeAge * profile.age
            + c.eeIntercept
        return max(0, kJPerMin / kJPerMinutePerKcalPerSecond)
    }

    // MARK: - Private

    /// How each reading earns its slice of time.
    private enum Weighting {
        /// Time until the next reading, capped; the last reading gets one second.
        case elapsed
        /// Exactly one second per reading, and the total capped at a day.
        case perSecond
    }

    private static func integrate(_ hrSamples: [HRSample], profile: UserProfile,
                                  hrmax: Double?, restingHR: Double?,
                                  activeFraction: Double, weighting: Weighting) -> Double {
        guard !hrSamples.isEmpty else { return 0 }
        let sorted = hrSamples.sorted { $0.ts < $1.ts }
        let rest = restingHR ?? StrainScorer.defaultRestingHR
        let maxHR = hrmax ?? StrainScorer.tanakaHRmax(age: profile.age)
        let reserve = max(0, maxHR - rest)
        let gate = rest + activeFraction * reserve
        let restRate = restingKcalPerSecond(profile)

        var kcal = 0.0
        var spent = 0.0
        for (i, s) in sorted.enumerated() {
            let seconds: Double
            switch weighting {
            case .elapsed:
                if i + 1 < sorted.count {
                    let gap = Double(sorted[i + 1].ts - s.ts)
                    seconds = gap > 0 ? min(gap, sessionSampleCapSeconds) : 1.0
                } else {
                    seconds = 1.0
                }
            case .perSecond:
                guard spent < secondsPerDay else { return kcal }
                seconds = 1.0
            }
            spent += seconds

            let bpm = min(Double(s.bpm), maxHR)
            // The gate is INCLUSIVE: a pulse sitting exactly on the threshold counts as effort.
            if bpm >= gate {
                let active = activeKcalPerSecond(bpm: bpm, profile: profile)
                // On the day route a second can never burn less than basal.
                kcal += (weighting == .perSecond ? max(active, restRate) : active) * seconds
            } else {
                kcal += restRate * seconds
            }
        }
        return kcal
    }

    /// The published coefficient sets, and the interpolation between them.
    private struct Coefficients {
        let bmrIntercept: Double
        let bmrWeight: Double
        let bmrHeight: Double
        let bmrAge: Double
        let eeHR: Double
        let eeWeight: Double
        let eeAge: Double
        let eeIntercept: Double

        /// Halfway between two sets — the unpublished third set. See the file header.
        static func midpoint(_ a: Coefficients, _ b: Coefficients) -> Coefficients {
            Coefficients(bmrIntercept: (a.bmrIntercept + b.bmrIntercept) / 2,
                         bmrWeight: (a.bmrWeight + b.bmrWeight) / 2,
                         bmrHeight: (a.bmrHeight + b.bmrHeight) / 2,
                         bmrAge: (a.bmrAge + b.bmrAge) / 2,
                         eeHR: (a.eeHR + b.eeHR) / 2,
                         eeWeight: (a.eeWeight + b.eeWeight) / 2,
                         eeAge: (a.eeAge + b.eeAge) / 2,
                         eeIntercept: (a.eeIntercept + b.eeIntercept) / 2)
        }
    }

    private static let maleCoefficients = Coefficients(
        bmrIntercept: 88.362, bmrWeight: 13.397, bmrHeight: 4.799, bmrAge: -5.677,
        eeHR: 0.6309, eeWeight: 0.1988, eeAge: 0.2017, eeIntercept: -55.0969)

    private static let femaleCoefficients = Coefficients(
        bmrIntercept: 447.593, bmrWeight: 9.247, bmrHeight: 3.098, bmrAge: -4.330,
        eeHR: 0.4472, eeWeight: -0.1263, eeAge: 0.0740, eeIntercept: -20.4022)

    private static let interpolatedCoefficients =
        Coefficients.midpoint(maleCoefficients, femaleCoefficients)

    private static func coefficients(for sex: String) -> Coefficients {
        let s = sex.lowercased()
        if s.hasPrefix("f") { return femaleCoefficients }
        if s.hasPrefix("m") { return maleCoefficients }
        return interpolatedCoefficients
    }
}
