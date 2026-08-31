import AppKit

/// Entrega el texto a la app en la que estabas: lo pone en el portapapeles,
/// simula ⌘V y devuelve el portapapeles a como estaba.
enum Pegado {

    /// Cuánto esperar antes de devolver el portapapeles a como estaba.
    ///
    /// Esto es la diferencia entre que se pegue lo que dictaste y que se pegue
    /// lo que tenías copiado de antes. ⌘V no es instantáneo: Chrome, Slack,
    /// Notion y en general todo lo que sea Electron leen el portapapeles por
    /// IPC y tardan. Si restauramos antes de que lean, leen el respaldo y pegan
    /// eso. Con 0.6 s fallaba a ratos; 1.8 s le da aire a las apps lentas y no
    /// molesta, porque para entonces ya te fuiste a seguir escribiendo.
    private static let esperaRestaurar: TimeInterval = 1.8

    /// Aire entre dejar el texto y mandar ⌘V, para que el portapapeles alcance
    /// a propagarse a la app de destino. Lo mínimo que se siente instantáneo:
    /// el problema de pegar texto viejo no estaba aquí sino en la restauración.
    private static let esperaAntesDePegar: TimeInterval = 0.03

    static func pegar(_ texto: String, restaurarPortapapeles: Bool = true) {
        guard !texto.isEmpty else { return }
        let pb = NSPasteboard.general
        let respaldo = restaurarPortapapeles ? capturar(pb) : nil

        pb.clearContents()
        pb.setString(texto, forType: .string)
        let nuestroCambio = pb.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + esperaAntesDePegar) {
            enviarComandoV()
            if let respaldo {
                DispatchQueue.main.asyncAfter(deadline: .now() + esperaRestaurar) {
                    // Si copiaste algo mientras tanto, lo tuyo manda: no le
                    // pisamos el portapapeles con un respaldo ya viejo.
                    guard pb.changeCount == nuestroCambio else { return }
                    restaurar(respaldo, en: pb)
                }
            }
        }
    }

    /// Deja el texto en el portapapeles sin pegarlo.
    static func copiar(_ texto: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texto, forType: .string)
    }

    // MARK: - Privado

    private static func enviarComandoV() {
        let fuente = CGEventSource(stateID: .combinedSessionState)
        fuente?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let vKey: CGKeyCode = 9 // tecla V
        guard let abajo = CGEvent(keyboardEventSource: fuente, virtualKey: vKey, keyDown: true),
              let arriba = CGEvent(keyboardEventSource: fuente, virtualKey: vKey, keyDown: false)
        else { return }
        abajo.flags = .maskCommand
        arriba.flags = .maskCommand
        abajo.post(tap: .cghidEventTap)
        arriba.post(tap: .cghidEventTap)
    }

    private static func capturar(_ pb: NSPasteboard) -> [[String: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var copia: [String: Data] = [:]
            for tipo in item.types {
                if let datos = item.data(forType: tipo) {
                    copia[tipo.rawValue] = datos
                }
            }
            return copia
        }
    }

    private static func restaurar(_ respaldo: [[String: Data]], en pb: NSPasteboard) {
        pb.clearContents()
        let items: [NSPasteboardItem] = respaldo.map { guardado in
            let item = NSPasteboardItem()
            for (tipo, datos) in guardado {
                item.setData(datos, forType: NSPasteboard.PasteboardType(tipo))
            }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}
