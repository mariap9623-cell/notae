import Foundation
import AVFoundation
import Speech
import ScreenCaptureKit

/// Graba una reunión y la va transcribiendo mientras ocurre.
///
/// Captura dos fuentes al tiempo: lo que suena en el Mac (las otras personas de
/// la llamada) y tu micrófono. Las mezcla y se las pasa al motor de voz, así que
/// al colgar la transcripción ya está lista y solo falta armar el acta.
///
/// El audio del sistema se toma con ScreenCaptureKit, que es la vía que da
/// macOS. Por eso pide permiso de grabación de pantalla aunque no grabemos
/// ninguna imagen: solo se piden las pistas de audio.
@MainActor
final class Reunion: NSObject, ObservableObject {

    enum Estado: Equatable {
        case quieta
        case preparando(String)
        case grabando
        case cerrando
        case error(String)
    }

    @Published private(set) var estado: Estado = .quieta
    @Published private(set) var texto: String = ""
    @Published private(set) var segundos: TimeInterval = 0
    @Published private(set) var nivel: Double = 0
    @Published private(set) var marcas: [TimeInterval] = []

    private var stream: SCStream?
    private var transcriptor: SpeechTranscriber?
    private var analizador: SpeechAnalyzer?
    private var flujo: AsyncStream<AnalyzerInput>.Continuation?
    private var recolector: Task<Void, Never>?
    private var reloj: Timer?
    private var arranque: Date?

    private var formatoDestino: AVAudioFormat?
    private var archivoAudio: AVAudioFile?
    private(set) var rutaAudio: URL?

    private var fragmentos: [Fragmento] = []
    private let mezclador = Mezclador()

    var fragmentosFinales: [Fragmento] { fragmentos }

    // MARK: - Empezar

