#!/usr/bin/env bash

# -- Exit with a message and a non-zero exit code
die() {
  printf 'error: %s\n' "$*" >&2
  # empty dir stack if any
  dirs -c 2>/dev/null
  exit 1
}

ROOT_PRJ_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
MEMSTRESS_DIR="${ROOT_PRJ_DIR}/src/memstress"
MEMSTRESS_BIN="${MEMSTRESS_DIR}/build/memstress"

[ -d "$MEMSTRESS_DIR" ] || die "memstress directory not found: $MEMSTRESS_DIR. Please init the submodules with 'git submodule update --init --recursive'."

pushd "$MEMSTRESS_DIR" >/dev/null || die "could not change directory to $MEMSTRESS_DIR"
make
#ensure the binary exists and is executable
[ -x "$MEMSTRESS_BIN" ] || die "memstress binary not found or not executable: $MEMSTRESS_BIN"


echo " ---- Get ready for running memstress experiments, this will take a while (approx 5 hours and 15 minutes) ----"

mkdir -p memstressout

for perc in 5 10 25 35 50 60 75 80
do
  echo " ---- Starting memstress at iteration ${perc}: $(date '+%Y-%m-%d %H:%M:%S %Z') ----"

  # 8 perc, 180+30 secs per run, 15 runs
  #   -> 26640 seconds = 7 hours and 24 minutes 
  $MEMSTRESS_BIN \
    --percentage ${perc} \
    --time-to-run 180 \
    --wait-time 30 \
    --runs 15
  sleep 180
  # backup the file for futher analysis
  mv ${MEMSTRESS_DIR}/memstress.csv ${MEMSTRESS_DIR}/memstressout/memstress_${perc}.csv
  mv ${MEMSTRESS_DIR}/memstress_events.log ${MEMSTRESS_DIR}/memstressout/memstress_events_${perc}.log
done

popd >/dev/null # return to ROOT_PRJ_DIR
