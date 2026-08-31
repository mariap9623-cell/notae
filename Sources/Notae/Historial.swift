import Foundation

/// Una entrada del historial: algo que dictaste o algo que transcribiste.
struct Entrada: Identifiable, Codable, Equatable {
    enum Tipo: String, Codable {
        case dictado
        case transcripcion
        case reunion
        /// Lo que dictas para guardar, sin pegarlo en ningún lado.
        ///
        /// Llegó tarde: antes una nota se guardaba como `dictado` y lo único
        /// que la distinguía era que no se pegaba. Por eso las notas anteriores
        /// al 30 de agosto de 2026 siguen apareciendo en Dictado; esa
        /// diferencia nunca se escribió en el archivo y no hay de dónde
        /// sacarla.
        case nota

        var nombre: String {
            switch self {
            case .dictado: return "dictado"
            case .transcripcion: return "transcripción"
            case .reunion: return "reunión"
            case .nota: return "nota"
            }
        }

        /// En cuál de las secciones de la ventana vive.
        var seccion: Seccion {
            switch self {
            case .dictado: return .dictado
            case .nota: return .notas
            // Una transcripción y una reunión son lo mismo: un audio del que
            // sale texto. Van juntas.
            case .reunion, .transcripcion: return .reuniones
            }
        }
    }

    let id: UUID
    let tipo: Tipo
    let fecha: Date
    var titulo: String
    var texto: String
    /// Solo en transcripciones: de qué archivo salió y cuánto duraba.
    var origen: String?
    var duracion: TimeInterval?
    /// El acta, si se llegó a armar.
    var resumen: String?
    var tareas: [String]
    /// Momentos que marcaste durante la reunión, en segundos.
    var marcas: [TimeInterval] = []
    /// Lo que se dijo alrededor de cada marca, ya recortado.
    var destacados: [String] = []
    /// Dónde quedó el audio guardado, para poder volver si el acta sale mal.
    var audio: String?

    init(tipo: Tipo, texto: String, titulo: String? = nil, origen: String? = nil,
         duracion: TimeInterval? = nil, resumen: String? = nil, tareas: [String] = [],
         marcas: [TimeInterval] = [], destacados: [String] = [], audio: String? = nil) {
        self.id = UUID()
        self.tipo = tipo
        self.fecha = Date()
        self.texto = texto
        self.origen = origen
        self.duracion = duracion
        self.resumen = resumen
        self.tareas = tareas
        self.marcas = marcas
        self.destacados = destacados
        self.audio = audio
        self.titulo = titulo ?? Entrada.tituloDe(texto)
    }

    /// Lectura tolerante, y no es un lujo.
    ///
    /// Swift **no** usa los valores por defecto de arriba al decodificar: si a
    /// un `historial.json` viejo le falta una clave que se agregó después
    /// (`marcas`, `audio`, lo que venga), la decodificación falla entera y se
    /// pierde todo. Aquí cada campo nuevo se lee «si está», y si no, se usa su
    /// valor por defecto. Así una versión nueva siempre puede leer lo viejo.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        tipo = (try? c.decode(Tipo.self, forKey: .tipo)) ?? .dictado
        fecha = (try? c.decode(Date.self, forKey: .fecha)) ?? Date()
        texto = try c.decode(String.self, forKey: .texto)
        titulo = (try? c.decode(String.self, forKey: .titulo)) ?? Entrada.tituloDe(texto)
        origen = try? c.decodeIfPresent(String.self, forKey: .origen)
        duracion = try? c.decodeIfPresent(TimeInterval.self, forKey: .duracion)
        resumen = try? c.decodeIfPresent(String.self, forKey: .resumen)
        tareas = (try? c.decodeIfPresent([String].self, forKey: .tareas)) as? [String] ?? []
        marcas = (try? c.decodeIfPresent([TimeInterval].self, forKey: .marcas)) as? [TimeInterval] ?? []
        destacados = (try? c.decodeIfPresent([String].self, forKey: .destacados)) as? [String] ?? []
        audio = try? c.decodeIfPresent(String.self, forKey: .audio)
    }

    /// Un título decente sin pedirle nada al usuario: la primera frase, cortada.
    static func tituloDe(_ texto: String) -> String {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return "Sin texto" }
        let corte = limpio.prefix(while: { $0 != "." && $0 != "\n" })
        let frase = corte.count > 4 ? String(corte) : limpio
        return frase.count > 70 ? String(frase.prefix(70)) + "…" : frase
    }

    var cuando: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        if Calendar.current.isDateInToday(fecha) {
            f.dateFormat = "'hoy' HH:mm"
        } else if Calendar.current.isDateInYesterday(fecha) {
            f.dateFormat = "'ayer' HH:mm"
        } else {
            f.dateFormat = "d 'de' MMMM, HH:mm"
        }
        return f.string(from: fecha)
    }

    var palabras: Int {
        texto.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}

