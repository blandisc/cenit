#if os(iOS) && DEBUG
import Foundation
import SwiftUI

/// Debug-only navigation for screenshot automation.
///
/// Two transport layers — both post to `.cenitDebugNav` which RootTabView observes:
///   1. Darwin notifications (no dialog): notifyutil -p cenit.nav.<screen>
///   2. URL scheme (backup):              xcrun simctl openurl booted "cenit://<screen>"
///
/// Supported screen keys (FER-182 — 4-tab shell after FER-240):
///   Tabs: today · body (aliases: trends, sleep — Sueño lives inside Cuerpo now) ·
///     train (alias: entrenar) · settings (aliases: ajustes, more)
///   Pushed onto a hub: breathe · intervals · routineToday ·
///     library · weeklyplan · misrutinas · workouthistory ·
///     explore · compare · workouts ·
///     applehealth · datasources · support
///   // FER-381: `coach`/`dieta`/`automations` retiradas (claves muertas → falso verde). Para llegar a
///   // una pantalla sin `nav` (marcas, volumen, tickets…) usa `-cenit.route <familia/clave>`.
///   (En vivo is no longer a key — it opens as a cover from Today's "beat by beat".)
///
/// The list below must stay in sync with `RootTabView.SecondaryScreen`'s raw values: the handler
/// resolves ANY of them, but only the keys observed here are reachable by Darwin notification (the
/// transport `CenitScreenshotTests` uses). The four Entrenar screens above were resolvable but
/// unobserved, so the screenshot suite had to tap through localized labels to reach them instead.
extension Notification.Name {
    static let cenitDebugNav = Notification.Name("cenit.debugNav")
}

/// Handles `cenit://<screen>` URLs and broadcasts the target screen via NotificationCenter.
///
/// `session` is NOT handled here: that one is the Live Activity's deep link and has to work in
/// Release too, so `RootTabView` owns it (FER-398). Skipping it keeps the two handlers from both
/// reacting to the same URL.
struct DebugURLHandler: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.scheme == "cenit", let screen = url.host, screen != "session" else { return }
            NotificationCenter.default.post(name: .cenitDebugNav, object: screen)
        }
    }
}

/// Watches Darwin notifications posted by `notifyutil -p cenit.nav.<screen>` and
/// bridges them to NSNotificationCenter so RootTabView can react without any iOS
/// permission dialogs or URL-scheme intercept flows.
final class DebugNavWatcher {
    static let shared = DebugNavWatcher()
    private init() {}

    private static let prefix = "cenit.nav."
    // FER-381: se quitaron las claves muertas `coach` (Patrones archivada), `dieta` (retirada del enum)
    // y `automations` (sin destino) — capturaban la pantalla ANTERIOR con nombre ajeno y el test seguía
    // verde (falso verde que `Tools/check-shots.py` ahora mata). Toda clave aquí resuelve a una pantalla real.
    private static let screens = [
        "today", "body", "trends", "train", "entrenar", "settings", "ajustes", "more",
        "breathe", "intervals", "routineToday",
        "library", "weeklyplan", "misrutinas", "workouthistory",
        "sleep", "explore", "compare", "workouts",
        "applehealth", "datasources", "support",
    ]

    func start() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for screen in Self.screens {
            let name = "\(Self.prefix)\(screen)" as CFString
            CFNotificationCenterAddObserver(center, nil, darwinCallback, name, nil, .deliverImmediately)
        }
    }
}

private let darwinCallback: CFNotificationCallback = { _, _, rawName, _, _ in
    guard let rawName else { return }
    let full = rawName.rawValue as String
    let prefix = "cenit.nav."
    guard full.hasPrefix(prefix) else { return }
    let screen = String(full.dropFirst(prefix.count))
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .cenitDebugNav, object: screen)
    }
}
#endif