    func empezar(idioma: String) async {
        guard estado == .quieta else { return }
        fragmentos = []
        marcas = []
        texto = ""
        segundos = 0
        estado = .preparando("Preparando el idioma…")

        guard let locale = await Transcripcion.idiomaSoportado(idioma) else {
            estado = .error("El idioma \(idioma) no está soportado.")
            return
        }
        let t = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        transcriptor = t

        do {
            let instaladas = await SpeechTranscriber.installedLocales
            if !instaladas.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                estado = .preparando("Descargando el modelo de voz…")
                if let pedido = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                    try await pedido.downloadAndInstall()
                }
            }
            _ = try? await AssetInventory.reserve(locale: locale)
        } catch {
            estado = .error("No se pudo preparar el idioma: \(error.localizedDescription)")
            return
        }

        guard let destino = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else {
            estado = .error("Sin formato de audio compatible.")
            return
        }
        formatoDestino = destino
        mezclador.destino = destino

        // Archivo de respaldo: si el acta sale mal, la reunión no se pierde.
        prepararArchivo(formato: mezclador.mezcla ?? destino)

        let (secuencia, continuacion) = AsyncStream<AnalyzerInput>.makeStream()
        flujo = continuacion
        mezclador.entrega = { [weak self] buffer in
            self?.flujo?.yield(AnalyzerInput(buffer: buffer))
        }
        mezclador.entregaFlotante = { [weak self] buffer in
            self?.guardar(buffer)
        }

        let a = SpeechAnalyzer(
            inputSequence: secuencia,
            modules: [t],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        analizador = a

        recolector = Task { [weak self] in
            do {
                for try await resultado in t.results {
                    guard let self else { return }
                    let trozos = Transcripcion.trocear(resultado)
                    await MainActor.run {
                        if resultado.isFinal {
                            self.fragmentos.append(contentsOf: trozos)
                            self.texto = Documento.textoPlano(self.fragmentos)
                        } else if let ultimo = trozos.last {
                            // Lo volátil se muestra al final, sin guardarse.
                            self.texto = Documento.textoPlano(self.fragmentos)
                                + (self.fragmentos.isEmpty ? "" : "\n\n") + ultimo.texto
                        }
                    }
                }
            } catch {
                Registro.di("reunión · resultados: \(error)")
            }
        }

        estado = .preparando("Pidiendo permiso para oír el Mac…")
        do {
            try await prenderCaptura()
        } catch {
            estado = .error(explicar(error))
            await limpiar()
            return
        }

        arranque = Date()
        reloj = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let arranque = self.arranque else { return }
                self.segundos = Date().timeIntervalSince(arranque)
            }
        }
        estado = .grabando
        Registro.di("reunión · grabando")
    }

    /// Vuelve a dejar la grabadora lista después de un error.
    ///
    /// `empezar` exige estar en `.quieta`, así que sin esto una sola reunión
    /// fallida (negaste el permiso de pantalla, por ejemplo) dejaba el botón
    /// muerto hasta cerrar la app.
    func reiniciar() {
        if case .error = estado { estado = .quieta }
    }

    /// Marca este momento como importante. El acta les da prioridad.
    func marcarMomento() {
        guard estado == .grabando else { return }
        marcas.append(segundos)
    }

    // MARK: - Terminar

    func terminar() async {
        guard estado == .grabando else { return }
        estado = .cerrando
        reloj?.invalidate()
        reloj = nil

        try? await stream?.stopCapture()
        stream = nil
        mezclador.vaciar()
        flujo?.finish()
        Registro.di("reunión · audio: \(mezclador.resumenCuentas)")
        try? await analizador?.finalizeAndFinishThroughEndOfInput()

        // Si el motor nunca recibió audio, el flujo de resultados no cierra solo.
        // Se le da un margen y se sigue, en vez de dejar la ventana colgada.
        let terminado = await withTaskGroup(of: Bool.self) { grupo -> Bool in
            grupo.addTask { [recolector] in _ = await recolector?.value; return true }
            grupo.addTask { try? await Task.sleep(for: .seconds(6)); return false }
            let primero = await grupo.next() ?? false
            grupo.cancelAll()
            return primero
        }
        if !terminado { Registro.di("reunión · el flujo no cerró en 6 s, sigo") }

        fragmentos.sort { $0.inicio < $1.inicio }
        texto = Documento.textoPlano(fragmentos)
        archivoAudio = nil
        await limpiar()
        estado = .quieta
        Registro.di("reunión · cerrada, \(fragmentos.count) fragmentos")
    }

    func cancelar() async {
        reloj?.invalidate()
        try? await stream?.stopCapture()
        stream = nil
        flujo?.finish()
        await analizador?.cancelAndFinishNow()
        archivoAudio = nil
        if let rutaAudio { try? FileManager.default.removeItem(at: rutaAudio) }
        rutaAudio = nil
        await limpiar()
        estado = .quieta
    }

    private func limpiar() async {
        recolector?.cancel()
        recolector = nil
        analizador = nil
        transcriptor = nil
        flujo = nil
        arranque = nil
        nivel = 0
    }

    // MARK: - Captura

    private func prenderCaptura() async throws {
        let contenido = try await SCShareableContent.excludingDesktopWindows(false,
                                                                            onScreenWindowsOnly: false)
        guard let pantalla = contenido.displays.first else {
            throw NSError(domain: "Notae", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "No encontré ninguna pantalla de la que tomar el audio."
            ])
        }

        let filtro = SCContentFilter(display: pantalla, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // que no se oiga a sí misma
        config.sampleRate = 48000
        config.channelCount = 2
        config.captureMicrophone = true
        // No queremos imagen: el mínimo posible y un cuadro cada tanto.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let s = SCStream(filter: filtro, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .global(qos: .userInitiated))
        try await s.startCapture()
        stream = s
    }

    private func explicar(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" || e.code == -3801 {
            return "Falta el permiso para oír el Mac. Ve a Ajustes del sistema › Privacidad y seguridad › Grabación de pantalla y activa Notae. No se graba ninguna imagen, solo el audio."
        }
        return "No se pudo empezar a grabar: \(e.localizedDescription)"
    }

    // MARK: - Archivo de respaldo

    private func prepararArchivo(formato: AVAudioFormat) {
        let carpeta = Historial.compartido.carpetaEnDisco.appendingPathComponent("Reuniones",
                                                                                 isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let destino = carpeta.appendingPathComponent("reunion-\(f.string(from: Date())).caf")
        archivoAudio = try? AVAudioFile(forWriting: destino, settings: formato.settings)
        rutaAudio = archivoAudio == nil ? nil : destino
    }

    private nonisolated func guardar(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor in
            try? self.archivoAudio?.write(from: buffer)
            self.nivel = Reunion.pico(buffer)
        }
    }

    private nonisolated static func pico(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let datos = buffer.floatChannelData?[0] else { return 0 }
        var maximo: Float = 0
        for i in 0..<Int(buffer.frameLength) { maximo = max(maximo, abs(datos[i])) }
        return min(1, Double(maximo) * 3)
    }
}

