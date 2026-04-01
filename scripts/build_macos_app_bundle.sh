#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <executable-path> <output-app-path> [version]" >&2
  exit 1
fi

executable_path="$1"
app_path="$2"
version="${3:-0.1.0}"
contents_path="${app_path}/Contents"
macos_path="${contents_path}/MacOS"
resources_path="${contents_path}/Resources"

rm -rf "$app_path"
mkdir -p "$macos_path" "$resources_path"

cp "$executable_path" "${macos_path}/filippod"
chmod 755 "${macos_path}/filippod"

cat > "${contents_path}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>filippod</string>
  <key>CFBundleIdentifier</key>
  <string>com.lucamaraschi.filippo</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Filippo</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST
