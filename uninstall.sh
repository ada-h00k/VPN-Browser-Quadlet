#!/usr/bin/env bash
# vpn-browser-quadlet - remove rootless Quadlet definitions and helper.
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only

set -Eeuo pipefail

[[ "$EUID" -ne 0 ]] || { echo 'Do not run as root.' >&2; exit 1; }
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
QUADLET_DIR="$CONFIG_HOME/containers/systemd"
FISH_FUNCTION="$CONFIG_HOME/fish/functions/vpn-browser.fish"

if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user stop mullvad-browser.service gluetun.service >/dev/null 2>&1 || true
fi

rm -f "$QUADLET_DIR/mullvad-browser.container" \
      "$QUADLET_DIR/gluetun.container" \
      "$QUADLET_DIR/mullvad-browser.env" \
      "$QUADLET_DIR/gluetun.env" \
      "$QUADLET_DIR/browser-profile.volume" \
      "$QUADLET_DIR/gluetun-data.volume" \
      "$FISH_FUNCTION"

if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user reset-failed gluetun.service mullvad-browser.service >/dev/null 2>&1 || true
fi

printf 'Quadlet definitions, environment files, and Fish helper removed.\n'
printf 'Persistent Podman volumes are kept by default:\n'
printf '  vpn-browser-profile\n  vpn-browser-gluetun-data\n'
read -r -p 'Delete both persistent volumes and all stored browser/VPN data? [y/N] ' answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    podman volume rm vpn-browser-profile vpn-browser-gluetun-data
    printf 'Persistent volumes removed.\n'
else
    printf 'Persistent volumes kept.\n'
fi
