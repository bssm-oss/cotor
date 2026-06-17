#!/bin/bash
# Build the native macOS desktop app bundle into a staging directory.

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin${PATH:+:$PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${COTOR_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$SCRIPT_DIR/resolve-gradle-java.sh"
PACKAGE_ROOT="$PROJECT_ROOT/macos"
PACKAGING_ROOT="$PACKAGE_ROOT/Packaging"
BRANDING_ROOT="$PACKAGE_ROOT/Branding"
TMPDIR_VALUE="${TMPDIR:-/tmp}"
STAGING_ROOT="${COTOR_DESKTOP_BUILD_OUTPUT_ROOT:-${TMPDIR_VALUE%/}/cotor-desktop-build}"
APP_NAME="Cotor Desktop"
BUNDLE_NAME="$APP_NAME.app"
STAGING_APP="$STAGING_ROOT/$BUNDLE_NAME"
SWIFT_HOME="$STAGING_ROOT/swift-home"
SWIFT_CACHE="$STAGING_ROOT/swift-cache"
SWIFT_MODULE_CACHE="$PACKAGE_ROOT/.build/module-cache"
CLANG_MODULE_CACHE="$PACKAGE_ROOT/.build/clang-module-cache"
VERSION="$(grep -E '^version = ' "$PROJECT_ROOT/build.gradle.kts" | head -n 1 | cut -d '"' -f 2)"
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"

if [[ -z "$VERSION" ]]; then
    VERSION="dev"
fi

refuse_unsafe_staging_root() {
    local candidate="${1%/}"
    local project_root="${PROJECT_ROOT%/}"
    local package_root="${PACKAGE_ROOT%/}"
    local home_root="${HOME%/}"

    if [[ -z "$candidate" || "$candidate" == "/" ]]; then
        echo "Refusing to remove unsafe staging root: '${1}'" >&2
        exit 1
    fi
    if [[ "$candidate" == "$project_root" || "$candidate" == "$package_root" || "$candidate" == "$home_root" ]]; then
        echo "Refusing to remove staging root that points at a source or home directory: '$candidate'" >&2
        exit 1
    fi
}

refuse_unsafe_staging_root "$STAGING_ROOT"
rm -rf "$STAGING_ROOT"
mkdir -p "$STAGING_ROOT"
mkdir -p "$SWIFT_HOME" "$SWIFT_CACHE" "$SWIFT_MODULE_CACHE" "$CLANG_MODULE_CACHE"

find_built_app_binary() {
    find "$PACKAGE_ROOT/.build" -path '*/release/CotorDesktopApp' -type f | head -n 1
}

echo "📦 Building bundled Cotor backend..."
configure_gradle_java
(cd "$PROJECT_ROOT" && ./gradlew shadowJar --no-daemon)

echo "🖥️  Building native macOS shell..."
if ! env \
    HOME="$SWIFT_HOME" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_MODULE_CACHE" \
    CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE" \
    swift build \
    --package-path "$PACKAGE_ROOT" \
    --scratch-path "$PACKAGE_ROOT/.build" \
    --cache-path "$SWIFT_CACHE" \
    --disable-sandbox \
    -c release; then
    APP_BINARY="$(find_built_app_binary)"
    if [[ "${COTOR_ALLOW_STALE_SWIFT_BINARY:-0}" == "1" && -n "$APP_BINARY" && -f "$APP_BINARY" ]]; then
        echo "⚠️  Native macOS shell rebuild failed. Reusing the most recent cached release binary:"
        echo "   $APP_BINARY"
        echo "   This machine's Command Line Tools installation is broken (swift-package/llbuild mismatch)."
    else
        echo "❌ Native macOS shell build failed."
        if [[ -n "$APP_BINARY" && -f "$APP_BINARY" ]]; then
            echo "   A cached release binary exists, but reuse is disabled by default."
            echo "   Set COTOR_ALLOW_STALE_SWIFT_BINARY=1 to opt into stale-binary reuse."
        fi
        exit 1
    fi
fi

APP_BINARY="${APP_BINARY:-$(find_built_app_binary)}"
BACKEND_JAR="$(find "$PROJECT_ROOT/build/libs" -name 'cotor-*-all.jar' -type f | head -n 1)"
RESOURCE_BUNDLES="$(find "$PACKAGE_ROOT/.build" -path '*/release/*.bundle' -type d)"
DESKTOP_RESOURCE_BUNDLE="CotorDesktop_CotorDesktopApp.bundle"
DESKTOP_RESOURCE_BUNDLE_PATH="$(find "$PACKAGE_ROOT/.build" -path "*/release/$DESKTOP_RESOURCE_BUNDLE" -type d | head -n 1)"

if [[ -z "$APP_BINARY" || ! -f "$APP_BINARY" ]]; then
    echo "❌ Could not locate the built CotorDesktopApp binary."
    exit 1
fi

if [[ -z "$BACKEND_JAR" || ! -f "$BACKEND_JAR" ]]; then
    echo "❌ Could not locate the bundled backend jar."
    exit 1
fi

if [[ -z "$DESKTOP_RESOURCE_BUNDLE_PATH" || ! -d "$DESKTOP_RESOURCE_BUNDLE_PATH" ]]; then
    echo "❌ Could not locate the built desktop resource bundle: $DESKTOP_RESOURCE_BUNDLE"
    exit 1
fi

if [[ ! -f "$DESKTOP_RESOURCE_BUNDLE_PATH/Brand/CotorHeaderMark.png" || ! -f "$DESKTOP_RESOURCE_BUNDLE_PATH/Terminal/terminal.html" ]]; then
    echo "❌ Desktop resource bundle is missing required Brand or Terminal assets."
    exit 1
fi

APP_CONTENTS="$STAGING_APP/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BACKEND="$APP_RESOURCES/backend"
ICONSET_DIR="$STAGING_ROOT/AppIcon.iconset"
ICON_PNG="$STAGING_ROOT/AppIcon-1024.png"
ICON_ICNS="$APP_RESOURCES/AppIcon.icns"
ICON_SVG="$BRANDING_ROOT/cotor.svg"
PREBUILT_ICON_PNG="$BRANDING_ROOT/AppIcon-1024.png"
SVG_RENDER_PNG="$STAGING_ROOT/cotor.svg.png"

mkdir -p "$APP_MACOS" "$APP_BACKEND" "$APP_RESOURCES" "$ICONSET_DIR"

prebundle_playwright_if_requested() {
    if [[ "${COTOR_PREBUNDLE_PLAYWRIGHT:-0}" != "1" ]]; then
        return
    fi
    if ! command -v npm >/dev/null 2>&1; then
        echo "❌ COTOR_PREBUNDLE_PLAYWRIGHT=1 requires npm on PATH."
        exit 1
    fi
    local browser_resource_dir="$APP_RESOURCES/browser-skills"
    mkdir -p "$browser_resource_dir"
    echo "🌐 Prebundling Playwright for browser skills..."
    npm install \
        --silent \
        --no-audit \
        --no-fund \
        --prefix "$browser_resource_dir" \
        playwright@1.52.0
}

echo "🎨 Generating app icon..."
if [[ -f "$PREBUILT_ICON_PNG" ]]; then
    cp "$PREBUILT_ICON_PNG" "$ICON_PNG"
elif [[ -f "$ICON_SVG" ]]; then
    qlmanage -t -s 1024 -o "$STAGING_ROOT" "$ICON_SVG" >/dev/null 2>&1

    if [[ ! -f "$SVG_RENDER_PNG" ]]; then
        echo "❌ Failed to rasterize $ICON_SVG via Quick Look."
        exit 1
    fi

    cp "$SVG_RENDER_PNG" "$ICON_PNG"
else
    echo "❌ Could not locate $ICON_SVG."
    exit 1
fi

resize_icon() {
    local pixels="$1"
    local name="$2"
    sips -z "$pixels" "$pixels" "$ICON_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

resize_icon 16 icon_16x16.png
resize_icon 32 icon_16x16@2x.png
resize_icon 32 icon_32x32.png
resize_icon 64 icon_32x32@2x.png
resize_icon 128 icon_128x128.png
resize_icon 256 icon_128x128@2x.png
resize_icon 256 icon_256x256.png
resize_icon 512 icon_256x256@2x.png
resize_icon 512 icon_512x512.png
resize_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"

cp "$APP_BINARY" "$APP_MACOS/CotorDesktopBinary"
chmod +x "$APP_MACOS/CotorDesktopBinary"
cp "$BACKEND_JAR" "$APP_BACKEND/cotor-backend.jar"

if [[ -n "$RESOURCE_BUNDLES" ]]; then
    while IFS= read -r bundle_path; do
        [[ -z "$bundle_path" ]] && continue
        bundle_name="$(basename "$bundle_path")"
        rm -rf "$APP_RESOURCES/$bundle_name"
        cp -R "$bundle_path" "$APP_RESOURCES/"
    done <<< "$RESOURCE_BUNDLES"
fi

prebundle_playwright_if_requested

sed \
    -e "s#__EXECUTABLE__#CotorDesktopBinary#g" \
    -e "s#__VERSION__#$VERSION#g" \
    -e "s#__BUILD__#$BUILD_NUMBER#g" \
    "$PACKAGING_ROOT/Info.plist.template" > "$APP_CONTENTS/Info.plist"

cp "$PACKAGING_ROOT/CotorDesktopLauncher.sh.template" "$APP_MACOS/CotorDesktopLauncher"
chmod +x "$APP_MACOS/CotorDesktopLauncher"

if codesign --force --deep --sign - "$STAGING_APP"; then
    echo "✅ Applied ad-hoc signature to desktop bundle."
else
    echo "⚠️  Ad-hoc codesign failed; bundle was built without a refreshed signature."
fi

echo "✅ Built Cotor Desktop bundle."
echo "   Bundle: $STAGING_APP"
