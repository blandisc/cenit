import SwiftUI
import CenitDesign
import CenitAnalytics
import CenitTraining

// MARK: - Acto 5 · Tu sesión · cierre (FER-520)
//
// Tras el permiso y el Acta(+coda), muestra el `DosePlan` concreto del día — mismo dueño que
// Entrenar (`Repository.seedTodayDose` → `DosePlanner`). El `verdeCarga` del peso es el ÚNICO hue
// saturado de la pantalla; las palabras del veredicto van en tinta (decisión del dueño).
//
// Variante sin reloj (D3 / FER-431): misma tarjeta como foco; en vez de la traducción
// palabra→carga, el mapa de pestañas. El aviso matutino YA NO se ofrece aquí (FER-525).
//
// El lienzo entra en `.circulacion`, con DOS centros: las motas viajan de un orbe al otro.

struct OnbActoSesion: View {

    let landing: OnboardingLanding?
    /// CTA final aterriza en Entrenar cuando es `true` (FER-431). La ruta con reloj pasa `false`
    /// salvo que eligió «Ir a Entrenar» en una rama sin palabra.
    let destinoEntrenar: Bool
    let onAtras: () -> Void
    let onEntrar: () -> Void

    @Environment(AppModel.self) private var model
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw: String = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { .init(rawValue: unitSystemRaw) ?? .metric }

    @State private var plan: DosePlan?
    @State private var cargo = false

    /// Variante adaptada para quien no tiene reloj (FER-431). Una sola definición vía
    /// `OnboardingLanding.esSinReloj`. «Ahora no» llega con `landing == nil` → también sin reloj.
    private var sinReloj: Bool {
        landing == nil || landing?.esSinReloj == true
    }

    /// ¿Hay palabra? Solo entonces se muestra la traducción palabra→carga.
    private var hayPalabra: Bool {
        if case .lectura = landing { return true }
        return false
    }

    var body: some View {
        let cta = destinoEntrenar ? OnbCopy.sinFcCta : OnbCopy.entrar

        OnbShell(indicadores: true) {
            Group {
                OnbAtras(accion: onAtras)

                OnbOverline(OnbCopy.sesionOverline)
                    .padding(.top, LiquidSpace.s250)
                OnbTitular(OnbCopy.sesionTitular)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(OnbCopy.sesionCuerpo)
                    .padding(.top, LiquidSpace.s300)
            }

            Group {
                tarjetaSesion
                    .padding(.top, LiquidSpace.s600)

                if hayPalabra && !sinReloj {
                    OnbOverline(OnbCopy.sesionPie)
                        .padding(.top, LiquidSpace.s800)
                    // FER-520: las tres palabras en TINTA (tono: nil), no teñidas. El único hue
                    // saturado de la pantalla es el `verdeCarga` del peso en la tarjeta.
                    OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.full),
                            tono: nil, glosa: OnbCopy.cicloFull)
                    OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.caution),
                            tono: nil, glosa: OnbCopy.cicloCaution)
                    OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.easy),
                            tono: nil, glosa: OnbCopy.cicloEasy)
                } else if sinReloj {
                    mapaSinReloj
                }
            }

            Group {
                OnbTitular(OnbCopy.cicloTitular)
                    .padding(.top, LiquidSpace.s800)

                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    Text(OnbCopy.cicloDock)
                        .groteskOverline()
                        .foregroundStyle(LiquidColor.tinta500)
                    OnbCuerpo(OnbCopy.cicloDockPie, tono: LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, LiquidSpace.s600)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(cta, variant: .primary, expands: true, action: onEntrar)
            }
        }
        .task { await cargarPlan() }
    }

    // MARK: - Tarjeta «Tu sesión»

    @ViewBuilder
    private var tarjetaSesion: some View {
        OnbTarjeta {
            if let plan, !plan.exercises.isEmpty {
                HStack(spacing: LiquidSpace.s200) {
                    Image(systemName: "dumbbell")
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .accessibilityHidden(true)
                    OnbOverline(plan.routineName)
                }
                ForEach(Array(plan.exercises.enumerated()), id: \.offset) { idx, ex in
                    if idx > 0 { OnbHairline() }
                    OnbSesionFila(exercise: ex, unitSystem: unitSystem)
                }
            } else if cargo {
                // Estado vacío honesto: sin numeral, sin verdeCarga.
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    Image(systemName: "dumbbell")
                        .font(LiquidType.valorM)
                        .foregroundStyle(LiquidColor.tinta500)
                        .accessibilityHidden(true)
                    OnbCuerpo(OnbCopy.sesionVacia, tono: LiquidColor.tinta700)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                // Cargando: no inventar una sesión falsa.
                ProgressView()
                    .tint(LiquidColor.tinta500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text(OnbCopy.sesionOverline))
            }
        }
    }

    // MARK: - Mapa sin reloj (FER-431 · D3)

    @ViewBuilder
    private var mapaSinReloj: some View {
        let sinDatos: Bool = {
            if case .sinDatos = landing { return true }
            return false
        }()
        OnbOverline(OnbCopy.cicloSinRelojOverlineMapa)
            .padding(.top, LiquidSpace.s800)
        OnbFila(nombre: OnbCopy.pestanaCuerpo,
                tono: nil,
                glosa: sinDatos ? OnbCopy.cicloSinRelojCuerpoSinSalud : OnbCopy.cicloSinRelojCuerpoGlosa)
        OnbFila(nombre: OnbCopy.pestanaEntrenar,
                tono: nil,
                glosa: OnbCopy.cicloSinRelojEntrenar)
        OnbFila(nombre: OnbCopy.pestanaAjustes,
                tono: nil,
                glosa: sinDatos ? OnbCopy.cicloSinRelojAjustesSinSalud : OnbCopy.cicloSinRelojAjustes)
    }

    // MARK: - DosePlan (mismo camino que Entrenar / widgets)

    @MainActor
    private func cargarPlan() async {
        defer { cargo = true }
        guard let tid = await repo.todayRoutineId() else {
            plan = nil
            return
        }
        let serving = await repo.programServing()
        let name = (await repo.routines()).first { $0.id == tid }?.name
        let result = await repo.seedTodayDose(
            routineId: tid,
            advice: repo.trainingAdvice,
            inventory: model.plates.inventory,
            serving: serving,
            routineName: name)
        plan = result.plan
    }
}

