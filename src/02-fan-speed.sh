#!/usr/bin/env bash

# NOTE: this script was not tested directly, apparently DELL server, starting from a
#       certain version of IDRAC block the possiblity of editing the fan speed with
#       tool from command line like ipmitool, and even the root user get an error for
#       insufficient privileges.
#       In the article we do the experiment by hand editing the value from IDRAC GUI
#       interface. This in theour is the script that should do almost the same thing
#       if your server manifacturer allows it!

# set -uo pipefail
#
# #
# # --- 0. Configuration
# #
# START_SPEED=10
# MAX_SPEED=100
# STEP=5
# WAIT_SECONDS=180
# MAX_TEMP_C=85 # safety threshold: if any sensor exceeds this, abort immediately
# LOGFILE="/var/log/fan_test_$(date +%Y%m%d_%H%M%S).csv"
#
# #
# # --- 1. Prerequisites
# #
# die() {
#   printf 'error: %s\n' "$*" >&2
#   exit 1
# }
#
# commands=(ipmitool sudo)
# for cmd in "${commands[@]}"; do
#   command -v "$cmd" >/dev/null 2>&1 ||
#     die "command $cmd not available. Please install $cmd to use this script."
# done
#
# echo "Running 'sudo -v' to check for sudo privileges..."
# sudo -v ||
#   die "cannot use sudo. Please make sure your user has sudo privileges to use this script."
#
# # TODO:  comment it out if needed:
# #   Keep the sudo timestamp alive for the whole run: a full xxx%->100% sweep
# #   can take well over an hour, longer than sudo's default credential cache.
# # (
# #     while true; do
# #         sudo -n true 2>/dev/null
# #         sleep 60
# #         kill -0 "$$" 2>/dev/null || exit
# #     done
# # ) &
# # SUDO_KEEPALIVE_PID=$!
#
# log_line() {
#   echo "$1" | sudo tee -a "$LOGFILE" >/dev/null
# }
#
# log_line "timestamp,fan_speed_percent,phase,temperature_readings_C"
#
# ABORT_REASON=""
#
# # -- Set up a trap, so that we can restore automatic fan control on exit, even if the script is aborted.
# cleanup() {
#   echo
#   echo ">>> Restoring automatic (dynamic) fan control..."
#   sudo ipmitool raw 0x30 0x30 0x01 0x01 &>/dev/null
#   kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
#   if [[ -n "$ABORT_REASON" ]]; then
#     echo ">>> Test aborted: $ABORT_REASON"
#   fi
#   echo ">>> Done. Log saved to: $LOGFILE"
# }
# trap cleanup EXIT INT TERM
#
# set_fan_speed() {
#   local percent="$1"
#   local hex
#   hex=$(printf '0x%02x' "$percent")
#   # 0xff = apply to all fans
#   sudo ipmitool raw 0x30 0x30 0x02 0xff "$hex" &>/dev/null
# }
#
# # Logs current temperatures, returns via global variable MAX_READING
# check_and_log_temps() {
#   local speed="$1"
#   local phase="$2"
#   local ts
#   ts=$(date '+%Y-%m-%d %H:%M:%S')
#
#   local raw
#   raw=$(sudo ipmitool sdr type temperature 2>/dev/null)
#
#   # Extract all numeric readings "NN degrees C"
#   local readings
#   readings=$(echo "$raw" | grep -oE '[0-9]+ degrees C' | awk '{print $1}')
#
#   local readings_joined
#   readings_joined=$(echo "$readings" | paste -sd';' -)
#
#   log_line "$ts,$speed,$phase,\"$readings_joined\""
#   echo "    Temperatures ($phase): $(echo "$raw" | grep 'degrees C' | tr '\n' ' | ')"
#
#   MAX_READING=0
#   for t in $readings; do
#     ((t > MAX_READING)) && MAX_READING=$t
#   done
# }
#
# echo "=== Enabling manual fan control ==="
# sudo ipmitool raw 0x30 0x30 0x01 0x00 &>/dev/null
#
# speed=$START_SPEED
# while [[ $speed -le $MAX_SPEED ]]; do
#   echo
#   echo "=== Fans at ${speed}% ==="
#   set_fan_speed "$speed"
#
#   check_and_log_temps "$speed" "step_start"
#   if ((MAX_READING >= MAX_TEMP_C)); then
#     ABORT_REASON="temperature ${MAX_READING}C >= threshold ${MAX_TEMP_C}C at ${speed}% fan speed"
#     exit 1
#   fi
#
#   echo "    Waiting ${WAIT_SECONDS}s (3 minutes)..."
#   sleep "$WAIT_SECONDS"
#
#   check_and_log_temps "$speed" "step_end"
#   if ((MAX_READING >= MAX_TEMP_C)); then
#     ABORT_REASON="temperature ${MAX_READING}C >= threshold ${MAX_TEMP_C}C at ${speed}% fan speed"
#     exit 1
#   fi
#
#   speed=$((speed + STEP))
# done
#
# echo
# echo "=== Test completed normally ==="
