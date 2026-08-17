#!/usr/bin/env bash

#SBATCH -A lade
#SBATCH -p GPU
#SBATCH --nodes=1
#SBATCH --mem=230G
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=24
#SBATCH --time=10:00:00
#SBATCH --job-name=memstressbch
#SBATCH --nodelist=gpu002
#SBATCH --output=slurmout/slurm-%j.out
#SBATCH --error=slurmout/slurm-%j.err
#SBATCH --exclusive

mkdir -p slurmout

echo "------------- JOB PREAMBLE ---------------"
echo "Date:              $(date '+%Y-%m-%d')"
echo "Time:              $(date '+%H:%M:%S %Z')"
echo "Job name:          ${SLURM_JOB_NAME:-<not in slurm>}"
echo "Job ID:            ${SLURM_JOB_ID:-<not in slurm>}"
echo "SLURM partition:   ${SLURM_JOB_PARTITION:-<not in slurm>}"
echo "Number of nodes:   ${SLURM_JOB_NUM_NODES:-<not in slurm>}"
echo "Tasks per node:    ${SLURM_NTASKS_PER_NODE:-<not in slurm>}"
echo "CPUs per task:     ${SLURM_CPUS_PER_TASK:-<not in slurm>}"
echo "Node assigned:     ${SLURM_JOB_NODELIST:-$(hostname)}"
echo "Submit directory:  ${SLURM_SUBMIT_DIR:-$PWD}"
echo "------------------------------------------"

set -euo pipefail

# -- Exit with a message and a non-zero exit code
die() {
  printf 'error: %s\n' "$*" >&2
  # empty dir stack if any
  dirs -c 2>/dev/null
  exit 1
}

#
# --- 0. Prerequisites
#

# TODO: <---  Adjust it 
if command -v module >/dev/null 2>&1; then
  module purge
  module Core/26.03
  module load gcc/14.2.0
  module load cmake/3.31.9
  module load python/3.12.12
fi


commands=(python3 sudo git podman)
for cmd in "${commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 ||
    die "error, command $cmd not available. Please install $cmd to use this script."
done

echo "Running 'sudo -v' to check for sudo privileges..."
sudo -v ||
  die "error, cannot use sudo. Please make sure your user has sudo privileges to use this script."

# -- Python virtual environment: reuse ./env if it is already there, otherwise create it
if [ -d env ]; then
  # shellcheck source=/dev/null
  source env/bin/activate ||
    die "error, could not activate the existing virtual environment in ./env"
else
  [ -f requirements.txt ] ||
    die "error, requirements.txt not found, cannot set up the virtual environment."
  python3 -m venv env ||
    die "error, could not create the virtual environment in ./env"
  # shellcheck source=/dev/null
  source env/bin/activate ||
    die "error, could not activate the virtual environment in ./env"
  pip install -r requirements.txt ||
    die "error, could not install the dependencies listed in requirements.txt"
fi

python3 -c 'import jinja2' >/dev/null 2>&1 ||
  die "the jinja2 python module is not available in ./env; remove the env directory and re-run this script to rebuild it."

# check that podman is at least version 4.0 (quadlet was introduced in 4.0)
podman_version=$(sudo podman --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
podman_major=${podman_version%%.*}
[[ "$podman_major" =~ ^[0-9]+$ ]] ||
  die "error, could not determine podman version from 'podman --version'."

((podman_major >= 4)) ||
  die "error, podman version 4.0 or later is required (found $podman_version). Please upgrade your podman installation."

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
MEMSTRESS_DIR="${ROOT_PRJ_DIR}/src/memstress"
MEMSTRESS_BIN="${MEMSTRESS_DIR}/build/memstress"

# checks
[ -d "$ROOT_PRJ_DIR" ] || die "not in a git repository, clone the project from the git server please."
[ -d "$TEMPLATE_DIR" ] || die "template directory not found: $TEMPLATE_DIR"
[ -f "$VALUES_FILE" ] || die "values file not found: $VALUES_FILE"
[ -d "$TELEGRAF_CONFIG_DIR" ] || die "telegraf helper scripts directory not found: $TELEGRAF_CONFIG_DIR"
[ -f "$RENDER_JINJA_TEMPLATES_SCRIPT" ] || die "render script not found: $RENDER_JINJA_TEMPLATES_SCRIPT"
[ -f "$DEPLOY_QUADLET_SCRIPT" ] || die "deploy script not found: $DEPLOY_QUADLET_SCRIPT"
[ -f "$DESTROY_QUADLET_SCRIPT" ] || die "destroy script not found: $DESTROY_QUADLET_SCRIPT"
[ -d "$MEMSTRESS_DIR" ] || die "memstress directory not found: $MEMSTRESS_DIR. Please init the submodules with 'git submodule update --init --recursive'."

#
# --- 2. Render jinja templates
#
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$RENDER_JINJA_TEMPLATES_SCRIPT" \
  --templates "$TEMPLATE_DIR" \
  --values "$VALUES_FILE" \
  --out "$OUT_DIR" ||
  die "template rendering failed."

printf '\nconfiguration rendered in %s\n' "$OUT_DIR"

#
# --- 3. Deploy the monitoring (telegraf quadlet container)
#
bash "$DEPLOY_QUADLET_SCRIPT" ||
  die "deployment of the telegraf quadlet failed."

# Set up the cleanup as a trap, so it will run on exit, no matter how the script exits (success, error, or interrupt).
# A signal handler that just returns would let the script resume where it was
# interrupted, so INT/TERM exit explicitly (128 + signal number).
cleanup() {
  trap - EXIT INT TERM
  printf '\n=== cleaning up ===\n'
  bash "$DESTROY_QUADLET_SCRIPT" ||
    printf 'warning: cleanup did not complete, check the node by hand.\n' >&2
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

#
# --- 4. Experiments
#

# --- 4.1. Build the memstress binary

pushd "$MEMSTRESS_DIR" >/dev/null || die "could not change directory to $MEMSTRESS_DIR"
make
#ensure the binary exists and is executable
[ -x "$MEMSTRESS_BIN" ] || die "memstress binary not found or not executable: $MEMSTRESS_BIN"

# 4 experiments, each with 15 run of 300 seconds, with 30 seconds wait time between runs:
#    --> total: approx: 18900 seconds = 5 hours and 15 minutes

echo " ---- Get ready for running memstress experiments, this will take a while (approx 5 hours and 15 minutes) ----"
echo " ---- Starting memstress at: $(date '+%Y-%m-%d %H:%M:%S %Z') ----"

$MEMSTRESS_BIN \
  --size 150G \
  --time-to-run 300 \
  --wait-time 30 \ 
  --runs 15



popd >/dev/null # return to ROOT_PRJ_DIR