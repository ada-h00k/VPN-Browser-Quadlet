# Changelog

## Unreleased

- Disable LinuxServer browser web authentication by default; do not generate a browser username or password.
- Remove legacy `CUSTOM_USER`/`PASSWORD` settings from existing browser env files during upgrades; preserve a sanitized backup without the obsolete credentials.

- Normalize Mullvad ISO country codes (including `ch`) to Gluetun's accepted country labels.
- Automatically back up and repair existing `gluetun.env` country settings during installer upgrades.
- Explicitly configure Gluetun's healthcheck for Quadlet `Notify=healthy`.
- Bound Gluetun restart attempts to avoid endless retries on configuration errors.
- Preserve existing credentials and Podman volumes during installer upgrades.
- Retain the user's Fish toggle workflow and add clearer startup diagnostics.
