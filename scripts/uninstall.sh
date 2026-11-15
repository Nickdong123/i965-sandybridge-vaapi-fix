#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/.local/share/applications"

echo "=== Uninstalling i965 Sandy Bridge VA-API Fix ==="

rm -f "$APP_DIR/microsoft-edge-vaapi-patched.desktop"
rm -f "$APP_DIR/google-chrome-vaapi-patched.desktop"
rm -f "$APP_DIR/chromium-vaapi-patched.desktop"
rm -f "$APP_DIR/brave-browser-vaapi-patched.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" 2>/dev/null || true
fi

echo "--> Removed desktop launchers from $APP_DIR"
echo "=== Uninstallation Complete! (System completely clean) ==="
