import SwiftUI
import AppKit

/// Lo que muestra la píldora flotante mientras dictas.
@MainActor
final class HudModelo: ObservableObject {
    enum Fase: Equatable {
        case oculto
        /// Quieta en su ancla, esperando. Es el estado normal.
        case reposo
        case escuchando
        case procesando
        case listo
        case aviso(String)
    }

    @Published var fase: Fase = .oculto
    @Published var texto: String = ""
    @Published var nivel: Double = 0
    @Published var mostrarTexto: Bool = false
    /// El ratón encima de la píldora: ahí se despliegan los controles.
    @Published var encima: Bool = false

    /// Lo que hacen los botones de la píldora.
    var alTocarNotas: () -> Void = {}
    var alCambiarIdioma: () -> Void = {}
    var alDictar: () -> Void = {}
    var alGrabarReunion: () -> Void = {}
    var alNotaNueva: () -> Void = {}
    var alPortapapeles: () -> Void = {}
    /// Encendido mientras hay una reunión grabando.
    @Published var enReunion: Bool = false
    /// Hay algo copiado que se pueda volver a pegar.
    @Published var hayCopias: Bool = false
    /// Texto corto del idioma actual, para pintarlo.
    @Published var etiquetaIdioma: String = ""
    /// Qué botón tiene el cursor encima, para mostrar su etiqueta.
    @Published var etiquetaFlotante: String = ""
    /// El atajo que abre el dictado, para enseñarlo en la etiqueta.
    @Published var atajoDictar: String = "fn"
    /// Vertical cuando la píldora vive pegada a un borde lateral.
    @Published var vertical: Bool = false
    /// El cursor va de paso: la raya se aparta en vez de estorbar.
    @Published var apartada: Bool = false

    /// Arrastrar la barra para ponerla donde no estorbe.
    var alArrastrar: (CGSize) -> Void = { _ in }
    var alSoltar: () -> Void = {}
}

// MARK: - Anclas

/// Los seis sitios donde la píldora puede vivir.
///
/// Se guarda cuál, no unas coordenadas: al cambiar de monitor o desconectar la
/// pantalla externa vuelve al mismo lugar en vez de quedar fuera de la vista.
enum Ancla: String, CaseIterable {
    case abajoCentro, abajoIzquierda, abajoDerecha
    case arribaCentro, bordeIzquierdo, bordeDerecho

    var esVertical: Bool { self == .bordeIzquierdo || self == .bordeDerecho }

    /// Dónde va el centro de lo que se ve, dentro del área útil de la pantalla.
    func centro(en marco: NSRect, tamano: NSSize) -> NSPoint {
        let aire: CGFloat = 10
        let mediaAncho = tamano.width / 2
        let mediaAlto = tamano.height / 2
        switch self {
        case .abajoCentro:
            return NSPoint(x: marco.midX, y: marco.minY + mediaAlto + aire)
        case .abajoIzquierda:
            return NSPoint(x: marco.minX + mediaAncho + aire * 3, y: marco.minY + mediaAlto + aire)
        case .abajoDerecha:
            return NSPoint(x: marco.maxX - mediaAncho - aire * 3, y: marco.minY + mediaAlto + aire)
        case .arribaCentro:
            return NSPoint(x: marco.midX, y: marco.maxY - mediaAlto - aire)
        case .bordeIzquierdo:
            return NSPoint(x: marco.minX + mediaAncho + aire, y: marco.midY)
        case .bordeDerecho:
            return NSPoint(x: marco.maxX - mediaAncho - aire, y: marco.midY)
        }
    }

    /// La más cercana a donde soltaste, midiendo contra un tamaño de referencia
    /// para que la comparación entre anclas sea justa.
    static func masCercana(a punto: NSPoint, en marco: NSRect) -> Ancla {
        let referencia = NSSize(width: 80, height: 20)
        return allCases.min { a, b in
            hipotenusa(punto, a.centro(en: marco, tamano: referencia))
                < hipotenusa(punto, b.centro(en: marco, tamano: referencia))
        } ?? .abajoCentro
    }

