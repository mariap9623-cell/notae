import Foundation
import FoundationModels

/// Convierte lo que salió del dictado en texto listo para pegar.
/// Primero pasa por reglas rápidas y, si el estilo lo pide, por el modelo de
/// Apple Intelligence que corre dentro del Mac (no sale nada a internet).
@MainActor
final class Limpieza {

    private var sesion: LanguageModelSession?
    private var instruccionesCacheadas: String = ""

    /// Una sesión ya creada y precalentada, esperando su turno.
    ///
    /// Crear la sesión no es gratis: el modelo tiene que digerir las
    /// instrucciones (que con tus reglas y tu vocabulario son largas) antes de
    /// mirar tu texto. Si eso pasa cuando sueltas la tecla, lo esperas tú. Aquí
    /// se hace de antemano, mientras no estás dictando.
    private var repuesto: LanguageModelSession?
    private var repuestoInstrucciones: String = ""

    /// Cuánto texto lleva vista la sesión activa, para saber cuándo jubilarla.
    private var gastadoEnSesion = 0

    /// El límite es 4096 tokens y ahí la llamada falla entera. Pero mucho antes
    /// de fallar ya se pone lenta: medido con dictados largos, 0.87 s en el
    /// primero, 1.04 s en el décimo, 1.50 s en el vigésimo, y reventó en el 28.
    /// Con este tope se jubila la sesión cuando todavía va rápida, y como el
    /// relevo ya está precalentado, el cambio no te cuesta nada a ti.
    private static let topeCaracteresPorSesion = 1200

    var iaDisponible: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var motivoNoDisponible: String? {
        guard case .unavailable(let razon) = SystemLanguageModel.default.availability else { return nil }
        switch razon {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence está apagado. Actívalo en Ajustes del sistema para la limpieza con IA."
        case .modelNotReady:
            return "El modelo de Apple Intelligence todavía se está descargando."
        case .deviceNotEligible:
            return "Este Mac no soporta Apple Intelligence. Puedes usar el modo Crudo."
        @unknown default:
            return "La IA local no está disponible ahora mismo."
        }
    }

    /// Deja el modelo cargado en memoria para que la primera limpieza no demore.
    func precalentar(estilo: EstiloLimpieza, reglas: [String], vocabulario: [String]) {
        guard estilo.usaIA, iaDisponible else { return }
        prepararRepuesto(estilo: estilo, reglas: reglas, vocabulario: vocabulario)
    }

    /// Deja lista la sesión del próximo dictado. Barato de llamar de más:
    /// si ya hay una con estas mismas instrucciones, no hace nada.
    private func prepararRepuesto(estilo: EstiloLimpieza, reglas: [String], vocabulario: [String]) {
        let texto = instrucciones(estilo: estilo, reglas: reglas, vocabulario: vocabulario)
        if repuesto != nil, repuestoInstrucciones == texto { return }
        let nueva = LanguageModelSession(instructions: texto)
        nueva.prewarm()
        repuesto = nueva
        repuestoInstrucciones = texto
    }

    func procesar(_ crudo: String,
                  estilo: EstiloLimpieza,
                  reglas: [String],
                  vocabulario: [String],
                  atajos: [(dicho: String, escribe: String)] = []) async -> String {

        // Los atajos se aplican antes que la IA: así el modelo ve el correo ya
        // escrito y no intenta "arreglarlo".
        let conAtajos = aplicarAtajos(crudo, atajos: atajos)
        let base = reglasRapidas(conAtajos)
        guard estilo.usaIA, iaDisponible, base.count > 1 else { return base }

        let sesion = sesionPara(estilo: estilo, reglas: reglas, vocabulario: vocabulario)
        let inicio = Date()
        do {
            let respuesta = try await sesion.respond(
                to: "Texto dictado:\n\(base)",
                options: GenerationOptions(temperature: 0.1)
            )
            gastadoEnSesion += base.count + respuesta.content.count
            Registro.di("ia: \(String(format: "%.2f", Date().timeIntervalSince(inicio))) s para \(base.count) caracteres · sesión lleva \(gastadoEnSesion)")
            let salida = depurarSalida(respuesta.content)
            return salida.isEmpty ? base : reglasRapidas(salida)
        } catch {
            // Se jubila la sesión: si falló por contexto lleno, la siguiente
            // llamada con esta misma sesión volvería a fallar.
            Registro.di("ia: falló (\(error)); va el texto con reglas rápidas")
            self.sesion = nil
            gastadoEnSesion = 0
            return base
        }
    }

    // MARK: - Sesión

    /// Una sesión nueva por dictado, a propósito.
    ///
    /// Reutilizar la sesión parecía más rápido, pero cada respuesta se queda en
    /// su transcripción: a la décima o vigésima dictada el contexto se
    /// desborda, la llamada falla y el texto sale crudo sin que nadie entienda
    /// por qué. Los dictados no tienen nada que ver entre sí, así que no hay
    /// nada que conservar. Lo caro es cargar el modelo, y eso ya quedó hecho
    /// por `precalentar` y vive mientras viva la app.
    private func sesionPara(estilo: EstiloLimpieza, reglas: [String], vocabulario: [String]) -> LanguageModelSession {
        let texto = instrucciones(estilo: estilo, reglas: reglas, vocabulario: vocabulario)
        defer { instruccionesCacheadas = texto }

        // Reutilizar la sesión es lo que más acelera: medido en 18 dictados,
        // 0.441 s de mediana creando una cada vez contra 0.332 s reutilizando.
        // El modelo ya tiene digeridas las instrucciones y no las vuelve a leer.
        if let viva = sesion,
           instruccionesCacheadas == texto,
           gastadoEnSesion < Self.topeCaracteresPorSesion {
            return viva
        }

        // Toca relevo. Si el repuesto sirve, ya está precalentado y entra sin
        // costo; si no, no queda más que crear una aquí mismo.
        let elegida: LanguageModelSession
        if let listo = repuesto, repuestoInstrucciones == texto {
            elegida = listo
        } else {
            elegida = LanguageModelSession(instructions: texto)
        }
        repuesto = nil
        repuestoInstrucciones = ""
        sesion = elegida
        gastadoEnSesion = 0

        // Y de una vez se arma el siguiente relevo, fuera del camino crítico.
        prepararRepuesto(estilo: estilo, reglas: reglas, vocabulario: vocabulario)
        return elegida
    }

