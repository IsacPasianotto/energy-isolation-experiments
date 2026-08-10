#!/usr/bin/env bash

# NOTE: Needs root! Every privileged command is run through sudo.

set -euo pipefail

# -- Exit with a message and a non-zero exit code
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

#
# --- 0. Destination layout (must match the Volume= lines of the quadlet template)
#
TELEGRAF_DIR="/root/telegraf"
QUADLET_DIR="/etc/containers/systemd"
QUADLET_UNIT_FILE="${QUADLET_DIR}/quadlet-telegraf.container"
SERVICE_NAME="quadlet-telegraf.service"

#
# --- 1. Paths
#
ROOT_PRJ_DIR=$(git rev-parse --show-toplevel 2>/dev/null) \
    || die "not in a git repository, clone the project from the git server please."
OUT_DIR="${ROOT_PRJ_DIR}/last_applied_configuration"
TELEGRAF_CONFIG_DIR="${ROOT_PRJ_DIR}/config/telegraf"
TELEGRAF_CONF="${OUT_DIR}/telegraf-config.toml"
QUADLET_CONF="${OUT_DIR}/telegraf-quadlet.container"
PARSE_SH="${TELEGRAF_CONFIG_DIR}/parse.sh"
PSU_SH="${TELEGRAF_CONFIG_DIR}/psu.sh"

# checks
for f in "$TELEGRAF_CONF" "$QUADLET_CONF"; do
    [ -f "$f" ] || die "missing file: $f (render the templates first, see 00-render-template.py)."
done

for f in "$PARSE_SH" "$PSU_SH"; do
    [ -f "$f" ] || die "missing file: $f"
done


#
# --- 2. Directories and config filesls
#

# echo "==> creating ${TELEGRAF_DIR} and ${QUADLET_DIR}"
sudo install -d -o root -g root -m 0750 "$TELEGRAF_DIR"
sudo install -d -o root -g root -m 0750 "$QUADLET_DIR"


# echo "==> installing telegraf configuration and helper scripts"

sudo install -o root -g root -m 0644 "$TELEGRAF_CONF" "${TELEGRAF_DIR}/telegraf.config"
sudo install -o root -g root -m 0644 "$PARSE_SH"      "${TELEGRAF_DIR}/parse.sh"
sudo install -o root -g root -m 0644 "$PSU_SH"        "${TELEGRAF_DIR}/psu.sh"

# echo "==> installing the quadlet unit in ${QUADLET_UNIT_FILE}"
sudo install -o root -g root -m 0644 "$QUADLET_CONF" "$QUADLET_UNIT_FILE"

#
# --- 3. Start systemd unit
#
# echo "==> reloading systemd to pick up the new unit"
sudo systemctl daemon-reload

# echo "==> starting ${SERVICE_NAME}"
sudo systemctl restart "$SERVICE_NAME" \
    || die "failed to start ${SERVICE_NAME}. Inspect it with 'sudo systemctl status ${SERVICE_NAME}' and 'sudo journalctl -u ${SERVICE_NAME}'."

# Quadlet services are generated units: they are started at boot through the
# [Install] section of the .container file, so 'systemctl enable' is expected to
# fail here and is not needed.
sudo systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 \
    || echo "    (not enabling ${SERVICE_NAME} explicitly: generated unit, boot start comes from [Install] in the quadlet file)"

echo
echo "telegraf quadlet deployed. Check it with:"
echo "    sudo systemctl status ${SERVICE_NAME}"
echo "    sudo podman ps --filter name=telegraf"
