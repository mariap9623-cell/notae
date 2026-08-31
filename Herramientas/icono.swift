#!/usr/bin/env swift
// Dibuja el ícono de la app con el símbolo de nosecomousarlaia (racimo horizontal).
// Uso: swift Herramientas/icono.swift salida.png [variante]
// Variantes: verde | oscuro | claro | contorno

import AppKit

let destino = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icono.png"
let variante = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "verde"
// iOS recorta el ícono él mismo, así que ahí va cuadrado.
let cuadrado = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "cuadrado"

// Círculos del símbolo, tal cual salen de logos/nose.svg (viewBox 336.43 x 197.93).
let circulos: [(CGFloat, CGFloat, CGFloat)] = [
    (45.63, 20.78, 9.06), (121.38, 20.64, 12.90), (197.13, 20.62, 19.33), (272.83, 20.63, 20.63),
    (7.84, 71.99, 7.84), (83.57, 71.99, 11.64), (159.30, 72.05, 15.40), (234.98, 72.01, 21.92),
    (310.66, 72.02, 25.77),
    (45.65, 123.29, 9.03), (121.38, 123.36, 12.91), (197.18, 123.37, 19.33), (272.81, 123.41, 24.51),
    (83.61, 174.64, 11.62), (235.02, 174.73, 23.19)
]
let anchoSVG: CGFloat = 336.43
let altoSVG: CGFloat = 197.93

func color(_ hex: String) -> CGColor {
    var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if h.count == 6 { h += "FF" }
    let v = UInt32(h, radix: 16) ?? 0
    return CGColor(red: CGFloat((v >> 24) & 255) / 255,
                   green: CGFloat((v >> 16) & 255) / 255,
                   blue: CGFloat((v >> 8) & 255) / 255,
                   alpha: CGFloat(v & 255) / 255)
}

// Paletas tomadas de tokens.css (marca nose).
let fondo: (String, String)
let tinta: String
switch variante {
case "oscuro":   fondo = ("#181E18", "#0C110C"); tinta = "#5FBE7A"   // oscuro + verde claro
case "claro":    fondo = ("#FFFFFF", "#EFF6F0"); tinta = "#43A05E"   // blanco + verde de marca
case "contorno": fondo = ("#101510", "#101510"); tinta = "#E8EBDD"   // oscuro + crema
default:         fondo = ("#4FB26B", "#369052"); tinta = "#FFFFFF"   // verde + blanco
}

let lado: CGFloat = 1024

// Ojo: `NSImage.lockFocus` dibuja a la escala de la pantalla, así que en un Mac
// retina saldría de 2048 px y iOS rechaza el ícono. Se dibuja en un mapa de
// bits de tamaño exacto.
guard let mapa = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(lado), pixelsHigh: Int(lado),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mapa)
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

let radio = cuadrado ? 0 : lado * 0.2237
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: lado, height: lado),
                   cornerWidth: radio, cornerHeight: radio, transform: nil))
ctx.clip()

let espacio = CGColorSpaceCreateDeviceRGB()
if let degradado = CGGradient(colorsSpace: espacio,
                              colors: [color(fondo.0), color(fondo.1)] as CFArray,
                              locations: [0, 1]) {
    ctx.drawLinearGradient(degradado,
                           start: CGPoint(x: 0, y: lado),
                           end: CGPoint(x: lado, y: 0),
                           options: [])
}

// El símbolo, centrado y con aire alrededor.
let escala = (lado * 0.66) / anchoSVG
let anchoFinal = anchoSVG * escala
let altoFinal = altoSVG * escala
let origenX = (lado - anchoFinal) / 2
let origenY = (lado - altoFinal) / 2

ctx.setFillColor(color(tinta))
for (cx, cy, r) in circulos {
    let x = origenX + cx * escala
    let y = origenY + (altoSVG - cy) * escala   // el SVG crece hacia abajo
    let rr = r * escala
    ctx.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
}
ctx.fillPath()

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let png = mapa.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: destino))
print("ícono \(variante) en \(destino)")