/// Guarda todo lo que pasa por Notae en un archivo, dentro del Mac.
/// Las cuatro secciones de la ventana.
enum Seccion: String, CaseIterable, Identifiable {
    case dictado, reuniones, notas, configuracion

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .dictado: return "Dictado"
        case .reuniones: return "Reuniones"
        case .notas: return "Notas"
        case .configuracion: return "Configuración"
        }
    }

    var icono: String {
        switch self {
        case .dictado: return "text.alignleft"
        case .reuniones: return "record.circle"
        case .notas: return "square.and.pencil"
        case .configuracion: return "slider.horizontal.3"
        }
    }

    /// La de configuración no lista nada.
    var listaEntradas: Bool { self != .configuracion }

    var vacioTitulo: String {
        switch self {
        case .dictado: return "Todavía no has dictado nada"
        case .reuniones: return "Ninguna reunión grabada"
        case .notas: return "Ninguna nota"
        case .configuracion: return ""
        }
    }

    var vacioDetalle: String {
        switch self {
        case .dictado: return "Mantén la tecla, habla y suéltala. Lo que dictes queda aquí."
        case .reuniones: return "Graba una reunión o suelta un audio en esta ventana."
        case .notas: return "Una nota se dicta para guardarla, no para pegarla."
        case .configuracion: return ""
        }
    }
}

/// Nada se sube a ningún lado y se puede borrar entrada por entrada.
@MainActor
final class Historial: ObservableObject {
    static let compartido = Historial()

    @Published private(set) var entradas: [Entrada] = []
    @Published var busqueda = ""

    private let archivo: URL

    private init() {
        let carpeta = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notae", isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        archivo = carpeta.appendingPathComponent("historial.json")
        cargar()
    }

    var filtradas: [Entrada] {
        buscar(en: entradas)
    }

    /// Lo de una sección, ya buscado.
    func filtradas(_ seccion: Seccion) -> [Entrada] {
        buscar(en: entradas.filter { $0.tipo.seccion == seccion })
    }

    func cuantas(_ seccion: Seccion) -> Int {
        entradas.lazy.filter { $0.tipo.seccion == seccion }.count
    }

    private func buscar(en lista: [Entrada]) -> [Entrada] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return lista }
        return lista.filter {
            $0.texto.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || $0.titulo.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    func agregar(_ entrada: Entrada) {
        entradas.insert(entrada, at: 0)
        guardar()
    }

    func actualizar(_ entrada: Entrada) {
        guard let i = entradas.firstIndex(where: { $0.id == entrada.id }) else { return }
        entradas[i] = entrada
        guardar()
    }

    func borrar(_ entrada: Entrada) {
        entradas.removeAll { $0.id == entrada.id }
        guardar()
    }

    func borrarTodo() {
        entradas = []
        guardar()
    }

    var carpetaEnDisco: URL { archivo.deletingLastPathComponent() }

    // MARK: - Disco

    private func cargar() {
        guard let datos = try? Data(contentsOf: archivo), !datos.isEmpty else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        do {
            entradas = try d.decode([Entrada].self, from: datos)
        } catch {
            // Antes esto se tragaba el error, dejaba la lista vacía, y al
            // guardar la siguiente entrada el archivo se sobrescribía con
            // nada: se perdía todo el historial sin que nadie se enterara.
            // Ahora el archivo se aparta y se puede recuperar a mano.
            let respaldo = archivo.deletingLastPathComponent()
                .appendingPathComponent("historial-no-se-pudo-leer-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: archivo, to: respaldo)
            Registro.di("historial: no se pudo leer (\(error)) · copia guardada en \(respaldo.lastPathComponent)")
            entradas = []
        }
    }

    private func guardar() {
        let c = JSONEncoder()
        c.dateEncodingStrategy = .iso8601
        c.outputFormatting = [.prettyPrinted]
        do {
            let datos = try c.encode(entradas)
            try datos.write(to: archivo, options: .atomic)
        } catch {
            Registro.di("historial: NO se pudo guardar · \(error)")
        }
    }
}
