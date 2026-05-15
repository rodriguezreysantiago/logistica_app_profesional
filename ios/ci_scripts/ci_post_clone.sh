#!/bin/sh

# Xcode Cloud post-clone hook para proyectos Flutter.
#
# Apple corre este script automaticamente despues de clonar el repo
# en su Mac runner (Apple Silicon), ANTES de iniciar el build de Xcode.
#
# Lo que hacemos aca:
#  1. Instalar Flutter (clone del SDK estable).
#  2. Symlink a /usr/local/bin/flutter para que xcodebuild lo encuentre
#     en sus build phases (el PATH del shell no se propaga).
#  3. flutter pub get (instala deps Dart + genera Generated.xcconfig).
#  4. flutter precache --ios (baja el engine iOS).
#  5. cd ios && pod install (instala los Pods de Cocoapods).
#
# Path estandar Apple: ios/ci_scripts/ci_post_clone.sh (al lado del Xcode workspace).

set -e

echo "===== Xcode Cloud post-clone (Flutter setup) ====="

# 1. Instalar Flutter en HOME (el unico path persistente entre passes)
echo "==> Clonando Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

echo "==> Flutter version:"
flutter --version

# 2. Symlink global para que xcodebuild encuentre flutter en su build phase
#    El shell de xcodebuild NO hereda nuestro PATH, asi que necesitamos un
#    symlink en una ubicacion estandar del sistema. /usr/local/bin esta en
#    el PATH default de macOS.
echo "==> Creando symlink global a /usr/local/bin/flutter..."
mkdir -p /usr/local/bin
ln -sf "$HOME/flutter/bin/flutter" /usr/local/bin/flutter
ln -sf "$HOME/flutter/bin/dart" /usr/local/bin/dart
which flutter
flutter --version

# 2b. Instalar flutterfire CLI (lo necesita el Build Phase
# "FlutterFire: flutterfire upload-crashlytics-symbols" del pbxproj
# para subir los dSYMs a Firebase Crashlytics. Sin esto, el archive
# falla con "flutterfire: command not found".)
echo "==> Instalando flutterfire CLI..."
dart pub global activate flutterfire_cli
export PATH="$HOME/.pub-cache/bin:$PATH"
ln -sf "$HOME/.pub-cache/bin/flutterfire" /usr/local/bin/flutterfire
which flutterfire
flutterfire --version

# 3. Subir a la raiz del repo (Xcode Cloud nos deja en ios/)
echo "==> Yendo a la raiz del repo..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
pwd

# 4. flutter pub get (esto crea ios/Flutter/Generated.xcconfig, necesario para Xcode)
echo "==> flutter pub get..."
flutter pub get

# 5. Pre-cachear el engine iOS para que el build sea mas rapido
echo "==> flutter precache --ios..."
flutter precache --ios

# 6. CocoaPods (workaround UTF-8 por si las moscas)
echo "==> pod install..."
cd ios
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
cd ..

# 7. Verificar Generated.xcconfig tenga FLUTTER_ROOT correcto
echo "==> Generated.xcconfig:"
cat ios/Flutter/Generated.xcconfig | grep -E "FLUTTER_ROOT|FLUTTER_APPLICATION_PATH"

# 8. Manual Signing setup (opcional — solo si las env vars estan definidas)
#
# Workaround para cuentas Apple Developer recien aprobadas donde Apple Cloud
# no puede comunicarse con el portal Apple para generar profiles automatica-
# mente ("Communication with Apple failed: No profiles for X were found").
#
# Si las 3 env vars estan setadas, importamos el cert + profile pre-generados
# y dejamos que xcodebuild use Manual Signing.
#
# Setup en Xcode Cloud (App Store Connect -> tu app -> Xcode Cloud ->
# workflow -> Edit -> Custom Environment Variables):
#   - IOS_DIST_CERT_P12_BASE64       (Secret) — base64 del .p12 exportado del Keychain
#   - IOS_DIST_CERT_P12_PASSWORD     (Secret) — password con que se exporto el .p12
#   - IOS_DIST_PROFILE_BASE64        (Secret) — base64 del .mobileprovision bajado del portal Apple
if [ -n "$IOS_DIST_CERT_P12_BASE64" ] && [ -n "$IOS_DIST_CERT_P12_PASSWORD" ] && [ -n "$IOS_DIST_PROFILE_BASE64" ]; then
    echo "==> Manual Signing detectado: importando cert + profile..."

    # Crear keychain temporal solo para este build
    KEYCHAIN_PATH="$HOME/build.keychain"
    KEYCHAIN_PASSWORD="ci-temp-$(date +%s)"

    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security default-keychain -s "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -t 3600 -u "$KEYCHAIN_PATH"

    # Decodear .p12 e importar
    echo "$IOS_DIST_CERT_P12_BASE64" | base64 --decode > "$HOME/cert.p12"
    security import "$HOME/cert.p12" \
        -P "$IOS_DIST_CERT_P12_PASSWORD" \
        -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
    rm "$HOME/cert.p12"

    # Permitir que codesign acceda al cert sin password prompt
    security set-key-partition-list -S apple-tool:,apple: \
        -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

    # Instalar el provisioning profile
    PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILES_DIR"
    echo "$IOS_DIST_PROFILE_BASE64" | base64 --decode > \
        "$PROFILES_DIR/Coopertrans_Movil_App_Store.mobileprovision"

    echo "==> Manual Signing OK: cert importado + profile instalado."
else
    echo "==> Manual Signing skip (env vars no definidas — usando Auto Signing)."
fi

echo "===== Setup Flutter completado, Xcode Cloud puede arrancar el build ====="
