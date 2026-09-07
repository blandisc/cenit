#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - «Acerca de y soporte» — Liquid Glass · El Eje (FER-180)
//
// Hoja Liquid Glass · El Eje (familia FER-108): header (overline + displayS + subtítulo),
// identidad/versión/misión en una `liquidTarjetaSeccion`, disclaimer quieto al pie, suelo
// `LiquidSheetFondo`. Solo piel — FER-381 ya dejó el contenido en identidad + versión + misión +
// el disclaimer «no afiliado / no dispositivo médico». Cada caller la monta en su propio

struct SupportView: View {
    /// Single source of truth for the version pill: the app bundle's marketing version, same value
    /// `AjustesView`'s footer shows.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s800) {
                header
                aboutCard
                creditsSection
                linksSection
                disclaimer
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidOverline(String(localized: "About"))
            Text("About & support")
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text("\(ProjectInfo.appName): all your data, none uploaded.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false,
                           vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - About (identity + version pill + offline mission) — one Liquid card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(spacing: LiquidSpace.s200) {
                Text(ProjectInfo.appName).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                Text("v\(appVersion)")
                    .font(LiquidType.unidadCompacta)
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.horizontal, LiquidSpace.s250)
                    .padding(.vertical, LiquidSpace.s075)
                    // Opaque pill: this screen rides a SHEET (paper), so no translucent glass inside
                    // it (design-lint `no-sheet-glass`) — `.pastillaSolida` is the solid paper variant
                    // (same recipe DataSourcesView uses for its coverage pill).
                    .liquidGlass(.pastillaSolida)
                Spacer(minLength: 0)
            }

            Text("A health app built on Apple Health. It all runs on this device: your history, your nights, your numbers. Cénit uploads nothing. \(ProjectInfo.appName) is an independent, experimental project.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false,
                           vertical: true)
        }
        .liquidTarjetaSeccion()
    }

    // MARK: - Credits & licenses (FER-398)

    /// Third-party work Cénit ships. `ATTRIBUTION.md` and the bundled `SpaceGrotesk-OFL.txt` carry
    /// the full texts; this is the in-app acknowledgment, which is the one an App Store reviewer
    /// (and a user) can actually reach. Not a link list on purpose — naming the work and its
    /// licence is what attribution owes; a chevron here would promise a screen that doesn't exist.
    private var creditsSection: some View {
        section(String(localized: "Credits & licenses")) {
            VStack(spacing: .zero) {
                creditRow("GRDB.swift", "MIT")
                creditRow("ZIPFoundation", "MIT")
                // Los nombres de licencia NO se traducen: son nombres propios, igual que los de las
                // bibliotecas. Por eso van como literal y no por el catálogo.
                creditRow("Space Grotesk", "SIL Open Font License 1.1")
                creditRow("free-exercise-db", "The Unlicense", divider: false)
            }
            .liquidTarjetaSeccion()
        }
    }

    /// One credit: the work on the left, its licence in the row's accessory slot. The licence rides
    /// in `accessory` rather than `trailing` on purpose — a non-`EmptyView` accessory REPLACES the
    /// standard affordance, so the row drops the chevron it would otherwise promise.
    private func creditRow(_ name: String, _ license: String, divider: Bool = true) -> some View {
        LiquidListRow(title: name, divider: divider) {
            Text(license)
                .font(LiquidType.unidadCompacta)
                .foregroundStyle(LiquidColor.tinta500)
        }
    }

    // MARK: - Links (FER-398)

    /// The three pages App Review asks for by name — privacy policy, support, terms — reachable from
    /// inside the app, not only from the store listing. `Link` over `LiquidListRow`: the row keeps the
    /// system's geometry and chevron, and the link gives VoiceOver the right trait.
    private var linksSection: some View {
        section(String(localized: "Links")) {
            VStack(spacing: .zero) {
                Link(destination: Self.privacyURL) {
                    LiquidListRow(title: String(localized: "Privacy policy"))
                }
                Link(destination: Self.supportURL) {
                    LiquidListRow(title: String(localized: "Support"))
                }
                Link(destination: Terms.fullTermsURL) {
                    LiquidListRow(title: String(localized: "Terms of use"), divider: false)
                }
            }
            .liquidTarjetaSeccion()
        }
    }

    private static let privacyURL = URL(string: "https://blandisc.github.io/cenit/privacidad.html")!
    private static let supportURL = URL(string: "https://blandisc.github.io/cenit/soporte.html")!

    // MARK: - Section shell

    /// Overline + content, the same shape the rest of the sheet families use.
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidOverline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Disclaimer (single, quiet, at the foot)

    private var disclaimer: some View {
        Text("Not a medical device.")
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false,
                       vertical: true)
    }
}

#Preview {
    NavigationStack { SupportView() }
}
#endif