    private static func hipotenusa(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

// MARK: - Vista

/// Píldora discreta con los puntos de la marca adentro: se encienden con tu voz.
/// Casi no se ve, pero te dice en qué va.
struct VistaHud: View {
    @ObservedObject var modelo: HudModelo
    @Environment(\.colorScheme) private var esquema

    /// Aire transparente alrededor del contenido.
    ///
    /// La ventana mide exactamente lo que mide lo que se ve, así que la sombra
    /// se dibujaba hasta el borde y ahí se cortaba en seco: se veía un cuadrado
    /// gris alrededor de la cápsula. Con este margen la sombra termina de
    /// desvanecerse dentro de la ventana. `PanelHud` lo resta al posicionar,
    /// para que la barra no suba.
    static let margen: CGFloat = 30

    /// La raya en reposo. Pequeña a propósito: vive encima de tu trabajo.
    private static let rayaAncho: CGFloat = 62
    private static let rayaAlto: CGFloat = 13

    var body: some View {
        Group {
            switch modelo.fase {
            case .reposo:
                reposo
            case .escuchando:
                // Reposo y escuchando son la MISMA pieza: la raya con los
                // puntos, que se encienden con la voz. Antes eran dos formas
                // distintas que se cambiaban una por otra y daba un brinco.
                raya(energia: 0.25 + modelo.nivel * 0.75, viva: true)
                    .animation(.easeOut(duration: 0.1), value: modelo.nivel)
            case .procesando:
                raya(energia: 0, viva: true, latiendo: true)
            case .listo:
                capsulaOscura {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Marca.verdeClaro)
                        .frame(width: Self.rayaAncho, height: Self.rayaAlto)
                }
            case .aviso(let mensaje):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(mensaje)
                        .font(Marca.sans(12))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: 340)
                .background(fondoOscuro)
            case .oculto:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: modelo.fase)
        .padding(Self.margen)
    }

    // MARK: Reposo

    /// En reposo: la raya. Al quedarse el cursor encima, la bandeja.
    private var reposo: some View {
        VStack(spacing: 7) {
            etiqueta

            // Se intercambian de verdad, no se superponen: si la bandeja
            // siguiera ahí invisible, se tragaría los clics de lo que tengas
            // abajo en la pantalla.
            Group {
                if modelo.encima {
                    botones.transition(
                        .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)
                    )
                } else {
                    raya(energia: 0, viva: false)
                        .opacity(modelo.apartada ? 0.12 : 1)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: modelo.encima)
        .animation(.easeOut(duration: 0.14), value: modelo.apartada)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { modelo.alArrastrar($0.translation) }
                .onEnded { _ in modelo.alSoltar() }
        )
    }

    /// La raya: cápsula sólida con los tres puntos de la marca adentro.
    ///
    /// Antes era una línea de 3.5 px translúcida y se leía como suciedad de la
    /// pantalla, no como un control. Con cuerpo y color sólido se ve que es
    /// algo, y sigue siendo chica.
    private func raya(energia: Double, viva: Bool, latiendo: Bool = false) -> some View {
        let largo = Self.rayaAncho
        let grueso = Self.rayaAlto
        // Se intercambian ancho y alto, no se rota la cápsula: `rotationEffect`
        // dibuja girado pero el hueco que ocupa sigue siendo el de antes, así
        // que la ventana salía apaisada aunque la pieza se viera de pie.
        return capsulaOscura {
            Group {
                if latiendo {
                    Latido()
                } else {
                    puntos(energia: energia, viva: viva)
                }
            }
            .frame(width: modelo.vertical ? grueso : largo,
                   height: modelo.vertical ? largo : grueso)
        }
        // El área para atinarle es más grande que la raya, para no pelear.
        .padding(.horizontal, modelo.vertical ? 22 : 16)
        .padding(.vertical, modelo.vertical ? 16 : 22)
        .contentShape(Rectangle())
    }

    /// Tres puntos, no el símbolo completo.
    ///
    /// El símbolo de la marca no baja de 32 px (se vuelve mancha), y aquí
    /// caben 13. Así que se usan sus puntos como cita, no el símbolo entero.
    private func puntos(energia: Double, viva: Bool) -> some View {
        let total = 3
        let encendidos = Int((Double(total) * max(0, min(1, energia))).rounded())
        let puntitos = ForEach(0..<total, id: \.self) { i in
            Circle()
                .fill(viva && i < encendidos
                      ? Marca.verdeClaro
                      : Color.white.opacity(viva ? 0.30 : 0.55))
                .frame(width: 3.5, height: 3.5)
        }
        return Group {
            if modelo.vertical {
                VStack(spacing: 3) { puntitos }
            } else {
                HStack(spacing: 3) { puntitos }
            }
        }
    }

    // MARK: Bandeja

    /// Cuatro acciones. Antes eran seis y no cabían en la cabeza de nadie.
    private var botones: some View {
        HStack(spacing: 4) {
            botonPrincipal

            boton(id: "reunion",
                  ayuda: modelo.enReunion ? "Terminar la reunión" : "Grabar una reunión") {
                Image(systemName: modelo.enReunion ? "stop.circle" : "record.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(modelo.enReunion ? Color.red : Color.white.opacity(0.92))
            } accion: { modelo.alGrabarReunion() }

            boton(id: "notas", ayuda: "Tus notas") {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.92))
            } accion: { modelo.alTocarNotas() }

            boton(id: "idioma", ayuda: "Escribir en otro idioma") {
                Text(modelo.etiquetaIdioma.isEmpty ? "ES" : modelo.etiquetaIdioma)
                    .font(Marca.sans(9.5, .semibold))
                    .tracking(0.3)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            } accion: { modelo.alCambiarIdioma() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(fondoOscuro)
    }

    /// El micrófono manda: un poco más grande y verde cuando está oyendo.
    private var botonPrincipal: some View {
        let activo = modelo.fase == .escuchando
        let señalado = modelo.etiquetaFlotante.hasPrefix("Dictar")
        return Button { modelo.alDictar() } label: {
            ZStack {
                Circle()
                    .fill(activo ? AnyShapeStyle(Marca.verde)
                                 : AnyShapeStyle(Color.white.opacity(señalado ? 0.20 : 0.13)))
                    .frame(width: 34, height: 34)
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(señalado ? 1.06 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: modelo.etiquetaFlotante)
        .onHover { dentro in
            modelo.etiquetaFlotante = dentro ? "Dictar\u{0000}\(modelo.atajoDictar)" : ""
        }
    }

    /// Un botón redondo de la bandeja.
    private func boton<C: View>(id: String,
                                ayuda: String,
                                @ViewBuilder contenido: () -> C,
                                accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(modelo.etiquetaFlotante == ayuda ? 0.20 : 0.13))
                    .frame(width: 32, height: 32)
                contenido()
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(modelo.etiquetaFlotante == ayuda ? 1.06 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: modelo.etiquetaFlotante)
        .onHover { dentro in
            modelo.etiquetaFlotante = dentro ? ayuda : ""
        }
    }

    /// El nombre del botón que tienes debajo del cursor, con su atajo.
    ///
    /// El atajo va aquí y no en un manual: es la única forma de que la próxima
    /// vez no necesites la barra.
    private var etiqueta: some View {
        let partes = modelo.etiquetaFlotante.split(separator: "\u{0000}", maxSplits: 1)
        let nombre = partes.first.map(String.init) ?? ""
        let atajo = partes.count > 1 ? String(partes[1]) : ""
        return HStack(spacing: 5) {
            Text(nombre)
                .font(Marca.sans(11.5, .medium))
                .foregroundStyle(.white)
            if !atajo.isEmpty {
                Text(atajo)
                    .font(Marca.sans(11.5, .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(fondoOscuro)
        .fixedSize()
        .opacity(modelo.etiquetaFlotante.isEmpty ? 0 : 1)
        .scaleEffect(modelo.etiquetaFlotante.isEmpty ? 0.9 : 1, anchor: .bottom)
        .animation(.spring(response: 0.2, dampingFraction: 0.82),
                   value: modelo.etiquetaFlotante)
        .frame(height: 24)
    }

    // MARK: Fondos

    private func capsulaOscura<C: View>(@ViewBuilder contenido: () -> C) -> some View {
        contenido().background(fondoOscuro)
    }

    /// Sólido, no vidrio.
    ///
    /// El material translúcido se veía como un parche brillante sobre las apps
    /// oscuras y desaparecía sobre las claras. Con tinta sólida la pieza se lee
    /// igual encima de cualquier cosa; en tema oscuro lleva un filete finísimo
    /// para despegarse del fondo.
    private var fondoOscuro: some View {
        Capsule(style: .continuous)
            .fill(Color(red: 0x14 / 255, green: 0x15 / 255, blue: 0x17 / 255)
                .opacity(esquema == .dark ? 0.94 : 0.88))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(esquema == .dark ? 0.14 : 0.06),
                                  lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.24), radius: 14, y: 5)
    }
}

/// Mientras la IA pule el texto, los puntos respiran.
private struct Latido: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Marca.verdeClaro)
                        .frame(width: 3.5, height: 3.5)
                        .opacity(0.25 + 0.75 * (sin(t * 4 - Double(i) * 0.6) + 1) / 2)
                }
            }
        }
    }
}

