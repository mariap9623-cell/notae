import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// La ventana de Notae: todo lo que has dictado y transcrito, en un solo sitio.
struct VistaVentana: View {
    @ObservedObject var coordinador: Coordinador
    @ObservedObject var historial = Historial.compartido
    @StateObject private var transcripcion = Transcripcion()
    @StateObject private var resumen = Resumen()
    @ObservedObject private var reunion = Coordinador.compartido.reunion
    @Environment(\.colorScheme) private var esquema

    @State private var elegida: Entrada.ID?
    @State private var encima = false
    @State private var seccion: Seccion = .dictado

    var body: some View {
        NavigationSplitView {
            barraSecciones
                .navigationSplitViewColumnWidth(min: 198, ideal: 212, max: 240)
        } detail: {
            if seccion == .configuracion {
                VistaAjustes(coordinador: coordinador, ajustes: coordinador.ajustes)
            } else {
                // HStack y no HSplitView: el split view de AppKit impone sus
                // propios anchos mínimos, el conjunto pedía más de lo que mide
                // la ventana y la barra lateral se dibujaba fuera del borde
                // izquierdo, recortada.
                HStack(spacing: 0) {
                    lista
                        .frame(width: 290)
                    Divider()
                    detalle
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            transcribir(u)
            return true
        } isTargeted: { encima = $0 }
        .overlay { if encima { marcaSoltar } }
    }

    // MARK: - Barra de secciones

    /// Las cuatro secciones y, abajo del todo, en qué idioma hablas y en cuál
    /// escribe. Ese selector estaba escondido en la ventana de ajustes y por eso
    /// nadie sabía que Notae puede oírte en español y escribir en inglés.
    private var barraSecciones: some View {
        VStack(spacing: 0) {
            // Una List de verdad, no un VStack de botones.
            //
            // La barra lateral de macOS espera una lista: con un VStack los
            // márgenes que mete el sistema no cuadran y el contenido termina
            // dibujado fuera del borde izquierdo, recortado.
            List(selection: $seccion) {
                Section {
                    ForEach(Seccion.allCases) { s in
                        HStack(spacing: 7) {
                            Image(systemName: s.icono)
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text(s.nombre)
                                .font(Marca.sans(12.5))
                                .lineLimit(1)
                            Spacer(minLength: 3)
                            if s.listaEntradas {
                                let n = historial.cuantas(s)
                                if n > 0 {
                                    Text("\(n)")
                                        .font(Marca.sans(10.5))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(s)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Simbolo(ancho: 20)
                        Text("Notae").font(Marca.sans(14, .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.bottom, 4)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: seccion) { _, _ in
                elegida = nil
                historial.busqueda = ""
            }

            Divider().opacity(0.4)
            selectorIdioma
        }
    }

    /// Hablo en X, escribo en Y. Un clic para apagarlo.
    private var selectorIdioma: some View {
        let ajustes = coordinador.ajustes
        let hablado = Traductor.nombre(ajustes.idioma)
        let traduce = !ajustes.idiomaSalida.isEmpty
            && Traductor.raiz(ajustes.idiomaSalida) != Traductor.raiz(ajustes.idioma)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "mic")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text("hablo \(hablado.lowercased())")
                    .font(Marca.sans(10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 2)
            Menu {
                Button("Escribir en el mismo idioma") { ajustes.idiomaSalida = "" }
                Divider()
                ForEach(idiomasSalida, id: \.self) { codigo in
                    Button(Traductor.nombre(codigo)) { ajustes.idiomaSalida = codigo }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: traduce ? "character.book.closed" : "text.alignleft")
                        .font(.system(size: 11))
                        .foregroundStyle(traduce ? Marca.verdeLegible(esquema) : .secondary)
                    Text(traduce ? "escribo \(Traductor.nombre(ajustes.idiomaSalida).lowercased())"
                                 : "escribo igual")
                        .font(Marca.sans(11.5, traduce ? .semibold : .regular))
                        .foregroundStyle(traduce ? Marca.verdeLegible(esquema) : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(traduce ? Marca.verde.opacity(0.10) : Color.primary.opacity(0.06))
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// Los idiomas de salida que ya se pueden usar sin descargar nada más.
    /// La lista larga y la descarga siguen en Configuración, que es donde el
    /// sistema exige mostrar su propia ventana.
    private var idiomasSalida: [String] {
        ["en", "es", "pt", "fr", "it", "de"].filter {
            Traductor.raiz($0) != Traductor.raiz(coordinador.ajustes.idioma)
        }
    }

    // MARK: - Lista

    private var lista: some View {
        VStack(spacing: 0) {
            // Grabar solo aparece donde tiene sentido: en Reuniones.
            if seccion == .reuniones {
            Button {
                reunion.estado == .grabando ? terminarReunion() : empezarReunion()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(reunion.estado == .grabando ? Color.red : Marca.verdeLogo(esquema))
                        .frame(width: 9, height: 9)
                    Text(reunion.estado == .grabando ? "Terminar y armar el acta" : "Grabar reunión")
                        .font(Marca.sans(13, .medium))
                    Spacer()
                    if reunion.estado == .grabando {
                        Text(Fragmento.reloj(reunion.segundos))
                            .font(Marca.sans(12)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Buscar en \(seccion.nombre.lowercased())", text: $historial.busqueda)
                    .textFieldStyle(.plain)
                    .font(Marca.sans(12))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.055)))
            .padding(.horizontal, 12)
            .padding(.top, seccion == .reuniones ? 0 : 14)
            .padding(.bottom, 8)

            if historial.filtradas(seccion).isEmpty {
                vacio
            } else {
                List(historial.filtradas(seccion), selection: $elegida) { e in
                    fila(e).tag(e.id)
                }
                // `.sidebar` pintaba un bloque gris que no llegaba a los bordes
                // y dejaba el buscador flotando sobre otro fondo. Con `.inset`
                // y el fondo apagado, la columna entera es una sola pieza.
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider().opacity(0.4)

            HStack(spacing: 10) {
                if seccion == .reuniones {
                    Button {
                        elegirArchivo()
                    } label: {
                        Label("Transcribir audio", systemImage: "waveform")
                            .font(Marca.sans(12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Marca.verdeLegible(esquema))
                }
                if seccion == .notas {
                    Button {
                        coordinador.dictarNota()
                    } label: {
                        Label("Dictar una nota", systemImage: "mic")
                            .font(Marca.sans(12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Marca.verdeLegible(esquema))
                }
                Spacer()
                let cuantas = historial.cuantas(seccion)
                if cuantas > 0 {
                    Text("\(cuantas)")
                        .font(Marca.sans(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func fila(_ e: Entrada) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.titulo)
                .font(Marca.sans(12.5))
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(e.cuando)
                    .font(Marca.sans(10.5))
                    .foregroundStyle(.secondary)
                if let d = e.duracion {
                    Text("· \(Fragmento.reloj(d))")
                        .font(Marca.sans(10.5))
                        .foregroundStyle(.secondary)
                }
                // Dentro de Reuniones conviven las grabadas y los audios que
                // soltaste: ahí sí hace falta decir cuál es cuál.
                if seccion == .reuniones {
                    Text("· \(e.tipo.nombre)")
                        .font(Marca.sans(10.5))
                        .foregroundStyle(.secondary)
                }
                if e.resumen != nil {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                        .foregroundStyle(Marca.verdeLegible(esquema))
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copiar") { copiar(e.texto) }
            Button("Borrar", role: .destructive) { historial.borrar(e) }
        }
    }

    private var vacio: some View {
        VStack(spacing: 8) {
            Spacer()
            Simbolo(ancho: 42, energia: 0.4)
            Text(historial.busqueda.isEmpty ? seccion.vacioTitulo : "Nada coincide con esa búsqueda")
                .font(Marca.sans(12.5, .medium))
                .multilineTextAlignment(.center)
            if historial.busqueda.isEmpty {
                Text(seccion.vacioDetalle)
                    .font(Marca.sans(11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 230)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: - Detalle

    @ViewBuilder
    private var detalle: some View {
        if reunion.estado == .grabando || reunion.estado == .cerrando {
            enVivo
        } else if case .preparando(let paso) = reunion.estado {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(paso).font(Marca.sans(12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .error(let mensaje) = reunion.estado {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22)).foregroundStyle(.orange)
                Text(mensaje)
                    .font(Marca.sans(13))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                Button("Abrir Ajustes del sistema") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .font(Marca.sans(12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .trabajando(let avance) = transcripcion.estado {
            trabajando(avance)
        } else if case .preparando(let paso) = transcripcion.estado {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(paso).font(Marca.sans(12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let id = elegida, let e = historial.entradas.first(where: { $0.id == id }) {
            contenido(e)
        } else {
            VStack(spacing: 12) {
                Simbolo(ancho: 52, energia: 0.35)
                Text(seccion == .reuniones
                     ? "Elige una reunión, o suelta aquí un audio para transcribirlo"
                     : "Elige algo de la lista")
                    .font(Marca.sans(12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func trabajando(_ avance: Double) -> some View {
        VStack(spacing: 14) {
            Simbolo(ancho: 54, energia: max(0.2, avance))
            ProgressView(value: avance)
                .frame(width: 240)
                .tint(Marca.verdeLogo(esquema))
            Text("\(Int(avance * 100))% · \(Fragmento.reloj(avance * transcripcion.duracion)) de \(Fragmento.reloj(transcripcion.duracion))")
                .font(Marca.sans(11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contenido(_ e: Entrada) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.titulo)
                        .font(Marca.sans(20, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(e.tipo.nombre.uppercased())
                            .font(Marca.sans(9.5, .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Marca.verdeLegible(esquema))
                        Text(e.cuando).font(Marca.sans(11)).foregroundStyle(.secondary)
                        Text("· \(e.palabras) palabras").font(Marca.sans(11)).foregroundStyle(.secondary)
                        if let o = e.origen {
                            Text("· \(o)").font(Marca.sans(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }

                if let r = e.resumen, !r.isEmpty {
                    bloque("resumen") {
                        Text(r).font(Marca.sans(14)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !e.destacados.isEmpty {
                    bloque("lo que marcaste") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(e.destacados, id: \.self) { d in
                                HStack(alignment: .top, spacing: 9) {
                                    Rectangle()
                                        .fill(Marca.verdeLogo(esquema))
                                        .frame(width: 2)
                                    Text(d)
                                        .font(Marca.sans(13.5))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if !e.tareas.isEmpty {
                    bloque("tareas") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(e.tareas, id: \.self) { t in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Image(systemName: "square").font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text(t).font(Marca.sans(14))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                bloque(e.tipo == .dictado ? "lo que dijiste" : "transcripción") {
                    Text(e.texto)
                        .font(Marca.sans(14))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Copiar") { copiar(e.texto) }
                    if e.tipo == .transcripcion, e.resumen == nil {
                        Button("Armar el acta") { armarActa(e) }
                            .buttonStyle(.borderedProminent)
                            .tint(Marca.verdeLogo(esquema))
                    }
                    if case .trabajando(let paso) = resumen.estado {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(paso).font(Marca.sans(11)).foregroundStyle(.secondary)
                        }
                    }
                    if case .sinIA(let motivo) = resumen.estado {
                        Text(motivo).font(Marca.sans(11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Borrar", role: .destructive) {
                        historial.borrar(e)
                        elegida = nil
                    }
                }
                .font(Marca.sans(12))
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var enVivo: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text(reunion.estado == .cerrando ? "Cerrando…" : "Grabando")
                    .font(Marca.sans(13, .medium))
                Text(Fragmento.reloj(reunion.segundos))
                    .font(Marca.sans(13)).monospacedDigit().foregroundStyle(.secondary)
                Simbolo(ancho: 30, energia: 0.25 + reunion.nivel * 0.75)
                Spacer()
                if reunion.estado == .grabando {
                    Button("Marcar momento") { reunion.marcarMomento() }
                        .buttonStyle(.plain)
                        .font(Marca.sans(12, .medium))
                        .foregroundStyle(Marca.verdeLegible(esquema))
                    if !reunion.marcas.isEmpty {
                        Text("\(reunion.marcas.count)")
                            .font(Marca.sans(11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Divider().opacity(0.4)

            ScrollView {
                Text(reunion.texto.isEmpty
                     ? "Cuando alguien hable, va a ir apareciendo aquí."
                     : reunion.texto)
                    .font(Marca.sans(14))
                    .foregroundStyle(reunion.texto.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }

            Divider().opacity(0.4)
            Text("Se está grabando tu micrófono y lo que suena en el Mac. El audio queda guardado por si hay que volver.")
                .font(Marca.sans(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
        }
    }

    private func empezarReunion() {
        Task { await reunion.empezar(idioma: coordinador.ajustes.idioma) }
    }

    private func terminarReunion() {
        Task {
            await reunion.terminar()
            let texto = reunion.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { return }
            let f = DateFormatter()
            f.locale = Locale(identifier: "es")
            f.dateFormat = "d 'de' MMMM, HH:mm"
            let destacados = Documento.momentos(reunion.fragmentosFinales, marcas: reunion.marcas)
            let e = Entrada(tipo: .reunion,
                            texto: texto,
                            titulo: "Reunión del \(f.string(from: Date()))",
                            duracion: reunion.segundos,
                            marcas: reunion.marcas,
                            destacados: destacados,
                            audio: reunion.rutaAudio?.lastPathComponent)
            historial.agregar(e)
            elegida = e.id
            armarActa(e)
        }
    }

    private func bloque<C: View>(_ titulo: String, @ViewBuilder contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(titulo)
                .font(Marca.sans(10, .semibold))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Marca.verdeLegible(esquema))
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var marcaSoltar: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Marca.verdeLogo(esquema), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
            .overlay(Text("Suelta el audio para transcribirlo").font(Marca.sans(14, .medium)))
            .padding(10)
            .allowsHitTesting(false)
    }

    // MARK: - Acciones

    private func transcribir(_ url: URL) {
        Task {
            await transcripcion.transcribir(archivo: url, idioma: coordinador.ajustes.idioma)
            guard case .listo = transcripcion.estado else { return }
            let texto = Documento.textoPlano(transcripcion.fragmentos)
            guard !texto.isEmpty else { return }
            let e = Entrada(tipo: .transcripcion,
                            texto: texto,
                            titulo: url.deletingPathExtension().lastPathComponent,
                            origen: url.lastPathComponent,
                            duracion: transcripcion.duracion)
            historial.agregar(e)
            elegida = e.id
        }
    }

    private func armarActa(_ e: Entrada) {
        Task {
            await resumen.procesar(e.texto, titulo: e.titulo, destacados: e.destacados)
            guard case .listo = resumen.estado else { return }
            var copia = e
            copia.resumen = resumen.resumen
            copia.tareas = resumen.tareas
            historial.actualizar(copia)
        }
    }

    private func elegirArchivo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Audio, .mp3, .wav]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url { transcribir(u) }
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
}
