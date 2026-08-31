import Foundation
import SwiftUI

/// Tecla que activa el dictado. Todas son teclas modificadoras que casi nadie
/// usa sola, para no chocar con atajos de otras apps.
enum TeclaAtajo: String, CaseIterable, Identifiable {
    case fn
    case opcionDerecha
    case comandoDerecho
    case controlDerecho

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .fn: return "fn (globo 🌐)"
        case .opcionDerecha: return "Option derecha ⌥"
        case .comandoDerecho: return "Command derecha ⌘"
        case .controlDerecho: return "Control derecha ⌃"
        }
    }

    /// El símbolo corto, para la etiqueta de la píldora.
    var simbolo: String {
        switch self {
        case .fn: return "fn"
        case .opcionDerecha: return "⌥"
        case .comandoDerecho: return "⌘"
        case .controlDerecho: return "⌃"
        }
    }

    /// Código de tecla física (para distinguir izquierda de derecha).
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .opcionDerecha: return 61
        case .comandoDerecho: return 54
        case .controlDerecho: return 62
        }
    }
}

enum ModoAtajo: String, CaseIterable, Identifiable {
    case mantener
    case alternar

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .mantener: return "Mantener presionada"
        case .alternar: return "Tocar para empezar, tocar para terminar"
        }
    }
}

/// Qué tanto puede reescribir la IA local lo que dictaste.
enum EstiloLimpieza: String, CaseIterable, Identifiable {
    case crudo
    case fiel
    case natural
    case mensaje

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .crudo: return "Crudo (sin IA, lo más rápido)"
        case .fiel: return "Fiel (arregla puntuación y muletillas)"
        case .natural: return "Natural (además ordena las frases)"
        case .mensaje: return "Mensaje (lo deja listo para enviar)"
        }
    }

    var detalle: String {
        switch self {
        case .crudo: return "Pega exactamente lo que entendió el dictado. Instantáneo."
        case .fiel: return "Quita eeeh, o sea, este… y pone comas y puntos. No cambia tus palabras."
        case .natural: return "Además corta las frases largas y quita repeticiones. Sigue siendo tu voz."
        case .mensaje: return "Lo convierte en un mensaje limpio para WhatsApp, Slack o correo."
        }
    }

    var usaIA: Bool { self != .crudo }
}

/// Preferencias de la app. Se guardan en UserDefaults.
@MainActor
final class Ajustes: ObservableObject {
    static let compartidos = Ajustes()

    private let d = UserDefaults.standard

    @Published var idioma: String {
        didSet { d.set(idioma, forKey: "idioma") }
    }
    @Published var tecla: TeclaAtajo {
        didSet { d.set(tecla.rawValue, forKey: "tecla"); alCambiarAtajo?() }
    }
    @Published var modo: ModoAtajo {
        didSet { d.set(modo.rawValue, forKey: "modo"); alCambiarAtajo?() }
    }
    /// En qué idioma escribe. Vacío = el mismo en el que hablas.
    @Published var idiomaSalida: String {
        didSet { d.set(idiomaSalida, forKey: "idiomaSalida") }
    }
    @Published var estilo: EstiloLimpieza {
        didSet { d.set(estilo.rawValue, forKey: "estilo") }
    }
    @Published var vocabulario: String {
        didSet { d.set(vocabulario, forKey: "vocabulario") }
    }
    @Published var reglas: String {
        didSet { d.set(reglas, forKey: "reglas") }
    }
    /// Atajos de voz: "lo que dices = lo que escribe", uno por línea.
    @Published var atajos: String {
        didSet { d.set(atajos, forKey: "atajos") }
    }
    /// La píldora se queda abajo aunque no estés dictando.
    @Published var pildoraFija: Bool {
        didSet { d.set(pildoraFija, forKey: "pildoraFija"); alCambiarHud?() }
    }
    /// Dónde dejaste la barra, en coordenadas de lo que se ve (la ventana es
    /// más grande porque lleva aire para la sombra). Negativo = de fábrica.
    ///
    /// Las claves llevan un 2 a propósito: antes se guardaba el origen de la
    /// ventana y ese número ya no significa lo mismo. Empezar de cero una vez
    /// es mejor que dejar la barra corrida sin explicación.
    /// En cuál de las seis anclas quedó la píldora.
    ///
    /// Se guarda el ancla y no unas coordenadas: así vuelve al mismo sitio
    /// aunque cambies de monitor o desconectes la pantalla externa, que es
    /// donde antes se perdía de vista.
    @Published var pildoraAncla: String {
        didSet { d.set(pildoraAncla, forKey: "pildoraAncla") }
    }

