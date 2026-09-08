import SwiftUI
import Foundation
import CenitAnalytics
import CenitDesign
import CenitStore

// MARK: - Stress model (presentation layer)
//
// The math — the 0–3 stress proxy, its band thresholds and the per-source baseline derivation —
// lives in `CenitAnalytics.DailyStressModel` / `CenitAnalytics.StressMath` (FER-756). This file
// keeps only PRESENTATION: the band's copy and colors, the explanation copy, the calm-time strings,
// and a thin `StressModel` shim so the live consumers (TodayView, CuerpoView, StressDetailScreen)
// keep their surface unchanged.

// MARK: - Stress band presentation (copy + color)
//
// The band enum (with its 0–3 → band init) lives in CenitAnalytics; every consumer screen already
// imports the package, so `StressBand` resolves directly — only its presentation lives here.

extension StressBand {
    /// La palabra en mayúsculas del medidor legado oscuro.
    var title: String {
        switch self {
        case .low:    String(localized: "LOW")
        case .medium: String(localized: "MEDIUM")
        case .high:   String(localized: "HIGH")
        }
    }

    /// Sentence-case band word for «Instrumento» surfaces ("Low" / "Moderate" / "High"). Single source
    /// for the band→word mapping; distinct from `title` (ALL-CAPS, for the dark legacy gauge).
    var displayWord: LocalizedStringKey {
        switch self {
        case .low:    return "Low"
        case .medium: return "Moderate"
        case .high:   return "High"
        }
    }

    var tone: CenitTone {
        switch self {
        case .low:    .positive
        case .medium: .warning
        case .high:   .critical
        }
    }

    /// The data color for this band (low→verdict, medium→warning, high→critical).
    /// Single source for the stress band→color mapping (FER-326).
    func dataColor() -> Color {
        switch self {
        case .low:    return LiquidColor.verdePrimario
        case .medium: return LiquidColor.atencion
        case .high:   return LiquidColor.negativo
        }
    }
}

// MARK: - Stress model shim (math in CenitAnalytics + copy here)

struct StressModel: Sendable {
    let score: Double            // 0–3, el día ancla
    let band: StressBand
    let explanation: String
    let rhrToday: Int?
    let hrvToday: Double?
    let rhrDelta: Double?        // hoy − media de la línea base (bpm)
    let hrvDelta: Double?        // hoy − media de la línea base (ms)
    let fullTrend: [TrendPoint]  // toda la historia del proxy diario, del más viejo al más nuevo
    let calmTimeValue: String    // p. ej. «58%»
    let calmTimeCaption: String  // p. ej. «de los últimos 30 días»
    let usingStored: Bool        // el valor del día salió de la serie ya guardada

    // FER-397 — the hero is anchored to the most recent day that actually carries a reading, so a still-
    // empty "today" row at the midnight boundary doesn't blank the screen. These describe that anchor.
    let anchorDayKey: String     // the day the hero score is from
    let anchorIsToday: Bool      // false → the view MUST date the hero (it's yesterday's, never "today's")
    let heroIsFresh: Bool        // anchor ∈ {today, yesterday}: show the hero. Older → hide it, but the
                                 // trend/patterns below still render from `fullTrend`.

    /// Los últimos 14 valores de la tendencia (o los que haya), para la chispa del héroe.
    var sparkValues: [Double] { fullTrend.suffix(14).map(\.value) }

    /// Build from oldest→newest daily metrics plus any stored "stress" series — delegates the math to
    /// `DailyStressModel` (CenitAnalytics) and adds the display copy on top.
    /// Devuelve nil sólo cuando no hay ninguna señal aprovechable.
    init?(days: [DailyMetric], stored: [(day: String, value: Double)], todayKey: String,
          appleDays: Set<String> = []) {
        guard let core = DailyStressModel(days: days, stored: stored, todayKey: todayKey,
                                          appleDays: appleDays) else { return nil }
        self.score = core.score
        self.band = core.band
        self.rhrToday = core.rhrToday
        self.hrvToday = core.hrvToday
        self.rhrDelta = core.rhrDelta
        self.hrvDelta = core.hrvDelta
        self.usingStored = core.usingStored
        self.anchorDayKey = core.anchorDayKey
        self.anchorIsToday = core.anchorIsToday
        self.heroIsFresh = core.heroIsFresh
        self.fullTrend = core.fullTrend.map { TrendPoint(date: $0.date, value: $0.value) }

        self.explanation = StressModel.explanation(
            band: core.band,
            rhrDelta: core.rhrDelta,
            hrvDelta: core.hrvDelta,
            usingStored: core.usingStored
        )

        // «Tiempo en calma»: qué parte de los últimos 30 días graficados cayó en la banda baja.
        if core.calmWindow > 0 {
            let porcentaje = Int((Double(core.calmDays) / Double(core.calmWindow) * 100).rounded())
            self.calmTimeValue = "\(porcentaje)%"
            self.calmTimeCaption = "low-stress days · \(core.calmWindow)d"
        } else {
            self.calmTimeValue = "—"
            self.calmTimeCaption = "needs history"
        }
    }

    static func explanation(band: StressBand, rhrDelta: Double?, hrvDelta: Double?, usingStored: Bool) -> String {
        // Un movimiento sólo cuenta si se separa más de 1 bpm / 1 ms de la línea base.
        let umbral = 1.0
        let rhrArriba = (rhrDelta ?? 0) > umbral
        let rhrAbajo = (rhrDelta ?? 0) < -umbral
        let hrvArriba = (hrvDelta ?? 0) > umbral
        let hrvAbajo = (hrvDelta ?? 0) < -umbral

        switch band {
        case .high:
            if rhrArriba && hrvAbajo {
                return String(localized: "Resting HR is elevated and HRV is below your baseline: both classic signs of high activation. Prioritise rest, hydration and an easy day.")
            } else if hrvAbajo {
                return String(localized: "HRV has dropped well below your baseline, pointing to elevated stress or fatigue. Ease off and give your body time to recover.")
            } else if rhrArriba {
                return String(localized: "Resting heart rate is running high versus your norm: your body is under load today. Keep effort light.")
            }
            return String(localized: "Your autonomic markers are skewed toward stress today. Treat it as a recovery-focused day.")
        case .medium:
            if rhrArriba || hrvAbajo {
                let driver = rhrArriba ? String(localized: "resting HR is a touch high") : String(localized: "HRV is a little low")
                return String(localized: "Slightly off baseline, \(driver), so you're moderately activated. Nothing alarming; just don't overreach.")
            }
            return String(localized: "You're sitting around your typical autonomic baseline: moderate stress, a normal, balanced day.")
        case .low:
            if rhrAbajo && hrvArriba {
                return String(localized: "Resting heart rate is low and HRV is up: your nervous system looks well-recovered and calm. A great day to push if you want to.")
            } else if hrvArriba {
                return String(localized: "HRV is above baseline, a sign of a relaxed, well-recovered nervous system. Stress is low.")
            }
            return String(localized: "Resting heart rate and HRV are sitting at or below baseline: low physiological stress. You're in a calm, recovered state.")
        }
    }
}