// MARK: - Fila de ejercicio (composición; sin tokens nuevos)

/// Una fila de la tarjeta «Tu sesión»: nombre a la izquierda; peso teñido `verdeCarga` + reps a la
/// derecha. En Dynamic Type AX apila (no trunca). VoiceOver combina el grupo.
struct OnbSesionFila: View {
    let exercise: DoseExercise
    let unitSystem: UnitSystem

    private var work: [DoseSet] {
        exercise.workSets.filter { $0.kind == .work }
    }

    private var seedKg: Double? { work.first?.seedWeightKg }
    private var series: Int { work.count }

    private var repsTexto: String {
        guard let set = work.first else { return "—" }
        if let top = set.repsRangeTop, let floor = set.reps, top != floor {
            return "\(floor)–\(top)"
        }
        if let r = set.reps { return "\(r)" }
        if let top = set.repsRangeTop { return "\(top)" }
        return "—"
    }

    private var pesoNumero: String {
        guard let kg = seedKg else { return "—" }
        return StrengthDisplay.weightNumber(kg, system: unitSystem)
    }

    private var unidad: String { StrengthDisplay.weightUnit(unitSystem) }

    private var repsLado: String {
        "\(unidad) · \(series)×\(repsTexto)"
    }

    private var subidaTexto: String? {
        guard let raise = exercise.heldRaise else { return nil }
        let peso = StrengthDisplay.weight(raise.toKg, system: unitSystem)
        return OnbCopy.sesionSubida(peso)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
                    nombre
                    Spacer(minLength: LiquidSpace.s200)
                    valores
                }
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    nombre
                    valores
                }
            }
            if let subidaTexto {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    Image(systemName: "arrow.up")
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.verdeCarga)
                        .accessibilityHidden(true)
                    Text(subidaTexto)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, LiquidSpace.s150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(a11yLabel))
    }

    private var nombre: some View {
        Text(exercise.name)
            .font(LiquidType.label)
            .tracking(LiquidType.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(LiquidColor.tinta900)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valores: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
            if seedKg != nil {
                Text(pesoNumero)
                    .font(LiquidType.valorM)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(LiquidColor.verdeCarga)
            }
            Text(repsLado)
                .font(LiquidType.datoMenor)
                .foregroundStyle(LiquidColor.tinta700)
        }
    }

    /// «Press de banca, 60 kilos, 3 series de 8; la subida a 62.5 kg queda a un toque».
    private var a11yLabel: String {
        var parts: [String] = [exercise.name]
        if seedKg != nil {
            parts.append(StrengthDisplay.weight(seedKg!, system: unitSystem))
        }
        parts.append("\(series)×\(repsTexto)")
        if let subidaTexto {
            parts.append(subidaTexto)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Predicado «sin reloj» (FER-431)

extension OnboardingLanding {
    /// `true` para `.sinRitmoEnReposo` y `.sinDatos`: decide la variante sin reloj de «Tu sesión».
    var esSinReloj: Bool {
        switch self {
        case .sinRitmoEnReposo, .sinDatos: return true
        default: return false
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct OnbSesionPreview: View {
    @State private var model = AppModel.preview
    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            OnbActoSesion(
                landing: .lectura(verdict: .full, noches: 22, diasHistoria: 180),
                destinoEntrenar: false,
                onAtras: {}, onEntrar: {})
        }
        .environment(model)
        .environmentObject(model.repo)
        .frame(width: 390, height: 800)
    }
}

private struct OnbSesionFilaPreview: View {
    var body: some View {
        let ex = DoseExercise(
            exerciseId: "bench",
            name: "Press de banca",
            order: 0,
            workSets: [
                DoseSet(reps: 8, seedWeightKg: 60, kind: .work),
                DoseSet(reps: 8, seedWeightKg: 60, kind: .work),
                DoseSet(reps: 8, seedWeightKg: 60, kind: .work),
            ],
            restSeconds: 120,
            heldRaise: DoseRaise(fromKg: 60, toKg: 62.5, phrase: "x"))
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            OnbTarjeta {
                OnbSesionFila(exercise: ex, unitSystem: .metric)
            }
            .padding(LiquidSpace.s400)
        }
        .frame(width: 390, height: 200)
    }
}

#Preview("Onboarding · Tu sesión") { OnbSesionPreview() }
#Preview("Onboarding · SesionFila") { OnbSesionFilaPreview() }
#endif
