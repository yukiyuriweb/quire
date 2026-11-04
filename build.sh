#!/bin/sh
# Builds Quire.app into ./build; with --install, also copies it to ~/Applications
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Quire.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Quire "$APP/Contents/MacOS/Quire"

# App icon
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make-icon.swift .build/icon_1024.png
for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) .build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# UI strings are English in code; other languages live in Localization/*.lproj
cp -R Localization/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Quire</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
    <key>CFBundleIdentifier</key><string>local.quire</string>
    <key>CFBundleExecutable</key><string>Quire</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>EPUB</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>org.idpf.epub-container</string></array>
            <key>NSDocumentClass</key><string>Document</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Quick Look extensions: the preview (Space in Finder) and the Finder thumbnail (the cover).
# Built with swiftc rather than SwiftPM, because an .appex starts at _NSExtensionMain, not main.
# They share Zip.swift and Book.swift with the app.
build_extension() {  # <name> <bundle id> <extension point> <principal class> <extra attributes> <sources...>
    NAME=$1 ID=$2 POINT=$3 CLASS=$4 ATTRIBUTES=$5
    shift 5
    EXT="$APP/Contents/PlugIns/$NAME.appex"
    mkdir -p "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
    swiftc -O -parse-as-library -application-extension -module-name "$NAME" \
        -target "$(uname -m)-apple-macos13.0" \
        -Xlinker -e -Xlinker _NSExtensionMain \
        Sources/Quire/Zip.swift Sources/Quire/Book.swift "$@" -o "$EXT/Contents/MacOS/$NAME"
    cp -R Localization/*.lproj "$EXT/Contents/Resources/"
    cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>Quire</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleIdentifier</key><string>$ID</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>$POINT</string>
        <key>NSExtensionPrincipalClass</key><string>$NAME.$CLASS</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLSupportedContentTypes</key><array><string>org.idpf.epub-container</string></array>
            $ATTRIBUTES
        </dict>
    </dict>
</dict>
</plist>
PLIST
    codesign --force --sign - --entitlements Extensions/Extension.entitlements "$EXT"
}
build_extension QuirePreview local.quire.preview com.apple.quicklook.preview PreviewProvider \
    '<key>QLIsDataBasedPreview</key><true/><key>QLSupportsSearchableItems</key><false/>' \
    Extensions/Preview/*.swift
build_extension QuireThumbnail local.quire.thumbnail com.apple.quicklook.thumbnail ThumbnailProvider \
    '<key>QLThumbnailMinimumDimension</key><integer>0</integer>' \
    Extensions/Thumbnail/*.swift

# Sign the app last: its signature covers the already-signed extensions.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$1" = "--install" ]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Quire.app
    cp -R "$APP" ~/Applications/
    echo "Installed ~/Applications/Quire.app"
fi
