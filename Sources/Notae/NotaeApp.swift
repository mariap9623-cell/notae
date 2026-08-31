import SwiftUI
import AppKit

@main
struct NotaeApp: App {
    @NSApplicationDelegateAdaptor(Delegado.self) var delegado
    @StateObject private var coordinador = Coordinador.compartido
    @StateObject private var ajustes = Ajustes.compartidos

    var body: some Scene {
        MenuBarExtra {
            MenuNotae(coordinador: coordinador, ajustes: ajustes)
        } label: {
            // El símbolo de la marca, no un micrófono genérico.
            Image(nsImage: IconoBarra.imagen(estadoIcono, energia: coordinador.hud.nivel))
        }
        .menuBarExtraStyle(.menu)
    }

    private var estadoIcono: IconoBarra.Estado {
        switch coordinador.hud.fase {
        case .escuchando: return .escuchando
        case .procesando: return .procesando
        default: return .quieto
        }
    }
}

final class Delegado: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            Coordinador.compartido.arrancar()
            if !Ajustes.compartidos.yaHizoOnboarding {
                Ventanas.abrirBienvenida()
            }
        }
    }

    /// Si vuelves a abrir la app desde el Dock, Spotlight o Aplicaciones,
    /// mostramos los ajustes en vez de no hacer nada.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            if Ajustes.compartidos.yaHizoOnboarding {
                Ventanas.abrirPrincipal()
            } else {
                Ventanas.abrirBienvenida()
            }
        }
        return true
    }
}

struct MenuNotae: View {
    @ObservedObject var coordinador: Coordinador
    @ObservedObject var ajustes: Ajustes

    var body: some View {
        Text(estado)

        Button(coordinador.dictandoAhora ? "Terminar y pegar" : "Dictar ahora") {
            coordinador.alternarDesdeMenu()
        }
        .disabled(!coordinador.listo)

        Divider()

        Picker("Estilo", selection: $ajustes.estilo) {
            ForEach(EstiloLimpieza.allCases) { estilo in
                Text(estilo.nombre).tag(estilo)
            }
        }

        if !coordinador.ultimoTexto.isEmpty {
            Button("Copiar lo último") {
                Pegado.copiar(coordinador.ultimoTexto)
            }
        }

        Divider()

        Button("Abrir Notae") { Ventanas.abrirPrincipal() }
        Button("Ajustes…") { Ventanas.abrirAjustes() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Cómo se usa") { Ventanas.abrirBienvenida() }

        Divider()

        Button("Salir de Notae") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var estado: String {
        if coordinador.faltaMicrofono { return "Falta el permiso de micrófono" }
        if coordinador.faltaAccesibilidad { return "Falta el permiso de accesibilidad" }
        if !coordinador.mensajeEstado.isEmpty { return coordinador.mensajeEstado }
        if !coordinador.listo { return "Preparando…" }
        return coordinador.descripcionAtajo
    }
}
