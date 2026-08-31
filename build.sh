#!/bin/bash
# Compila Notae, arma el .app y (opcional) el .dmg para regalar.
#   ./build.sh          -> compila y arma Notae.app en dist.noindex/
#   ./build.sh dmg      -> además genera dist.noindex/Notae.dmg
set -euo pipefail

cd "$(dirname "$0")"

NOMBRE="Notae"
BUNDLE_ID="com.nosecomousarlaia.notae"
# Variante del ícono: verde | oscuro | claro | contorno
ICONO="${ICONO:-oscuro}"
VERSION="1.0"
BUILD="1"
DIST="dist.noindex"
APP="$DIST/$NOMBRE.app"

echo "==> Compilando (release, universal)"
if ! swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  echo "    universal no disponible, compilando solo arm64"
  swift build -c release --arch arm64
  BIN=$(swift build -c release --arch arm64 --show-bin-path)/$NOMBRE
else
  BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$NOMBRE
fi

echo "==> Armando el bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NOMBRE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NOMBRE</string>
  <key>CFBundleDisplayName</key><string>$NOMBRE</string>
  <key>CFBundleExecutable</key><string>$NOMBRE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleiconFile</key><string>AppIcon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 Maria Paula Moreno · nosecomousarlaia. Código bajo licencia MIT.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Notae usa el micrófono para convertir lo que dices en texto. El audio se procesa dentro de tu Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Notae usa el reconocimiento de voz local de macOS para escribir lo que dictas.</string>
</dict>
</plist>
PLIST

echo "==> Copiando las fuentes de marca (Instrument Sans, OFL)"
mkdir -p "$APP/Contents/Resources/Fonts"
cp Recursos/Fonts/*.ttf Recursos/Fonts/OFL-InstrumentSans.txt "$APP/Contents/Resources/Fonts/"
cp LICENCIA.txt "$APP/Contents/Resources/LICENCIA.txt"

echo "==> Generando ícono ($ICONO)"
TMPICON=$(mktemp -d)
swift Herramientas/icono.swift "$TMPICON/base.png" "$ICONO" >/dev/null
ICONSET="$TMPICON/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
  sips -z $size $size "$TMPICON/base.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  doble=$((size * 2))
  sips -z $doble $doble "$TMPICON/base.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMPICON"

echo "==> Firmando"
# El entitlement de micrófono es obligatorio con hardened runtime: sin él,
# macOS niega el micrófono sin siquiera preguntar.
#
# Con firma ad-hoc, la identidad de la app cambia en cada compilación y macOS
# revoca los permisos de accesibilidad cada vez. Si hay un certificado de
# desarrollador en el llavero, se usa ese: la identidad queda estable y los
# permisos sobreviven a las recompilaciones.
IDENTIDAD=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$IDENTIDAD" ] && [ "${ADHOC:-}" != "1" ]; then
  echo "    firmando con: $IDENTIDAD"
  codesign --force --deep --sign "$IDENTIDAD" --options runtime \
    --entitlements Recursos/Notae.entitlements "$APP"
else
  echo "    firmando ad-hoc (para repartir)"
  codesign --force --deep --sign - --options runtime \
    --entitlements Recursos/Notae.entitlements "$APP"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1

echo "==> Listo: $APP"

if [ "${1:-}" = "dmg" ]; then
  echo "==> Armando el .dmg"
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Aplicaciones"
  cp INSTALAR.txt "$STAGE/LÉEME PRIMERO.txt" 2>/dev/null || true
  cp LICENCIA.txt "$STAGE/LICENCIA.txt" 2>/dev/null || true
  rm -f "$DIST/$NOMBRE.dmg"
  hdiutil create -volname "$NOMBRE" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NOMBRE.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "==> Listo: $DIST/$NOMBRE.dmg"
fi
