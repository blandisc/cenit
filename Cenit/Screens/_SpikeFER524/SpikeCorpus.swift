#if DEBUG && CENIT_SPIKE_IALOCAL
import Foundation

// FER-524 spike DESECHABLE. Corpus embebido es-MX (~18 rutinas de texto libre)
// para medir calidad/latencia sin teclear. Coloquial, sinonimos, taquigrafia.

struct SpikeCorpusItem: Identifiable, Sendable {
    let id: String
    let title: String
    /// Texto libre que el dueno pega / carga al modelo.
    let text: String
    /// Notas de cobertura (taquigrafia, superserie, etc.) para la rubrica.
    let tags: [String]
}

enum SpikeCorpus {
    static let items: [SpikeCorpusItem] = [
        .init(
            id: "taqui-sentadilla",
            title: "Taquigrafia · sentadilla",
            text: "4x8 sentadilla 80kg descanso 2min",
            tags: ["taquigrafia", "peso", "descanso"]
        ),
        .init(
            id: "empuje-basico",
            title: "Empuje basico",
            text: """
            Dia de empuje:
            - Press banca 4 series de 8 con 60 kg, descanso 2 minutos
            - Press militar 3x10 a 35kg
            - Fondos en paralelas 3x12 (peso corporal)
            """,
            tags: ["multi-ejercicio", "bodyweight"]
        ),
        .init(
            id: "sinonimo-banca",
            title: "Sinonimo · banca",
            text: "Hoy pecho: banca 5x5 100kg, luego aperturas con mancuernas 3x12 18kg",
            tags: ["sinonimo", "banca"]
        ),
        .init(
            id: "rdl-coloquial",
            title: "Coloquial · RDL",
            text: "Pierna: sentadilla goblet 4x10 24kg, peso muerto rumano (RDL) 3x8 70kg, curl nordico 3x6",
            tags: ["sinonimo", "RDL", "coloquial"]
        ),
        .init(
            id: "rango-reps",
            title: "Rango de reps",
            text: "Remo con barra 4 series de 8-12 reps con 60kg, descanso 90s",
            tags: ["rango", "descanso"]
        ),
        .init(
            id: "amrap",
            title: "AMRAP / al fallo",
            text: "Dominadas 4 series al fallo, despues remo mancuerna 3x10 25kg por lado",
            tags: ["AMRAP", "bodyweight"]
        ),
        .init(
            id: "superserie",
            title: "Superserie",
            text: "En superserie: curl barra 3x10 30kg con press frances 3x10 25kg. Descanso 90 segundos entre rondas.",
            tags: ["superserie"]
        ),
        .init(
            id: "split-2dias",
            title: "Split 2 dias",
            text: """
            Programa fuerza 2 dias
            Lunes Empuje: press banca 4x8 60kg, press militar 3x10 35kg, fondos 3x12
            Miercoles Jalon: dominadas 4x8, remo pendlay 4x8 70kg, face pull 3x15
            """,
            tags: ["multi-dia", "split"]
        ),
        .init(
            id: "lb-unidades",
            title: "Unidades lb",
            text: "Bench press 5x5 225 lb, rest 3 minutes. Incline dumbbell press 3x10 70 lb.",
            tags: ["lb", "mezcla-en"]
        ),
        .init(
            id: "sin-peso",
            title: "Sin peso declarado",
            text: "Sentadilla 5x5, peso muerto 3x5, press banca 5x5. Descansos largos.",
            tags: ["sin-peso", "alucinacion-trampa"]
        ),
        .init(
            id: "descanso-variado",
            title: "Descanso variado",
            text: "Hip thrust 4x8 100kg descansa 2 min. Luego zancadas caminando 3x12 por pierna sin descanso fijo.",
            tags: ["descanso", "unilateral"]
        ),
        .init(
            id: "typo-adversarial",
            title: "Typo adversarial",
            text: "sentadila frontal 4x6 70kgs, prss banca inclinado 3x10 40 kg, remo 4x8",
            tags: ["typo", "adversarial"]
        ),
        .init(
            id: "plancha-tiempo",
            title: "Plancha (tiempo)",
            text: "Core: plancha 3 series de 45 segundos, luego ab wheel 3x10",
            tags: ["time", "core"]
        ),
        .init(
            id: "full-body",
            title: "Full body coloquial",
            text: "Hoy full: sentadilla 3x8 70kg, banca 3x8 50kg, remo 3x8 50kg, press hombros 3x10 30kg, curl 2x12 15kg",
            tags: ["full-body", "taquigrafia"]
        ),
        .init(
            id: "pecho-plano",
            title: "Sinonimo · pecho plano",
            text: "Pecho plano con barra 4x8 a 80 kilos, despues cruces en polea 3x15",
            tags: ["sinonimo", "pecho plano"]
        ),
        .init(
            id: "solo-nombres",
            title: "Solo nombres (trampa)",
            text: "Haz sentadilla, peso muerto y press de banca. Lo tipico de fuerza.",
            tags: ["sin-cifras", "alucinacion-trampa"]
        ),
        .init(
            id: "minuto-descanso",
            title: "Descanso en minutos",
            text: "Peso muerto convencional 5 series de 3 con 120 kg, descanso 3 minutos entre series",
            tags: ["descanso", "parseo"]
        ),
        .init(
            id: "mix-es-en",
            title: "Mezcla es/en",
            text: "Deadlift 4x5 140kg, luego Bulgarian split squat 3x8 20kg por lado, rest 2 min",
            tags: ["mezcla-en", "sinonimo"]
        ),
    ]
}

#endif
