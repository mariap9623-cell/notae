import Foundation
import AVFoundation
import Speech

/// Un trozo de transcripción con su momento exacto en el audio.
struct Fragmento: Identifiable, Sendable {
    let id = UUID()
    let texto: String
    let inicio: TimeInterval
    let fin: TimeInterval

    var reloj: String { Fragmento.reloj(inicio) }

    static func reloj(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, seg = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, seg)
                     : String(format: "%d:%02d", m, seg)
    }

    /// Marca de tiempo con milisegundos, como la piden los .srt
    static func relojSRT(_ t: TimeInterval) -> String {
        let total = max(0, t)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let ms = Int((total - total.rounded(.down)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

/// Transcribe un archivo de audio o video completo, dentro del Mac.
///
/// Usa la vía que Apple hizo para archivos (`analyzeSequence(from:)`), que lee
/// y convierte el audio sola. Si el archivo es un video o un formato que
/// `AVAudioFile` no abre, primero se exporta el audio a un m4a temporal.
@MainActor
final class Transcripcion: ObservableObject {

    enum Estado: Equatable {
        case quieto
        case preparando(String)
        case trabajando(Double)   // 0...1
        case listo
        case error(String)
    }

    @Published private(set) var estado: Estado = .quieto
    @Published private(set) var fragmentos: [Fragmento] = []
    @Published private(set) var duracion: TimeInterval = 0

    private var cancelada = false
    private var temporal: URL?

    func cancelar() { cancelada = true }

    static func idiomaSoportado(_ identificador: String) async -> Locale? {
        if let l = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identificador)) {
            return l
        }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "es-MX"))
    }

    // MARK: - Transcribir

    func transcribir(archivo: URL, idioma: String) async {
        cancelada = false
        fragmentos = []
        estado = .preparando("Abriendo el archivo…")
        Registro.di("1 · empieza \(archivo.lastPathComponent)")

        guard SpeechTranscriber.isAvailable else {
            estado = .error("Este Mac no tiene el motor de voz de macOS 26.")
            return
        }
        guard let locale = await Self.idiomaSoportado(idioma) else {
            estado = .error("El idioma \(idioma) no está soportado.")
            return
        }

        let transcriptor = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        do {
            let instaladas = await SpeechTranscriber.installedLocales
            if !instaladas.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                estado = .preparando("Descargando el modelo de \(locale.identifier(.bcp47))…")
                if let pedido = try await AssetInventory.assetInstallationRequest(supporting: [transcriptor]) {
                    try await pedido.downloadAndInstall()
                }
            }
            _ = try? await AssetInventory.reserve(locale: locale)
        } catch {
            estado = .error("No se pudo preparar el idioma: \(error.localizedDescription)")
            return
        }
        Registro.di("2 · idioma \(locale.identifier(.bcp47)) listo")

        // Duración, para el avance.
        let asset = AVURLAsset(url: archivo)
        duracion = (try? CMTimeGetSeconds(await asset.load(.duration))) ?? 0
        guard duracion.isFinite, duracion > 0 else {
            estado = .error("Ese archivo no tiene audio que se pueda leer.")
            return
        }

        // El motor lee AVAudioFile. Si el archivo no abre (típico en .mov y
        // .mp4), se exporta el audio a un m4a temporal y se usa ese.
        var audio: AVAudioFile
        do {
            audio = try AVAudioFile(forReading: archivo)
            Registro.di("3 · abierto directo")
        } catch {
            estado = .preparando("Sacando el audio del video…")
            guard let extraido = await extraerAudio(de: asset) else {
                estado = .error("No se pudo extraer el audio de ese archivo.")
                return
            }
            do {
                audio = try AVAudioFile(forReading: extraido)
                temporal = extraido
                Registro.di("3 · audio extraído a temporal")
            } catch {
                estado = .error("No se pudo leer el audio extraído: \(error.localizedDescription)")
                return
            }
        }

        estado = .trabajando(0)
        let analizador = SpeechAnalyzer(modules: [transcriptor])

        // Recolector: va guardando cada resultado y moviendo la barra.
        let recolector = Task { [weak self] in
            do {
                for try await resultado in transcriptor.results {
                    guard let self else { return }
                    let nuevos = Self.trocear(resultado)
                    guard !nuevos.isEmpty else { continue }
                    await MainActor.run {
                        self.fragmentos.append(contentsOf: nuevos)
                        if self.duracion > 0, let ultimo = nuevos.last {
                            self.estado = .trabajando(min(0.99, ultimo.fin / self.duracion))
                        }
                    }
                }
            } catch {
                Registro.di("resultados: \(error)")
            }
            Registro.di("6 · flujo de resultados cerrado")
        }

        do {
            Registro.di("4 · analizando…")
            _ = try await analizador.analyzeSequence(from: audio)
            Registro.di("5 · audio consumido")
            try await analizador.finalizeAndFinishThroughEndOfInput()
        } catch {
            recolector.cancel()
            limpiarTemporal()
            estado = .error("El motor no pudo con el audio: \(error.localizedDescription)")
            return
        }

        _ = await recolector.value
        limpiarTemporal()

        fragmentos.sort { $0.inicio < $1.inicio }
        Registro.di("7 · listo, \(fragmentos.count) fragmentos")
        estado = cancelada ? .quieto : .listo
    }

    // MARK: - Cortar el resultado en frases

    /// El motor devuelve tramos largos. Adentro, cada palabra trae su momento
    /// exacto, así que cortamos por punto, por coma larga o cada pocos segundos.
    nonisolated static func trocear(_ resultado: SpeechTranscriber.Result,
                                            maximo: TimeInterval = 9) -> [Fragmento] {
        let atribuido = resultado.text
        var salida: [Fragmento] = []
        var texto = ""
        var inicio: TimeInterval?
        var fin: TimeInterval = 0

        func cerrar() {
            let limpio = texto.trimmingCharacters(in: .whitespaces)
            guard !limpio.isEmpty, let i = inicio else { texto = ""; inicio = nil; return }
            salida.append(Fragmento(texto: limpio, inicio: i, fin: max(fin, i)))
            texto = ""
            inicio = nil
        }

        for tramo in atribuido.runs {
            let pedazo = String(atribuido[tramo.range].characters)
            guard !pedazo.isEmpty else { continue }

            if let rango = tramo.audioTimeRange {
                let a = CMTimeGetSeconds(rango.start)
                let b = CMTimeGetSeconds(rango.end)
                if inicio == nil, a.isFinite { inicio = a }
                if b.isFinite { fin = b }
            }
            texto += pedazo

            let termina = pedazo.contains(where: { ".?!…".contains($0) })
            let largo = (inicio.map { fin - $0 } ?? 0) >= maximo
            if termina || largo { cerrar() }
        }
        cerrar()

        // Si el resultado no traía marcas de tiempo, al menos devolvemos el texto.
        if salida.isEmpty {
            let plano = String(atribuido.characters).trimmingCharacters(in: .whitespaces)
            if !plano.isEmpty {
                salida.append(Fragmento(texto: plano,
                                        inicio: CMTimeGetSeconds(resultado.range.start),
                                        fin: CMTimeGetSeconds(resultado.range.end)))
            }
        }
        return salida
    }

    // MARK: - Video a audio

    /// Saca la pista de audio de un video a un m4a temporal.
    private func extraerAudio(de asset: AVAsset) async -> URL? {
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("acta-\(UUID().uuidString).m4a")
        guard let sesion = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        do {
            try await sesion.export(to: destino, as: .m4a)
            return destino
        } catch {
            Registro.di("extraer audio: \(error)")
            return nil
        }
    }

    private func limpiarTemporal() {
        if let temporal { try? FileManager.default.removeItem(at: temporal) }
        temporal = nil
    }
}
