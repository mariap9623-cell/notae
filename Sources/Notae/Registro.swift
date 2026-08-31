import Foundation

/// Registro simple a ~/Library/Logs/Notae.log, para poder diagnosticar
/// sin tener la app abierta en un depurador.
enum Registro {

    static let ruta: URL = {
        let carpeta = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        return carpeta.appendingPathComponent("Notae.log")
    }()

    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let cola = DispatchQueue(label: "voz.registro")

    static func di(_ mensaje: String) {
        let linea = "\(formato.string(from: Date()))  \(mensaje)\n"
        cola.async {
            guard let datos = linea.data(using: .utf8) else { return }
            if let manejador = try? FileHandle(forWritingTo: ruta) {
                manejador.seekToEndOfFile()
                manejador.write(datos)
                try? manejador.close()
            } else {
                try? datos.write(to: ruta)
            }
        }
    }

    static func limpiar() {
        try? FileManager.default.removeItem(at: ruta)
    }
}
