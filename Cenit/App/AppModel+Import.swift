import BiometricStreams
import CenitDesign
import CenitStore
import Combine
import Observation
import StrandAnalytics
import StrandImport
import StrandTraining
import SwiftUI

/// De qué fuente viene la importación que está corriendo desde «Datos y fuentes».
enum DataSourceImportKind {
    case appleHealth
}

extension AppModel {

    /// Detiene la importación en vuelo, si la hay. El importador para en su siguiente punto de
    /// cooperación y la tarjeta vuelve a su estado en reposo.
    func cancelImport() { importTask?.cancel() }

    /// Cierto solo para la fuente que está importando en este momento.
    func isImporting(_ source: DataSourceImportKind) -> Bool {
        activeImportSource == source
    }

    /// Si la última importación de esa fuente terminó mal. La tarjeta lo usa para pintarse de aviso.
    func importFailed(_ source: DataSourceImportKind) -> Bool {
        switch source {
        case .appleHealth: return appleHealthImportFailed
        }
    }

    /// Importa una exportación de Apple Salud: la lee en flujo, la agrega por día bajo la fuente de
    /// Apple y refresca el tablero. Un archivo grande tarda uno o dos minutos.
    func importAppleHealth(url: URL) {
        beginImport(.appleHealth)
        importTask?.cancel()

        importTask = Task { [weak self] in
            guard let self else { return }

            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                guard let store = await repo.storeHandle() else {
                    finishImport(.appleHealth, summary: "Couldn't open the local store.", failed: true)
                    return
                }

                // El parseo avisa su avance desde otro hilo; hay que volver al actor principal para
                // mover el contador que la tarjeta está observando.
                let progress: AppleHealthImporter.ProgressHandler = { count in
                    Task { @MainActor [weak self] in self?.appleHealthImportProgress = count }
                }

                let summary = try await AppleHealthImport.importExport(
                    url: url,
                    into: store,
                    deviceId: appleDeviceId,
                    maxHR: repo.strainHRmax,
                    sex: repo.strainSex,
                    progress: progress,
                    isCancelled: { Task.isCancelled }
                )

                await repo.refresh()
                finishImport(.appleHealth, summary: "Imported \(summary.recordCount) records")
            } catch is CancellationError {
                // Irse a media importación no es una falla: no hay nada que reportar en rojo.
                finishImport(.appleHealth, summary: "Import cancelled.")
            } catch {
                finishImport(.appleHealth, summary: "Import failed: \(error)", failed: true)
            }
        }
    }

    /// Marca la fuente como ocupada y limpia SOLO su estado anterior: el texto, el indicador de falla
    /// y el avance. Lo de las demás fuentes se queda como estaba.
    private func beginImport(_ source: DataSourceImportKind) {
        activeImportSource = source
        switch source {
        case .appleHealth:
            appleHealthImportSummary = nil
            appleHealthImportFailed = false
            appleHealthImportProgress = nil
        }
    }

    /// Deja el resultado en la tarjeta de su fuente y libera el carril de importación.
    private func finishImport(_ source: DataSourceImportKind, summary: String, failed: Bool = false) {
        switch source {
        case .appleHealth:
            appleHealthImportSummary = summary
            appleHealthImportFailed = failed
            appleHealthImportProgress = nil
        }
        activeImportSource = nil
    }
}
