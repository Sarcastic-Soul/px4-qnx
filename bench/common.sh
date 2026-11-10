# Shared parts of the timing benchmarks. Source, don't run.
# shellcheck shell=bash
#
# Measurement: the PC_INTERVAL perf counter "mc_rate_control: interval"
# (added by patch 0004) counts the time between rate-controller updates.
# Each phase does `perf reset`, waits PHASE_S seconds, then reads the counter.

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$BENCH_DIR/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
SCRIPTS="$REPO_DIR/scripts"
PY="${PYTHON:-$WORK_DIR/venv/bin/python}"
RESULTS="${RESULTS:-$REPO_DIR/bench/results}"
PHASE_S="${PHASE_S:-30}"
mkdir -p "$RESULTS"

log() { echo "[$(basename "$0")] $*"; }

# "mc_rate_control: interval: 4099 events, 1249.56us avg, min 770us max 2229us 437.000us rms"
# -> JSON object. rms is the standard deviation of the interval.
perf_to_json() { # label < perf output
    awk -v label="$1" '/mc_rate_control: interval:/ {
        gsub(/us/, "");
        printf "{\"label\": \"%s\", \"events\": %s, \"avg_us\": %s, \"min_us\": %s, \"max_us\": %s, \"std_us\": %s}\n",
            label, $3, $5, $8, $10, $11; found=1; exit }
        END { if (!found) exit 1 }'
}
