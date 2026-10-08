#!/usr/bin/env bash
# Submit all SIMPLE_SYSTEMS datasets from data_testing.yml as independent Slurm jobs.
# Usage: bash ./submit_data_testing.sh [DATA_TESTING_CHECKOUT [SIMPLE_BUILD [OUTPUT_PARENT]]]
# Defaults: checkout containing this script, SIMPLE_BUILD=$SIMPLE_PATH, OUTPUT_PARENT=$PWD.
# Load the SIMPLE runtime modules before submission; Slurm inherits this environment.
# Optional environment: SIMPLE_TEST_MEMORY (default 128G), SIMPLE_TEST_TIME
# (default 24:00:00), SIMPLE_TEST_ACCOUNT (default cluster account).
# Each node must support 80 CPUs: the existing scripts use nparts=10 nthr=8.
# Input datasets must be available at the /mnt/beegfs paths in those scripts.
# Uses an existing build; does not build SIMPLE or publish the Pages report.
set -euo pipefail

if (( $# > 3 )); then
    echo "Usage: $0 [DATA_TESTING_CHECKOUT [SIMPLE_BUILD [OUTPUT_PARENT]]]" >&2
    exit 2
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
data_checkout=$(cd -- "${1:-$script_dir}" && pwd -P)
simple_build=${2:-${SIMPLE_PATH:-}}
if [[ -z "$simple_build" ]]; then
    echo "Set SIMPLE_PATH to your SIMPLE build directory or provide SIMPLE_BUILD as the second argument." >&2
    exit 2
fi
simple_build=$(cd -- "$simple_build" && pwd -P)
systems=(betagal apof clc motab proteasome trpm4 nanox)
for system in "${systems[@]}"; do
    [[ -r "$data_checkout/$system.sh" ]] || { echo "Missing $data_checkout/$system.sh" >&2; exit 1; }
done
[[ -x "$simple_build/bin/simple_exec" ]] || { echo "Missing executable $simple_build/bin/simple_exec" >&2; exit 1; }
[[ -x "$simple_build/bin/single_exec" ]] || { echo "Missing executable $simple_build/bin/single_exec" >&2; exit 1; }
[[ -r "$data_checkout/positions_all.box" ]] || { echo "Missing $data_checkout/positions_all.box (required by nanox)" >&2; exit 1; }
command -v sbatch >/dev/null
output_parent=${3:-$PWD}
mkdir -p -- "$output_parent"
output_parent=$(cd -- "$output_parent" && pwd -P)
run_dir=$(mktemp -d "$output_parent/simple-data-testing.XXXXXXXX")
mkdir -p "$run_dir/logs"
# nanox.sh reads this relative to its dataset directory.
cp -- "$data_checkout/positions_all.box" "$run_dir/positions_all.box"
account_args=()
if [[ -n ${SIMPLE_TEST_ACCOUNT:-} ]]; then
    account_args=(--account="$SIMPLE_TEST_ACCOUNT")
fi
echo "Results: $run_dir"
for system in "${systems[@]}"; do
    # Snapshot the input script and isolate repeated submissions from each other.
    cp -- "$data_checkout/$system.sh" "$run_dir/$system.sh"
    job_id=$(sbatch --parsable --partition=norm --nodes=1 --ntasks=1 \
        --cpus-per-task=80 --mem="${SIMPLE_TEST_MEMORY:-128G}" \
        --time="${SIMPLE_TEST_TIME:-24:00:00}" "${account_args[@]}" \
        --job-name="simple-$system" --chdir="$run_dir" --export=ALL \
        --output="$run_dir/logs/$system-%j.out" \
        --error="$run_dir/logs/$system-%j.err" \
        /dev/stdin "$system" "$simple_build" <<'SBATCH'
#!/usr/bin/env bash
set -euo pipefail
system=$1
export SIMPLE_PATH=$2
export PATH="$SIMPLE_PATH/scripts:$SIMPLE_PATH/bin:$PATH"
export SIMPLE_QSYS=local
# Individual SIMPLE commands set nthr explicitly, as in the Actions workflow.
echo "Dataset: $system; job: $SLURM_JOB_ID; host: $(hostname)"
exec bash -e "./$system.sh"
SBATCH
    )
    printf '%s %s\n' "$system" "$job_id" | tee -a "$run_dir/jobs.txt"
done
