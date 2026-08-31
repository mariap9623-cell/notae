import AppKit
import SwiftUI

/// Ventanas de la app (ajustes y bienvenida). Se crean a mano porque Notae vive
/// en la barra de menú y no tiene ventana principal.
@MainActor
enum Ventanas {

    private static var principal: NSWindow?
    private static var ajustes: NSWindow?
    private static var bienvenida: NSWindow?

    /// La ventana con el historial. Es la cara de Notae.
    static func abrirPrincipal() {
        if principal == nil {
            principal = crear(
                titulo: "Notae",
                ancho: 940, alto: 620,
                vista: AnyView(VistaVentana(coordinador: Coordinador.compartido))
            )
        }
        traerAlFrente(principal)
    }

    static func abrirAjustes() {
        if ajustes == nil {
            ajustes = crear(
                titulo: "Notae",
                ancho: 520, alto: 560,
                vista: AnyView(VistaAjustes(
                    coordinador: Coordinador.compartido,
                    ajustes: Ajustes.compartidos
                ))
            )
        }
        traerAlFrente(ajustes)
    }

    static func abrirBienvenida() {
        if bienvenida == nil {
            bienvenida = crear(
                titulo: "Bienvenida a Notae",
                ancho: 520, alto: 580,
                vista: AnyView(VistaBienvenida(coordinador: Coordinador.compartido))
            )
        }
        traerAlFrente(bienvenida)
    }

    private static func crear(titulo: String, ancho: CGFloat, alto: CGFloat, vista: AnyView) -> NSWindow {
        let ventana = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: ancho, height: alto),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // El nombre ya está dentro, en la barra lateral, así que la barra de
        // título va sin texto. Ojo: se deja vacío en vez de usar
        // `titleVisibility = .hidden`, que con `fullSizeContentView` corre el
        // contenido de la barra lateral hacia la izquierda y lo recorta.
        ventana.title = ""
        // El nombre real, para la lista de ventanas del sistema.
        ventana.setAccessibilityTitle(titulo)
        ventana.titlebarAppearsTransparent = true
        ventana.isReleasedWhenClosed = false
        ventana.center()
        ventana.contentView = NSHostingView(rootView: vista)
        return ventana
    }

    private static func traerAlFrente(_ ventana: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ventana?.makeKeyAndOrderFront(nil)
    }

    /// Vuelve a esconder el ícono del Dock cuando no hay ventanas abiertas.
    static func revisarDock() {
        let hayVentanas = [principal, ajustes, bienvenida].contains { $0?.isVisible == true }
        if !hayVentanas {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
