# vpn-browser-quadlet - toggle Gluetun and LinuxServer Mullvad Browser.
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only

function vpn-browser --description 'Toggle the rootless Gluetun + Mullvad Browser Quadlet stack'
    set -l gluetun_state (systemctl --user is-active gluetun.service 2>/dev/null; or true)
    set -l browser_state (systemctl --user is-active mullvad-browser.service 2>/dev/null; or true)

    if contains -- "$gluetun_state" active activating reloading failed; or contains -- "$browser_state" active activating reloading failed
        echo '⏹ Stopping Mullvad Browser and Gluetun...'
        systemctl --user stop mullvad-browser.service gluetun.service
        or return 1
        echo '✓ VPN browser services stopped'
        return 0
    end

    echo '▶ Starting Mullvad Browser (Gluetun starts as a dependency)...'
    if not systemctl --user start mullvad-browser.service
        echo '✗ Stack startup failed. Recent Gluetun logs:'
        journalctl --user -u gluetun.service -n 30 --no-pager
        systemctl --user stop mullvad-browser.service gluetun.service >/dev/null 2>&1
        return 1
    end

    if not systemctl --user is-active --quiet mullvad-browser.service
        echo '✗ Mullvad Browser is not active. Check its user journal.'
        journalctl --user -u mullvad-browser.service -n 30 --no-pager
        systemctl --user stop mullvad-browser.service gluetun.service >/dev/null 2>&1
        return 1
    end

    echo '✓ Gluetun and Mullvad Browser are running'
    echo '🌐 Opening https://localhost:3001 ...'
    if type -q xdg-open
        command xdg-open https://localhost:3001 >/dev/null 2>&1 &
    else
        echo 'Open https://localhost:3001 in your browser.'
    end
end