// MARK: - Ventana

/// Ventana sin bordes que flota encima de todo y nunca roba el foco,
/// para que el texto se pegue en la app donde estabas.
@MainActor
final class PanelHud {
    private let modelo: HudModelo
    private var panel: NSPanel?
    private var ocultarLuego: DispatchWorkItem?
    private var origenArrastre: NSPoint?
    private var arrastrando = false
    /// Vigila el cursor para abrir la bandeja solo si de verdad te detuviste.
    private var vigia: Any?
    private var abrirLuego: DispatchWorkItem?

    init(modelo: HudModelo) {
        self.modelo = modelo
    }

    var ancla: Ancla {
        Ancla(rawValue: Ajustes.compartidos.pildoraAncla) ?? .abajoCentro
    }

    func mostrar() {
        ocultarLuego?.cancel()
        let p = panel ?? crear()
        panel = p
        modelo.vertical = ancla.esVertical
        acomodar(p)
        p.orderFrontRegardless()
        vigilarCursor()
    }

    /// Reacomoda mientras está visible (el contenido cambia de tamaño).
    func actualizar() {
        guard let p = panel, p.isVisible else { return }
        acomodar(p)
    }

    /// Vuelve al reposo (o se esconde, si la píldora fija está apagada).
    func ocultarEn(_ segundos: TimeInterval, volverAReposo: Bool = false) {
        ocultarLuego?.cancel()
        let trabajo = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if volverAReposo {
                self.modelo.fase = .reposo
                self.actualizar()
            } else {
                self.panel?.orderOut(nil)
                self.modelo.fase = .oculto
            }
        }
        ocultarLuego = trabajo
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: trabajo)
    }

    func ocultarYa() {
        ocultarLuego?.cancel()
        panel?.orderOut(nil)
        modelo.fase = .oculto
    }

    // MARK: Cursor

    /// Abrir la bandeja al primer roce del cursor era molesto, y desvanecerla
    /// al pasar por encima impedía abrirla nunca. Se resuelve con intención:
    /// si el cursor va de paso, la raya se aparta y deja pasar el clic; si te
    /// quedas quieto encima un cuarto de segundo, se abre la bandeja.
    private func vigilarCursor() {
        guard vigia == nil else { return }
        vigia = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.revisarCursor() }
        }
    }

    private func revisarCursor() {
        guard let p = panel, p.isVisible, !arrastrando else { return }
        guard case .reposo = modelo.fase else {
            if modelo.apartada { modelo.apartada = false }
            return
        }
        let raton = NSEvent.mouseLocation
        let zona = p.frame.insetBy(dx: VistaHud.margen - 8, dy: VistaHud.margen - 8)
        let dentro = zona.contains(raton)

        if dentro {
            if !modelo.apartada && !modelo.encima { modelo.apartada = true }
            if abrirLuego == nil {
                let trabajo = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    // Sigue ahí quieto: era intención, no de paso.
                    guard zona.contains(NSEvent.mouseLocation) else { return }
                    self.modelo.apartada = false
                    self.modelo.encima = true
                    self.actualizar()
                }
                abrirLuego = trabajo
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: trabajo)
            }
        } else {
            abrirLuego?.cancel()
            abrirLuego = nil
            if modelo.apartada { modelo.apartada = false }
            if modelo.encima {
                modelo.encima = false
                modelo.etiquetaFlotante = ""
                actualizar()
            }
        }
    }

    // MARK: Construcción y sitio

    private func crear() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 90, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        // Tiene que recibir clics para sus controles. Al ser un panel que no
        // activa la app, pulsarlo no le quita el foco a donde estabas
        // escribiendo, que es lo que permite seguir pegando ahí.
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: VistaHud(modelo: modelo))
        hosting.sizingOptions = [.intrinsicContentSize]
        p.contentView = hosting
        return p
    }

    private func pantallaActual() -> NSScreen? {
        let raton = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(raton, $0.frame, false) } ?? NSScreen.main
    }

    private func acomodar(_ p: NSPanel, animado: Bool = false) {
        guard !arrastrando, let pantalla = pantallaActual() else { return }
        p.layoutIfNeeded()
        // La ventana no crece sola cuando se abre la bandeja: hay que medir el
        // contenido y reacomodarla, o los botones quedan cortados.
        let ajustado = p.contentView?.fittingSize ?? .zero
        let tamano = ajustado == .zero ? NSSize(width: 90, height: 34) : ajustado
        let aire = VistaHud.margen
        // Lo que de verdad se ve, sin el margen transparente de la sombra.
        let visible = NSSize(width: tamano.width - aire * 2, height: tamano.height - aire * 2)

        // Se coloca por el CENTRO, no por la esquina.
        //
        // Antes se guardaba el borde izquierdo, así que al abrirse la bandeja
        // crecía solo hacia la derecha y la raya quedaba descentrada respecto a
        // los botones. Anclando el centro, crece hacia los dos lados.
        let util = pantalla.visibleFrame
        let centro = ancla.centro(en: util, tamano: visible)
        var x = centro.x - tamano.width / 2
        var y = centro.y - tamano.height / 2

        // Que nunca quede fuera de la pantalla. Sin esto, un ancla mal guardada
        // o una pantalla que se desconecta la mandan a coordenadas donde no la
        // vuelves a ver. El margen transparente de la sombra no cuenta.
        let aireVisible = VistaHud.margen
        x = min(max(util.minX - aireVisible, x), util.maxX - tamano.width + aireVisible)
        y = min(max(util.minY - aireVisible, y), util.maxY - tamano.height + aireVisible)

        p.setFrame(NSRect(x: x, y: y, width: tamano.width, height: tamano.height),
                   display: true, animate: animado)
    }

    /// Mueve la barra mientras la arrastras.
    func mover(_ desplazamiento: CGSize) {
        guard let p = panel else { return }
        arrastrando = true
        abrirLuego?.cancel(); abrirLuego = nil
        if origenArrastre == nil { origenArrastre = p.frame.origin }
        guard let origen = origenArrastre else { return }
        // En pantalla, y crece hacia arriba: el arrastre hacia abajo resta.
        let nuevo = NSPoint(x: origen.x + desplazamiento.width,
                            y: origen.y - desplazamiento.height)
        p.setFrameOrigin(nuevo)
    }

    /// Al soltar se pega al ancla más cercana, en vez de quedarse torcida.
    func soltar() {
        guard let p = panel, let pantalla = pantallaActual() else { return }
        origenArrastre = nil
        arrastrando = false
        let centro = NSPoint(x: p.frame.midX, y: p.frame.midY)
        let elegida = Ancla.masCercana(a: centro, en: pantalla.visibleFrame)
        Ajustes.compartidos.pildoraAncla = elegida.rawValue
        modelo.vertical = elegida.esVertical
        // Las coordenadas sueltas ya no se usan; se limpian para que una versión
        // vieja no las reviva y la deje otra vez a media pantalla.
        Ajustes.compartidos.pildoraX = -1
        Ajustes.compartidos.pildoraY = -1
        acomodar(p, animado: true)
    }
}
