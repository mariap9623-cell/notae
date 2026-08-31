import Foundation

/// Convierte los fragmentos crudos en las cosas que uno de verdad necesita:
/// párrafos legibles, un .srt, un markdown con marcas de tiempo.
enum Documento {

    // MARK: - Párrafos

    /// Junta fragmentos en párrafos. Corta cuando hay una pausa larga o cuando
    /// el párrafo ya se hizo largo de leer.
    static func parrafos(_ fragmentos: [Fragmento],
                         pausaLarga: TimeInterval = 1.2,
                         maximo: TimeInterval = 25,
                         frasesMaximo: Int = 4) -> [Fragmento] {
        var salida: [Fragmento] = []
        var acumulado: [Fragmento] = []

        func cerrar() {
            guard let primero = acumulado.first, let ultimo = acumulado.last else { return }
            let texto = acumulado.map(\.texto).joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ")
            salida.append(Fragmento(texto: texto, inicio: primero.inicio, fin: ultimo.fin))
            acumulado = []
        }

        for f in fragmentos {
            if let ultimo = acumulado.last {
                let pausa = f.inicio - ultimo.fin
                let largo = f.fin - (acumulado.first?.inicio ?? f.inicio)
                if pausa >= pausaLarga || largo >= maximo || acumulado.count >= frasesMaximo {
                    cerrar()
                }
            }
            acumulado.append(f)
        }
        cerrar()
        return salida
    }

    // MARK: - Salidas

    static func textoPlano(_ fragmentos: [Fragmento]) -> String {
        parrafos(fragmentos).map(\.texto).joined(separator: "\n\n")
    }

    static func conMarcas(_ fragmentos: [Fragmento], titulo: String) -> String {
        var lineas = ["# \(titulo)", ""]
        for p in parrafos(fragmentos) {
            lineas.append("**\(p.reloj)**  \(p.texto)")
            lineas.append("")
        }
        return lineas.joined(separator: "\n")
    }

    /// Subtítulos. Parte cada fragmento en trozos de máximo dos renglones y
    /// reparte el tiempo según cuántas letras lleva cada trozo.
    static func srt(_ fragmentos: [Fragmento], porRenglon: Int = 42) -> String {
        var bloques: [String] = []
        var n = 1

        for f in fragmentos {
            let trozos = partir(f.texto, maximo: porRenglon * 2)
            guard !trozos.isEmpty else { continue }
            let totalLetras = max(1, trozos.reduce(0) { $0 + $1.count })
            var t = f.inicio
            let duracion = max(0.4, f.fin - f.inicio)

            for trozo in trozos {
                let parte = duracion * Double(trozo.count) / Double(totalLetras)
                let fin = t + parte
                bloques.append("""
                \(n)
                \(Fragmento.relojSRT(t)) --> \(Fragmento.relojSRT(fin))
                \(dosRenglones(trozo, porRenglon: porRenglon))
                """)
                n += 1
                t = fin
            }
        }
        return bloques.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Momentos marcados

    /// Recorta lo que se dijo alrededor de cada marca.
    ///
    /// La ventana mira sobre todo hacia atrás, porque uno se da cuenta de que
    /// algo importa después de oírlo: cuando haces clic, lo valioso ya pasó.
    /// Las marcas que se pisan se juntan en un solo momento.
    static func momentos(_ fragmentos: [Fragmento],
                         marcas: [TimeInterval],
                         antes: TimeInterval = 45,
                         despues: TimeInterval = 15) -> [String] {
        guard !marcas.isEmpty, !fragmentos.isEmpty else { return [] }

        var ventanas: [(inicio: TimeInterval, fin: TimeInterval)] = []
        for marca in marcas.sorted() {
            let v = (max(0, marca - antes), marca + despues)
            if var ultima = ventanas.last, v.0 <= ultima.fin {
                ultima.fin = max(ultima.fin, v.1)
                ventanas[ventanas.count - 1] = ultima
            } else {
                ventanas.append(v)
            }
        }

        return ventanas.compactMap { v in
            let dentro = fragmentos.filter { $0.fin >= v.inicio && $0.inicio <= v.fin }
            guard !dentro.isEmpty else { return nil }
            let texto = dentro.map(\.texto).joined(separator: " ")
            return "[\(Fragmento.reloj(dentro[0].inicio))] " + texto
        }
    }

    // MARK: - Cortes de texto

    /// Parte respetando palabras.
    private static func partir(_ texto: String, maximo: Int) -> [String] {
        let palabras = texto.split(separator: " ")
        var trozos: [String] = []
        var actual = ""
        for p in palabras {
            if actual.isEmpty {
                actual = String(p)
            } else if actual.count + 1 + p.count <= maximo {
                actual += " " + p
            } else {
                trozos.append(actual)
                actual = String(p)
            }
        }
        if !actual.isEmpty { trozos.append(actual) }
        return trozos
    }

    /// Reparte un trozo en dos renglones lo más parejos posible.
    ///
    /// Ojo: en cuanto se pasa al segundo renglón no se vuelve al primero. Sin
    /// esa regla, las palabras cortas se devolvían al renglón de arriba y el
    /// subtítulo quedaba con las palabras desordenadas.
    private static func dosRenglones(_ texto: String, porRenglon: Int) -> String {
        guard texto.count > porRenglon else { return texto }
        let palabras = texto.split(separator: " ")
        var primera = ""
        var segunda = ""
        let mitad = texto.count / 2

        for p in palabras {
            if segunda.isEmpty && (primera.isEmpty || primera.count + 1 + p.count <= mitad) {
                primera += (primera.isEmpty ? "" : " ") + p
            } else {
                segunda += (segunda.isEmpty ? "" : " ") + p
            }
        }
        return segunda.isEmpty ? primera : primera + "\n" + segunda
    }
}
