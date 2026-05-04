#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Cotor Desktop"
APP_PROCESS="CotorDesktopBinary"
LAUNCHER_PROCESS="CotorDesktopLauncher"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/cotor-desktop-run"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

export COTOR_PROJECT_ROOT="$ROOT_DIR"
export COTOR_DESKTOP_BUILD_OUTPUT_ROOT="$DIST_DIR"

stop_running_app() {
  /usr/bin/osascript -e 'tell application id "com.cotor.desktop" to quit' >/dev/null 2>&1 || true
  sleep 0.8
  pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true
  pkill -x "$LAUNCHER_PROCESS" >/dev/null 2>&1 || true
  pkill -f "Cotor Desktop.app/Contents/MacOS/$APP_PROCESS" >/dev/null 2>&1 || true
  pkill -f "Cotor Desktop.app/Contents/MacOS/$LAUNCHER_PROCESS" >/dev/null 2>&1 || true
}

build_bundle() {
  "$ROOT_DIR/shell/build-desktop-app-bundle.sh"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_running() {
  for _ in {1..30}; do
    if pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_PROCESS" >/dev/null 2>&1 ||
      pgrep -f "$APP_BUNDLE/Contents/MacOS/$LAUNCHER_PROCESS" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.3
  done
  echo "Cotor Desktop did not stay running after launch." >&2
  return 1
}

case "$MODE" in
  run)
    stop_running_app
    build_bundle
    open_app
    ;;
  --verify|verify)
    stop_running_app
    build_bundle
    open_app
    verify_running
    ;;
  --debug|debug)
    stop_running_app
    build_bundle
    lldb -- "$APP_BUNDLE/Contents/MacOS/CotorDesktopLauncher"
    ;;
  --logs|logs)
    stop_running_app
    build_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_PROCESS\" OR process == \"$LAUNCHER_PROCESS\""
    ;;
  --telemetry|telemetry)
    stop_running_app
    build_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_PROCESS\" OR process == \"$LAUNCHER_PROCESS\""
    ;;
  *)
    echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac
