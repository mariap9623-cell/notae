import Foundation
import AppKit
import Combine

/// Une todas las piezas: tecla → micrófono → texto → limpieza → pegado.
@MainActor
final class Coordinador: ObservableObject {

    static let compartido = Coordinador()

    let ajustes = Ajustes.compartidos
    let dictado = Dictado()
    let limpieza = Limpieza()
    let traductor = Traductor()
    let monitor = MonitorAtajo()
    let hud = HudModelo()
    let reunion = Reunion()
    let portapapeles = Portapapeles()
    private lazy var panel = PanelHud(modelo: hud)

    @Published var listo = false
    @Published var mensajeEstado = ""
    @Published var faltaMicrofono = true
    @Published var faltaAccesibilidad = true
    @Published var ultimoTexto = ""
    /// Para el menú: si está dictando ahora mismo.
    @Published var dictandoAhora = false
    /// Par de idiomas que hay que bajar. La ventana de ajustes lo mira y lanza
    /// la descarga del sistema: un teclado o una barra no pueden hacerlo solos,
    /// macOS exige que salga de una vista.
    @Published var parPorDescargar: [String]?

    /// Empezar o terminar desde el menú de la barra. Sirve incluso sin el
    /// permiso de accesibilidad (ahí no hay tecla, pero sí se puede dictar).
    func alternarDesdeMenu() {
        if dictandoAhora { terminar() } else { empezar() }
    }

    private var cancelables = Set<AnyCancellable>()
    private var trabajando = false
    private var vigilante: Timer?
    /// Cuando es nota, el texto se guarda pero no se pega.
    private var modoNota = false
    /// Corta un dictado que se quedó abierto.
    private var tope: Timer?
    /// Cinco minutos: de sobra para cualquier dictado, y suficiente para que
    /// nada se quede colgado toda la tarde.
    private static let topeSegundos: TimeInterval = 300

    func arrancar() {
        Registro.di("app: arranca · versión \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        hud.mostrarTexto = ajustes.mostrarTexto

        // La píldora se queda abajo, como una barra de estado propia: desde
        // ahí se cambia el idioma y se abren las notas, sin ir al menú.
        hud.alTocarNotas = { Ventanas.abrirPrincipal() }
        hud.alCambiarIdioma = { [weak self] in self?.alternarIdiomaSalida() }
        hud.alDictar = { [weak self] in self?.alternarDesdeMenu() }
        hud.atajoDictar = ajustes.tecla.simbolo
        hud.alGrabarReunion = { [weak self] in self?.alternarReunion() }
        hud.alNotaNueva = { [weak self] in self?.dictarNota() }
        hud.alPortapapeles = { [weak self] in self?.abrirPortapapeles() }
        hud.alArrastrar = { [weak self] d in self?.panel.mover(d) }
        hud.alSoltar = { [weak self] in self?.panel.soltar() }
        refrescarEtiquetaIdioma()

        // Al abrirse la bandeja el contenido crece, y la ventana no cambia de
        // tamaño sola: hay que reacomodarla o los botones quedan cortados.
        hud.$encima
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panel.actualizar() }
            .store(in: &cancelables)

        portapapeles.$recientes
            .receive(on: RunLoop.main)
            .sink { [weak self] copias in self?.hud.hayCopias = !copias.isEmpty }
            .store(in: &cancelables)
        ajustes.alCambiarCopias = { [weak self] in self?.ajustarPortapapeles() }
        ajustarPortapapeles()
        ajustes.alCambiarHud = { [weak self] in
            guard let self else { return }
            self.hud.mostrarTexto = self.ajustes.mostrarTexto
        }

        dictado.$enVivo
            .receive(on: RunLoop.main)
            .sink { [weak self] texto in
                guard let self else { return }
                self.hud.texto = texto
                if self.ajustes.mostrarTexto { self.panel.actualizar() }
            }
            .store(in: &cancelables)

        reunion.$estado
            .receive(on: RunLoop.main)
            .sink { [weak self] e in self?.hud.enReunion = (e == .grabando) }
            .store(in: &cancelables)

        dictado.$nivel
            .receive(on: RunLoop.main)
            .sink { [weak self] nivel in self?.hud.nivel = nivel }
            .store(in: &cancelables)

        // Estado real de los permisos antes de pedir nada, para no mostrar
        // palomitas verdes mientras el diálogo del sistema sigue abierto.
        faltaMicrofono = !Dictado.microfonoAutorizado
        faltaAccesibilidad = !monitor.tienePermiso

        ajustes.alCambiarAtajo = { [weak self] in self?.reconfigurarAtajo() }

        monitor.alEmpezar = { [weak self] in self?.empezar() }
        monitor.alTerminar = { [weak self] in self?.terminar() }
        monitor.alCancelar = { [weak self] in self?.cancelar() }

        Task { await revisarPermisos() }
        Task { await revisarTraduccionGuardada() }
        vigilarPermisos()
        if ajustes.pildoraFija { mostrarReposo() }
    }

