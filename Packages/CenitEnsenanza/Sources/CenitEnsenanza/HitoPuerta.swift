import Foundation

/// Honestidad temporal de un hito (épico FER-428 · FER-436): un hito solo dispara si su umbral
/// se cruzó DESPUÉS de la primera evaluación con esta versión. Nadie recibe «tu primera lectura»
/// con 40 noches: la primera vez que la app evalúa un hito registra si el umbral YA estaba
/// cruzado (`inicial`); los que ya lo estaban no disparan nunca.
///
/// Es la única lógica del paquete: pura, Foundation-only, sin estado. Quien la llama (la app)
/// guarda `inicial` por hito y se lo devuelve en cada evaluación; TipKit garantiza el «una sola
/// vez» del disparo (`MaxDisplayCount(1)`), esta regla garantiza el «después de instalar».
///
/// Tabla (`inicial`, `cruzadoAhora`) → veredicto:
///   (nil, nil)     → `.esperar`                  el dato no está y no hay nada que registrar
///   (nil, x)       → `.registrarInicial(x)`      primera evaluación: se guarda x
///   (true, _)      → `.nunca`                    ya estaba cruzado al instalar
///   (false, false) → `.esperar`                  todavía no cruza
///   (false, nil)   → `.esperar`                  el dato se fue (motor sin calcular): espera
///   (false, true)  → `.disparar`                 cruzó con esta versión instalada
public enum HitoPuerta {
    public enum Veredicto: Equatable, Sendable {
        /// Primera evaluación: guarda `cruzado` como el estado inicial del umbral.
        case registrarInicial(cruzado: Bool)
        /// El umbral ya estaba cruzado al arrancar con esta versión: no dispara jamás.
        case nunca
        /// Aún no cruza, o el dato no está: no hagas nada.
        case esperar
        /// Cruzó después de la primera evaluación: el hito se enseña (una sola vez, TipKit).
        case disparar
    }

    /// `inicial` es lo que se registró en la primera evaluación (`nil` = todavía no se registró
    /// porque el dato no estaba listo). `cruzadoAhora == nil` = el dato aún no está (motor sin
    /// calcular): no registres nada, espera.
    public static func decidir(inicial: Bool?, cruzadoAhora: Bool?) -> Veredicto {
        switch (inicial, cruzadoAhora) {
        case (nil, nil):
            return .esperar
        case (nil, let cruzado?):
            return .registrarInicial(cruzado: cruzado)
        case (true?, _):
            return .nunca
        case (false?, true?):
            return .disparar
        case (false?, _):
            return .esperar
        }
    }
}
