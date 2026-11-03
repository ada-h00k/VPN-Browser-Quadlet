#!/usr/bin/env bash
# vpn-browser-quadlet - rootless Podman Quadlets for Gluetun + Mullvad Browser
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License, version 3 only, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
# for more details.

set -Eeuo pipefail

readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly QUADLET_DIR="$CONFIG_HOME/containers/systemd"
readonly FISH_FUNCTION_DIR="$CONFIG_HOME/fish/functions"
readonly GLUETUN_ENV="$QUADLET_DIR/gluetun.env"
readonly BROWSER_ENV="$QUADLET_DIR/mullvad-browser.env"
readonly GLUETUN_UNIT="$QUADLET_DIR/gluetun.container"
readonly BROWSER_UNIT="$QUADLET_DIR/mullvad-browser.container"
readonly GLUETUN_VOLUME_UNIT="$QUADLET_DIR/gluetun-data.volume"
readonly BROWSER_VOLUME_UNIT="$QUADLET_DIR/browser-profile.volume"
readonly FISH_FUNCTION="$FISH_FUNCTION_DIR/vpn-browser.fish"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

on_error() {
    local rc=$?
    if (( rc != 0 )); then
        warn "Installation stopped. Existing persistent Podman volumes have not been deleted."
    fi
    exit "$rc"
}
trap on_error ERR

