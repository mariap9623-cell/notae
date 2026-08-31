# Cámbiala a tu gusto

Notae es tuya. Esto es el código completo, el mismo con el que se hizo la app
que instalaste. Si algo no te sirve como está, lo cambias.

No necesitas saber programar. Yo tampoco sé. La hice hablando con una IA y esta
guía es para que hagas lo mismo.

---

## Lo que necesitas

1. **Un Mac con macOS 26.** Sin eso no compila: la app usa el motor de voz y
   los modelos que trae el sistema.
2. **Las herramientas de Xcode.** Se instalan solas con este comando en la app
   Terminal:

   ```
   xcode-select --install
   ```

3. **Una IA que pueda leer y escribir archivos.** Yo uso Claude Code. Cualquiera
   que trabaje sobre una carpeta sirve.

---

## Probar que compila, antes de cambiar nada

Abre Terminal, entra a esta carpeta y corre:

```
./build.sh
```

Si al final dice `Listo: dist.noindex/Notae.app`, ya está: esa es tu app. Arrástrala a
Aplicaciones y ábrela.

Hazlo **antes** de tocar nada. Así, si algo se rompe después, sabes que fuiste
tú y no tu computador.

---

## Dónde está cada cosa

Todo el código vive en `Sources/Notae/`. Los archivos que probablemente quieras
tocar son los primeros:

| Archivo | Qué hace |
|---|---|
| `Ajustes.swift` | Todas las preferencias y sus valores de fábrica |
| `VistaAjustes.swift` | La ventana de ajustes que ves |
| `Limpieza.swift` | Las instrucciones que recibe la IA para arreglar tu texto |
| `Hud.swift` | La barrita de abajo y sus botones |
| `Marca.swift` | Colores y tipografía |
| `Dictado.swift` | El micrófono y el motor de voz |
| `Coordinador.swift` | Une todo: tecla, micrófono, texto, pegado |
| `Reunion.swift` | Grabar reuniones (audio del sistema más tu micrófono) |
| `Portapapeles.swift` | El historial de lo que copias |

Y hay un archivo que te va a salvar: **`~/Library/Logs/Notae.log`**. Ahí la app
cuenta lo que le pasa. Si algo deja de funcionar, ábrelo y mándaselo a la IA.
Casi todos los errores de esta app se resolvieron leyendo ese archivo.

---

## El prompt

Copia esto, pégaselo a tu IA dentro de la carpeta del proyecto, y cambia la
última línea por lo que quieras.

```
Este es el código de Notae, una app de dictado para macOS 26 escrita en
SwiftUI. Compila con ./build.sh y el resultado queda en dist.noindex/Notae.app.

Antes de cambiar nada:
- Lee Sources/Notae/Coordinador.swift para entender cómo se conecta todo.
- El código y los comentarios están en español. Escribe igual: nombres en
  español, comentarios que expliquen por qué se hizo así, no qué hace la línea.
- No agregues librerías de terceros. Todo tiene que seguir funcionando sin
  internet y sin cuentas.

Cuando termines un cambio:
- Corre ./build.sh y confirma que compila.
- Si algo no funciona al usarla, revisa ~/Library/Logs/Notae.log antes de
  adivinar. Si te falta información ahí, agrega una línea de registro con
  Registro.di(...) y vuelve a probar.

Lo que quiero cambiar: [ESCRIBE AQUÍ LO QUE QUIERES]
```

---

## Ideas por si no sabes qué pedirle

- Que la tecla sea otra, o que se active con doble toque.
- Que el estilo de limpieza cambie según la app donde estés escribiendo.
- Que al terminar una reunión te mande el acta por correo.
- Que la barrita se esconda cuando estás en pantalla completa.
- Otro idioma en la interfaz.
- Otros colores, otra tipografía, otro nombre. Si la vas a compartir con
  alguien, mira lo que dice `LICENCIA.txt` sobre esto.

---

## Lo único que te pido

Está en `LICENCIA.txt`, pero en corto: úsala, cámbiala, regálala. No la
vendas y no la publiques como si fuera tuya.

Hecha por @mariapaula_rayo · nosecomousarlaia.com