// MARK: - Salida del stream

extension Reunion: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio || type == .microphone else { return }
        mezclador.recibir(sampleBuffer, deMicrofono: type == .microphone)
    }
}

/// Junta las dos fuentes en una sola pista.
///
/// No separa quién habla (el motor de Apple todavía no lo hace), pero sumar las
/// dos evita el problema real: que se transcriba solo tu voz y se pierda la de
/// los demás, o al revés.
final class Mezclador: @unchecked Sendable {
    /// El formato que pide el motor de voz. Ojo: puede ser de enteros, no de
    /// coma flotante, así que no sirve para sumar las dos fuentes.
    var destino: AVAudioFormat? {
        didSet {
            guard let destino else { return }
            // Se mezcla siempre en flotante mono, y al final se convierte.
            mezcla = AVAudioFormat(standardFormatWithSampleRate: destino.sampleRate, channels: 1)
            conversorSalida = mezcla.flatMap { AVAudioConverter(from: $0, to: destino) }
        }
    }
    private(set) var mezcla: AVAudioFormat?
    private var conversorSalida: AVAudioConverter?
    var entrega: ((AVAudioPCMBuffer) -> Void)?
    /// La misma mezcla en flotante, para guardarla en disco y medir el nivel.
    var entregaFlotante: ((AVAudioPCMBuffer) -> Void)?

    private let candado = NSLock()
    private var pendienteMic: [Float] = []
    private var pendienteSistema: [Float] = []
    /// Tamaño del trozo que se entrega al motor.
    private let trozo = 1600   // 0.1 s a 16 kHz
    private var recibidosMic = 0
    private var recibidosSistema = 0
    private var motivos: [String: Int] = [:]
    /// Un conversor por fuente, creado una sola vez.
    ///
    /// Antes se creaba uno por paquete: como además cambia el ritmo de 48 kHz a
    /// 16 kHz, un conversor recién nacido con un paquete corto devuelve cero
    /// muestras, y así no se transcribía absolutamente nada.
    private var conversorMic: AVAudioConverter?
    private var conversorSistema: AVAudioConverter?
    private var entregados = 0

    func recibir(_ muestra: CMSampleBuffer, deMicrofono: Bool) {
        guard let destino else { return }
        guard let mezcla else { return }
        let (mono, motivo) = aMono(muestra, destino: mezcla, deMicrofono: deMicrofono)
        guard let mono else {
            contarFallo(motivo)
            return
        }
        candado.lock()
        if deMicrofono { pendienteMic.append(contentsOf: mono); recibidosMic += mono.count }
        else { pendienteSistema.append(contentsOf: mono); recibidosSistema += mono.count }

        // Se entrega por tiempo, no por igualdad: lo que falte de una fuente se
        // rellena con silencio. Si se espera a que las dos vayan parejas, una
        // reunión donde solo habla el otro no entrega nada nunca.
        var salida: [Float] = []
        let disponible = max(pendienteMic.count, pendienteSistema.count)
        if disponible >= trozo {
            let n = (disponible / trozo) * trozo
            salida = (0..<n).map { i in
                let a = i < pendienteMic.count ? pendienteMic[i] : 0
                let b = i < pendienteSistema.count ? pendienteSistema[i] : 0
                return max(-1, min(1, a + b))
            }
            pendienteMic.removeFirst(min(n, pendienteMic.count))
            pendienteSistema.removeFirst(min(n, pendienteSistema.count))
            entregados += n
        }
        candado.unlock()

        guard !salida.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: mezcla,
                                            frameCapacity: AVAudioFrameCount(salida.count)),
              let canal = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(salida.count)
        salida.withUnsafeBufferPointer { canal.update(from: $0.baseAddress!, count: salida.count) }