[[ "$EUID" -ne 0 ]] || die "Do not run this installer with sudo. It installs rootless user Quadlets."
[[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME is not set to a valid directory."
command -v podman >/dev/null 2>&1 || die "Podman is not installed."
command -v systemctl >/dev/null 2>&1 || die "systemd/systemctl is required."
command -v base64 >/dev/null 2>&1 || die "The base64 utility is required."
systemctl --user show-environment >/dev/null 2>&1 || die "The systemd user manager is unavailable. Log in to your desktop/user session first."

ROOTLESS="$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true)"
[[ "$ROOTLESS" == "true" ]] || die "Podman is not running rootless for this user. Check 'podman info'."
CGROUPS="$(podman info --format '{{.Host.CgroupsVersion}}' 2>/dev/null || true)"
[[ "$CGROUPS" == "v2" ]] || die "Quadlet requires cgroup v2; Podman reported '${CGROUPS:-unknown}'."

[[ -c /dev/net/tun ]] || die "/dev/net/tun is missing. An administrator may need to load the tun kernel module."
[[ -r /dev/net/tun && -w /dev/net/tun ]] || die "/dev/net/tun is not accessible to this user. Check device permissions and host security policy."

EXISTING_PROFILE_MOUNT="$(podman volume inspect --format '{{.Mountpoint}}' vpn-browser-profile 2>/dev/null || true)"
if [[ -n "$EXISTING_PROFILE_MOUNT" ]] && podman unshare test -f "$EXISTING_PROFILE_MOUNT/wg0.conf" 2>/dev/null; then
    die "The existing vpn-browser-profile volume contains wg0.conf. This setup shares Gluetun's network namespace; back up and remove that file so the browser image does not try to start a second WireGuard tunnel."
fi

[[ -f "$SCRIPT_DIR/fish/vpn-browser.fish" ]] || die "Missing fish/vpn-browser.fish in the project directory. Re-download or re-extract the complete project."

mkdir -p "$QUADLET_DIR" "$FISH_FUNCTION_DIR"
chmod 700 "$QUADLET_DIR"

get_timezone() {
    local tz=""
    if command -v timedatectl >/dev/null 2>&1; then
        tz="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    fi
    printf '%s' "${tz:-Etc/UTC}"
}

validate_address() {
    local value="$1" ip prefix octet
    local -a octets
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || return 1
    ip="${value%/*}"
    prefix="${value##*/}"
    IFS='.' read -r -a octets <<< "$ip"
    [[ "${#octets[@]}" -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
    (( 10#$prefix <= 32 ))
}

env_value() {
    local key="$1" file="$2"
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

# Shared country normalization library (also covered by tests/test-countries.sh).
source "$SCRIPT_DIR/lib/countries.sh"

backup_file() {
    local file="$1" stamp
    stamp="$(date '+%Y%m%d-%H%M%S')-$$"
    cp -p -- "$file" "$file.bak.$stamp"
    say "Backup created: $file.bak.$stamp"
}

write_env_without_key() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp "${file}.tmp.XXXXXX")"
    grep -v "^${key}=" "$file" > "$tmp" || true
    if [[ -n "$value" ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
    fi
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$file"
}

# Stop an existing stack before replacing its unit files. Ignore not-loaded
# units on first install; a failed old unit can still be stopped this way.
if systemctl --user is-active --quiet mullvad-browser.service 2>/dev/null || \
   systemctl --user is-active --quiet gluetun.service 2>/dev/null || \
   systemctl --user is-failed --quiet mullvad-browser.service 2>/dev/null || \
   systemctl --user is-failed --quiet gluetun.service 2>/dev/null; then
    say "Stopping the existing VPN browser stack..."
    systemctl --user stop mullvad-browser.service gluetun.service || true
fi

if [[ ! -f "$GLUETUN_ENV" ]]; then
    printf '\nMullvad WireGuard credentials are required.\n'
    printf 'Generate a configuration at https://mullvad.net/account/wireguard-config\n'
    printf 'Use PrivateKey and the first IPv4 CIDR from Address in a downloaded JSON file.\n\n'
    while :; do
        read -r -s -p 'Mullvad WireGuard PrivateKey: ' WG_PRIVATE_KEY
        printf '\n'
        if [[ "$WG_PRIVATE_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] && \
           printf '%s' "$WG_PRIVATE_KEY" | base64 -d >/dev/null 2>&1; then
            break
        fi
        warn "That is not a valid-looking 32-byte base64 WireGuard private key. Try again."
    done

    while :; do
        read -r -p 'Mullvad WireGuard IPv4 address (CIDR, e.g. 10.64.222.21/32): ' WG_ADDRESS
        if validate_address "$WG_ADDRESS"; then break; fi
        warn 'Enter an IPv4 CIDR address, e.g. 10.64.222.21/32.'
    done

    printf '\nOptional server-country filter. Use a full name (e.g. Switzerland) or ISO code (CH).\n'
    printf 'Leave empty to let Gluetun choose any available Mullvad server.\n'
    while :; do
        read -r -p 'Mullvad server country [any]: ' COUNTRY_INPUT
        if [[ -z "${COUNTRY_INPUT//[[:space:]]/}" ]]; then
            SERVER_COUNTRIES=""
            break
        fi
        if SERVER_COUNTRIES="$(normalize_country_list "$COUNTRY_INPUT")"; then
            break
        fi
        warn "Unknown or unsupported country. Example values: Switzerland, Germany, Netherlands, Sweden, CH, DE."
    done

    TZ_VALUE="$(get_timezone)"
    {
        printf 'VPN_SERVICE_PROVIDER=mullvad\n'
        printf 'VPN_TYPE=wireguard\n'
        printf 'WIREGUARD_PRIVATE_KEY=%s\n' "$WG_PRIVATE_KEY"
        printf 'WIREGUARD_ADDRESSES=%s\n' "$WG_ADDRESS"
        printf 'TZ=%s\n' "$TZ_VALUE"
        printf 'FIREWALL_INPUT_PORTS=3001\n'
        [[ -n "$SERVER_COUNTRIES" ]] && printf 'SERVER_COUNTRIES=%s\n' "$SERVER_COUNTRIES"
    } > "$GLUETUN_ENV"
    unset WG_PRIVATE_KEY WG_ADDRESS
    chmod 600 "$GLUETUN_ENV"
fi

# Validate credentials and provider values in both new and preserved env files.
[[ "$(env_value VPN_SERVICE_PROVIDER "$GLUETUN_ENV")" == 'mullvad' ]] || die "gluetun.env must contain VPN_SERVICE_PROVIDER=mullvad."
[[ "$(env_value VPN_TYPE "$GLUETUN_ENV")" == 'wireguard' ]] || die "gluetun.env must contain VPN_TYPE=wireguard."
EXISTING_WG_KEY="$(env_value WIREGUARD_PRIVATE_KEY "$GLUETUN_ENV")"
[[ "$EXISTING_WG_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] && \
    printf '%s' "$EXISTING_WG_KEY" | base64 -d >/dev/null 2>&1 || \
    die "gluetun.env does not contain a valid 32-byte base64 WIREGUARD_PRIVATE_KEY."
EXISTING_WG_ADDRESS="$(env_value WIREGUARD_ADDRESSES "$GLUETUN_ENV")"
validate_address "$EXISTING_WG_ADDRESS" || die "gluetun.env does not contain a valid IPv4 CIDR WIREGUARD_ADDRESSES value."
unset EXISTING_WG_KEY EXISTING_WG_ADDRESS

# Automatically repair country abbreviations and lower-case country names in
# existing installations. For example SERVER_COUNTRIES=ch becomes Switzerland.
CURRENT_COUNTRIES="$(env_value SERVER_COUNTRIES "$GLUETUN_ENV")"
if [[ -n "${CURRENT_COUNTRIES//[[:space:]]/}" ]]; then
    NORMALIZED_COUNTRIES="$(normalize_country_list "$CURRENT_COUNTRIES")" || \
        die "Unsupported SERVER_COUNTRIES='$CURRENT_COUNTRIES'. Use a Gluetun country name (e.g. Switzerland) or ISO code (e.g. CH), or remove SERVER_COUNTRIES from gluetun.env."
    if [[ "$NORMALIZED_COUNTRIES" != "$CURRENT_COUNTRIES" ]]; then
        backup_file "$GLUETUN_ENV"
        write_env_without_key "$GLUETUN_ENV" SERVER_COUNTRIES "$NORMALIZED_COUNTRIES"
        say "Normalized SERVER_COUNTRIES='$CURRENT_COUNTRIES' to '$NORMALIZED_COUNTRIES'."
    fi
fi

# Ensure Gluetun permits the browser HTTPS port inside its firewall.
CURRENT_INPUT_PORTS="$(env_value FIREWALL_INPUT_PORTS "$GLUETUN_ENV")"
case ",${CURRENT_INPUT_PORTS//[[:space:]]/}," in
    *,3001,*) ;;
    *)
        backup_file "$GLUETUN_ENV"
        if [[ -n "$CURRENT_INPUT_PORTS" ]]; then
            UPDATED_INPUT_PORTS="${CURRENT_INPUT_PORTS},3001"
        else
            UPDATED_INPUT_PORTS='3001'
        fi
        write_env_without_key "$GLUETUN_ENV" FIREWALL_INPUT_PORTS "$UPDATED_INPUT_PORTS"
        say 'Added port 3001 to FIREWALL_INPUT_PORTS.'
        ;;
esac
chmod 600 "$GLUETUN_ENV"

# The browser UI is intentionally unauthenticated by default. It is published
# on 127.0.0.1 only; do not expose it to your LAN or the Internet. On upgrades,
# remove credentials created by older versions of this installer while keeping
# PUID, PGID, TZ, and any unrelated user settings intact.
if [[ ! -f "$BROWSER_ENV" ]]; then
    {
        printf 'PUID=%s\n' "$(id -u)"
        printf 'PGID=%s\n' "$(id -g)"
        printf 'TZ=%s\n' "$(get_timezone)"
    } > "$BROWSER_ENV"
    chmod 600 "$BROWSER_ENV"
else
    if grep -Eq '^(CUSTOM_USER|PASSWORD|FILE__CUSTOM_USER|FILE__PASSWORD)=' "$BROWSER_ENV"; then
        # Preserve the non-secret browser settings in a timestamped backup,
        # but do not retain the old generated login in either file.
        stamp="$(date '+%Y%m%d-%H%M%S')-$$"
        tmp="$(mktemp "${BROWSER_ENV}.tmp.XXXXXX")"
        grep -Ev '^(CUSTOM_USER|PASSWORD|FILE__CUSTOM_USER|FILE__PASSWORD)=' "$BROWSER_ENV" > "$tmp" || true
        chmod 600 "$tmp"
        cp -p -- "$tmp" "$BROWSER_ENV.bak.$stamp"
        mv -f -- "$tmp" "$BROWSER_ENV"
        say "Removed browser web authentication settings. Sanitized backup created: $BROWSER_ENV.bak.$stamp"
    fi
    [[ -n "$(env_value PUID "$BROWSER_ENV")" ]] || die "mullvad-browser.env is missing PUID."
    [[ -n "$(env_value PGID "$BROWSER_ENV")" ]] || die "mullvad-browser.env is missing PGID."
fi
chmod 600 "$BROWSER_ENV"

cat > "$GLUETUN_VOLUME_UNIT" <<'EOF_UNIT'
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only
[Volume]
VolumeName=vpn-browser-gluetun-data
EOF_UNIT

cat > "$BROWSER_VOLUME_UNIT" <<'EOF_UNIT'
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only
[Volume]
VolumeName=vpn-browser-profile
EOF_UNIT

cat > "$GLUETUN_UNIT" <<EOF_UNIT
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only
[Unit]
Description=Gluetun VPN tunnel (Mullvad WireGuard)
StartLimitIntervalSec=60
StartLimitBurst=5

[Container]
Image=docker.io/qmcgaw/gluetun:latest
ContainerName=gluetun
AddCapability=NET_ADMIN
AddDevice=/dev/net/tun:/dev/net/tun
EnvironmentFile=$GLUETUN_ENV
Volume=gluetun-data.volume:/gluetun
PublishPort=127.0.0.1:3001:3001/tcp

# Explicitly define the Gluetun healthcheck. Do not rely on registry metadata.
HealthCmd=/gluetun-entrypoint healthcheck
HealthInterval=10s
HealthTimeout=5s
HealthStartPeriod=60s
HealthRetries=6
Notify=healthy
HealthOnFailure=kill

[Service]
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
EOF_UNIT

cat > "$BROWSER_UNIT" <<EOF_UNIT
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only
[Unit]
Description=LinuxServer Mullvad Browser routed through Gluetun
PartOf=gluetun.service

[Container]
Image=lscr.io/linuxserver/mullvad-browser:latest
ContainerName=mullvad-browser
Network=gluetun.container
EnvironmentFile=$BROWSER_ENV
Volume=browser-profile.volume:/config
ShmSize=1g

[Service]
Restart=on-failure
RestartSec=5
TimeoutStartSec=300
EOF_UNIT

chmod 600 "$GLUETUN_UNIT" "$BROWSER_UNIT"
chmod 644 "$GLUETUN_VOLUME_UNIT" "$BROWSER_VOLUME_UNIT"
install -m 644 "$SCRIPT_DIR/fish/vpn-browser.fish" "$FISH_FUNCTION"

say 'Reloading the rootless Quadlet systemd generator...'
systemctl --user daemon-reload
systemctl --user reset-failed gluetun.service mullvad-browser.service >/dev/null 2>&1 || true

systemctl --user cat gluetun.service >/dev/null 2>&1 || die 'Quadlet did not generate gluetun.service. Check Podman Quadlet support and the user journal.'
systemctl --user cat mullvad-browser.service >/dev/null 2>&1 || die 'Quadlet did not generate mullvad-browser.service. Check Podman Quadlet support and the user journal.'

printf '\nInstallation/update completed.\n'
printf 'Quadlet directory: %s\n' "$QUADLET_DIR"
printf 'Persistent volumes: vpn-browser-gluetun-data, vpn-browser-profile\n'
printf '\nStart the full stack (the browser pulls in Gluetun):\n  systemctl --user start mullvad-browser.service\n'
printf '\nStop the stack:\n  systemctl --user stop mullvad-browser.service gluetun.service\n'
printf '\nFish toggle function:\n  source %s\n  vpn-browser\n' "$FISH_FUNCTION"
printf '\nBrowser URL: https://localhost:3001\n'
printf 'Browser web authentication: disabled (no username or password required).\n'
printf '\nExisting Mullvad settings were preserved. Country abbreviations such as CH/DE are normalized to Gluetun names.\n'
printf 'The unauthenticated browser UI is bound to 127.0.0.1 only. Do not expose it publicly.\n'
