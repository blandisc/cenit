// ensenanza: ajustes.novedades
#if os(iOS)
import SwiftUI
import CenitDesign
import CenitEnsenanza

// MARK: - «Novedades» (épico FER-428 · L2/FER-435, D2 = A)
//
// Qué cambió, por versión, la más reciente arriba; cada ítem con nombre · una línea · su ruta
// (la misma `AyudaFila` de Ayuda, sin puertas). Con pendientes, primero «Nuevo en {versión}» y
// después las anteriores bajo «Antes · {versión}»; sin pendientes, una tarjeta corta «Estás al
// día» y las versiones anteriores debajo. Al aparecer marca vista la versión actual: el «Nuevo»
// de la fila de Ajustes se apaga al volver. Nunca un modal — llega desde Ajustes → Novedades o
// desde la puerta de la tarjeta «Nuevo en esta versión» al fondo de Hoy.

struct NovedadesSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Foto de lo pendiente AL ABRIR: si se recalculara después de `marcarVistas()`, «Nuevo en …»
    /// se volvería «Antes» ante los ojos del usuario.
    @State private var pendientes: [Novedades.Version] = NovedadesEstado.pendientes

    private var anteriores: [Novedades.Version] {
        let nuevas = Set(pendientes.map(\.version))
        return NovedadesEstado.porVersion.filter { !nuevas.contains($0.version) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                header
                if pendientes.isEmpty {
                    alDia.padding(.top, LiquidSpace.s300)
                }
                ForEach(pendientes, id: \.version) { version in
                    seccion(version, kicker: String(localized: "novedades.seccion.nuevo",
                                                    defaultValue: "New in \(version.version)"))
                }
                ForEach(anteriores, id: \.version) { version in
                    seccion(version, kicker: String(localized: "novedades.seccion.antes",
                                                    defaultValue: "Before · \(version.version)"))
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) { dismiss() }
                    .foregroundStyle(LiquidColor.tinta900)
            }
        }
        .onAppear { NovedadesEstado.marcarVistas() }
    }

    // MARK: - Header (hermano de Ayuda)

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidOverline(String(localized: "What's new"))
            Text(String(localized: "novedades.titulo", defaultValue: "What changed"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "novedades.subtitulo",
                        defaultValue: "Each version: what's new and where to find it."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - «Estás al día»

    /// Una noticia chica, no un estado vacío con ilustración: el único color es el dato
    /// «no hay nada nuevo» (`checkmark.circle` en `verdeProfundo`).
    private var alDia: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s250) {
            Image(systemName: "checkmark.circle")
                .font(LiquidType.iconSF(size: 18))
                .foregroundStyle(LiquidColor.verdeProfundo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(String(localized: "novedades.alDia.titulo", defaultValue: "You're up to date"))
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(anteriores.isEmpty
                     ? String(localized: "novedades.alDia.sinLista",
                              defaultValue: "Nothing to list yet for this version.")
                     : String(localized: "novedades.alDia.cuerpo",
                              defaultValue: "You've seen what's in \(NovedadesEstado.versionActual). Below, what each version brought."))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Una versión

    private func seccion(_ version: Novedades.Version, kicker: String) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            LiquidSectionHeader(LocalizedStringKey(kicker)) {
                if version.version == NovedadesEstado.versionActual {
                    Text(String(localized: "novedades.seccion.estaVersion", defaultValue: "this version"))
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            VStack(spacing: .zero) {
                ForEach(version.funcionalidades) { funcionalidad in
                    AyudaFila(funcionalidad: funcionalidad,
                              divider: funcionalidad.id != version.funcionalidades.last?.id)
                }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
    }
}
#endif
