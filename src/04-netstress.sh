#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "error: $*" >&2
  dirs -c 2>/dev/null
  exit 1
}

# --- Vars and configs

ROOT_PRJ_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo, cannot determine ROOT_PRJ_DIR"
SRC_DIR="${ROOT_PRJ_DIR}/src"
OSU_BENCHMARK_DIR="${SRC_DIR}/osu-micro-benchmarks"

VERSION=7.5.2
WARMUP=0
SLEEP_BETWEEN=30
RUNS_PER_CONFIG=10
TARGET="${TARGET:-thin008}"   # monitored node, overridable via env

ETH_MCA="--mca pml ob1 --mca btl tcp,self,vader --mca btl_tcp_if_include bond0"

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

#
# --- 0. Build osu-micro-benchmarks if not already installed
#
echo "=== 0. setup osu-micro-benchmarks v${VERSION} ==="

mkdir -p "${OSU_BENCHMARK_DIR}"
pushd "${OSU_BENCHMARK_DIR}" >/dev/null

if [ ! -f "osu-micro-benchmarks-${VERSION}.tar.gz" ] && [ ! -d "osu-micro-benchmarks-${VERSION}" ]; then
  url="http://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-${VERSION}.tar.gz"
  echo "sources not found, downloading from ${url}"
  wget -q "$url" -O "osu-micro-benchmarks-${VERSION}.tar.gz" || die "could not download $url"
  echo "extracting archive"
  tar -xzf "osu-micro-benchmarks-${VERSION}.tar.gz"
else
  echo "sources already present, skipping download"
fi

pushd "osu-micro-benchmarks-${VERSION}" >/dev/null

BIN_DIR="${OSU_BENCHMARK_DIR}/bin"
PT2PT_DIR="${BIN_DIR}/libexec/osu-micro-benchmarks/mpi/pt2pt"

if [ ! -x "${PT2PT_DIR}/osu_bw" ]; then
  echo "binaries not found, configuring and building (prefix=${BIN_DIR})"
  ./configure CC=mpicc CXX=mpicxx --prefix="${BIN_DIR}" || die "could not configure osu-micro-benchmarks"
  make -j 8 || die "could not build osu-micro-benchmarks"
  make install || die "could not install osu-micro-benchmarks"
  echo "build completed"
else
  echo "binaries already built in ${PT2PT_DIR}, skipping build"
fi

pushd "${PT2PT_DIR}" >/dev/null
echo "working dir: $(pwd)"

#
# --- 1. SLURM node discovery
#
echo "=== 1. node discovery ==="

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST") || die "could not resolve SLURM_JOB_NODELIST"
peer=$(grep -v -x "${TARGET}" <<< "$nodes")

echo "monitored node: ${TARGET}"
echo "peer node:      ${peer}"

#
# --- 2. Test configurations: label | host_order | benchmark | extra mca opts
#
configs=(
  "IB-transmit|${TARGET},${peer}|osu_bw|"
  "IB-receive|${peer},${TARGET}|osu_bw|"
  "IB-bidirectional|${TARGET},${peer}|osu_bibw|"
  "ETH-transmit|${TARGET},${peer}|osu_bw|${ETH_MCA}"
  "ETH-receive|${peer},${TARGET}|osu_bw|${ETH_MCA}"
  "ETH-bidirectional|${TARGET},${peer}|osu_bibw|${ETH_MCA}"
)

#
# --- 3. Run everything: for each configuration, RUNS_PER_CONFIG repetitions,
#        one message size at a time, -i looked up from the right table so
#        each run lasts ~10 minutes instead of a fixed iteration count.
#
for cfg in "${configs[@]}"; do
  IFS='|' read -r label host_order bench mca <<< "$cfg"

  # pick the iteration table matching this configuration's network
  if [[ "$label" == IB-* ]]; then
    net_table="IB_ITERS"
  else
    net_table="ETH_ITERS"
  fi

  for run in $(seq 1 "$RUNS_PER_CONFIG"); do
      for MSG_SIZE in 512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576 2097152 4194304; do

         if [[ "$net_table" == "IB_ITERS" ]]; then
           ITERS="${IB_ITERS[$MSG_SIZE]}"
         else
           ITERS="${ETH_ITERS[$MSG_SIZE]}"
         fi

         echo ""
         echo "=== ${label} | run ${run}/${RUNS_PER_CONFIG} ==="
         echo "host order: ${host_order}  benchmark: ${bench}  mca: ${mca:-<none>}"
         echo "message size: ${MSG_SIZE} bytes  iterations: ${ITERS} (~10min target)  warmup: ${WARMUP}"

         mpirun -np 2 --host "${host_order}" ${mca} \
            "./${bench}" -m "${MSG_SIZE}:${MSG_SIZE}" -x "${WARMUP}" -i "${ITERS}"

         echo "run ${run}/${RUNS_PER_CONFIG} for ${label} @ ${MSG_SIZE}B done, sleeping ${SLEEP_BETWEEN}s"
         sleep "${SLEEP_BETWEEN}"
      done
  done
done

#
# --- 4. Done
#
echo "=== all OSU tests completed ==="

popd >/dev/null # leave PT2PT_DIR
popd >/dev/null # leave osu-micro-benchmarks-$VERSION
popd >/dev/null # leave OSU_BENCHMARK_DIR