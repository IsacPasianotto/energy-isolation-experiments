#!/usr/bin/env bash
set -euo pipefail


# -- Exit with a message and a non-zero exit code
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

#
# --- 0. Prerequisites
# 
commands=(python3 sudo git podman)
for cmd in "${commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "error, command $cmd not available. Please install $cmd to use this script."
done

echo "Running 'sudo -v' to check for sudo privileges..."
sudo -v \
    || die "error, cannot use sudo. Please make sure your user has sudo privileges to use this script."

python3 -c 'import jinja2' >/dev/null 2>&1 \
    || die "the jinja2 python module is not available; install it with 'python3 -m pip install jinja2' (or the distro package python3-jinja2)."


# check that podman is at least version 4.0 (quadlet was introduced in 4.0)
podman_version=$(sudo podman --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
podman_major=${podman_version%%.*}
[[ "$podman_major" =~ ^[0-9]+$ ]] \
    || die "error, could not determine podman version from 'podman --version'."

(( podman_major >= 4 )) \
    || die "error, podman version 4.0 or later is required (found $podman_version). Please upgrade your podman installation."

#
# --- 1. Paths
#
ROOT_PRJ_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
TEMPLATE_DIR="${ROOT_PRJ_DIR}/config/templates"
VALUES_FILE="${ROOT_PRJ_DIR}/config/telegraf/template-values.toml"
TELEGRAF_CONFIG_DIR="${ROOT_PRJ_DIR}/config/telegraf"
OUT_DIR="${ROOT_PRJ_DIR}/last_applied_configuration"
RENDER_JINJA_TEMPLATES_SCRIPT="${ROOT_PRJ_DIR}/src/00-render-template.py"
DEPLOY_QUADLET_SCRIPT="${ROOT_PRJ_DIR}/src/01-deploy-quadlet-container.sh"
DESTROY_QUADLET_SCRIPT="${ROOT_PRJ_DIR}/src/99-destroy-quadlet-container.sh"

# checks
[ -d "$ROOT_PRJ_DIR" ]    || die "not in a git repository, clone the project from the git server please."
[ -d "$TEMPLATE_DIR" ]    || die "template directory not found: $TEMPLATE_DIR"
[ -f "$VALUES_FILE" ]     || die "values file not found: $VALUES_FILE"
[ -d "$TELEGRAF_CONFIG_DIR" ]             || die "telegraf helper scripts directory not found: $TELEGRAF_CONFIG_DIR"
[ -f "$RENDER_JINJA_TEMPLATES_SCRIPT" ]   || die "render script not found: $RENDER_JINJA_TEMPLATES_SCRIPT"
[ -f "$DEPLOY_QUADLET_SCRIPT" ]           || die "deploy script not found: $DEPLOY_QUADLET_SCRIPT"
[ -f "$DESTROY_QUADLET_SCRIPT" ]          || die "destroy script not found: $DESTROY_QUADLET_SCRIPT"

#
# --- 2. Render jinja templates
#
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$RENDER_JINJA_TEMPLATES_SCRIPT" \
    --templates "$TEMPLATE_DIR" \
    --values "$VALUES_FILE" \
    --out "$OUT_DIR" \
    || die "template rendering failed."

printf '\nconfiguration rendered in %s\n' "$OUT_DIR"

#
# --- 3. Deploy the monitoring (telegraf quadlet container)
#
bash "$DEPLOY_QUADLET_SCRIPT" \
    || die "deployment of the telegraf quadlet failed."

# Set up the cleanup as a trap, so it will run on exit, no matter how the script exits (success, error, or interrupt).
# A signal handler that just returns would let the script resume where it was
# interrupted, so INT/TERM exit explicitly (128 + signal number).
cleanup() {
    trap - EXIT INT TERM
    printf '\n=== cleaning up ===\n'
    bash "$DESTROY_QUADLET_SCRIPT" \
        || printf 'warning: cleanup did not complete, check the node by hand.\n' >&2
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

#
# --- 4. Experiments
#
# TODO: the actual workload goes here (fan sweep, memstress, netstress, ...)
echo "TODO: no experiment implemented yet"
