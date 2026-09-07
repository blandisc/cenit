import Foundation

/// Los Términos de Uso que enseña la puerta del primer arranque.
///
/// `currentVersion` es lo que decide si hay que volver a preguntar: súbela cuando el texto cambie
/// **de fondo** — riesgo, responsabilidad, salud, afiliación — y todos los usuarios verán la puerta
/// otra vez para aceptar de nuevo. Un typo corregido no mueve la versión.
///
/// El texto completo vive en `TERMS.md` dentro del repositorio y, para quien instala el app, en
/// `fullTermsURL`.
enum Terms {
    static let currentVersion = "2.0"

    /// One load-bearing point the gate lists — plain-English summary of `TERMS.md` §1–§6.
    /// Kept identical in substance to the Android `Terms.points`.
    struct Point: Identifiable {
        let id: String
        let title: String
        let body: String
    }

    /// The four points the user must accept on first launch. Symbolic keys (`terms.pointN.*`) +
    /// English `defaultValue` — the catalog is `sourceLanguage: en`.
    static var points: [Point] {
        [
            Point(
                id: "1",
                title: String(localized: "terms.point1.title",
                              defaultValue: "Reads your data from Apple Health, on your device"),
                body: String(localized: "terms.point1.body",
                             defaultValue: "Cénit reads your health and fitness data directly from Apple Health, on your iPhone — no separate hardware pairing required.")
            ),
            Point(
                id: "2",
                title: String(localized: "terms.point2.title",
                              defaultValue: "Offline and local — no account, no server"),
                body: String(localized: "terms.point2.body",
                             defaultValue: "Every metric is processed and stored only on your device. There is no Cénit server, no Cénit account, and no telemetry — the maintainers cannot see your data and never receive it.")
            ),
            Point(
                id: "3",
                title: String(localized: "terms.point3.title",
                              defaultValue: "General wellness only — not a medical device"),
                body: String(localized: "terms.point3.body",
                             defaultValue: "Cénit is not a medical device and provides no medical advice. Every metric is an unvalidated approximation — don't use Cénit to diagnose, treat, or make any health decision. Always consult a qualified professional.")
            ),
            Point(
                id: "4",
                title: String(localized: "terms.point4.title",
                              defaultValue: "No warranty; liability limited"),
                body: String(localized: "terms.point4.body",
                             defaultValue: "Cénit is free and provided \"as is\", with no warranty. Liability is limited to the maximum extent the law that applies to you allows, and nothing here removes protections your local law won't let us remove.")
            ),
        ]
    }

    // MARK: - Gate chrome (TermsGateView)

    static var title: String {
        String(localized: "terms.title", defaultValue: "Before you use Cénit")
    }
    static var intro: String {
        String(localized: "terms.intro",
               defaultValue: "Please read and accept the points below.")
    }
    /// FER-398: el texto completo vive en la web de soporte, no en un archivo del repo. «TERMS.md,
    /// shipped with Cénit» era cierto para quien clona el repositorio y falso para quien baja la app
    /// de la tienda: ese archivo no viaja dentro del bundle, así que la puerta remitía a un documento
    /// inalcanzable. `TermsGateView` pinta esta línea como enlace a `fullTermsURL`.
    static var fine: String {
        String(localized: "terms.fine",
               defaultValue: "The full terms are at blandisc.github.io/cenit/terminos.html — this is not legal advice.")
    }

    /// La URL que abre la letra chica de arriba.
    static let fullTermsURL = URL(string: "https://blandisc.github.io/cenit/terminos.html")!
    static var consent: String {
        String(localized: "terms.consent",
               defaultValue: "I have read and accept these terms, and I'm using Cénit with my own device and my own data, at my own risk.")
    }
    static var cta: String {
        String(localized: "terms.cta", defaultValue: "Accept & Continue")
    }
}
