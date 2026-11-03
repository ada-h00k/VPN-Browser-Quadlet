# VPN Browser Quadlet

Install and manage a **rootless Podman** setup that routes the LinuxServer Mullvad Browser container through **Gluetun + Mullvad WireGuard**.

This project installs two Podman Quadlets:

- `gluetun.container` runs Gluetun, owns the Mullvad WireGuard tunnel and firewall, and publishes the browser's HTTPS port on host loopback only.
- `mullvad-browser.container` shares Gluetun's network namespace through `Network=gluetun.container`. It does not create a second VPN tunnel.

A Fish function named `vpn-browser` toggles both services. Starting the browser service automatically starts Gluetun as a dependency. The stack is not enabled at boot by default.

> **Scope:** this project deploys the LinuxServer `mullvad-browser` container image. It does not install the standalone Mullvad Browser desktop package.

## What is fixed in this release

This release includes fixes based on real startup errors seen with rootless Podman 5.8.x:

- **Explicit Gluetun healthcheck:** the Gluetun Quadlet defines `HealthCmd=/gluetun-entrypoint healthcheck` and its timing options. This is required when using `Notify=healthy`; Podman otherwise exits with `sdnotify policy "healthy" requires a healthcheck to be set`.
- **Country filter normalization:** Gluetun expects provider country names such as `Switzerland`, not ISO codes such as `ch`. The installer repairs existing values like `SERVER_COUNTRIES=ch` to `SERVER_COUNTRIES=Switzerland`, with a timestamped backup of `gluetun.env`. It also accepts ISO codes and case-insensitive names during a fresh install.
- **Safer restart behavior:** Gluetun uses a bounded systemd start rate instead of retrying a permanently invalid configuration forever.
- **Upgrade-friendly installer:** existing WireGuard credentials and persistent volumes are preserved. Browser web authentication is disabled by default. The installer regenerates the Quadlets and resets failed systemd units after reloading them.
- **Original Fish workflow:** the `vpn-browser` toggle remains available and opens the local browser UI after a successful start.

## Features

- Rootless Podman and user-level systemd Quadlets; no rootful container service is created.
- Mullvad WireGuard credentials are requested interactively by the installer.
- Optional server-country filter, accepting names or ISO codes (for example `Switzerland` or `CH`).
- Explicit Gluetun healthcheck gates the browser startup (`Notify=healthy`).
- Gluetun's firewall kills an unhealthy VPN container so systemd can restart it.
- Browser HTTPS is published on `127.0.0.1:3001` only.
- Browser web authentication is disabled by default; no username or password is generated or required.
- Browser profile and Gluetun data persist in dedicated rootless Podman named volumes.
- Fish toggle helper included; Fish is optional.
- Installer repairs an existing `SERVER_COUNTRIES=ch` configuration automatically.

## Requirements

- A Linux host with systemd and a working `systemctl --user` session.
- Podman with Quadlet support and cgroup v2.
- Rootless Podman configured for the current user, including subordinate UID/GID mappings where required by the distribution.
- `/dev/net/tun` present and readable/writable by the user running Podman.
- Mullvad account and a generated WireGuard configuration.
- x86-64 hardware for the LinuxServer Mullvad Browser image. The image's current README lists x86-64 support and no ARM64 variant.
- Fish is optional and only needed for the `vpn-browser` toggle function.

Check the host before installing:

```bash
podman info --format '{{.Host.Security.Rootless}}'
podman info --format '{{.Host.CgroupsVersion}}'
podman --version
ls -l /dev/net/tun
systemctl --user show-environment >/dev/null
```

Expected Podman output is `true` for rootless and `v2` for cgroups.

## Install or repair an existing installation

Run the installer as your normal user. **Do not use `sudo`.**

```bash
git clone https://github.com/YOUR-ACCOUNT/vpn-browser-quadlet.git
cd vpn-browser-quadlet
chmod +x install.sh
./install.sh
```

On first install, the installer:

1. Checks rootless Podman, cgroup v2, the user systemd manager, and `/dev/net/tun`.
2. Requests the Mullvad WireGuard `PrivateKey` and IPv4 CIDR address.
3. Optionally asks for a server country. Enter a full country name or ISO code; leave it empty for automatic server selection.
4. Creates the Gluetun and Browser Quadlets, volume Quadlets, and protected environment files.
5. Creates a browser environment file without authentication variables.
6. Installs the Fish helper under `~/.config/fish/functions/`.
7. Reloads the user systemd manager and verifies that both services were generated.

### Repair / upgrade behavior

