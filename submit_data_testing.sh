#!/usr/bin/env bash
# Submit all SIMPLE_SYSTEMS datasets and four generated-data tests as independent Slurm jobs.
# Usage: bash ./submit_data_testing.sh [DATA_TESTING_CHECKOUT [SIMPLE_BUILD]]
# Defaults: checkout containing this script, SIMPLE_BUILD=$SIMPLE_PATH.
# Dataset scripts run in the current directory; results, logs and jobs.txt stay there.
# Load the SIMPLE runtime modules before submission; Slurm inherits this environment.
# Optional environment: SIMPLE_TEST_MEMORY (default 128G), SIMPLE_TEST_TIME
# (default 24:00:00), SIMPLE_TEST_ACCOUNT (default cluster account).
# Each node must support 80 CPUs: the existing scripts use nparts=10 nthr=8.
# Input datasets must be available at the /mnt/beegfs paths in those scripts.
# Waits for every job and exits nonzero if any submission or job fails.
# Uses an existing build; does not build SIMPLE or publish the Pages report.
set -euo pipefail

if (( $# > 2 )); then
    echo "Usage: $0 [DATA_TESTING_CHECKOUT [SIMPLE_BUILD]]" >&2
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
[[ -x "$simple_build/bin/simple_test_exec" ]] || { echo "Missing executable $simple_build/bin/simple_test_exec" >&2; exit 1; }
[[ -r "$data_checkout/positions_all.box" ]] || { echo "Missing $data_checkout/positions_all.box (required by nanox)" >&2; exit 1; }
command -v sbatch >/dev/null
run_dir=$(pwd -P)
mkdir -p "$run_dir/logs"
# nanox.sh reads this relative to its dataset directory.
if [[ ! "$data_checkout/positions_all.box" -ef "$run_dir/positions_all.box" ]]; then
    cp -- "$data_checkout/positions_all.box" "$run_dir/positions_all.box"
fi
account_args=()
if [[ -n ${SIMPLE_TEST_ACCOUNT:-} ]]; then
    account_args=(--account="$SIMPLE_TEST_ACCOUNT")
fi
# Each background sbatch waits for its own job; pipefail preserves its exit status.
# Stream job IDs immediately so jobs.txt remains useful while jobs are running.
submit_and_wait() {
    local label=$1
    shift
    sbatch --wait "$@" | while IFS= read -r job_id; do
        printf '%s %s\n' "$label" "$job_id" | tee -a "$run_dir/jobs.txt"
    done
}
wait_pids=()
wait_labels=()
echo "Results: $run_dir"
for system in "${systems[@]}"; do
    # Copy scripts only when submitting outside their checkout.
    if [[ ! "$data_checkout/$system.sh" -ef "$run_dir/$system.sh" ]]; then
        cp -- "$data_checkout/$system.sh" "$run_dir/$system.sh"
    fi
    submit_and_wait "$system" --parsable --partition=norm --nodes=1 --ntasks=1 \
        --cpus-per-task=80 --mem="${SIMPLE_TEST_MEMORY:-128G}" \
        --time="${SIMPLE_TEST_TIME:-24:00:00}" "${account_args[@]}" \
        --job-name="simple-$system" --chdir="$run_dir" --export=ALL \
        --output="$run_dir/logs/$system-%j.out" \
        --error="$run_dir/logs/$system-%j.err" \
        /dev/stdin "$system" "$simple_build" <<'SBATCH' &
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
    wait_pids+=("$!")
    wait_labels+=("$system")
done

for test_case in simulated_workflow:6vxx simulated_workflow:1jxy single_workflow:fcc single_workflow:wurtzite; do
    test_name=${test_case%%:*}
    suite=${test_case#*:}
    label=$suite
    if [[ "$test_name" == single_workflow ]]; then
        label=single_$suite
    fi
    submit_and_wait "$label" --parsable --partition=norm --nodes=1 --ntasks=1 \
        --cpus-per-task=80 --mem="${SIMPLE_TEST_MEMORY:-128G}" \
        --time="${SIMPLE_TEST_TIME:-24:00:00}" "${account_args[@]}" \
        --job-name="simple-$label" --chdir="$run_dir" --export=ALL \
        --output="$run_dir/logs/$label-%j.out" \
        --error="$run_dir/logs/$label-%j.err" \
        /dev/stdin "$test_name" "$suite" "$label" "$simple_build" <<'SBATCH' &
#!/usr/bin/env bash
set -euo pipefail
test_name=$1
suite=$2
label=$3
export SIMPLE_PATH=$4
export PATH="$SIMPLE_PATH/scripts:$SIMPLE_PATH/bin:$PATH"
export SIMPLE_QSYS=local
echo "Test: $test_name; suite: $suite; job: $SLURM_JOB_ID; host: $(hostname)"
exec simple_test_exec "test=$test_name" "suite=$suite" > "LOG_$label"
SBATCH
    wait_pids+=("$!")
    wait_labels+=("$label")
done

echo "Waiting for all ${#wait_pids[@]} Slurm jobs to finish..."
failed=0
for i in "${!wait_pids[@]}"; do
    if wait "${wait_pids[$i]}"; then
        echo "Completed: ${wait_labels[$i]}"
    else
        status=$?
        echo "Failed: ${wait_labels[$i]} (submission or job exit status $status)" >&2
        failed=1
    fi
done
exit "$failed"
