import Foundation
import AVFoundation
import Speech

/// Motor de dictado. Usa el reconocimiento de voz local de macOS 26
/// (SpeechAnalyzer + SpeechTranscriber): no manda audio a ningún servidor.
@MainActor
final class Dictado: ObservableObject {

    enum Estado: Equatable {
        case inactivo
        case preparando(String)
        case escuchando
        case procesando
        case error(String)
    }

    @Published private(set) var estado: Estado = .inactivo
    /// Texto que se va viendo mientras hablas (todavía puede cambiar).
    @Published private(set) var enVivo: String = ""
    /// Nivel de audio 0...1 para el medidor del HUD.
    @Published private(set) var nivel: Double = 0

    /// Se llama cada vez que el motor da por cerrada una frase, todavía con el
    /// micrófono abierto. Es lo que permite ir limpiando mientras hablas en vez
    /// de hacerlo todo al soltar la tecla.
    var alCerrarFrase: ((String) -> Void)?

    private let motorAudio = AVAudioEngine()
    private var transcriptor: SpeechTranscriber?
    private var analizador: SpeechAnalyzer?
    private var flujo: AsyncStream<AnalyzerInput>.Continuation?
    private var tareaResultados: Task<Void, Never>?
    private var conversor: AVAudioConverter?
    private var formatoAnalizador: AVAudioFormat?
    /// Analizador de mentira que solo existe para que el modelo quede cargado
    /// desde que abres la app. Ver `preparar`.
    private var precalentado: SpeechAnalyzer?

    private var textoFinal = ""
    private var textoVolatil = ""

    var idiomaActual: Locale?

    // MARK: - Preparación

