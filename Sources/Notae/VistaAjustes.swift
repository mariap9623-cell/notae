import SwiftUI
import Speech
import Translation

struct VistaAjustes: View {
    @ObservedObject var coordinador: Coordinador
    @ObservedObject var ajustes: Ajustes
    @Environment(\.colorScheme) private var esquema

    @State private var idiomas: [Locale] = []
    @State private var idiomaElegido: String = ""
    @State private var idiomasTraduccion: [String] = []
    @State private var estadoTraduccion = ""
    @State private var configDescarga: TranslationSession.Configuration?

    var body: some View {
        VStack(spacing: 0) {
            cabecera
            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {

                    seccion("cómo se activa") {
                        fila("Tecla") {
                            Picker("", selection: $ajustes.tecla) {
                                ForEach(TeclaAtajo.allCases) { t in Text(t.nombre).tag(t) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        fila("Forma") {
                            Picker("", selection: $ajustes.modo) {
                                ForEach(ModoAtajo.allCases) { m in Text(m.nombre).tag(m) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        if ajustes.tecla == .fn {
                            nota("Si al usar fn se abre el selector de emojis, ve a Ajustes del sistema › Teclado › «Al presionar 🌐» y elige «No hacer nada».")
                        }
                    }

                    seccion("idioma") {
                        fila("Dictado en") {
                            Picker("", selection: $idiomaElegido) {
                                ForEach(idiomas, id: \.identifier) { l in
                                    Text(nombre(de: l)).tag(l.identifier)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: idiomaElegido) { _, nuevo in
                                guard !nuevo.isEmpty, nuevo != ajustes.idioma else { return }
                                ajustes.idioma = nuevo
                                coordinador.recargarIdioma()
                            }
                        }
                        if !coordinador.mensajeEstado.isEmpty {
                            Text(coordinador.mensajeEstado)
                                .font(Marca.sans(11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    seccion("escribir en otro idioma") {
                        fila("Escribir en") {
                            Picker("", selection: $ajustes.idiomaSalida) {
                                Text("el mismo que hablo").tag("")
                                ForEach(idiomasTraduccion, id: \.self) { c in
                                    Text(Traductor.nombre(c)).tag(c)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: ajustes.idiomaSalida) { _, _ in
                                Task { await revisarTraduccion() }
                            }
                        }
                        Text("Hablas en \(nombreCorto(ajustes.idioma)) y Notae escribe en el idioma que elijas. La traducción también ocurre dentro de tu Mac.")
                            .font(Marca.sans(11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !estadoTraduccion.isEmpty {
                            nota(estadoTraduccion)
                        }
                        if estadoTraduccion.contains("descargar") {
                            enlace("Descargar el idioma") {
                                configDescarga = TranslationSession.Configuration(
                                    source: Locale.Language(identifier: Traductor.raiz(ajustes.idioma)),
                                    target: Locale.Language(identifier: Traductor.raiz(ajustes.idiomaSalida)))
                            }
                        }
                    }

                    seccion("qué hace con lo que dictas") {
                        fila("Estilo") {
                            Picker("", selection: $ajustes.estilo) {
                                ForEach(EstiloLimpieza.allCases) { e in Text(e.nombre).tag(e) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Text(ajustes.estilo.detalle)
                            .font(Marca.sans(11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if ajustes.estilo.usaIA, let motivo = coordinador.limpieza.motivoNoDisponible {
                            nota(motivo)
                        }
                    }

                    seccion("tus palabras") {
                        Text("Nombres, marcas y términos que quieres que escriba bien. Uno por línea.")
                            .font(Marca.sans(11.5))
                            .foregroundStyle(.secondary)
                        editor($ajustes.vocabulario)
                    }

                    seccion("atajos de voz") {
                        Text("Dices lo de la izquierda y Notae escribe lo de la derecha. Uno por línea, separados por el signo igual.")
                            .font(Marca.sans(11.5))
                            .foregroundStyle(.secondary)
                        editor($ajustes.atajos)
                        Text("Ejemplo:  mi correo = hola@nosecomousarlaia.com\nUsa \\n dentro del texto para saltos de línea.")
                            .font(Marca.sans(11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    seccion("tus reglas de escritura") {
                        Text("Instrucciones para la IA local. Por ejemplo: «nunca uses guiones largos» o «tutea siempre».")
                            .font(Marca.sans(11.5))
                            .foregroundStyle(.secondary)
                        editor($ajustes.reglas)
                    }

                    seccion("portapapeles") {
                        interruptor("Recordar lo último que copio", $ajustes.guardarCopias)
                        Text("El botón del portapapeles en la barra te deja volver a pegar las últimas \(Portapapeles.maximo) cosas que copiaste. Se guardan solo en memoria: al cerrar Notae se borran, y no se guarda nada que venga de un gestor de contraseñas.")
                            .font(Marca.sans(11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    seccion("detalles") {
                        interruptor("Pegar automáticamente donde esté el cursor", $ajustes.pegarAutomatico)
                        interruptor("Sonidos al empezar y terminar", $ajustes.sonidos)
                        interruptor("Mostrar lo que vas diciendo", $ajustes.mostrarTexto)
                    }

                    if coordinador.faltaMicrofono || coordinador.faltaAccesibilidad {
                        seccion("permisos") {
                            if coordinador.faltaMicrofono {
                                enlace("Dar permiso de micrófono") {
                                    abrir("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                                }
                            }
                            if coordinador.faltaAccesibilidad {
                                enlace("Dar permiso de accesibilidad") {
                                    coordinador.monitor.pedirPermiso()
                                    abrir("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                                }
                            }
                            enlace("Ya los di, volver a revisar") {
                                Task { await coordinador.revisarPermisos() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
        }
        .frame(minWidth: 480)
        .task {
            idiomaElegido = ajustes.idioma
            let paraTraducir = await Traductor.idiomasSoportados()
            idiomasTraduccion = Array(Set(paraTraducir.compactMap { $0.languageCode?.identifier })).sorted {
                Traductor.nombre($0) < Traductor.nombre($1)
            }
            await revisarTraduccion()
            let soportados = await SpeechTranscriber.supportedLocales
            idiomas = soportados.sorted { nombre(de: $0) < nombre(de: $1) }
            if !idiomas.contains(where: { $0.identifier == idiomaElegido }) {
                if let equivalente = idiomas.first(where: {
                    $0.identifier(.bcp47) == Locale(identifier: ajustes.idioma).identifier(.bcp47)
                }) {
                    idiomaElegido = equivalente.identifier
                    ajustes.idioma = equivalente.identifier
                }
            }
        }
        .translationTask(configDescarga) { sesion in
            try? await sesion.prepareTranslation()
            await revisarTraduccion()
        }
        // La barra pidió bajar un idioma: aquí es donde macOS deja hacerlo.
        .onChange(of: coordinador.parPorDescargar) { _, par in
            guard let par, par.count == 2 else { return }
            configDescarga = TranslationSession.Configuration(
                source: Locale.Language(identifier: par[0]),
                target: Locale.Language(identifier: par[1]))
            coordinador.parPorDescargar = nil
        }
        .onDisappear { Ventanas.revisarDock() }
    }

    // MARK: - Piezas

    private var cabecera: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ajustes").font(Marca.sans(24, .semibold))
            Spacer()
            Wordmark(tamano: 12).opacity(0.85)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func seccion<C: View>(_ titulo: String, @ViewBuilder contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo)
                .font(Marca.sans(10, .semibold))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Marca.verdeLegible(esquema))
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Etiqueta a la izquierda, control a la derecha, filete debajo.
    @ViewBuilder
    private func fila<C: View>(_ titulo: String, @ViewBuilder control: () -> C) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(titulo).font(Marca.sans(13))
                Spacer()
                control()
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }

    private func interruptor(_ titulo: String, _ valor: Binding<Bool>) -> some View {
        VStack(spacing: 8) {
            Toggle(isOn: valor) {
                Text(titulo).font(Marca.sans(13))
            }
            .toggleStyle(.switch)
            .tint(Marca.verdeLogo(esquema))
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }

    private func editor(_ texto: Binding<String>) -> some View {
        TextEditor(text: texto)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
            )
    }

    private func enlace(_ titulo: String, accion: @escaping () -> Void) -> some View {
        Button(titulo, action: accion)
            .buttonStyle(.plain)
            .font(Marca.sans(12, .medium))
            .foregroundStyle(Marca.verdeLegible(esquema))
    }

    private func nota(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Marca.verdeLogo(esquema).opacity(0.6))
                .frame(width: 2)
            Text(texto)
                .font(Marca.sans(11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mira si el par de idiomas está listo, o si hay que bajarlo.
    private func revisarTraduccion() async {
        guard !ajustes.idiomaSalida.isEmpty,
              Traductor.raiz(ajustes.idiomaSalida) != Traductor.raiz(ajustes.idioma) else {
            estadoTraduccion = ""
            return
        }
        let estado = await Traductor.estado(de: ajustes.idioma, a: ajustes.idiomaSalida)
        switch estado {
        case .installed:
            estadoTraduccion = ""
        case .supported:
            estadoTraduccion = "Hay que descargar este idioma una vez. Son unos pocos megas y después funciona sin internet."
        case .unsupported:
            estadoTraduccion = "Este par de idiomas no lo traduce macOS."
        @unknown default:
            estadoTraduccion = ""
        }
    }

    private func nombreCorto(_ id: String) -> String { Traductor.nombre(id) }

    private func nombre(de locale: Locale) -> String {
        let base = Locale.current.localizedString(forIdentifier: locale.identifier)
        return (base ?? locale.identifier).capitalized
    }

    private func abrir(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
