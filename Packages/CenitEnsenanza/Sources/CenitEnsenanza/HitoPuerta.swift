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

/// Elegibilidad de los DOS hitos de Hoy —«Primera lectura» (noche `seed`) y «Base firme»
/// (noche `trust`)— a partir de la lectura de Preparación, SIN tocar `Preparedness.Read`: el
/// paquete es Foundation-only, así que la app extrae los campos y los pasa como primitivas.
///
/// La clave (FER-436 · qa r1): **dato ausente ≠ umbral no cruzado**. El pase completo corre sobre
/// un store VACÍO antes de que el onboarding conecte Apple Salud, y publica un `Read` con 0 noches
/// (`lowSignal`, `drivers: []`, `autonomicNights: 0`). Eso NO es «tu umbral todavía no cruza» —que
/// se registraría como `false` y luego DISPARARÍA con el primer sync de 180 días, sacándole «Base
/// firme» a alguien con 179 noches—: es «todavía no sé nada de ti». Cuando `hayHistoria == false`
/// ambos hitos devuelven `nil`, y `HitoPuerta` espera (no registra) hasta que exista historia real.
///
/// `hayHistoria` es la MISMA «no encontré tu día» de `Repository.conservaVeredictoPrevio`:
/// `!(drivers.isEmpty && autonomicNights == 0)`.
///
/// Ambos hitos exigen reloj (`!sinReloj`): sin la señal autonómica de anoche no hay «primera
/// lectura», y la mañana en que `autonomicNights` llega a `trust` sin lectura no debe sacar «Base
/// firme» bajo un héroe «Baja señal» (FER-436 · D2).
public enum HitoHoy {
    /// `nil` = dato ausente (espera); `false` = con historia pero el umbral aún no cruza;
    /// `true` = cruzado. Devuelve el par en el orden en que los evalúa la app.
    public static func elegibilidad(hayHistoria: Bool,
                                    hayVeredicto: Bool,
                                    sinReloj: Bool,
                                    autonomicNights: Int,
                                    seed: Int,
                                    trust: Int) -> (primeraLectura: Bool?, baseFirme: Bool?) {
        guard hayHistoria else { return (nil, nil) }
        let primeraLectura = !sinReloj && hayVeredicto && autonomicNights >= seed
        let baseFirme = !sinReloj && autonomicNights >= trust
        return (primeraLectura, baseFirme)
    }
}
