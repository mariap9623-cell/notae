import Foundation
import AppKit
import ApplicationServices

/// Escucha la tecla del dictado en todo el sistema.
/// Usa monitores globales de NSEvent: solo observan, nunca bloquean el evento,
/// así que no rompen atajos de otras apps.
@MainActor
final class MonitorAtajo {

    var alEmpezar: () -> Void = {}
    var alTerminar: () -> Void = {}
    var alCancelar: () -> Void = {}

    private var tecla: TeclaAtajo = .fn
    private var modo: ModoAtajo = .mantener

    private var monitorGlobal: Any?
    private var monitorLocal: Any?

    private var teclaAbajo = false
    private var dictando = false
    private var arranqueDiferido: DispatchWorkItem?

    /// Espera corta antes de arrancar: si la persona usa la tecla como parte de
    /// un atajo (fn + flecha, ⌘ + C), no se dispara el dictado.
    private let retardo: TimeInterval = 0.18

    var tienePermiso: Bool { AXIsProcessTrusted() }

    func pedirPermiso() {
        let opciones = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opciones)
    }

    func configurar(tecla: TeclaAtajo, modo: ModoAtajo) {
        self.tecla = tecla
        self.modo = modo
    }

    @discardableResult
    func encender() -> Bool {
        apagar()
        guard tienePermiso else {
            Registro.di("atajo: sin permiso de accesibilidad")
            return false
        }

        let tipos: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        monitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: tipos) { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        // El monitor global no ve los eventos cuando la propia app tiene el foco.
        monitorLocal = NSEvent.addLocalMonitorForEvents(matching: tipos) { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
            return evento
        }

        let ok = monitorGlobal != nil
        Registro.di("atajo: monitor \(ok ? "encendido" : "falló") · tecla=\(tecla.rawValue) modo=\(modo.rawValue)")
        return ok
    }

    func apagar() {
        if let monitorGlobal { NSEvent.removeMonitor(monitorGlobal) }
        if let monitorLocal { NSEvent.removeMonitor(monitorLocal) }
        monitorGlobal = nil
        monitorLocal = nil
        teclaAbajo = false
        dictando = false
    }

    // MARK: - Lógica

    private func recibir(_ evento: NSEvent) {
        if evento.type == .keyDown {
            // Si escribe algo mientras sostiene la tecla, era un atajo: cancelamos.
            if teclaAbajo {
                arranqueDiferido?.cancel()
                arranqueDiferido = nil
                if dictando {
                    dictando = false
                    Registro.di("atajo: cancelado (tecla + otra tecla)")
                    alCancelar()
                }
            }
            return
        }

        guard evento.type == .flagsChanged else { return }

        let codigo = Int64(evento.keyCode)
        let abajo = evento.modifierFlags.contains(bandera(de: tecla))
        Registro.di("atajo: flagsChanged codigo=\(codigo) abajo=\(abajo) esperado=\(tecla.keyCode)")

        guard codigo == tecla.keyCode else { return }
        guard abajo != teclaAbajo else { return }
        teclaAbajo = abajo

        switch modo {
        case .mantener:
            if abajo {
                let trabajo = DispatchWorkItem { [weak self] in
                    guard let self, self.teclaAbajo else { return }
                    self.dictando = true
                    Registro.di("atajo: empezar")
                    self.alEmpezar()
                }
                arranqueDiferido = trabajo
                DispatchQueue.main.asyncAfter(deadline: .now() + retardo, execute: trabajo)
            } else {
                arranqueDiferido?.cancel()
                arranqueDiferido = nil
                if dictando {
                    dictando = false
                    Registro.di("atajo: terminar")
                    alTerminar()
                }
            }

        case .alternar:
            guard abajo else { return }
            if dictando {
                dictando = false
                Registro.di("atajo: terminar (alternar)")
                alTerminar()
            } else {
                dictando = true
                Registro.di("atajo: empezar (alternar)")
                alEmpezar()
            }
        }
    }

    private func bandera(de tecla: TeclaAtajo) -> NSEvent.ModifierFlags {
        switch tecla {
        case .fn: return .function
        case .opcionDerecha: return .option
        case .comandoDerecho: return .command
        case .controlDerecho: return .control
        }
    }
}
