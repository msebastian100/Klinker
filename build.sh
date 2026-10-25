#!/bin/bash
# Native Builds: arm64 für die M-Serie, x86_64 für Intel, plus ein Universal-Binary.
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
MIN=13.0
mkdir -p build dist Resources

python3 tools/make_icon.py build/icon-1024.png
rm -rf build/icon.iconset
mkdir -p build/icon.iconset
icon_size() {
  sips -z "$1" "$1" build/icon-1024.png --out "build/icon.iconset/$2" >/dev/null
}
icon_size 16 icon_16x16.png
icon_size 32 icon_16x16@2x.png
icon_size 32 icon_32x32.png
icon_size 64 icon_32x32@2x.png
icon_size 128 icon_128x128.png
icon_size 256 icon_128x128@2x.png
icon_size 256 icon_256x256.png
icon_size 512 icon_256x256@2x.png
icon_size 512 icon_512x512.png
icon_size 1024 icon_512x512@2x.png
iconutil -c icns build/icon.iconset -o Resources/AppIcon.icns

SRC=(Sources/Sim.swift Sources/Campaign.swift Sources/Roster.swift Sources/Audio.swift Sources/Scene.swift Sources/App.swift)
FLAGS=(
  -O -whole-module-optimization -swift-version 5
  -sdk "$SDK"
  -framework AppKit -framework SpriteKit -framework AVFoundation -framework GameController
  -Xlinker -dead_strip
)

echo "Übersetze arm64 …"
swiftc "${FLAGS[@]}" -target "arm64-apple-macosx${MIN}" -o build/Klinker-arm64 "${SRC[@]}"
echo "Übersetze x86_64 …"
swiftc "${FLAGS[@]}" -target "x86_64-apple-macosx${MIN}" -o build/Klinker-x86_64 "${SRC[@]}"
lipo -create build/Klinker-arm64 build/Klinker-x86_64 -output build/Klinker-universal

bundle() {
  local name="$1" bin="$2" ident="$3"
  local app="dist/${name}.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$bin" "$app/Contents/MacOS/Klinker"
  chmod +x "$app/Contents/MacOS/Klinker"
  sed "s/__BUNDLE_ID__/${ident}/" Info.plist > "$app/Contents/Info.plist"
  cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  codesign --force --sign - "$app" >/dev/null
}

bundle "Klinker (M-Serie)" build/Klinker-arm64 de.klinker.m
bundle "Klinker (Intel)" build/Klinker-x86_64 de.klinker.intel
bundle "Klinker" build/Klinker-universal de.klinker.app

echo "Prüfe die Physik …"
build/Klinker-arm64 --self-test
arch -x86_64 build/Klinker-x86_64 --self-test

echo
lipo -info build/Klinker-universal
file "dist/Klinker (M-Serie).app/Contents/MacOS/Klinker"
file "dist/Klinker (Intel).app/Contents/MacOS/Klinker"
echo "Fertig: dist/"
