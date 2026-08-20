#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "error: $*" >&2
  dirs -c 2>/dev/null
  exit 1
}

# Logging helper: prefixes every status line with a UTC timestamp.
log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

# --- Vars and configs

ROOT_PRJ_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo, cannot determine ROOT_PRJ_DIR"
SRC_DIR="${ROOT_PRJ_DIR}/src"
OSU_BENCHMARK_DIR="${SRC_DIR}/osu-micro-benchmarks"

VERSION=7.5.2
WARMUP=0
SLEEP_BETWEEN=30
RUNS_PER_CONFIG=2

ETH_MCA="--mca pml ob1 --mca btl tcp,self,vader --mca btl_tcp_if_include bond0"

# CSV log: one row per single benchmark run.
CSV_FILE="${ROOT_PRJ_DIR}/osu_runs.csv"
if [ ! -f "${CSV_FILE}" ]; then
  echo "iter,message_size,situation,infiniband,t_start,t_end" > "${CSV_FILE}"
fi

# Iterations per message size, calibrated so each run takes ~10 minutes,
# based on the bandwidth actually measured at that size (not fixed -i).
# size(bytes) -> iterations
declare -A IB_ITERS=(
  [512]=48838000   [1024]=43941000  [2048]=29558000  [4096]=20027000
  [8192]=11804600  [16384]=6293500  [32768]=3300900  [65536]=1684900
  [131072]=852900  [262144]=432970  [524288]=216330  [1048576]=108070
  [2097152]=54120  [4194304]=27080
)

declare -A ETH_ITERS=(
  [512]=2993000    [1024]=2746500   [2048]=2571200   [4096]=2075300
  [8192]=1434500   [16384]=888800   [32768]=464150   [65536]=228940
  [131072]=147750  [262144]=100060  [524288]=51590   [1048576]=26040
  [2097152]=13060  [4194304]=6550
)

MSG_SIZES=(512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576 2097152 4194304)

#
# --- 0. Build osu-micro-benchmarks if not already installed
#
log "=== 0. setup osu-micro-benchmarks v${VERSION} ==="

mkdir -p "${OSU_BENCHMARK_DIR}"
pushd "${OSU_BENCHMARK_DIR}" >/dev/null

if [ ! -f "osu-micro-benchmarks-${VERSION}.tar.gz" ] && [ ! -d "osu-micro-benchmarks-${VERSION}" ]; then
  url="http://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-${VERSION}.tar.gz"
  log "sources not found, downloading from ${url}"
  wget -q "$url" -O "osu-micro-benchmarks-${VERSION}.tar.gz" || die "could not download $url"
  log "extracting archive"
  tar -xzf "osu-micro-benchmarks-${VERSION}.tar.gz"
else
  log "sources already present, skipping download"
fi

pushd "osu-micro-benchmarks-${VERSION}" >/dev/null

BIN_DIR="${OSU_BENCHMARK_DIR}/bin"
PT2PT_DIR="${BIN_DIR}/libexec/osu-micro-benchmarks/mpi/pt2pt"

if [ ! -x "${PT2PT_DIR}/osu_bw" ]; then
  log "binaries not found, configuring and building (prefix=${BIN_DIR})"
  ./configure CC=mpicc CXX=mpicxx --prefix="${BIN_DIR}" || die "could not configure osu-micro-benchmarks"
  make -j 8 || die "could not build osu-micro-benchmarks"
  make install || die "could not install osu-micro-benchmarks"
  log "build completed"
else
  log "binaries already built in ${PT2PT_DIR}, skipping build"
fi

pushd "${PT2PT_DIR}" >/dev/null
log "working dir: $(pwd)"

#
# --- 1. SLURM node discovery
#
log "=== 1. node discovery ==="

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST") || die "could not resolve SLURM_JOB_NODELIST"
mapfile -t node_list <<< "$nodes"

[ "${#node_list[@]}" -ge 2 ] || die "expected 2 nodes in \$SLURM_JOB_NODELIST, got: ${nodes}"

node1="${node_list[0]}"
node2="${node_list[1]}"

log "node1: ${node1}     node2: ${node2}"

#
# --- 2. Test configurations: situation | infiniband | host_order | benchmark | extra mca opts
#
configs=(
  "transmit|True|${node1},${node2}|osu_bw|"
  "receive|True|${node2},${node1}|osu_bw|"
  "bibw|True|${node1},${node2}|osu_bibw|"
  "transmit|False|${node1},${node2}|osu_bw|${ETH_MCA}"
  "receive|False|${node2},${node1}|osu_bw|${ETH_MCA}"
  "bibw|False|${node1},${node2}|osu_bibw|${ETH_MCA}"
)

#
# --- 3. Run everything: outer loop is the repetition (iter), then message
#        size, then configuration, as requested:
#
#        for iter in 1..10:
#            for size in sizes:
#                for conf in configs:
#                    do_the_benchmark
#
log "=== 3. running benchmarks ==="

for run in $(seq 1 "$RUNS_PER_CONFIG"); do
  for MSG_SIZE in "${MSG_SIZES[@]}"; do
    for cfg in "${configs[@]}"; do
      IFS='|' read -r situation infiniband host_order bench mca <<< "$cfg"

      if [[ "$infiniband" == "True" ]]; then
        ITERS="${IB_ITERS[$MSG_SIZE]}"
      else
        ITERS="${ETH_ITERS[$MSG_SIZE]}"
      fi

      log "iter ${run}/${RUNS_PER_CONFIG} | size ${MSG_SIZE}B | ${situation} | infiniband=${infiniband} | host order: ${host_order} | benchmark: ${bench} | mca: ${mca:-<none>} | iterations: ${ITERS}"

      t_start=$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')

      mpirun -np 2 --host "${host_order}" ${mca} \
        "./${bench}" -m "${MSG_SIZE}:${MSG_SIZE}" -x "${WARMUP}" -i "${ITERS}"

      t_end=$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')

      echo "${run},${MSG_SIZE},${situation},${infiniband},${t_start},${t_end}" >> "${CSV_FILE}"

      log "done iter ${run}/${RUNS_PER_CONFIG} | size ${MSG_SIZE}B | ${situation} | infiniband=${infiniband}, sleeping ${SLEEP_BETWEEN}s"
      sleep "${SLEEP_BETWEEN}"
    done
  done
done

#
# --- 4. Done
#
log "=== all OSU tests completed ==="
log "csv log written to ${CSV_FILE}"

popd >/dev/null # leave PT2PT_DIR
popd >/dev/null # leave osu-micro-benchmarks-$VERSION
popd >/dev/null # leave OSU_BENCHMARK_DIR