    @Published var pildoraX: Double {
        didSet { d.set(pildoraX, forKey: "pildoraX2") }
    }
    @Published var pildoraY: Double {
        didSet { d.set(pildoraY, forKey: "pildoraY2") }
    }
    /// El último idioma al que tradujiste, para el botón de la píldora.
    @Published var ultimoIdiomaSalida: String {
        didSet { d.set(ultimoIdiomaSalida, forKey: "ultimoIdiomaSalida") }
    }
    @Published var sonidos: Bool {
        didSet { d.set(sonidos, forKey: "sonidos") }
    }
    /// Mostrar lo que vas diciendo debajo de la píldora. Apagado por defecto:
    /// la idea es que casi no se note.
    @Published var mostrarTexto: Bool {
        didSet { d.set(mostrarTexto, forKey: "mostrarTexto"); alCambiarHud?() }
    }
    @Published var pegarAutomatico: Bool {
        didSet { d.set(pegarAutomatico, forKey: "pegarAutomatico") }
    }
    /// Recordar lo último que copiaste, para volver a pegarlo desde la barra.
    /// Solo en memoria: al cerrar Notae se borra.
    @Published var guardarCopias: Bool {
        didSet { d.set(guardarCopias, forKey: "guardarCopias"); alCambiarCopias?() }
    }
    @Published var yaHizoOnboarding: Bool {
        didSet { d.set(yaHizoOnboarding, forKey: "yaHizoOnboarding") }
    }

    /// Se dispara cuando cambia la tecla o el modo, para reconfigurar el monitor.
    var alCambiarAtajo: (() -> Void)?
    /// Se dispara cuando cambia algo visual de la píldora.
    var alCambiarHud: (() -> Void)?
    /// Se dispara al prender o apagar el historial del portapapeles.
    var alCambiarCopias: (() -> Void)?

    private init() {
        idioma = d.string(forKey: "idioma") ?? Locale.current.identifier
        tecla = TeclaAtajo(rawValue: d.string(forKey: "tecla") ?? "") ?? .fn
        modo = ModoAtajo(rawValue: d.string(forKey: "modo") ?? "") ?? .mantener
        idiomaSalida = d.string(forKey: "idiomaSalida") ?? ""
        estilo = EstiloLimpieza(rawValue: d.string(forKey: "estilo") ?? "") ?? .fiel
        vocabulario = d.string(forKey: "vocabulario") ?? ""
        reglas = d.string(forKey: "reglas") ?? ""
        atajos = d.string(forKey: "atajos") ?? ""
        pildoraFija = d.object(forKey: "pildoraFija") as? Bool ?? true
        pildoraAncla = d.string(forKey: "pildoraAncla") ?? "abajoCentro"
        pildoraX = d.object(forKey: "pildoraX2") as? Double ?? -1
        pildoraY = d.object(forKey: "pildoraY2") as? Double ?? -1
        ultimoIdiomaSalida = d.string(forKey: "ultimoIdiomaSalida") ?? "en"
        sonidos = d.object(forKey: "sonidos") as? Bool ?? true
        mostrarTexto = d.object(forKey: "mostrarTexto") as? Bool ?? false
        pegarAutomatico = d.object(forKey: "pegarAutomatico") as? Bool ?? true
        guardarCopias = d.object(forKey: "guardarCopias") as? Bool ?? true
        yaHizoOnboarding = d.bool(forKey: "yaHizoOnboarding")
    }

    /// Palabras propias, una por línea o separadas por comas.
    var listaVocabulario: [String] {
        vocabulario
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Los atajos ya partidos. El texto admite \\n para saltos de línea.
    var listaAtajos: [(dicho: String, escribe: String)] {
        atajos.split(separator: "\n").compactMap { linea in
            let partes = linea.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard partes.count == 2 else { return nil }
            let dicho = partes[0].trimmingCharacters(in: .whitespaces)
            let escribe = partes[1].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\n", with: "\n")
            guard !dicho.isEmpty, !escribe.isEmpty else { return nil }
            return (dicho, escribe)
        }
    }

    var listaReglas: [String] {
        reglas
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
