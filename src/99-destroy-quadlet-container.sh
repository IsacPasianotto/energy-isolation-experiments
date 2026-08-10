#!/usr/bin/env bash

# NOTE: Needs root! Every privileged command is run through sudo.

set -euo pipefail

# -- Exit with a message and a non-zero exit code
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

#
# --- 0. What has to be removed (must match 01-deploy-quadlet-container.sh)
#
TELEGRAF_DIR="/root/telegraf"
QUADLET_UNIT_FILE="/etc/containers/systemd/quadlet-telegraf.container"
SERVICE_NAME="quadlet-telegraf.service"

#
# --- 1. Paths
#
ROOT_PRJ_DIR=$(git rev-parse --show-toplevel 2>/dev/null) \
    || die "not in a git repository, clone the project from the git server please."

VALUES_FILE="${ROOT_PRJ_DIR}/config/telegraf/template-values.toml"

# the container name is needed to sweep away an orphan container, if any
CONTAINER_NAME=""
if [ -f "$VALUES_FILE" ]; then
    CONTAINER_NAME=$(sed -n 's/^[[:space:]]*container_name[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$VALUES_FILE" | head -n1)
fi
CONTAINER_NAME="${CONTAINER_NAME:-telegraf}"

#
# --- 2. Stop the service
#

command -v systemctl >/dev/null 2>&1 \
    || die "systemctl not found: this script targets a systemd node."


sudo systemctl stop "$SERVICE_NAME" 2>/dev/null \
    || echo "    (${SERVICE_NAME} was not running)"

sudo systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 \
    || true   # generated unit: nothing to disable, see the deploy script

sudo rm -f "$QUADLET_UNIT_FILE"
sudo rm -rf "${TELEGRAF_DIR:?}"

sudo systemctl daemon-reload

# echo "==> removing container '${CONTAINER_NAME}' if it is still around"
sudo podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 \
        || echo " container '${CONTAINER_NAME}' was not found, nothing to remove"
