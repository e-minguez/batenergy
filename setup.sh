#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/usr/local/bin"
SYSTEMD_SLEEP_DIR="/etc/systemd/system-sleep"
# When run via sudo, detect the real user (not root)
if [[ $EUID -eq 0 && -n "$SUDO_USER" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(whoami)"
fi
USER_SYSTEMD_DIR="/home/${REAL_USER}/.config/systemd/user"
USER_ID="$(id -u "${REAL_USER}")"

usage() {
    echo "Usage: $0 [install|uninstall|status]"
    echo ""
    echo "  install   - Install batenergy (requires root for system-wide files)"
    echo "  uninstall - Remove all batenergy files"
    echo "  status    - Check if everything is set up correctly"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: install/uninstall requires root (use sudo)"
        exit 1
    fi
}

install() {
    check_root

    echo "Installing batenergy..."

    # Install the main script
    cp "$SCRIPT_DIR/batenergy.sh" "$INSTALL_DIR/batenergy.sh"
    chmod 755 "$INSTALL_DIR/batenergy.sh"
    echo "  Installed: $INSTALL_DIR/batenergy.sh"

    # Install systemd-sleep hook
    mkdir -p "$SYSTEMD_SLEEP_DIR"
    ln -sf "$INSTALL_DIR/batenergy.sh" "$SYSTEMD_SLEEP_DIR/batenergy.sh"
    echo "  Installed: $SYSTEMD_SLEEP_DIR/batenergy.sh -> $INSTALL_DIR/batenergy.sh"

    # Install user-level systemd units
    mkdir -p "$USER_SYSTEMD_DIR"
    cp "$SCRIPT_DIR/batenergy-notify.path" "$USER_SYSTEMD_DIR/"
    cp "$SCRIPT_DIR/batenergy-notify.service" "$USER_SYSTEMD_DIR/"
    chown "${REAL_USER}:${REAL_USER}" "$USER_SYSTEMD_DIR/batenergy-notify.path" "$USER_SYSTEMD_DIR/batenergy-notify.service"
    echo "  Installed: $USER_SYSTEMD_DIR/batenergy-notify.{path,service}"

    # Enable and start the path watcher (run as the real user)
    sudo -u "${REAL_USER}" systemctl --user daemon-reload
    sudo -u "${REAL_USER}" systemctl --user enable --now batenergy-notify.path
    echo "  Enabled: batenergy-notify.path"

    echo ""
    echo "Installation complete."
    echo ""
    echo "Before first use, edit $INSTALL_DIR/batenergy.sh and set:"
    echo "  USER=\"<your-username>\""
    echo "  USERID=$(id -u)"
    echo ""
    echo "Then run: sudo batenergy.sh pre suspend"
}

uninstall() {
    check_root

    echo "Removing batenergy..."

    rm -f "$INSTALL_DIR/batenergy.sh"
    echo "  Removed: $INSTALL_DIR/batenergy.sh"

    rm -f "$SYSTEMD_SLEEP_DIR/batenergy.sh"
    echo "  Removed: $SYSTEMD_SLEEP_DIR/batenergy.sh"

    sudo -u "${REAL_USER}" systemctl --user disable --now batenergy-notify.path 2>/dev/null || true
    rm -f "$USER_SYSTEMD_DIR/batenergy-notify.path"
    rm -f "$USER_SYSTEMD_DIR/batenergy-notify.service"
    echo "  Removed: $USER_SYSTEMD_DIR/batenergy-notify.{path,service}"

    sudo -u "${REAL_USER}" systemctl --user daemon-reload
    echo "  Reloaded user systemd"

    echo ""
    echo "Uninstall complete."
}

status() {
    echo "batenergy status:"
    echo ""

    # Check main script
    if [[ -x "$INSTALL_DIR/batenergy.sh" ]]; then
        echo "  [OK] Script: $INSTALL_DIR/batenergy.sh"
    else
        echo "  [ ] Script: $INSTALL_DIR/batenergy.sh (not installed)"
    fi

    # Check systemd-sleep hook
    if [[ -L "$SYSTEMD_SLEEP_DIR/batenergy.sh" ]]; then
        echo "  [OK] Sleep hook: $SYSTEMD_SLEEP_DIR/batenergy.sh"
    elif [[ -f "$SYSTEMD_SLEEP_DIR/batenergy.sh" ]]; then
        echo "  [OK] Sleep hook: $SYSTEMD_SLEEP_DIR/batenergy.sh (not symlink)"
    else
        echo "  [ ] Sleep hook: $SYSTEMD_SLEEP_DIR/batenergy.sh (not installed)"
    fi

    # Check user systemd units
    if [[ -f "$USER_SYSTEMD_DIR/batenergy-notify.path" ]]; then
        local path_status
        path_status=$(sudo -u "${REAL_USER}" systemctl --user is-active batenergy-notify.path 2>/dev/null || echo "unknown")
        echo "  [OK] Path unit: batenergy-notify.path ($path_status)"
    else
        echo "  [ ] Path unit: batenergy-notify.path (not installed)"
    fi

    if [[ -f "$USER_SYSTEMD_DIR/batenergy-notify.service" ]]; then
        local svc_status
        svc_status=$(sudo -u "${REAL_USER}" systemctl --user is-active batenergy-notify.service 2>/dev/null || echo "unknown")
        echo "  [OK] Service: batenergy-notify.service ($svc_status)"
    else
        echo "  [ ] Service: batenergy-notify.service (not installed)"
    fi

    # Check battery
    local bat_path="/sys/class/power_supply/BAT*"
    if ls $bat_path &>/dev/null; then
        echo "  [OK] Battery detected: $(ls -d $bat_path | head -1)"
    else
        echo "  [!] No battery detected"
    fi

    # Check notify-send
    if command -v notify-send &>/dev/null; then
        echo "  [OK] notify-send available"
    else
        echo "  [!] notify-send not found (notifications won't work)"
    fi

    echo ""
}

[[ $# -eq 0 ]] && usage
case "$1" in
    install)   install ;;
    uninstall) uninstall ;;
    status)    status ;;
    *)         usage ;;
esac
