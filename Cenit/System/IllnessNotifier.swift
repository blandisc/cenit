import Foundation
import CenitStore
import UserNotifications

/// Saca el aviso temprano de enfermedad a una notificación del sistema, justo en el salto de
/// «sin aviso» a «aviso». Sin ella el aviso sólo se ve con la app abierta. Va limitado a uno
/// por día natural local; el aviso dentro de la app sigue siendo la superficie viva. Todo se
/// calcula en el dispositivo y el resumen es APROXIMADO: información, nunca un diagnóstico.
enum IllnessNotifier {
    /// Preferencia local: el día natural en que salió el último aviso.
    private static let lastPostedDayKey = "behavior.illnessLastNotifiedDay"
    /// Un solo aviso vivo — el nuevo reemplaza al anterior en el centro de notificaciones.
    private static let requestID = "illness-watch"

    /// Se pide de frente, al encender la vigilancia, para que el diálogo del sistema salga en un
    /// momento predecible y no en la primera transición de las 3 de la mañana. Devuelve si el
    /// sistema la concedió: Ajustes necesita la respuesta para saber si el interruptor puede
    /// quedarse encendido.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The current, real system permission — read again whenever Ajustes returns to the foreground,
    /// so granting it in iOS Settings and coming back doesn't leave the switch on stale state.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Publica el aviso temprano, a lo más una vez por día natural local.
    static func post(_ message: String) {
        let hoy = dayKey(Date())
        let prefs = UserDefaults.standard
        guard prefs.string(forKey: lastPostedDayKey) != hoy else { return }
        // El día se marca ANTES de publicar: así el tope de uno por día se sostiene aunque el
        // usuario haya rechazado las notificaciones o la entrega se difiera. El aviso dentro de
        // la app sigue ahí de cualquier modo, y nunca se re-pregunta ni se reintenta.
        prefs.set(hoy, forKey: lastPostedDayKey)

        let centro = UNUserNotificationCenter.current()
        // El permiso se pide una sola vez desde `requestAuthorization()`, al encender la
        // vigilancia. Aquí sólo se consulta el estado: nada de un segundo diálogo del sistema.
        centro.getNotificationSettings { ajustes in
            guard ajustes.authorizationStatus == .authorized else { return }
            centro.add(UNNotificationRequest(identifier: requestID,
                                             content: alertContent(for: message),
                                             trigger: nil))
        }
    }

    private static func alertContent(for message: String) -> UNMutableNotificationContent {
        let alerta = UNMutableNotificationContent()
        alerta.title = String(localized: "Unusual signals last night · take it easy")
        alerta.subtitle = String(localized: "On-device estimate (approximate): not a diagnosis.")
        alerta.body = message
        alerta.sound = .default
        return alerta
    }

    private static func dayKey(_ date: Date) -> String { DayKey.local(date) }
}
