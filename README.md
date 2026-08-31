# Notae

Dictado local para Mac, de **nosecomousarlaia**. Mantienes una tecla, hablas, y
el texto aparece donde tengas el cursor. Nada de lo que dices sale del
computador y no hay suscripción.

Reemplaza al dictado por suscripción usando lo que ya trae macOS 26:

| pieza | qué usa |
|---|---|
| reconocimiento de voz | `SpeechAnalyzer` + `SpeechTranscriber` (Speech, macOS 26) |
| corrección del texto | `FoundationModels` (Apple Intelligence, en el chip) |
| atajo global | `CGEventTap` sobre `flagsChanged` |
| pegado | portapapeles + ⌘V, y devuelve el portapapeles a como estaba |

## Antes de descargarla, lee esto

Notae usa los modelos que ya trae macOS. Por eso pesa 3 MB, no descarga nada
pesado y no manda tu voz a ningún servidor. El precio de esa decisión es que
**es exigente con el Mac**:

- **macOS 26 o superior.** En macOS 15 o anterior no abre.
- **Apple Silicon** (M1 o posterior). En Intel no funciona.
- **Apple Intelligence encendido** para la corrección del texto. Ojo: el idioma
  del sistema y el de Siri tienen que coincidir, o Apple Intelligence se queda
  apagado. Sin él, el dictado funciona igual en modo **Crudo**, sin puntuación
  automática.
- El idioma de dictado se descarga solo la primera vez (es-ES, es-MX, es-CL, es-US).

Si tu Mac no cumple, hay otras herramientas de dictado de código abierto que
traen sus propios modelos en vez de usar los de Apple: funcionan en Macs más
antiguos y en Intel, a cambio de pesar bastante más. Búscalas, no te quedes sin
dictado por esto.

## macOS la va a bloquear la primera vez

Notae **no está notarizada**, porque eso pide una cuenta de desarrollador de
Apple de 99 dólares al año. macOS va a decir que no puede comprobar si contiene
malware. Se abre así, una sola vez:

1. Doble clic en Notae, en Aplicaciones. Sale el aviso, ciérralo.
2. Ajustes del sistema › Privacidad y seguridad.
3. Abajo dice «Se ha bloqueado el uso de Notae». Clic en **Abrir de todos modos**.

Después pide **Micrófono** y **Accesibilidad**. Los dos hacen falta: el primero
para oírte, el segundo para detectar la tecla y pegar donde tengas el cursor.

## Esto no es un producto

Notae es la herramienta que uso a diario, publicada por si le sirve a alguien
más. No es una empresa, no tiene soporte, no tiene actualizaciones automáticas
y no hay nadie más que yo detrás. Si se rompe, se rompe.

El código está bajo MIT: cógelo, cámbialo, hazlo tuyo. Lo único que no entra en
la licencia es la marca (el nombre, el logotipo y el símbolo de puntos), para
que tu versión y la mía no se confundan. Está todo en `LICENSE`.

## Compilar

Solo necesita las Command Line Tools de Xcode, no Xcode completo.

```bash
./build.sh          # arma dist.noindex/Notae.app
./build.sh dmg      # además arma dist.noindex/Notae.dmg para regalar
ICONO=oscuro ./build.sh   # variantes: verde | oscuro | claro | contorno
```

## Estructura

```
Sources/Notae/
  NotaeApp.swift        entrada, ícono de la barra de menú
  Coordinador.swift   une todo: tecla → micrófono → texto → limpieza → pegado
  Dictado.swift       audio y reconocimiento de voz local
  Limpieza.swift      corrección con el modelo de Apple + reglas rápidas
  Atajo.swift         monitor de la tecla en todo el sistema
  Pegado.swift        entrega del texto a la app donde estabas
  Hud.swift           la píldora flotante
  Marca.swift         colores, tipografía y símbolo de nosecomousarlaia
  Ajustes.swift       preferencias
  Vista*.swift        bienvenida y ajustes
Herramientas/icono.swift   dibuja el ícono desde el símbolo de la marca
Recursos/Fonts/            Instrument Sans (SIL OFL)
```

## Grabador de reuniones

Captura el audio del sistema con ScreenCaptureKit (pide permiso de grabación de
pantalla, aunque no se toma ninguna imagen) y el micrófono en el mismo stream.
Las dos fuentes se mezclan y se transcriben en vivo, así que al terminar el
texto ya está.

Cuatro trampas que costaron encontrar, todas silenciosas (no había error, solo
no salía transcripción):

1. **El audio de ScreenCaptureKit se lee con `withAudioBufferList`.** Con
   `CMSampleBufferCopyPCMDataIntoAudioBufferList` fallaba el 100% de los
   paquetes.
2. **El `AVAudioFormat` se arma desde la descripción real de la muestra**
   (`AVAudioFormat(streamDescription:)`), no asumiendo si viene entrelazado.
3. **El conversor tiene que ser persistente, uno por fuente.** Creando uno por
   paquete, como además cambia de 48 kHz a 16 kHz, devuelve cero muestras.
4. **El motor de voz pide enteros, no coma flotante.** La mezcla se hace en un
   formato flotante aparte y se convierte al final; si no, `floatChannelData`
   es nulo y no hay nada que sumar.

El mezclador entrega por tiempo y rellena con silencio la fuente que falte: si
espera a que las dos vayan parejas, una reunión donde solo habla el otro no
entrega nada nunca.

## Notas de implementación

- **El entitlement `com.apple.security.device.audio-input` es obligatorio.** Con
  hardened runtime y sin él, macOS niega el micrófono sin mostrar el diálogo.
- **Firma con certificado de desarrollador para el uso propio.** Con firma
  ad-hoc, la identidad de la app cambia en cada compilación y macOS revoca el
  permiso de accesibilidad cada vez, sin avisar: la tecla simplemente deja de
  responder. `build.sh` usa el certificado «Apple Development» del llavero si
  existe, y así la identidad queda estable. Para repartir se fuerza ad-hoc con
  `ADHOC=1 ./build.sh dmg`.
- **Los atajos de voz se aplican antes de la limpieza con IA**, para que el
  modelo vea el correo o el enlace ya escritos y no intente corregirlos. Además
  las instrucciones le prohíben tocar correos, enlaces, teléfonos y usuarios.
- **Sin firma de desarrollador ($99/año) macOS bloquea la app la primera vez.**
  Las instrucciones para el usuario están en `INSTALAR.txt`. Si algún día se
  paga la cuenta, `notarytool` ya está disponible en las Command Line Tools.
- El monitor de teclas solo observa, nunca bloquea eventos, y espera 180 ms
  antes de arrancar para no dispararse cuando la tecla es parte de otro atajo.
- Los colores, la tipografía y el símbolo están todos dentro de `Marca.swift`.
  No hace falta nada externo para compilar.
- Si quieres cambiarla a tu gusto, empieza por `MODIFICALA.md`.
