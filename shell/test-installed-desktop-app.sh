#!/bin/bash
# Verify that the installed macOS desktop bundle is signed, launchable, and healthy.

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin${PATH:+:$PATH}"

APP_NAME="Cotor Desktop"
BUNDLE_NAME="$APP_NAME.app"
HEALTH_URL="${COTOR_DESKTOP_HEALTH_URL:-http://127.0.0.1:8787/health}"
TIMEOUT_SECONDS="${COTOR_DESKTOP_SMOKE_TIMEOUT_SECONDS:-45}"

if [[ -n "${COTOR_DESKTOP_APP_PATH:-}" ]]; then
    APP_PATH="$COTOR_DESKTOP_APP_PATH"
elif [[ -d "/Applications/$BUNDLE_NAME" ]]; then
    APP_PATH="/Applications/$BUNDLE_NAME"
elif [[ -d "$HOME/Applications/$BUNDLE_NAME" ]]; then
    APP_PATH="$HOME/Applications/$BUNDLE_NAME"
else
    echo "Missing installed Cotor Desktop bundle."
    echo "Checked: /Applications/$BUNDLE_NAME and $HOME/Applications/$BUNDLE_NAME"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Installed bundle does not exist: $APP_PATH"
    exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"

echo "Verifying installed Cotor Desktop bundle"
echo "  App:    $APP_PATH"
echo "  Health: $HEALTH_URL"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ -f "$INFO_PLIST" ]]; then
    echo "  Executable: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
    echo "  Version:    $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
    echo "  Build:      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)"
fi

if [[ "${COTOR_DESKTOP_SKIP_LAUNCH:-0}" != "1" ]]; then
    if [[ "${COTOR_DESKTOP_SKIP_QUIT:-0}" != "1" ]]; then
        osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
        sleep 1
    fi
    open "$APP_PATH"
else
    echo "Skipping app launch because COTOR_DESKTOP_SKIP_LAUNCH=1."
fi

deadline=$((SECONDS + TIMEOUT_SECONDS))
last_error=""
while (( SECONDS < deadline )); do
    if body="$(curl -fsS --max-time 2 "$HEALTH_URL" 2>&1)"; then
        echo "Health response: $body"
        if [[ "$body" == *'"ok":true'* || "$body" == *'"status":"ok"'* ]]; then
            echo "Installed Cotor Desktop smoke check passed."
            exit 0
        fi
        last_error="$body"
    else
        last_error="$body"
    fi
    sleep 1
done

echo "Timed out waiting for installed Cotor Desktop health after ${TIMEOUT_SECONDS}s."
if [[ -n "$last_error" ]]; then
    echo "Last health result: $last_error"
fi
exit 1
