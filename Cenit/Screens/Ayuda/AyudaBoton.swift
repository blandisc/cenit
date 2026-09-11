// ensenanza: ajustes.ayuda
#if os(iOS)
import SwiftUI
import CenitDesign
import CenitEnsenanza

// MARK: - El «?» de la cabecera (épico FER-428 · L2/FER-435)
//
// Un solo botón para las cuatro pestañas: el «?» que ya tenía el hub de Entrenar (`questionmark
// .circle` 18, tinta500, 44×44), promovido al aparecer en la tercera pantalla (LIQUID-GLASS §9.3)
// para que ninguna pestaña lo redibuje. Abre «Cómo funciona Cénit» desplazada a la sección de
// su pestaña. Sin rótulo visible: el glifo ya es la convención de la app (estantes de la Matriz,
// hojas) y el título de la hoja lo nombra al instante; VoiceOver lo lee como «Cómo funciona».
// Va en `Cenit/Screens` y no en `CenitDesign` por decisión del director (este lote no toca el
// paquete): si aparece un quinto sitio, promoverlo es mover este archivo.

struct AyudaBoton: View {
    let seccion: Pestana

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var presentada = false

    var body: some View {
        Button { presentada = true } label: {
            Image(systemName: "questionmark.circle")
                .font(LiquidType.iconSF(size: 18))
                .foregroundStyle(LiquidColor.tinta500)
                .frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityLabel(Text("How it works"))
        .accessibilityHint(Text(String(localized: "ayuda.boton.hint",
                                       defaultValue: "Opens help at the \(AyudaScreen.titulo(seccion)) section")))
        .sheet(isPresented: $presentada) {
            // La hoja abre una rama nueva del entorno: se reinyecta lo que Ayuda necesita (mismo
            // patrón que las hojas hermanas de Ajustes y de Hoy). `AyudaScreen` es dueña de su
            // NavigationStack (rediseño índice) — aquí ya no se envuelve.
            AyudaScreen(inicial: seccion)
                .environmentObject(repo)
                .environmentObject(tabRouter)
        }
    }
}
#endif
