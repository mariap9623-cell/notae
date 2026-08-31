import SwiftUI

/// Marca nosecomousarlaia. Los colores salen de tokens.css del design system,
/// no se inventan aquí.
enum Marca {

    // Claro
    static let verde = Color(red: 0x43 / 255, green: 0xA0 / 255, blue: 0x5E / 255)      // #43A05E
    static let verdeTexto = Color(red: 0x2F / 255, green: 0x73 / 255, blue: 0x46 / 255) // #2F7346
    // Oscuro
    static let verdeClaro = Color(red: 0x5F / 255, green: 0xBE / 255, blue: 0x7A / 255) // #5FBE7A

    /// El verde del logotipo, ya ajustado al tema para que no se apague.
    static func verdeLogo(_ esquema: ColorScheme) -> Color {
        esquema == .dark ? verdeClaro : verde
    }

    /// Verde seguro para texto pequeño (el #43A05E no pasa AA sobre blanco).
    static func verdeLegible(_ esquema: ColorScheme) -> Color {
        esquema == .dark ? verdeClaro : verdeTexto
    }

    static func sans(_ tamano: CGFloat, _ peso: Font.Weight = .regular) -> Font {
        .custom("Instrument Sans", size: tamano).weight(peso)
    }
}

/// El logotipo: una sola palabra pegada, minúscula, con "ia" en verde.
struct Wordmark: View {
    @Environment(\.colorScheme) private var esquema
    var tamano: CGFloat = 26

    var body: some View {
        (
            Text("nosecomousarla").foregroundColor(.primary)
            + Text("ia").foregroundColor(Marca.verdeLogo(esquema))
        )
        .font(Marca.sans(tamano, .medium))
        .tracking(-tamano * 0.012)
    }
}

/// El símbolo (racimo horizontal). Nunca por debajo de 32 px de ancho:
/// más chico se vuelve una mancha y ahí va el logotipo.
struct Simbolo: View {
    @Environment(\.colorScheme) private var esquema
    var ancho: CGFloat = 64
    /// De 0 a 1: cuántos puntos se pintan encendidos. Con esto el símbolo
    /// reacciona a la voz sin dejar de ser el símbolo.
    var energia: Double = 1
    var tinta: Color? = nil

    private static let circulos: [(CGFloat, CGFloat, CGFloat)] = [
        (45.63, 20.78, 9.06), (121.38, 20.64, 12.90), (197.13, 20.62, 19.33), (272.83, 20.63, 20.63),
        (7.84, 71.99, 7.84), (83.57, 71.99, 11.64), (159.30, 72.05, 15.40), (234.98, 72.01, 21.92),
        (310.66, 72.02, 25.77),
        (45.65, 123.29, 9.03), (121.38, 123.36, 12.91), (197.18, 123.37, 19.33), (272.81, 123.41, 24.51),
        (83.61, 174.64, 11.62), (235.02, 174.73, 23.19)
    ]
    private static let anchoSVG: CGFloat = 336.43
    private static let altoSVG: CGFloat = 197.93

    var body: some View {
        Canvas { contexto, tamano in
            let escala = tamano.width / Self.anchoSVG
            let color = tinta ?? Marca.verdeLogo(esquema)
            // Los puntos se encienden de izquierda a derecha, que es como
            // están ordenados en el símbolo original.
            let orden = Self.circulos.enumerated().sorted { $0.element.0 < $1.element.0 }
            let vivos = Int((Double(orden.count) * max(0, min(1, energia))).rounded())
            for (posicion, item) in orden.enumerated() {
                let (cx, cy, r) = item.element
                let d = r * escala * 2
                let rect = CGRect(x: cx * escala - d / 2, y: cy * escala - d / 2, width: d, height: d)
                contexto.fill(Path(ellipseIn: rect),
                              with: .color(color.opacity(posicion < vivos ? 1 : 0.2)))
            }
        }
        .frame(width: ancho, height: ancho * (Self.altoSVG / Self.anchoSVG))
    }
}
