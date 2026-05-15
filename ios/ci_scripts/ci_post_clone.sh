#!/bin/sh

# Xcode Cloud post-clone hook para proyectos Flutter.
#
# Apple corre este script automaticamente despues de clonar el repo
# en su Mac runner (Apple Silicon), ANTES de iniciar el build de Xcode.
#
# Lo que hacemos aca:
#  1. Instalar Flutter (clone del SDK estable).
#  2. Agregar flutter al PATH para los pasos siguientes.
#  3. flutter pub get (instala deps Dart + genera Generated.xcconfig).
#  4. cd ios && pod install (instala los Pods de Cocoapods).
#  5. flutter precache --ios (baja el engine iOS).
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

# 2. Subir a la raiz del repo (Xcode Cloud nos deja en ios/)
echo "==> Yendo a la raiz del repo..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
pwd

# 3. flutter pub get (esto crea ios/Flutter/Generated.xcconfig, necesario para Xcode)
echo "==> flutter pub get..."
flutter pub get

# 4. Pre-cachear el engine iOS para que el build sea mas rapido
echo "==> flutter precache --ios..."
flutter precache --ios

# 5. CocoaPods (workaround UTF-8 por si las moscas)
echo "==> pod install..."
cd ios
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
cd ..

echo "===== Setup Flutter completado, Xcode Cloud puede arrancar el build ====="
