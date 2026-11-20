#!/bin/bash
# Baut die Raketenwerft für iOS: Godot exportiert ein Xcode-Projekt, xcodebuild baut es.
#   tools/build_ios.sh sim      -> iPad-Simulator (startet die App dort)
#   tools/build_ios.sh device   -> angestecktes iPad/iPhone (signiert mit Team 5QAM4Z73EV)
#   tools/build_ios.sh testflight          -> App-Store-Archiv (Release) in build/Raketenwerft.xcarchive
#   UPLOAD=1 tools/build_ios.sh testflight -> zusätzlich zu App Store Connect / TestFlight hochladen
#   (Build-Nummer: BUILD=2 tools/build_ios.sh testflight – muss bei jedem Upload größer werden)
#   Ohne Xcode-Konto (z. B. auf GitHub): ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID setzen –
#   dann wird mit dem App-Store-Connect-API-Schlüssel signiert und hochgeladen.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
MODE="${1:-sim}"
mkdir -p build/ios
"$GODOT" --headless --path . --import
if [ "$MODE" = "testflight" ]; then
  if [ -n "${BUILD:-}" ]; then sed -i '' "s/^application\/version=.*/application\/version=\"$BUILD\"/" export_presets.cfg; fi
  "$GODOT" --headless --path . --export-release "iOS" build/ios/Raketenwerft.ipa
else
  "$GODOT" --headless --path . --export-debug "iOS" build/ios/Raketenwerft.ipa
fi
PROJ=$(ls -d build/ios/*.xcodeproj | head -1)
SCHEME=$(basename "$PROJ" .xcodeproj)
if [ "$MODE" = "testflight" ]; then
  AUTH=()
  if [ -n "${ASC_KEY_PATH:-}" ]; then
    AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    # Ohne Zertifikate auf der Maschine: Archiv unsigniert bauen, Xcode signiert beim Export (Cloud-Signierung)
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -destination "generic/platform=iOS" \
      -archivePath build/Raketenwerft.xcarchive DEVELOPMENT_TEAM=5QAM4Z73EV CODE_SIGNING_ALLOWED=NO archive | tail -3
  else
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -destination "generic/platform=iOS" \
      -archivePath build/Raketenwerft.xcarchive -allowProvisioningUpdates DEVELOPMENT_TEAM=5QAM4Z73EV CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" archive | tail -3
  fi
  cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ "${UPLOAD:-}" = "1" ] && echo upload || echo export)</string>
  <key>teamID</key><string>5QAM4Z73EV</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath build/Raketenwerft.xcarchive -exportPath build/appstore \
    -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} | tail -5
  exit 0
fi
if [ "$MODE" = "sim" ]; then
  # Godots offizielle Vorlage hat den Simulator nur für Intel-Macs (x86_64) und nur mit OpenGL.
  # Für Apple-Silicon bauen wir die arm64-Simulator-Bibliothek selbst, mit Metal (echte GPU, 60 fps):
  #   git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git
  #   git apply tools/godot-ios-simulator-metal.patch
  #   scons platform=ios target=template_debug simulator=yes arch=arm64 generate_bundle=no
  # Zwei Metal-Konstanten fehlen im Simulator-SDK -> als optional (-U) linken.
  SIM_LIB="${SIM_LIB:-$HOME/.local/share/godot-src/godot/bin/libgodot.ios.template_debug.arm64.simulator.a}"
  XCF_SIM=$(ls -d build/ios/*.xcframework/ios-arm64_x86_64-simulator | grep -v MoltenVK | head -1)
  [ -f "$SIM_LIB" ] || { echo "arm64-Simulator-Bibliothek fehlt: $SIM_LIB"; exit 1; }
  lipo -thin x86_64 "$XCF_SIM/libgodot.a" -output build/ios/sim_x86.a 2>/dev/null || cp "$XCF_SIM/libgodot.a" build/ios/sim_x86.a
  lipo -create build/ios/sim_x86.a "$SIM_LIB" -output "$XCF_SIM/libgodot.a"
  rm build/ios/sim_x86.a
  SIM="${SIM:-iPad Air 11-inch (M4)}"
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO OTHER_LDFLAGS='$(inherited) -Wl,-U,_MTLIOErrorDomain -Wl,-U,_MTLTensorDomain' build | tail -3
  APP=$(ls -d build/dd/Build/Products/Debug-iphonesimulator/*.app | head -1)
  UDID=$(xcrun simctl list devices available | grep "$SIM (" | head -1 | grep -oE "[0-9A-F-]{36}")
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" at.pfaffenbauer.raketenwerft
else
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -destination "generic/platform=iOS" -derivedDataPath build/dd -allowProvisioningUpdates DEVELOPMENT_TEAM=5QAM4Z73EV CODE_SIGN_STYLE=Automatic build | tail -3
  APP=$(ls -d build/dd/Build/Products/Debug-iphoneos/*.app | head -1)
  DEV=$(xcrun devicectl list devices 2>/dev/null | grep -E "connected|available" | grep -oE "[0-9A-F]{8}-[0-9A-F-]{20,}" | head -1)
  [ -n "$DEV" ] || { echo "Kein Gerät gefunden – iPad/iPhone anstecken und entsperren."; exit 1; }
  xcrun devicectl device install app --device "$DEV" "$APP"
  xcrun devicectl device process launch --device "$DEV" at.pfaffenbauer.raketenwerft || true
fi
