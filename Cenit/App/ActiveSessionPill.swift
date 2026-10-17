#if os(iOS)
import SwiftUI
import CenitDesign

// CEN-45: la píldora de sesión minimizada, sacada de `RootTabView` (borrado con el dock) a su propio
// archivo. La usa la raíz de Fuerza.

extension View {
    /// La monta la raíz de Fuerza (`FuerzaRootView`).
    /// Sin sesión (o con la hoja abierta) el contenido mide cero y `spacing` es cero:
    /// no se suma un hueco al pie de la raíz.
    func activeSessionPillInset(model: AppModel, confirmDiscard: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom, spacing: .zero) {
            ActiveSessionPillSlot(model: model, confirmDiscard: confirmDiscard)
        }
    }
}


/// El `if` vive en una vista propia para no leer `AppModel` dentro de la cadena de
/// la raíz (FER-985). Vacío, el `safeAreaInset` no reserva alto.
private struct ActiveSessionPillSlot: View {
    @Bindable var model: AppModel
    @Binding var confirmDiscard: Bool

    var body: some View {
        if model.strengthSession != nil && !model.strengthSheetPresented {
            ActiveSessionPillHost(model: model, confirmDiscard: $confirmDiscard)
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.bottom, LiquidSpace.s200)
                .transition(LiquidMotion.risingFadeTransition)
        }
    }
}

/// Hosts the `SessionPill` with a live-ticking clock (FER-716): a `TimelineView` recomputes the
/// elapsed time each second, and the BPM is the Apple Watch live mirror (`model.watchBpm` — the same
/// source as the session header; nil = no watch reading, so the pill drops its ♥ segment instead
/// of freezing a stale sample). Tapping re-opens the session. The routine hue is the indigo
/// (`dataSleep`) — the prototype's 6px pill dot (handoff V10 · FER-139), not the effort ember.
private struct ActiveSessionPillHost: View {
    @Bindable var model: AppModel
    /// Decisión Fer (2026-07-16): el ✕ del pill DESCARTA — destructivo, así que siempre confirma.
    /// El ConfirmCard vive en la raíz (pantalla completa); aquí solo se dispara.
    @Binding var confirmDiscard: Bool
    var body: some View {
        if let session = model.strengthSession {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // FER-952: pause-aware clock (the raw now−start kept ticking while paused).
                let elapsed = SessionClock.format(session.elapsedSeconds(now: context.date))
                let total = session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
                // FER-167 ronda 2 (R20, Grok 14 + QA O2): «Serie N de M» — la MISMA palabra y el
                // MISMO «N de N · completa» que la cabecera de la Hoja viva (`HojaCabeceraSesion`),
                // nunca dos fuentes que puedan divergir en la unidad de avance.
                let isComplete = total > 0 && session.pendingCount == 0
                let detail: String? = total == 0 ? nil : (isComplete
                    ? String(localized: "\(total) of \(total) · complete")
                    : String(localized: "Set \(min(session.doneCount + 1, total)) of \(total)"))
                SessionPill(
                    routineName: session.routineName,
                    elapsed: elapsed,
                    bpm: model.watchBpm,
                    detail: detail,
                    paused: session.paused,
                    hue: LiquidColor.indigo,
                    accessibilityLabel: pillLabel(session.routineName, elapsed, model.watchBpm),
                    accessibilityHint: Text("Returns to the session"),
                    action: { model.resumeStrengthSession() },
                    onDiscard: { confirmDiscard = true },
                    discardAccessibilityLabel: Text("Discard session")
                )
            }
        }
    }

    /// VoiceOver label for the pill — localized here because the CenitDesign package has no catalog.
    private func pillLabel(_ name: String, _ elapsed: String, _ bpm: Int?) -> Text {
        if let bpm { return Text("Active session: \(name), \(elapsed), heart rate \(bpm)") }
        return Text("Active session: \(name), \(elapsed)")
    }
}
#endif