        entregaFlotante?(buffer)
        guard let paraElMotor = alFormatoDelMotor(buffer) else { return }
        entrega?(paraElMotor)
    }

    private func contarFallo(_ motivo: String) {
        candado.lock()
        motivos[motivo, default: 0] += 1
        candado.unlock()
    }

    /// Para poder ver qué pasó cuando algo no suena.
    var resumenCuentas: String {
        candado.lock(); defer { candado.unlock() }
        let detalle = motivos.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return "mic \(recibidosMic) · sistema \(recibidosSistema) · entregadas \(entregados) · fallos: \(detalle)"
    }

    /// Pasa la mezcla en flotante al formato exacto que pide el motor.
    private func alFormatoDelMotor(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destino, let conversorSalida else { return buffer }
        if buffer.format == destino { return buffer }
        guard let salida = AVAudioPCMBuffer(pcmFormat: destino,
                                            frameCapacity: buffer.frameCapacity + 1024) else { return nil }
        var entregado = false
        var error: NSError?
        let estado = conversorSalida.convert(to: salida, error: &error) { _, aviso in
            if entregado { aviso.pointee = .noDataNow; return nil }
            entregado = true
            aviso.pointee = .haveData
            return buffer
        }
        guard estado != .error, error == nil, salida.frameLength > 0 else { return nil }
        return salida
    }

    func vaciar() {
        candado.lock()
        pendienteMic = []
        pendienteSistema = []
        candado.unlock()
    }

    /// Pasa la muestra a mono. Devuelve también el motivo si no pudo, para
    /// poder diagnosticar sin adivinar.
    private func aMono(_ muestra: CMSampleBuffer,
                       destino: AVAudioFormat,
                       deMicrofono: Bool) -> ([Float]?, String) {
        guard let descripcion = muestra.formatDescription else { return (nil, "sin-descripcion") }
        guard var asbd = descripcion.audioStreamBasicDescription else { return (nil, "sin-asbd") }
        guard let origen = AVAudioFormat(streamDescription: &asbd) else { return (nil, "sin-formato") }

        candado.lock()
        var conversor = deMicrofono ? conversorMic : conversorSistema
        if conversor == nil || conversor?.inputFormat != origen {
            conversor = AVAudioConverter(from: origen, to: destino)
            if deMicrofono { conversorMic = conversor } else { conversorSistema = conversor }
        }
        candado.unlock()
        guard let conversor else { return (nil, "sin-conversor") }

        var muestras: [Float]?
        var motivo = "ok"
        do {
            try muestra.withAudioBufferList { lista, _ in
                guard let entrada = AVAudioPCMBuffer(pcmFormat: origen,
                                                     bufferListNoCopy: lista.unsafePointer) else {
                    motivo = "sin-buffer"
                    return
                }
                guard entrada.frameLength > 0 else { motivo = "vacio"; return }

                let razon = destino.sampleRate / origen.sampleRate
                let capacidad = AVAudioFrameCount(Double(entrada.frameLength) * razon) + 2048
                guard let salida = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: capacidad) else {
                    motivo = "sin-salida"
                    return
                }

                var entregado = false
                var error: NSError?
                let estado = conversor.convert(to: salida, error: &error) { _, aviso in
                    if entregado { aviso.pointee = .noDataNow; return nil }
                    entregado = true
                    aviso.pointee = .haveData
                    return entrada
                }
                if estado == .error || error != nil { motivo = "conversion"; return }
                guard let canal = salida.floatChannelData?[0] else { motivo = "sin-canal"; return }
                // Cero muestras no es un fallo: el conversor está juntando datos.
                muestras = Array(UnsafeBufferPointer(start: canal, count: Int(salida.frameLength)))
            }
        } catch {
            return (nil, "excepcion")
        }
        return (muestras, motivo)
    }
}
