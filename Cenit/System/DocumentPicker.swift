#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// Envoltura asíncrona de `UIDocumentPickerViewController` para sacar y meter el respaldo de la
/// base en iOS. Cada llamada presenta el selector del sistema desde la ventana activa y despierta
/// a quien esperaba con la URL elegida, o con `nil` si la persona canceló.
enum DocumentPicker {

    /// Selector para EXPORTAR `url`: deja una copia en Archivos / iCloud Drive. Devuelve el destino
    /// que eligió la persona, o `nil` si canceló.
    @MainActor
    static func export(_ url: URL) async -> URL? {
        await present { UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
    }

    /// Selector para ABRIR un archivo de alguno de esos tipos. Va con `asCopy: true` para recibir una
    /// copia local legible dentro del recinto de la app: así no hay que llevar la contabilidad del
    /// alcance de seguridad.
    @MainActor
    static func importFile(_ types: [UTType]) async -> URL? {
        await present {
            let selector = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            selector.allowsMultipleSelection = false
            return selector
        }
    }

    /// Selector para elegir una CARPETA — por ejemplo dentro de iCloud Drive — como destino de los
    /// respaldos automáticos. A diferencia de los dos de arriba devuelve la URL real **con alcance de
    /// seguridad** (`asCopy: false`), para que quien llama guarde un marcador y siga escribiendo ahí
    /// en corridas posteriores sin volver a preguntar. Funciona con un Apple ID gratuito: toca el
    /// iCloud Drive de la persona a través de Archivos, y eso no necesita el permiso de contenedor de
    /// iCloud. Devuelve `nil` si canceló.
    @MainActor
    static func pickFolder() async -> URL? {
        await present {
            let selector = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            selector.allowsMultipleSelection = false
            return selector
        }
    }

    // MARK: - La fontanería de la presentación

    /// Arma el selector que le pidan, le engancha el coordinador, lo presenta desde la ventana
    /// activa y espera a que la persona decida.
    @MainActor
    private static func present(_ build: () -> UIDocumentPickerViewController) async -> URL? {
        guard let anfitrion = topViewController() else { return nil }
        return await withCheckedContinuation { (espera: CheckedContinuation<URL?, Never>) in
            let selector = build()
            let enlace = Coordinator(continuation: espera)
            selector.delegate = enlace
            // El coordinador tiene que seguir vivo mientras el selector esté en pantalla.
            objc_setAssociatedObject(selector, &Coordinator.assocKey, enlace, .OBJC_ASSOCIATION_RETAIN)
            anfitrion.present(selector, animated: true)
        }
    }

    /// Lo más arriba que hay en pantalla ahora mismo: la escena al frente (o la primera que haya),
    /// su ventana principal, y de ahí subiendo por lo que esté presentado encima.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let escena = escenas.first { $0.activationState == .foregroundActive } ?? escenas.first
        var cima = escena?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? escena?.windows.first?.rootViewController
        while let encima = cima?.presentedViewController { cima = encima }
        return cima
    }

    /// Traduce los dos desenlaces del selector — eligió o canceló — a una sola respuesta, y se
    /// asegura de contestar UNA vez: reanudar dos veces una continuación revienta el proceso.
    private final class Coordinator: NSObject, UIDocumentPickerDelegate {
        static var assocKey = 0
        private let continuation: CheckedContinuation<URL?, Never>
        private var yaRespondio = false

        init(continuation: CheckedContinuation<URL?, Never>) {
            self.continuation = continuation
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            responder(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            responder(nil)
        }

        private func responder(_ url: URL?) {
            guard !yaRespondio else { return }
            yaRespondio = true
            continuation.resume(returning: url)
        }
    }
}
#endif
