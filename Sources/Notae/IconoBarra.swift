import AppKit

/// El símbolo de la marca, dibujado a propósito para la barra de menú.
///
/// El racimo completo son quince puntos y a 18 px se convierte en una mancha
/// (por eso el design system prohíbe el símbolo por debajo de 32 px). Aquí se
/// conserva el gesto (puntos que crecen hacia la derecha) con seis puntos
/// grandes, que a ese tamaño sí se leen.
enum IconoBarra {

    enum Estado {
        case quieto
        case escuchando
        case procesando
    }

    /// Alto estándar de un ícono de barra de menú.
    private static let lado: CGFloat = 18

    /// Tres columnas, dos filas, radios que crecen hacia la derecha.
    private static let puntos: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (4.2, 6.0, 1.3), (9.0, 6.0, 1.95), (14.0, 6.0, 2.6),
        (4.2, 12.0, 1.3), (9.0, 12.0, 1.95), (14.0, 12.0, 2.6)
    ]

    /// Devuelve la imagen como «template»: macOS la pinta blanca o negra según
    /// el tema de la barra, sin que tengamos que decidirlo nosotros.
    static func imagen(_ estado: Estado, energia: Double = 0) -> NSImage {
        let imagen = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }

            // Cuántos puntos van encendidos según lo que esté pasando.
            let encendidos: Int
            switch estado {
            case .quieto: encendidos = 0
            case .escuchando: encendidos = 2 + Int((max(0, min(1, energia)) * 4).rounded())
            case .procesando: encendidos = 6
            }

            // Se encienden por columnas, de izquierda a derecha, como el racimo.
            let orden = [0, 3, 1, 4, 2, 5]

            for (posicion, indice) in orden.enumerated() {
                let p = puntos[indice]
                let vivo = posicion < encendidos
                ctx.setFillColor(NSColor.black.withAlphaComponent(vivo ? 1 : 0.6).cgColor)
                ctx.addEllipse(in: CGRect(x: p.x - p.r, y: p.y - p.r, width: p.r * 2, height: p.r * 2))
                ctx.fillPath()
            }
            return true
        }
        imagen.isTemplate = true
        return imagen
    }
}
