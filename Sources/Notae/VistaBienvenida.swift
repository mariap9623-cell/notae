import SwiftUI

struct VistaBienvenida: View {
    @ObservedObject var coordinador: Coordinador
    @Environment(\.colorScheme) private var esquema

    /// Lo que la persona dicta en la prueba. Nunca se guarda ni se manda a
    /// ningún lado: es solo para que vea con sus ojos que funciona.
    @State private var prueba = ""
    @FocusState private var pruebaEnfocada: Bool

    /// Los tres permisos/motores listos: ya se puede dictar.
    private var todoListo: Bool {
        !coordinador.faltaMicrofono && !coordinador.faltaAccesibilidad && coordinador.listo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(alignment: .center) {
                Simbolo(ancho: 46)
                Spacer()
                Wordmark(tamano: 12).opacity(0.85)
            }

            Text("Notae")
                .font(Marca.sans(50, .semibold))
                .padding(.top, 18)

            Text("Dictado que escribe como tú,\ndentro de tu Mac.")
                .font(Marca.sans(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            filete.padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 16) {
                paso("micrófono",
                     detalle: "para poder escucharte",
                     hecho: !coordinador.faltaMicrofono,
                     accion: { Task { await coordinador.revisarPermisos() } })

                paso("accesibilidad",
                     detalle: "para la tecla y para pegar donde estés",
                     hecho: !coordinador.faltaAccesibilidad,
                     accion: {
                         coordinador.monitor.pedirPermiso()
                         if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                             NSWorkspace.shared.open(u)
                         }
                     })

                // El tercer paso no lo das tú: es macOS bajando el idioma. Sin
                // esto la app parece rota los primeros minutos, porque la tecla
                // no hace nada y nadie explica por qué.
                pasoIdioma
            }

            filete.padding(.vertical, 20)

            prueba_

            Spacer(minLength: 18)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nada de lo que dices sale de tu computador.")
                        .font(Marca.sans(11))
                        .foregroundStyle(.secondary)
                    Text("Hecha por @mariapaula_rayo · © 2026 nosecomousarlaia")
                        .font(Marca.sans(10))
                        .foregroundStyle(.secondary)
                        .opacity(0.75)
                }
                Spacer()
                Button {
                    cerrar()
                } label: {
                    Text(todoListo ? "empezar" : "más tarde")
                        .font(Marca.sans(12, .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(todoListo
                                         ? (esquema == .dark ? Color.black : Color.white)
                                         : Color.primary.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if todoListo {
                                    Capsule().fill(Marca.verdeLogo(esquema))
                                } else {
                                    Capsule().strokeBorder(Color.primary.opacity(0.25),
                                                           lineWidth: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 480)
        .task {
            while !Task.isCancelled {
                coordinador.refrescarPermisos()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: todoListo) { _, listo in
            // En cuanto se puede dictar, el cursor se pone solo en la casilla
            // de prueba: no hay que adivinar dónde hacer clic.
            if listo { pruebaEnfocada = true }
        }
        .onDisappear { cerrar(cerrandoVentana: false) }
    }

    private func cerrar(cerrandoVentana: Bool = true) {
        coordinador.ajustes.yaHizoOnboarding = true
        if cerrandoVentana { NSApp.keyWindow?.close() }
        Ventanas.revisarDock()
    }

    // MARK: - Piezas

    /// El paso que no depende de la persona: preparar el idioma.
    private var pasoIdioma: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if coordinador.listo {
                Circle()
                    .fill(Marca.verdeLogo(esquema))
                    .frame(width: 9, height: 9)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 9, height: 9)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("idioma")
                    .font(Marca.sans(14))
                    .foregroundStyle(coordinador.listo ? .secondary : .primary)
                    .strikethrough(coordinador.listo, color: .secondary)
                Text(coordinador.listo
                     ? "descargado, funciona sin internet"
                     : (coordinador.mensajeEstado.isEmpty
                        ? "esperando los otros permisos"
                        : coordinador.mensajeEstado + " (una sola vez, puede tardar)"))
                    .font(Marca.sans(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
    }

    /// La prueba. Es lo único que convence: que lo vea escribirse.
    @ViewBuilder
    private var prueba_: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotulo(todoListo ? "pruébalo aquí" : "cómo se usa")

            Text(coordinador.descripcionAtajo + ". Suelta y el texto aparece donde tengas el cursor.")
                .font(Marca.sans(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if todoListo {
                TextField("mantén la tecla y di algo…", text: $prueba, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Marca.sans(14))
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(prueba.isEmpty
                                                  ? Color.primary.opacity(0.12)
                                                  : Marca.verdeLogo(esquema).opacity(0.55),
                                                  lineWidth: 1)
                            )
                    )
                    .focused($pruebaEnfocada)

                if !prueba.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Marca.verdeLogo(esquema))
                            .font(.system(size: 11))
                        Text("Eso es todo. Funciona igual en cualquier app.")
                            .font(Marca.sans(11.5))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }

            Text("Si al usar fn se abre el selector de emojis, ve a Ajustes del sistema › Teclado › «Al presionar 🌐» y elige «No hacer nada».")
                .font(Marca.sans(11))
                .foregroundStyle(.secondary)
                .opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .animation(.easeOut(duration: 0.2), value: todoListo)
        .animation(.easeOut(duration: 0.2), value: prueba.isEmpty)
    }

    private var filete: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
    }

    private func rotulo(_ t: String) -> some View {
        Text(t)
            .font(Marca.sans(10, .semibold))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Marca.verdeLegible(esquema))
    }

    /// Un permiso: punto, nombre y, si falta, el botón para darlo.
    private func paso(_ titulo: String, detalle: String,
                      hecho: Bool, accion: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(hecho ? Marca.verdeLogo(esquema) : Color.clear)
                .overlay(
                    Circle().strokeBorder(hecho ? Marca.verdeLogo(esquema) : Color.secondary,
                                          lineWidth: 1)
                )
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(titulo)
                    .font(Marca.sans(14))
                    .foregroundStyle(hecho ? .secondary : .primary)
                    .strikethrough(hecho, color: .secondary)
                Text(detalle)
                    .font(Marca.sans(11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !hecho {
                Button("permitir", action: accion)
                    .buttonStyle(.plain)
                    .font(Marca.sans(12, .medium))
                    .foregroundStyle(Marca.verdeLegible(esquema))
            }
        }
    }
}
