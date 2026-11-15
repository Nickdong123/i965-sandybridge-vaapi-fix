#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$REPO_ROOT/out"
DRIVER_SO="$OUT_DIR/i965_drv_video.so"
APP_DIR="$HOME/.local/share/applications"

echo "=== Installing i965 Sandy Bridge VA-API Fix ==="

if [ ! -f "$DRIVER_SO" ]; then
    echo "Compiled driver not found at $DRIVER_SO"
    echo "Running build script first..."
    "$SCRIPT_DIR/build.sh"
fi

mkdir -p "$APP_DIR"

install_launcher() {
    local browser_name="$1"
    local exec_cmd="$2"
    local icon_name="$3"
    local desktop_file="$APP_DIR/${browser_name}-vaapi-patched.desktop"

    echo "--> Installing desktop launcher: $desktop_file"
    cat << DESK > "$desktop_file"
[Desktop Entry]
Version=1.0
Name=${browser_name^} (VA-API Patched)
GenericName=Web Browser
Comment=Access the Internet with VA-API Hardware Video Decoding (Intel Sandy Bridge)
Exec=env LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH=${OUT_DIR} ${exec_cmd} --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy %U
Terminal=false
Icon=${icon_name}
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=env LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH=${OUT_DIR} ${exec_cmd} --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy

[Desktop Action new-private-window]
Name=New Private Window
Exec=env LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH=${OUT_DIR} ${exec_cmd} --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --inprivate
DESK
    chmod +x "$desktop_file"
}

# 1. Microsoft Edge
if [ -x "/opt/microsoft/msedge/msedge" ]; then
    install_launcher "microsoft-edge" "/opt/microsoft/msedge/msedge" "microsoft-edge"
fi

# 2. Google Chrome
if [ -x "/opt/google/chrome/google-chrome" ]; then
    install_launcher "google-chrome" "/opt/google/chrome/google-chrome" "google-chrome"
fi

# 3. Chromium
if command -v chromium >/dev/null 2>&1; then
    install_launcher "chromium" "$(command -v chromium)" "chromium"
fi

# 4. Brave
if command -v brave-browser >/dev/null 2>&1; then
    install_launcher "brave-browser" "$(command -v brave-browser)" "brave-browser"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" 2>/dev/null || true
fi

echo ""
echo "=== Installation Complete! ==="
echo "Launchers have been added to your application menu:"
echo "  - Microsoft Edge (VA-API Patched)"
echo ""
echo "You can launch directly from your application launcher or run:"
echo "  env LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH=$OUT_DIR /opt/microsoft/msedge/msedge --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy"