    /// Descarga (si hace falta) el modelo del idioma y deja todo listo en memoria
    /// para que la primera dictada no tenga demora.
    func preparar(idioma: String, progreso: @escaping (String) -> Void) async {
        guard SpeechTranscriber.isAvailable else {
            estado = .error("Este Mac no tiene el motor de voz de macOS 26.")
            return
        }
        var elegido = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: idioma))
        if elegido == nil {
            elegido = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "es-ES"))
        }
        guard let soportado = elegido else {
            estado = .error("El idioma \(idioma) no está soportado.")
            return
        }
        idiomaActual = soportado

        let t = SpeechTranscriber(
            locale: soportado,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        do {
            let instaladas = await SpeechTranscriber.installedLocales
            let yaEsta = instaladas.contains { $0.identifier(.bcp47) == soportado.identifier(.bcp47) }
            if !yaEsta {
                progreso("Descargando el modelo de voz…")
                if let pedido = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                    try await pedido.downloadAndInstall()
                }
            }
            _ = try? await AssetInventory.reserve(locale: soportado)
            formatoAnalizador = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
            progreso("")
            Registro.di("idioma: listo \(soportado.identifier(.bcp47)) · formato \(formatoAnalizador?.sampleRate ?? 0) Hz")

            // Precalentado: cargar el modelo AHORA y no en la primera dictada.
            //
            // Reservar el asset no carga el modelo; eso pasa la primera vez que
            // un analizador recibe audio. Por eso el primer dictado después de
            // abrir la app se demoraba unos cinco segundos (se ve en el log del
            // sistema como «first audio packet to first partial result») y los
            // siguientes no. Este analizador no analiza nada: solo fuerza la
            // carga, y como pide `.processLifetime`, el modelo se queda en
            // memoria del proceso para el analizador de verdad.
            let inicio = Date()
            let calentador = SpeechAnalyzer(
                modules: [t],
                options: SpeechAnalyzer.Options(priority: .utility, modelRetention: .processLifetime)
            )
            do {
                try await calentador.prepareToAnalyze(in: formatoAnalizador)
                precalentado = calentador
                Registro.di("precalentado: modelo listo en \(String(format: "%.2f", Date().timeIntervalSince(inicio))) s")
            } catch {
                // Si falla, no pasa nada malo: se cae al comportamiento viejo,
                // que es cargar el modelo en la primera dictada.
                Registro.di("precalentado: no se pudo (\(error)); el primer dictado va a ir lento")
            }
        } catch {
            Registro.di("idioma: ERROR \(error)")
            estado = .error("No se pudo preparar el idioma: \(error.localizedDescription)")
        }
    }

    // MARK: - Ciclo de dictado

    func empezar(vocabulario: [String]) async {
        guard case .inactivo = estado else { return }
        textoFinal = ""
        textoVolatil = ""
        enVivo = ""

        let locale = idiomaActual ?? Locale(identifier: "es-ES")
        let t = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        transcriptor = t

        let contexto = AnalysisContext()
        if !vocabulario.isEmpty {
            contexto.contextualStrings[.general] = vocabulario
        }

        let (secuencia, continuacion) = AsyncStream<AnalyzerInput>.makeStream()
        flujo = continuacion

        let a = SpeechAnalyzer(
            inputSequence: secuencia,
            modules: [t],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime),
            analysisContext: contexto
        )
        analizador = a

        tareaResultados = Task { [weak self] in
            do {
                for try await resultado in t.results {
                    let texto = String(resultado.text.characters)
                    await MainActor.run {
                        guard let self else { return }
                        if resultado.isFinal {
                            self.textoFinal += texto
                            self.textoVolatil = ""
                            // Ya no cambia: se puede ir limpiando desde ahora.
                            self.alCerrarFrase?(texto)
                        } else {
                            self.textoVolatil = texto
                        }
                        self.enVivo = (self.textoFinal + self.textoVolatil)
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
            } catch {
                // El flujo se cierra al terminar; no es un error real.
            }
        }

        do {
            if formatoAnalizador == nil {
                formatoAnalizador = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
            }
            // Ojo: el inicializador con `inputSequence` ya deja el analizador
            // consumiendo el flujo. Llamar además a `start` lo hace abortar.
            try prenderMicrofono()
            estado = .escuchando
            Registro.di("micrófono: escuchando · idioma \(locale.identifier(.bcp47))")
        } catch {
            Registro.di("micrófono: ERROR \(error)")
            estado = .error("No se pudo abrir el micrófono: \(error.localizedDescription)")
            await limpiar()
        }
    }

    /// Lo que hay al soltar la tecla, partido en dos: las frases que el motor
    /// ya cerró mientras hablabas (que la limpieza viene procesando desde hace
    /// rato) y la cola que nadie ha cerrado todavía.
    struct Cierre {
        var cerrado = ""
        var cola = ""
        var completo: String {
            (cerrado + cola).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Corta la grabación y devuelve el texto completo ya finalizado.
    func terminar() async -> Cierre {
        guard case .escuchando = estado else { return Cierre() }
        estado = .procesando

        motorAudio.inputNode.removeTap(onBus: 0)
        motorAudio.stop()
        flujo?.finish()

        // Con tope de tiempo: si el analizador no cierra (pasa cuando el
        // sistema está ocupado descargando modelos), sin esto la app se queda
        // esperando para siempre y la tecla deja de responder.
        await conEspera(segundos: 6) { [weak self] in
            try? await self?.analizador?.finalizeAndFinishThroughEndOfInput()
            _ = await self?.tareaResultados?.value
        }

        let cierre = Cierre(cerrado: textoFinal, cola: textoVolatil)
        await limpiar()
        return cierre
    }

    /// Corre algo y se rinde si tarda demasiado. Lo que importa es que el
    /// dictado siempre termine, aunque sea con lo que alcanzó a oír.
    private func conEspera(segundos: Double, _ trabajo: @escaping () async -> Void) async {
        let tarea = Task { await trabajo() }
        let reloj = Task {
            try? await Task.sleep(for: .seconds(segundos))
            if !Task.isCancelled {
                Registro.di("dictado: el analizador no cerró en \(Int(segundos))s · se sigue igual")
                tarea.cancel()
            }
        }
        _ = await tarea.value
        reloj.cancel()
    }

    func cancelar() async {
        motorAudio.inputNode.removeTap(onBus: 0)
        motorAudio.stop()
        flujo?.finish()
        await analizador?.cancelAndFinishNow()
        await limpiar()
    }

    func volverAInactivo() {
        estado = .inactivo
        enVivo = ""
        nivel = 0
    }

    private func limpiar() async {
        // El tap se quita aquí y no solo en `terminar`: si el motor de audio
        // falló al arrancar, quedaba instalado, y al segundo intento
        // AVAudioEngine revienta al encontrar dos taps en el mismo bus.
        motorAudio.inputNode.removeTap(onBus: 0)
        if motorAudio.isRunning { motorAudio.stop() }
        tareaResultados?.cancel()
        tareaResultados = nil
        analizador = nil
        transcriptor = nil
        flujo = nil
        conversor = nil
        nivel = 0
    }

    // MARK: - Audio

    private func prenderMicrofono() throws {
        let entrada = motorAudio.inputNode
        let formatoEntrada = entrada.outputFormat(forBus: 0)
        guard let destino = formatoAnalizador else {
            throw NSError(domain: "Notae", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Sin formato de audio compatible"])
        }
        let conv = AVAudioConverter(from: formatoEntrada, to: destino)
        conversor = conv
        let salidaFlujo = flujo

        entrada.installTap(onBus: 0, bufferSize: 4096, format: formatoEntrada) { [weak self] buffer, _ in
            let pico = Dictado.pico(de: buffer)
            if let self {
                Task { @MainActor in self.nivel = pico }
            }
            if let convertido = Dictado.convertir(buffer, con: conv, a: destino) {
                salidaFlujo?.yield(AnalyzerInput(buffer: convertido))
            }
        }

        motorAudio.prepare()
        try motorAudio.start()
    }

    private nonisolated static func convertir(_ buffer: AVAudioPCMBuffer,
                                              con conversor: AVAudioConverter?,
                                              a destino: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let conversor else { return nil }
        if buffer.format == destino { return buffer }
        let razon = destino.sampleRate / buffer.format.sampleRate
        let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * razon) + 1024
        guard let salida = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: capacidad) else { return nil }

        var entregado = false
        var error: NSError?
        let estado = conversor.convert(to: salida, error: &error) { _, estadoEntrada in
            if entregado {
                estadoEntrada.pointee = .noDataNow
                return nil
            }
            entregado = true
            estadoEntrada.pointee = .haveData
            return buffer
        }
        if estado == .error || error != nil { return nil }
        return salida.frameLength > 0 ? salida : nil
    }

    private nonisolated static func pico(de buffer: AVAudioPCMBuffer) -> Double {
        guard let datos = buffer.floatChannelData?[0] else { return 0 }
        var maximo: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            maximo = max(maximo, abs(datos[i]))
        }
        return min(1, Double(maximo) * 3)
    }

    // MARK: - Permiso de micrófono

    static var microfonoAutorizado: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func pedirMicrofono() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
