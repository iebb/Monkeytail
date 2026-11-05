#!/bin/bash
# App Store screenshots from demo data: 20 scenes each for iPhone 6.9", iPad 13" and Mac (2880 × 1800).
# Usage: Scripts/screenshots.sh [iphone|ipad|mac ...]   Output: build/screenshots/<platform>/NN-name.png
set -euo pipefail
cd "$(dirname "$0")/.."
platforms=("${@:-iphone ipad mac}"); platforms=(${platforms[@]})
default_scenes="01-workspace 02-tree 03-headers 04-tests 05-console 06-body 07-params 08-auth 09-scripts 10-docs 11-graphql 12-environments 13-import 14-runner 15-code 16-curl 17-history 18-settings 19-theme 20-dark"; scenes=(${SCENES:-$default_scenes})
out=build/screenshots; data=build/screenshots-derived; bundle=co.kitta.monkeytail

simulator() { # name, device type
  local id; id=$(xcrun simctl list devices available | grep -F "$1 (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
  [ -n "$id" ] || id=$(xcrun simctl create "$1" "$2")
  xcrun simctl boot "$id" 2>/dev/null || true; xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100
  echo "$id"
}
capture_ios() { # platform, simulator name, device type
  local id app; id=$(simulator "$2" "$3")
  xcodebuild -project Monkeytail.xcodeproj -scheme Monkeytail -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$data" build CODE_SIGNING_ALLOWED=NO -quiet
  app=$(find "$data/Build/Products" -maxdepth 2 -name Monkeytail.app -path "*iphonesimulator*" | head -1)
  xcrun simctl install "$id" "$app"; mkdir -p "$out/$1"
  for scene in "${scenes[@]}"; do
    xcrun simctl terminate "$id" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$id" "$bundle" --screenshot "$scene" -AppleLanguages "(en)" -AppleLocale en_US >/dev/null
    [ "$scene" = 14-runner ] && sleep 4; sleep 5; xcrun simctl io "$id" screenshot "$out/$1/$scene.png" >/dev/null 2>&1; echo "$1 $scene"
  done
  xcrun simctl terminate "$id" "$bundle" 2>/dev/null || true; xcrun simctl status_bar "$id" clear
}
capture_mac() {
  xcodebuild -project Monkeytail.xcodeproj -scheme MonkeytailMac -destination 'platform=macOS' -derivedDataPath "$data" build CODE_SIGN_IDENTITY=- -quiet
  swiftc -O Scripts/window_id.swift -o "$data/window_id"
  local app="$data/Build/Products/Debug/Monkeytail.app"; mkdir -p "$out/mac"
  for scene in "${scenes[@]}"; do
    pkill -x Monkeytail 2>/dev/null || true; sleep 1
    open -n "$app" --args --screenshot "$scene" -macWorkspaceLayout sideBySide -AppleLanguages "(en)" -AppleLocale en_US
    [ "$scene" = 14-runner ] && sleep 4; sleep 5.5; screencapture -x -o -l "$("$data/window_id" Monkeytail)" "$out/mac/$scene.png"; echo "mac $scene"
  done
  pkill -x Monkeytail 2>/dev/null || true
}
for platform in "${platforms[@]}"; do
  case "$platform" in
    iphone) capture_ios iphone "Monkeytail Screenshots iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max ;;
    ipad) capture_ios ipad "Monkeytail Screenshots iPad" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB ;;
    mac) capture_mac ;;
  esac
done
