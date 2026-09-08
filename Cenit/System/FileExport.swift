import Foundation
import UIKit
import UniformTypeIdentifiers

/// «Guardar o compartir un archivo».
///
/// Levanta la hoja de compartir del sistema (`UIActivityViewController`) para que la persona
/// guarde el archivo en Archivos, lo pase por AirDrop o lo mande a otra app: la forma nativa de
/// sacar algo del recinto de la app.
enum FileExport {

    /// Escribe `text` en un archivo temporal y deja que la persona elija a dónde va.
    /// - Returns: `true` cuando el archivo quedó escrito y la hoja se presentó; `false` cuando la
    ///   escritura falló, para que quien llama pueda avisar (FER-969 · X-05b). Antes un `return`
    ///   pelón dejaba a la persona sin hoja y sin mensaje.
    @MainActor
    @discardableResult
    static func exportText(_ text: String, suggestedName: String) -> Bool {
        // Se escribe PRIMERO y sólo se presenta la hoja si el archivo de verdad quedó en disco:
        // tragarse el fallo entregaba a la hoja una ruta que no existía, y la persona veía una
        // exportación rota sin ningún aviso. El temporal se borra al cerrar la hoja, para que
        // `temporaryDirectory` no acumule exportaciones muertas de una corrida a otra.
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
        do {
            try text.write(to: destino, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        present(activityItems: [destino], cleanup: [destino])
        return true
    }

    /// Deja que la persona guarde o comparta un archivo que ya existe en `src`. Ese archivo es de
    /// quien llama (por ejemplo una captura dentro del contenedor de la app) y NO se borra al
    /// cerrar la hoja: sólo se limpia lo que esta clase preparó.
    @MainActor
    static func exportFile(at src: URL, suggestedName: String? = nil) {
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        present(activityItems: [src], cleanup: [])
    }

    /// Comparte una imagen (una tarjeta de recibo ya dibujada, FER-720 · 3c) por la hoja del
    /// sistema: se puede guardar en Fotos, pasar por AirDrop o mandar a otra app. Nada sale de la
    /// app hasta que la persona elige un destino.
    @MainActor
    static func exportImage(_ image: UIImage) {
        present(activityItems: [image], cleanup: [])
    }

    /// Guarda una imagen directo en la fototeca (FER-720 · 3c «Guardar»). iOS pide su propio
    /// permiso de sólo-agregar la primera vez; es al mejor esfuerzo, así que un permiso negado
    /// simplemente no hace nada. Necesita la clave `NSPhotoLibraryAddUsageDescription`.
    @MainActor
    static func saveImageToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    /// Presenta la hoja de compartir y, al cerrarse, borra al mejor esfuerzo las URLs de `cleanup`,
    /// para que las exportaciones preparadas no se acumulen en `temporaryDirectory`.
    @MainActor
    private static func present(activityItems: [Any], cleanup: [URL]) {
        guard let anfitrion = topViewController() else { return }
        let hoja = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if !cleanup.isEmpty {
            hoja.completionWithItemsHandler = { _, _, _, _ in
                let disco = FileManager.default
                for temporal in cleanup where disco.fileExists(atPath: temporal.path) {
                    try? disco.removeItem(at: temporal)
                }
            }
        }
        // En iPad el popover necesita un ancla o revienta: se fija al centro de la pantalla.
        if let popover = hoja.popoverPresentationController {
            popover.sourceView = anfitrion.view
            popover.sourceRect = CGRect(x: anfitrion.view.bounds.midX,
                                        y: anfitrion.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        anfitrion.present(hoja, animated: true)
    }

    /// La vista que de verdad está en pantalla, no la raíz de la ventana. Cuando quien llama vive
    /// dentro de una hoja (Ajustes → Fuentes de datos), la raíz ya está presentando esa hoja de
    /// SwiftUI, y presentar encima de ella lanza «… which is already presenting …» sin que aparezca
    /// nada. Subir por la cadena de presentación deja la hoja sobre lo que se ve.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let escena = escenas.first { $0.activationState == .foregroundActive } ?? escenas.first
        guard var cima = escena?.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? escena?.windows.first?.rootViewController else { return nil }
        while let encima = cima.presentedViewController { cima = encima }
        return cima
    }
}