    private func instrucciones(estilo: EstiloLimpieza, reglas: [String], vocabulario: [String]) -> String {
        var partes: [String] = []

        partes.append("""
        Eres un editor de dictado. Recibes la transcripción de alguien hablando y \
        devuelves ese mismo texto listo para pegar. Trabajas en el idioma en que \
        está el texto y nunca lo traduces.
        """)

        switch estilo {
        case .crudo:
            break
        case .fiel:
            partes.append("""
            Reglas: corrige la puntuación, las mayúsculas y los acentos. Quita las \
            muletillas (eh, mmm, o sea, este, digamos, ¿sí?, ¿no?) y las repeticiones \
            por titubeo. No cambies las palabras que eligió la persona, no resumas, \
            no agregues nada.
            """)
        case .natural:
            partes.append("""
            Reglas: corrige puntuación, mayúsculas y acentos. Quita muletillas y \
            titubeos. Parte las frases muy largas en oraciones cortas y elimina \
            repeticiones. Conserva el vocabulario y el tono de la persona. No resumas \
            ni agregues ideas nuevas.
            """)
        case .mensaje:
            partes.append("""
            Reglas: devuelve un mensaje listo para enviar. Puntuación y mayúsculas \
            correctas, sin muletillas, frases cortas, párrafos separados si hay más de \
            una idea. Conserva el tono de la persona. No agregues saludos ni despedidas \
            que no dijo, no resumas, no inventes datos.
            """)
        }

        partes.append("""
        Formato de salida: devuelve únicamente el texto corregido. Sin comillas, sin \
        explicaciones, sin encabezados, sin comentarios sobre lo que hiciste.
        """)

        partes.append("Nunca uses guiones largos (—). Usa punto, coma, dos puntos o paréntesis.")

        partes.append("""
        No toques las direcciones de correo, los enlaces, los números de teléfono \
        ni los nombres de usuario: cópialos tal cual aparecen.
        """)

        if !vocabulario.isEmpty {
            partes.append("""
            Nombres y términos que la persona usa (escríbelos siempre así): \
            \(vocabulario.joined(separator: ", ")).
            """)
        }

        if !reglas.isEmpty {
            partes.append("Reglas propias de la persona:\n" + reglas.map { "- \($0)" }.joined(separator: "\n"))
        }

        return partes.joined(separator: "\n\n")
    }

    // MARK: - Atajos de voz

    /// Reemplaza lo que dijiste por el texto largo. No distingue mayúsculas ni
    /// tildes, porque el dictado escribe "mi correo" o "Mi Correo" según el día.
    func aplicarAtajos(_ texto: String, atajos: [(dicho: String, escribe: String)]) -> String {
        guard !atajos.isEmpty else { return texto }
        var salida = texto
        // De los más largos a los más cortos, para que "mi correo de trabajo"
        // gane sobre "mi correo".
        for atajo in atajos.sorted(by: { $0.dicho.count > $1.dicho.count }) {
            var buscarDesde = salida.startIndex
            while let rango = salida.range(of: atajo.dicho,
                                           options: [.caseInsensitive, .diacriticInsensitive],
                                           range: buscarDesde..<salida.endIndex) {
                salida.replaceSubrange(rango, with: atajo.escribe)
                guard let siguiente = salida.index(rango.lowerBound,
                                                   offsetBy: atajo.escribe.count,
                                                   limitedBy: salida.endIndex) else { break }
                buscarDesde = siguiente
            }
        }
        return salida
    }

    // MARK: - Reglas rápidas (siempre se aplican, no cuestan nada)

    private func reglasRapidas(_ texto: String) -> String {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }

        t = t.replacingOccurrences(of: "—", with: ",")
        t = t.replacingOccurrences(of: " ,", with: ",")
        t = t.replacingOccurrences(of: " .", with: ".")
        t = t.replacingOccurrences(of: "  ", with: " ")

        // Comandos de voz para puntuación, por si el dictado no los interpreta.
        let comandos: [(String, String)] = [
            ("nueva línea", "\n"),
            ("nuevo párrafo", "\n\n"),
            ("punto y aparte", ".\n\n"),
            ("new line", "\n"),
            ("new paragraph", "\n\n")
        ]
        for (frase, reemplazo) in comandos {
            t = t.replacingOccurrences(of: " \(frase)", with: reemplazo, options: .caseInsensitive)
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func depurarSalida(_ texto: String) -> String {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        // A veces el modelo envuelve la respuesta en comillas.
        let pares: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»")]
        for (a, b) in pares where t.count > 2 && t.first == a && t.last == b {
            t = String(t.dropFirst().dropLast())
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
