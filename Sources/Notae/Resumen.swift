import Foundation
import FoundationModels

/// Saca el resumen, los puntos clave y las tareas de una transcripción,
/// con el modelo que corre dentro del Mac.
///
/// Si Apple Intelligence está apagado, no inventa nada: arma el mismo encargo
/// en un texto que puedes pegar en Claude o donde quieras.
@MainActor
final class Resumen: ObservableObject {

    enum Estado: Equatable {
        case quieto
        case trabajando(String)
        case listo
        case sinIA(String)
        case error(String)
    }

    @Published private(set) var estado: Estado = .quieto
    @Published var resumen: String = ""
    @Published var puntos: [String] = []
    @Published var tareas: [String] = []

    var disponible: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var motivoNoDisponible: String {
        guard case .unavailable(let razon) = SystemLanguageModel.default.availability else { return "" }
        switch razon {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence está apagado. Actívalo en Ajustes del sistema para que el resumen salga aquí mismo."
        case .modelNotReady:
            return "El modelo de Apple Intelligence todavía se está descargando."
        case .deviceNotEligible:
            return "Este Mac no soporta Apple Intelligence."
        @unknown default:
            return "La IA local no está disponible ahora mismo."
        }
    }

    // MARK: - Trabajo

    func procesar(_ texto: String, titulo: String, destacados: [String] = []) async {
        guard !texto.isEmpty else { return }
        resumen = ""; puntos = []; tareas = []

        guard disponible else {
            estado = .sinIA(motivoNoDisponible)
            return
        }

        // El modelo local tiene ventana corta: se trabaja por tandas y al final
        // se resume el resumen.
        let tandas = partir(texto, maximo: 3500)
        var parciales: [String] = []

        do {
            for (i, tanda) in tandas.enumerated() {
                estado = .trabajando(tandas.count > 1
                                     ? "Resumiendo parte \(i + 1) de \(tandas.count)…"
                                     : "Resumiendo…")
                let sesion = LanguageModelSession(instructions: instruccionesParcial)
                let r = try await sesion.respond(to: tanda,
                                                 options: GenerationOptions(temperature: 0.2))
                parciales.append(r.content)
            }

            estado = .trabajando("Armando el acta…")
            let sesion = LanguageModelSession(instructions: instruccionesFinales)
            var entrada = """
            Título: \(titulo)

            Notas de la conversación:
            \(parciales.joined(separator: "\n\n"))
            """
            if !destacados.isEmpty {
                entrada += """
                

                Momentos que la persona marcó como importantes mientras ocurría la \
                reunión. Estos tienen que aparecer sí o sí en el acta:
                \(destacados.joined(separator: "\n"))
                """
            }
            let r = try await sesion.respond(to: entrada,
                                             options: GenerationOptions(temperature: 0.2))
            repartir(r.content)
            estado = .listo
        } catch {
            estado = .error("El modelo local no pudo con esto: \(error.localizedDescription)")
        }
    }

    /// El mismo encargo, listo para pegar en otro modelo si no hay IA local.
    func encargoParaPegar(_ texto: String, titulo: String) -> String {
        """
        Eres un asistente que arma actas de reuniones. Te paso la transcripción \
        de «\(titulo)». Devuélveme, en español y sin guiones largos:

        RESUMEN: tres o cuatro frases con lo que pasó.
        PUNTOS: los temas que se trataron, uno por línea, empezando con «- ».
        TAREAS: los compromisos concretos, uno por línea, empezando con «- », \
        con el responsable si se dijo. Si no hay tareas, escribe «- ninguna».

        No inventes nada que no esté en la transcripción.

        Transcripción:
        \(texto)
        """
    }

    // MARK: - Instrucciones

    private var instruccionesParcial: String {
        """
        Eres un asistente que toma notas de reuniones. Recibes un pedazo de la \
        transcripción y devuelves, en español, una lista breve de lo que se dijo: \
        temas tratados, decisiones y compromisos. Frases cortas, sin adornos. \
        No inventes nada que no esté en el texto. Nunca uses guiones largos.
        """
    }

    private var instruccionesFinales: String {
        """
        Eres un asistente que arma actas de reuniones en español. Recibes notas \
        de una conversación y devuelves exactamente este formato, sin nada más:

        RESUMEN: tres o cuatro frases con lo que pasó.
        PUNTOS:
        - un tema por línea
        TAREAS:
        - un compromiso por línea, con el responsable si aparece

        Si no hay tareas, escribe «- ninguna». No inventes nada que no esté en \
        las notas. Nunca uses guiones largos.
        """
    }

    // MARK: - Utilidades

    private func repartir(_ salida: String) {
        var seccion = ""
        for linea in salida.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = linea.trimmingCharacters(in: .whitespaces)
            let mayus = l.uppercased()
            if mayus.hasPrefix("RESUMEN") {
                seccion = "r"
                let resto = l.drop(while: { $0 != ":" }).dropFirst()
                resumen += resto.trimmingCharacters(in: .whitespaces)
                continue
            }
            if mayus.hasPrefix("PUNTOS") { seccion = "p"; continue }
            if mayus.hasPrefix("TAREAS") { seccion = "t"; continue }
            guard !l.isEmpty else { continue }
            let limpio = l.hasPrefix("-") ? String(l.dropFirst()).trimmingCharacters(in: .whitespaces) : l
            switch seccion {
            case "r": resumen += (resumen.isEmpty ? "" : " ") + l
            case "p": puntos.append(limpio)
            case "t": if limpio.lowercased() != "ninguna" { tareas.append(limpio) }
            default: break
            }
        }
        if resumen.isEmpty && puntos.isEmpty && tareas.isEmpty {
            resumen = salida.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Parte por párrafos, sin cortar frases a la mitad.
    private func partir(_ texto: String, maximo: Int) -> [String] {
        guard texto.count > maximo else { return [texto] }
        var tandas: [String] = []
        var actual = ""
        for parrafo in texto.components(separatedBy: "\n\n") {
            if actual.count + parrafo.count > maximo, !actual.isEmpty {
                tandas.append(actual)
                actual = parrafo
            } else {
                actual += (actual.isEmpty ? "" : "\n\n") + parrafo
            }
        }
        if !actual.isEmpty { tandas.append(actual) }
        return tandas
    }
}