    /// macOS puede conceder la accesibilidad en cualquier momento (y la revoca
    /// cuando la app se vuelve a firmar). Revisamos cada dos segundos hasta que
    /// esté todo en orden, para no obligar a reiniciar la app.
    private func vigilarPermisos() {
        vigilante?.invalidate()
        vigilante = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] reloj in
            MainActor.assumeIsolated {
                guard let self else { reloj.invalidate(); return }
                self.refrescarPermisos()
                if !self.faltaMicrofono && !self.faltaAccesibilidad {
                    reloj.invalidate()
                    self.vigilante = nil
                }
            }
        }
    }

    func revisarPermisos() async {
        faltaMicrofono = !(await Dictado.pedirMicrofono())
        faltaAccesibilidad = !monitor.tienePermiso

        if faltaAccesibilidad {
            // Muestra el diálogo del sistema y deja la app en la lista de
            // accesibilidad para que solo haya que prender el interruptor.
            monitor.pedirPermiso()
        } else {
            reconfigurarAtajo()
        }
        if !faltaMicrofono {
            await prepararMotores()
        }
    }

    /// Revisa los permisos sin abrir diálogos. La ventana de bienvenida la llama
    /// cada segundo para que las palomitas se enciendan solas.
    func refrescarPermisos() {
        let micOk = Dictado.microfonoAutorizado
        if faltaMicrofono == micOk {
            faltaMicrofono = !micOk
            if micOk && !listo { Task { await prepararMotores() } }
        }
        let axOk = monitor.tienePermiso
        if faltaAccesibilidad == axOk {
            faltaAccesibilidad = !axOk
            if axOk { reconfigurarAtajo() }
        }
    }

    func reconfigurarAtajo() {
        hud.atajoDictar = ajustes.tecla.simbolo
        monitor.configurar(tecla: ajustes.tecla, modo: ajustes.modo)
        let ok = monitor.encender()
        faltaAccesibilidad = !ok
        Registro.di("permisos: micrófono=\(!faltaMicrofono) accesibilidad=\(!faltaAccesibilidad)")
    }

    private func prepararMotores() async {
        mensajeEstado = "Preparando el idioma…"
        await dictado.preparar(idioma: ajustes.idioma) { [weak self] paso in
            self?.mensajeEstado = paso
        }
        limpieza.precalentar(estilo: ajustes.estilo,
                             reglas: ajustes.listaReglas,
                             vocabulario: ajustes.listaVocabulario)
        mensajeEstado = ""
        listo = true
    }

    /// Vuelve a preparar todo cuando cambia el idioma en ajustes.
    func recargarIdioma() {
        listo = false
        Task { await prepararMotores() }
    }

    // MARK: - Dictado

    func empezar() {
        guard !trabajando else { return }
        guard listo else {
            Registro.di("empezar: bloqueado, motor no listo (\(mensajeEstado))")
            avisar(mensajeEstado.isEmpty ? "Todavía estoy preparando el idioma." : mensajeEstado)
            return
        }
        trabajando = true; dictandoAhora = true
        hud.texto = ""
        hud.fase = .escuchando
        panel.mostrar()
        sonar("Morse")

        Task {
            await dictado.empezar(vocabulario: ajustes.listaVocabulario)
            switch dictado.estado {
            case .escuchando:
                armarTope()
            case .error(let mensaje):
                soltar()
                dictado.volverAInactivo()
                avisar(mensaje)
            default:
                // No arrancó y tampoco reportó error. Antes esto dejaba la app
                // trabada: `trabajando` en true para siempre, la tecla muda y
                // sin más salida que cerrarla.
                Registro.di("empezar: el motor no quedó escuchando (\(dictado.estado)) · se suelta")
                soltar()
                dictado.volverAInactivo()
                avisar("No se pudo empezar a dictar. Inténtalo otra vez.")
            }
        }
    }

    /// Devuelve la app al estado en que se puede volver a dictar.
    ///
    /// Todo lo que corta un dictado pasa por aquí. Que exista un solo sitio es
    /// lo que evita quedar a medias: antes, cada camino soltaba unas banderas y
    /// se olvidaba de otras.
    private func soltar() {
        tope?.invalidate(); tope = nil
        trabajando = false
        dictandoAhora = false
        modoNota = false
    }

    /// Tope de duración. Sin esto, un dictado que nunca recibe su «terminar»
    /// (la tecla se pierde, se revoca la accesibilidad a media sesión) deja la
    /// app inservible hasta reiniciarla. Se cierra sola y pega lo que oyó.
    private func armarTope() {
        tope?.invalidate()
        tope = Timer.scheduledTimer(withTimeInterval: Self.topeSegundos, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.trabajando else { return }
                Registro.di("dictado: tope de \(Int(Self.topeSegundos))s · se cierra solo")
                self.terminar()
            }
        }
    }

    func terminar() {
        guard trabajando else { return }
        tope?.invalidate(); tope = nil
        // Se lee antes de soltar: `soltar()` la apaga, y si se leyera después
        // una nota terminaría pegándose donde estuviera el cursor.
        let eraNota = modoNota

        Task {
            let crudo = await dictado.terminar()
            dictado.volverAInactivo()
            Registro.di("dictado: \(crudo.count) caracteres · «\(crudo.prefix(60))»")

            guard !crudo.isEmpty else {
                soltar()
                mostrarReposo()
                return
            }

            if ajustes.estilo.usaIA {
                hud.fase = .procesando
            }

            let final = await limpieza.procesar(
                crudo,
                estilo: ajustes.estilo,
                reglas: ajustes.listaReglas,
                vocabulario: ajustes.listaVocabulario,
                atajos: ajustes.listaAtajos
            )

            // Si pediste escribir en otro idioma, se traduce antes de pegar.
            var salida = final
            let destino = ajustes.idiomaSalida
            if !destino.isEmpty,
               Traductor.raiz(destino) != Traductor.raiz(ajustes.idioma) {
                hud.fase = .procesando
                salida = await traductor.traducir(final, de: ajustes.idioma, a: destino)
            }

            ultimoTexto = salida
            Historial.compartido.agregar(Entrada(tipo: eraNota ? .nota : .dictado, texto: salida))
            Registro.di("limpieza: \(salida.count) caracteres · pegar=\(ajustes.pegarAutomatico)")
            // Lo que escribe Notae no cuenta como algo que copiaste tú: el
            // historial del portapapeles es solo tuyo.
            // 4 s, no 2: el pegado ahora devuelve el portapapeles a como estaba
            // 1.9 s después de ⌘V (ver `Pegado.esperaRestaurar`), y esa
            // restauración tampoco es una copia tuya.
            portapapeles.silenciar(4)
            if eraNota {
                // Era una nota: queda guardada, no se pega en ningún lado.
            } else if ajustes.pegarAutomatico {
                Pegado.pegar(salida)
            } else {
                Pegado.copiar(salida)
            }
            sonar("Pop")
            hud.fase = .listo
            panel.ocultarEn(0.7, volverAReposo: ajustes.pildoraFija)
            soltar()
        }
    }

    func cancelar() {
        guard trabajando else { return }
        tope?.invalidate(); tope = nil
        Task {
            await dictado.cancelar()
            dictado.volverAInactivo()
            soltar()
            mostrarReposo()
        }
    }

    // MARK: - Utilidades

    /// Deja la píldora quieta abajo, esperando.
    func mostrarReposo() {
        guard ajustes.pildoraFija else { panel.ocultarYa(); return }
        hud.fase = .reposo
        panel.mostrar()
    }

    /// Prende o apaga el historial del portapapeles según los ajustes. Al
    /// apagarlo se olvida lo que ya había: dejarlo en memoria sería una trampa.
    private func ajustarPortapapeles() {
        if ajustes.guardarCopias {
            portapapeles.encender()
        } else {
            portapapeles.apagar()
            portapapeles.olvidarTodo()
        }
    }

    /// Lo último que copiaste, para volver a pegarlo sin buscarlo.
    ///
    /// El menú se abre desde un panel que no activa la app, así que al elegir
    /// una copia el cursor sigue donde estaba y el pegado cae ahí.
    private func abrirPortapapeles() {
        let menu = NSMenu()
        let copias = portapapeles.recientes

        if copias.isEmpty {
            let vacio = NSMenuItem(title: "Todavía no has copiado nada",
                                   action: nil, keyEquivalent: "")
            vacio.isEnabled = false
            menu.addItem(vacio)
        } else {
            for copia in copias {
                let item = NSMenuItem(title: copia.resumen,
                                      action: #selector(Portapapeles.Accion.ejecutar),
                                      keyEquivalent: "")
                let accion = Portapapeles.Accion { [weak self] in
                    guard let self else { return }
                    // Sin esto, el propio pegado entraría al historial.
                    self.portapapeles.silenciar(2)
                    Pegado.pegar(copia.texto)
                }
                item.target = accion
                // `target` es débil: el menú tiene que sostener la acción.
                item.representedObject = accion
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let borrar = NSMenuItem(title: "Olvidar todo",
                                    action: #selector(Portapapeles.Accion.ejecutar),
                                    keyEquivalent: "")
            let accionBorrar = Portapapeles.Accion { [weak self] in
                self?.portapapeles.olvidarTodo()
            }
            borrar.target = accionBorrar
            borrar.representedObject = accionBorrar
            menu.addItem(borrar)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Dictar como nota: no pega nada, solo guarda en tu historial.
    func dictarNota() {
        modoNota = true
        empezar()
    }

    /// Empieza o termina una reunión desde la píldora.
    func alternarReunion() {
        Ventanas.abrirPrincipal()
        Task {
            // Si la anterior quedó en error, se limpia y se vuelve a intentar
            // en vez de dejar el botón sin respuesta.
            reunion.reiniciar()
            if reunion.estado == .grabando {
                await reunion.terminar()
                guardarReunion()
            } else if reunion.estado == .quieta {
                await reunion.empezar(idioma: ajustes.idioma)
            }
        }
    }

    /// Guarda lo grabado como una entrada del historial.
    func guardarReunion() {
        let texto = reunion.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d 'de' MMMM, HH:mm"
        let destacados = Documento.momentos(reunion.fragmentosFinales, marcas: reunion.marcas)
        Historial.compartido.agregar(Entrada(tipo: .reunion,
                                             texto: texto,
                                             titulo: "Reunión del \(f.string(from: Date()))",
                                             duracion: reunion.segundos,
                                             marcas: reunion.marcas,
                                             destacados: destacados,
                                             audio: reunion.rutaAudio?.lastPathComponent))
    }

    /// Alterna entre escribir en tu idioma y escribir en el otro que elegiste.
    private func alternarIdiomaSalida() {
        guard ajustes.idiomaSalida.isEmpty else {
            ajustes.ultimoIdiomaSalida = ajustes.idiomaSalida
            ajustes.idiomaSalida = ""
            refrescarEtiquetaIdioma()
            panel.actualizar()
            return
        }

        let destino = ajustes.ultimoIdiomaSalida.isEmpty ? "en" : ajustes.ultimoIdiomaSalida
        ajustes.idiomaSalida = destino
        refrescarEtiquetaIdioma()
        panel.actualizar()

        // macOS traduce con un modelo que hay que bajar una vez por par de
        // idiomas. Sin él, traducir no falla: devuelve el texto igual. O sea
        // que dirías «escribe en inglés» y saldría en español sin una sola
        // explicación. Se revisa aquí y se apaga si no está listo.
        Task {
            switch await Traductor.estado(de: ajustes.idioma, a: destino) {
            case .installed:
                break
            case .supported:
                // En vez de mandarla a buscar el ajuste, se abre y se lanza la
                // descarga. Que falte un archivo no es problema de la persona.
                apagarTraduccion(destino)
                avisar("Descargando \(Traductor.nombre(destino)) una sola vez…")
                parPorDescargar = [Traductor.raiz(ajustes.idioma), Traductor.raiz(destino)]
                Ventanas.abrirAjustes()
            default:
                apagarTraduccion(destino)
                avisar("macOS todavía no traduce a \(Traductor.nombre(destino)).")
            }
        }
    }

    /// El idioma de salida se guarda entre sesiones, pero el modelo que lo
    /// traduce lo puede borrar macOS (o venir de otro Mac). Si al arrancar la
    /// barra dice «ES→EN» y el inglés ya no está, escribiría en español sin
    /// avisar. Se revisa una vez al abrir.
    private func revisarTraduccionGuardada() async {
        let destino = ajustes.idiomaSalida
        guard !destino.isEmpty,
              Traductor.raiz(destino) != Traductor.raiz(ajustes.idioma) else { return }
        if case .installed = await Traductor.estado(de: ajustes.idioma, a: destino) { return }
        Registro.di("traducción: \(destino) no está descargado · se apaga")
        apagarTraduccion(destino)
    }

    private func apagarTraduccion(_ destino: String) {
        ajustes.ultimoIdiomaSalida = destino
        ajustes.idiomaSalida = ""
        refrescarEtiquetaIdioma()
        panel.actualizar()
    }

    func refrescarEtiquetaIdioma() {
        let hablado = Traductor.raiz(ajustes.idioma).uppercased()
        if ajustes.idiomaSalida.isEmpty {
            hud.etiquetaIdioma = hablado
        } else {
            hud.etiquetaIdioma = hablado + "→" + Traductor.raiz(ajustes.idiomaSalida).uppercased()
        }
    }

    func avisar(_ mensaje: String) {
        hud.fase = .aviso(mensaje)
        panel.mostrar()
        panel.ocultarEn(3.5, volverAReposo: ajustes.pildoraFija)
    }

    private func sonar(_ nombre: String) {
        guard ajustes.sonidos else { return }
        NSSound(named: NSSound.Name(nombre))?.play()
    }

    var descripcionAtajo: String {
        switch ajustes.modo {
        case .mantener: return "Mantén \(ajustes.tecla.nombre) y habla"
        case .alternar: return "Toca \(ajustes.tecla.nombre) para empezar y terminar"
        }
    }
}
