import Foundation
import Translation

/// Traduce lo que dictaste antes de pegarlo.
///
/// La idea: hablas en español y escribe en inglés. Usa el traductor que trae
/// macOS, que corre dentro del Mac y no manda tu texto a ningún servidor.
///
/// El primer par de idiomas hay que descargarlo una vez. Eso lo dispara la
/// pantalla de ajustes, porque el sistema exige mostrar su propia ventana.
@MainActor
final class Traductor: ObservableObject {

    @Published private(set) var trabajando = false
    @Published private(set) var ultimoError = ""

    private var sesion: TranslationSession?
    private var parActual: String = ""

    /// ¿Se puede traducir de un idioma a otro, y hace falta descargar algo?
    static func estado(de origen: String, a destino: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Locale.Language(identifier: origen),
                                            to: Locale.Language(identifier: destino))
    }

    static func idiomasSoportados() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    /// Traduce. Si algo falla devuelve el texto original: más vale escribir en
    /// español que no escribir nada.
    func traducir(_ texto: String, de origen: String, a destino: String) async -> String {
        let o = Self.raiz(origen), d = Self.raiz(destino)
        guard !texto.isEmpty, o != d else { return texto }

        trabajando = true
        defer { trabajando = false }

        let par = "\(o)>\(d)"
        if sesion == nil || parActual != par {
            sesion = TranslationSession(installedSource: Locale.Language(identifier: o),
                                        target: Locale.Language(identifier: d))
            parActual = par
        }
        guard let sesion else { return texto }

        do {
            let r = try await sesion.translate(texto)
            ultimoError = ""
            return r.targetText
        } catch {
            ultimoError = "No se pudo traducir: \(error.localizedDescription)"
            self.sesion = nil
            return texto
        }
    }

    /// «es-MX» y «es-ES» son el mismo idioma para el traductor.
    static func raiz(_ identificador: String) -> String {
        Locale(identifier: identificador).language.languageCode?.identifier
            ?? String(identificador.prefix(2))
    }

    /// El nombre del idioma, siempre en español.
    ///
    /// `Locale.current` sigue al sistema, y el Mac de Maria está en inglés: por
    /// eso la app decía «hablo spanish». La app está escrita en español, así que
    /// los nombres de los idiomas también.
    static func nombre(_ identificador: String) -> String {
        let base = Locale(identifier: "es").localizedString(forLanguageCode: raiz(identificador))
        return (base ?? identificador).capitalized
    }
}
