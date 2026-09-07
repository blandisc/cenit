import SwiftUI
#if DEBUG
import Combine
#endif

// MARK: - Recarga en caliente (hot reload) — FER-398
//
// Este archivo SUSTITUYE al paquete `Inject` (github.com/krzysztofzablocki/Inject), que se retiró
// de `project.yml`. El paquete sigue el mismo contrato en Release —todo inerte— pero **igual viajaba
// dentro del binario de la tienda**: una dependencia de terceros, exclusivamente para desarrollo,
// en el .ipa que se sube a App Store. Las dos piezas que la app usa de él (`@ObserveInjection` y
// `.enableInjection()`) caben en 40 líneas, así que aquí viven, `#if DEBUG` de verdad: en Release
// no queda ni una línea de código de recarga en caliente.
//
// Uso (igual que antes, no cambia ningún call site):
//   @ObserveInjection private var inject      // en el struct de la vista
//   …
//   .enableInjection()                        // al final del `body`
//
// Cuidado con `private`: `-interposable` solo alcanza símbolos globales, así que los miembros de un
// tipo privado quedan inertes EN SILENCIO (la inyección reporta éxito y la pantalla no cambia).
// Cuelga los hooks de la vista NO privada más externa del archivo. Ver docs/BUILD.md.

#if DEBUG

/// Escucha `INJECTION_BUNDLE_NOTIFICATION` —la notificación que publica el bundle de inyección cada
/// vez que intercambia código— y publica un contador. Cualquier vista con `@ObserveInjection` observa
/// este objeto, así que su `body` se vuelve a evaluar (ya con el código nuevo) al guardar un archivo.
final class HotReloadObserver: ObservableObject, @unchecked Sendable {
    static let shared = HotReloadObserver()

    @Published private(set) var injectionNumber = 0
    private var cancellable: AnyCancellable?

    private init() {
        HotReload.loadBundleIfAvailable()
        cancellable = NotificationCenter.default
            .publisher(for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.injectionNumber += 1 }
    }
}

/// Marca una vista como «redibújate cuando entre código nuevo». No-op en Release.
@propertyWrapper @preconcurrency @MainActor
struct ObserveInjection: DynamicProperty {
    @ObservedObject private var observer = HotReloadObserver.shared
    nonisolated init() {}
    /// Cuántas inyecciones lleva el proceso. Los call sites no lo leen (declarar la propiedad basta
    /// para suscribir la vista); está expuesto por si alguna quiere reaccionar explícitamente.
    var wrappedValue: Int { observer.injectionNumber }
}

extension View {
    /// Activa la recarga en caliente para esta vista. `AnyView` a propósito (igual que hacía `Inject`):
    /// si la inyección cambia la ESTRUCTURA de la vista, el tipo concreto de `body` deja de coincidir
    /// con el que SwiftUI tiene cacheado; borrar el tipo evita ese choque. Solo en Debug.
    func enableInjection() -> some View {
        HotReload.loadBundleIfAvailable()
        return AnyView(self)
    }
}

/// Carga el bundle de inyección del Mac anfitrión, si la app de inyección está instalada.
enum HotReload {
    /// Idempotente y barata: la primera llamada carga el bundle, las demás no hacen nada.
    static func loadBundleIfAvailable() { _ = loadedOnce }

    /// `static let` perezoso: corre a lo más una vez por proceso y es thread-safe.
    private static let loadedOnce: Void = {
        // El bundle solo existe en el Mac del desarrollador, así que solo tiene sentido en el
        // simulador (o Catalyst). En un iPhone físico no hay nada que cargar.
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        guard objc_getClass("InjectionClient") == nil else { return }
        // InjectionNext es el sucesor de InjectionIII (el clásico ya no logra el redibujo en
        // toolchains Xcode 16.3+/26.x), pero los dos se siguen usando: se prueban ambos.
        // `maciOSInjection.bundle` es la variante para app iOS corriendo sobre el Mac.
        let apps = ["InjectionNext", "InjectionIII"]
        let bundles = ["iOSInjection.bundle", "maciOSInjection.bundle"]
        for app in apps {
            for bundle in bundles {
                let path = "/Applications/\(app).app/Contents/Resources/\(bundle)"
                if let b = Bundle(path: path), b.load() { return }
            }
        }
        print("⚠️ HotReload: no encontré el bundle de inyección en /Applications/Injection{Next,III}.app")
        #endif
    }()
}

#else

// Release: los mismos nombres, sin nada detrás. Ni observador, ni notificación, ni `AnyView`.

@propertyWrapper
struct ObserveInjection: DynamicProperty {
    init() {}
    var wrappedValue: Int { 0 }
}

extension View {
    @inlinable @inline(__always)
    func enableInjection() -> Self { self }
}

enum HotReload {
    @inlinable @inline(__always)
    static func loadBundleIfAvailable() {}
}

#endif
