import SwiftUI

// MARK: - LiquidSlider (FER-482)
//
// El deslizador de vidrio del sistema — hermano de `LiquidToggleStyle`/`EntrenarStepper`. Sustituye
// a los `Slider(...)` crudos de SwiftUI (que solo aceptan `.tint`, no el look El Eje): pista de
// vidrio (`tinta10`), relleno en el `base` del tono (verde de carga por defecto) y perilla de papel
// con sombra, como el knob del toggle.
//
// POR QUÉ NO ES UN `Slider` PELADO: los call sites viven DENTRO del `ScrollView` de una hoja
// (RestEditor). Un `DragGesture` de SwiftUI le roba el scroll vertical al ScrollView (FER-73, misma
// clase que el scrub de la Matriz), así que el arrastre se construye sobre `liquidScrubPan`: solo
// empieza si el dedo va más horizontal que vertical, y el scroll vertical de la hoja queda intacto.

public struct LiquidSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let tono: LiquidTono
    private let accessibilityValueText: String?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: valor actual (en las unidades de `range`).
    ///   - range: rango cerrado permitido.
    ///   - step: paso de cuantización; `nil` = continuo.
    ///   - tono: color del relleno (`.verde` → verde de carga, el color que ya usaban las sliders).
    ///   - accessibilityValueText: cómo lee VoiceOver el valor ("78 bpm", "42 %"). Si es `nil`, se
    ///     usa el número crudo.
    public init(value: Binding<Double>,
                in range: ClosedRange<Double>,
                step: Double? = nil,
                tono: LiquidTono = .verde,
                accessibilityValueText: String? = nil) {
        self._value = value
        self.range = range
        self.step = step
        self.tono = tono
        self.accessibilityValueText = accessibilityValueText
    }

    private let trackHeight: CGFloat = 6
    private let knobD: CGFloat = 28

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(1, width - knobD)
            let knobX = knobD / 2 + fraction(of: value) * usable
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LiquidColor.tinta10)
                    .frame(height: trackHeight)
                Capsule(style: .continuous)
                    .fill(tono.base)
                    .frame(width: knobX, height: trackHeight)
                Circle()
                    .fill(LiquidColor.papelTarjeta)
                    .overlay(Circle().strokeBorder(LiquidColor.tinta900.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: LiquidColor.tinta900.opacity(0.28), radius: 1.5, x: 0, y: 1)
                    .frame(width: knobD, height: knobD)
                    .offset(x: knobX - knobD / 2)
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .liquidScrubPan(enabled: isEnabled,
                            onChange: { p in setValue(fromX: p.x, usable: usable, animated: false) },
                            onEnd: {})
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { g in
                    setValue(fromX: g.location.x, usable: usable, animated: true)
                }
            )
        }
        .frame(height: LiquidControl.hitTarget)
        .opacity(isEnabled ? 1 : CenitOpacity.dim)
        .accessibilityElement()
        .accessibilityValue(Text(accessibilityValueText ?? defaultValueText))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = clampSnap(value + delta)
            case .decrement: value = clampSnap(value - delta)
            @unknown default: break
            }
        }
    }

    private func fraction(of v: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (v - range.lowerBound) / span))
    }

    private func setValue(fromX x: CGFloat, usable: CGFloat, animated: Bool) {
        guard isEnabled else { return }
        let frac = min(1, max(0, Double((x - knobD / 2) / usable)))
        let raw = range.lowerBound + frac * (range.upperBound - range.lowerBound)
        let snapped = clampSnap(raw)
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { value = snapped }
        } else {
            value = snapped
        }
    }

    private func clampSnap(_ v: Double) -> Double {
        var out = v
        if let step, step > 0 { out = (v / step).rounded() * step }
        return min(range.upperBound, max(range.lowerBound, out))
    }

    private var defaultValueText: String {
        if let step, step >= 1 { return String(Int(value.rounded())) }
        return String(format: "%.2f", value)
    }
}

#if DEBUG
#Preview("LiquidSlider · estados") {
    struct Demo: View {
        @State private var margin: Double = 20
        @State private var reserve: Double = 0.42
        @State private var fija: Double = 120
        var body: some View {
            VStack(alignment: .leading, spacing: LiquidSpace.s600) {
                LiquidSlider(value: $margin, in: 5...30, step: 1,
                             accessibilityValueText: "\(Int(margin)) bpm")
                LiquidSlider(value: $reserve, in: 0.30...0.55, step: 0.01,
                             accessibilityValueText: "\(Int((reserve * 100).rounded())) %")
                LiquidSlider(value: .constant(0.5), in: 0...1)
                    .disabled(true)
                LiquidSlider(value: $fija, in: 80...170, step: 1)
                    .environment(\.dynamicTypeSize, .accessibility3)
            }
            .padding(LiquidSpace.s600)
            .background(LiquidColor.fondoGradient)
        }
    }
    return Demo()
}
#endif