You can run `./install.sh` again on top of an existing installation. The installer stops the stack if it is running, preserves the existing environment files and browser profile, rewrites the Quadlets, reloads systemd, and clears failed unit states.

In particular, if your existing `gluetun.env` contains:

```ini
SERVER_COUNTRIES=ch
```

the installer backs up that file as `gluetun.env.bak.YYYYMMDD-HHMMSS-PID` and changes the value to:

```ini
SERVER_COUNTRIES=Switzerland
```

It also normalizes supported ISO codes such as `DE` to `Germany`. If it encounters an unknown country value, it stops with a clear error instead of repeatedly starting a broken service. You can then remove `SERVER_COUNTRIES` for automatic server selection or replace it with a supported country name.

The installer ensures that `FIREWALL_INPUT_PORTS` includes `3001`. It does not delete persistent Podman volumes.

## Getting Mullvad WireGuard values

Generate and download a WireGuard configuration from [Mullvad's WireGuard configuration page](https://mullvad.net/account/wireguard-config). Extract one of the JSON files from the download:

- `PrivateKey` is the value for `WIREGUARD_PRIVATE_KEY`.
- The first IPv4 entry in `Address` is the value for `WIREGUARD_ADDRESSES`, including its CIDR suffix (for example `10.64.222.21/32`).

Do not use the device's displayed public WireGuard key as the private key. See Gluetun's [Mullvad provider guide](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/mullvad.md) for details.

## Usage

### Start and stop with systemd

Start the browser service. Quadlet automatically starts Gluetun first and waits for its healthcheck to pass:

```bash
systemctl --user start mullvad-browser.service
```

Stop both services:

```bash
systemctl --user stop mullvad-browser.service gluetun.service
```

Check status:

```bash
systemctl --user status gluetun.service mullvad-browser.service
podman ps --all
```

Follow Gluetun logs:

```bash
journalctl --user -u gluetun.service -f
```

Follow browser logs:

```bash
journalctl --user -u mullvad-browser.service -f
```

### Fish toggle

In a new Fish session:

```fish
vpn-browser
```

To load the function in the current Fish session:

```fish
source ~/.config/fish/functions/vpn-browser.fish
vpn-browser
```

The function starts the browser Quadlet (which pulls in Gluetun), or stops both services when either one is running/starting/failed. After a successful start it opens `https://localhost:3001` with `xdg-open` if available.

### Browser URL and authentication

Open **https://localhost:3001**. The image uses a self-signed TLS certificate, so the browser displays a certificate warning on first access.

Browser web authentication is **disabled by default**. The installer does not generate a username or password and writes neither `CUSTOM_USER` nor `PASSWORD` to `mullvad-browser.env`. On upgrades, it removes those authentication variables if an older installer version created them. A timestamped backup of the remaining browser settings is created without copying the obsolete credentials.

The LinuxServer browser web interface includes a terminal with passwordless `sudo` inside the container. Because there is no login prompt, keep the service bound to localhost. Do not expose the UI directly to your LAN or the Internet. Read the upstream [security notes](https://docs.linuxserver.io/images/docker-mullvad-browser/#security).

## Configuration

The installer writes the following files:

```text
~/.config/containers/systemd/
├── gluetun.container
├── gluetun.env
├── gluetun-data.volume
├── mullvad-browser.container
├── mullvad-browser.env
└── browser-profile.volume

~/.config/fish/functions/vpn-browser.fish

Rootless Podman named volumes:
├── vpn-browser-gluetun-data
└── vpn-browser-profile
```

Environment files are protected with mode `0600`.

### Gluetun settings

`gluetun.env` contains the Mullvad WireGuard values, timezone, optional country selection, and:

```ini
FIREWALL_INPUT_PORTS=3001
```

This permits the browser HTTPS port through Gluetun's firewall. The host-side port is separately bound to loopback only:

```ini
PublishPort=127.0.0.1:3001:3001/tcp
```

Do not change the host binding to `0.0.0.0` unless you understand the exposure and have added suitable access controls.

### Selecting a Mullvad country

Gluetun expects the country labels used by its provider data. Examples include:

```ini
SERVER_COUNTRIES=Switzerland
SERVER_COUNTRIES=Germany
SERVER_COUNTRIES=Netherlands
```

The installer also accepts corresponding ISO country codes (`CH`, `DE`, `NL`) and writes the canonical Gluetun label. Country availability can change as provider/server data changes. For automatic server selection, remove the `SERVER_COUNTRIES` line entirely.

You can optionally add `SERVER_CITIES` manually, using a city name present in Gluetun's current Mullvad server list. Then restart the stack:

```bash
systemctl --user restart gluetun.service
```

The browser unit has `PartOf=gluetun.service`, so an explicit Gluetun restart is propagated to the browser. Quadlet's `Network=gluetun.container` also generates the dependency that starts Gluetun before the browser.

## Troubleshooting

### `sdnotify policy "healthy" requires a healthcheck to be set`

The Gluetun Quadlet must include an explicit healthcheck because `Notify=healthy` depends on a Podman healthcheck:

```ini
HealthCmd=/gluetun-entrypoint healthcheck
HealthInterval=10s
HealthTimeout=5s
HealthStartPeriod=60s
HealthRetries=6
Notify=healthy
HealthOnFailure=kill
```

The installer writes these settings automatically.

### `the country specified is not valid: value is not one of the possible choices: none of ch`

This means `SERVER_COUNTRIES` contains an ISO code such as `ch`, but Gluetun expects a provider label such as `Switzerland`. Re-run the installer; it will back up and normalize known ISO values. Alternatively, edit `gluetun.env` and use `SERVER_COUNTRIES=Switzerland`, or remove the line for automatic selection.

### Gluetun starts but the browser does not

Check the healthcheck, logs, and generated unit files:

```bash
podman ps --all
podman healthcheck run gluetun
journalctl --user -u gluetun.service -b --no-pager
journalctl --user -u mullvad-browser.service -b --no-pager
systemctl --user cat gluetun.service
systemctl --user cat mullvad-browser.service
```

The Browser Quadlet shares Gluetun's network namespace. Do not add a second VPN tunnel to the browser. If the existing `vpn-browser-profile` volume has a `wg0.conf` at its root, back it up and remove it; the installer detects this condition and stops rather than allowing the browser image to attempt its own WireGuard setup.

### `TUN device is not available` or permission denied

Check that `/dev/net/tun` exists and is accessible to the rootless Podman user. The installer does not modify host-wide device permissions or SELinux policy. On SELinux systems, inspect the AVC denial and your distribution's Podman guidance. See the [Gluetun TUN troubleshooting page](https://github.com/qdm12/gluetun-wiki/blob/main/errors/tun.md).

### Quadlet service is not found

Reload the user manager and check generator output:

```bash
systemctl --user daemon-reload
systemctl --user cat gluetun.service
systemctl --user cat mullvad-browser.service
```

The rootless Quadlet search path is `~/.config/containers/systemd/`, not `/etc/containers/systemd/`.

### Verify that browser traffic uses Mullvad

Inside the container browser, open [Mullvad Connection Check](https://mullvad.net/en/check). Confirm that it reports a Mullvad IP and that there are no DNS leaks. Do not treat a systemd `active` state alone as proof that the VPN tunnel is working.

## Enable the user manager across logouts (optional)

The stack is intentionally not enabled at boot. If you want user services to be available while logged out, enable systemd lingering:

```bash
sudo loginctl enable-linger "$USER"
```

This is optional and not required for an active desktop session.

## Uninstall

Run as the same normal user:

```bash
./uninstall.sh
```

This stops the services and removes the generated Quadlets, environment files, and Fish helper. Persistent Podman volumes are kept unless you explicitly confirm their deletion. Deleting the volumes also deletes the saved browser profile and Gluetun data.

## How it works

Podman's Quadlet `Network=` option accepts another `.container` unit. Setting `Network=gluetun.container` makes the Browser container reuse Gluetun's network namespace and automatically creates a dependency on `gluetun.service`. `Notify=healthy` delays Gluetun's systemd startup notification until the configured Podman healthcheck succeeds. See the [Podman Quadlet manual](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).

The Browser container has `PartOf=gluetun.service`, so stop/restart operations on Gluetun propagate to the Browser service. The Gluetun healthcheck uses `HealthOnFailure=kill`; systemd then handles restarts. A start-rate limit prevents an invalid configuration from retrying indefinitely.

## Third-party components

This repository contains only the installer, Quadlet definitions, country-normalization helper, tests, and Fish helper. It pulls third-party container images at runtime:

- [Gluetun](https://github.com/passteque/gluetun) (`docker.io/qmcgaw/gluetun`)
- [LinuxServer Mullvad Browser](https://github.com/linuxserver/docker-mullvad-browser) (`lscr.io/linuxserver/mullvad-browser`)

Those projects and images remain under their respective upstream licenses. This repository does not include, modify, or relicense those images.

## Tests

Run the country normalization tests:

```bash
./tests/test-countries.sh
```

Check Bash script syntax:

```bash
bash -n install.sh uninstall.sh tests/test-countries.sh
```

## License

This project is licensed under the **GNU Affero General Public License v3.0 only**. See [`LICENSE`](LICENSE).
