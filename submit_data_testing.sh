#!/usr/bin/env bash
# Submit the normal datasets, or one independent dataset campaign.
# Usage: bash ./submit_data_testing.sh [streptavidin|betagal_pose_cont|streptavidin_pose_errors] [DATA_TESTING_CHECKOUT [SIMPLE_BUILD]]
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

selected_system=""
case "${1:-}" in
    streptavidin|betagal_pose_cont|streptavidin_pose_errors) selected_system=$1; shift ;;
esac
if (( $# > 2 )); then
    echo "Usage: $0 [streptavidin|betagal_pose_cont|streptavidin_pose_errors] [DATA_TESTING_CHECKOUT [SIMPLE_BUILD]]" >&2
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
partition=norm
systems=(betagal apof proteasome nanox)
test_cases=(simulated_workflow:6vxx simulated_workflow:1jxy single_workflow:fcc single_workflow:wurtzite)
if [[ -n "$selected_system" ]]; then
    partition=csbdevel
    systems=("$selected_system")
    test_cases=()
fi
if [[ "$selected_system" == streptavidin ]]; then
    systems=()
    [[ -r "$data_checkout/streptav4.sh" ]] || { echo "Missing $data_checkout/streptav4.sh" >&2; exit 1; }
fi
if [[ "$selected_system" == streptavidin_pose_errors ]]; then
    systems=()
    for script in streptav4_pose_errors.sh perturb_project_poses.sh; do
        [[ -r "$data_checkout/$script" ]] || { echo "Missing $data_checkout/$script" >&2; exit 1; }
    done
    [[ ! -e "$PWD/streptavidin_pose_errors" ]] || { echo 'Pose-error campaign already exists.' >&2; exit 1; }
fi
for system in "${systems[@]}"; do
    [[ -r "$data_checkout/$system.sh" ]] || { echo "Missing $data_checkout/$system.sh" >&2; exit 1; }
done
[[ -x "$simple_build/bin/simple_exec" ]] || { echo "Missing executable $simple_build/bin/simple_exec" >&2; exit 1; }
if [[ -z "$selected_system" ]]; then
    [[ -x "$simple_build/bin/single_exec" ]] || { echo "Missing executable $simple_build/bin/single_exec" >&2; exit 1; }
    [[ -x "$simple_build/bin/simple_test_exec" ]] || { echo "Missing executable $simple_build/bin/simple_test_exec" >&2; exit 1; }
    [[ -r "$data_checkout/positions_all.box" ]] || { echo "Missing positions_all.box (required by nanox)" >&2; exit 1; }
fi
command -v sbatch >/dev/null
run_dir=$(pwd -P)
mkdir -p "$run_dir/logs"
streptavidin_dir="$run_dir/streptavidin"
if [[ "$selected_system" == streptavidin ]]; then
    mkdir "$streptavidin_dir" # Refuse an old campaign before submitting any jobs.
fi
# nanox.sh reads this relative to its dataset directory.
if [[ -z "$selected_system" && ! "$data_checkout/positions_all.box" -ef "$run_dir/positions_all.box" ]]; then
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
    submit_and_wait "$system" --parsable --partition="$partition" --nodes=1 --ntasks=1 \
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

for test_case in "${test_cases[@]}"; do
    test_name=${test_case%%:*}
    suite=${test_case#*:}
    label=$suite
    if [[ "$test_name" == single_workflow ]]; then
        label=single_$suite
    fi
    submit_and_wait "$label" --parsable --partition="$partition" --nodes=1 --ntasks=1 \
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

if [[ "$selected_system" == streptavidin ]]; then
# Each array task owns one solve3D invocation, runtime project and output directory.
submit_and_wait streptavidin --parsable --partition="$partition" --nodes=1 --ntasks=1 \
    --array=1-100%20 --cpus-per-task=32 --mem="${SIMPLE_TEST_MEMORY:-32G}" \
    --time="${SIMPLE_TEST_TIME:-24:00:00}" "${account_args[@]}" \
    --job-name=simple-streptavidin --chdir="$run_dir" --export=ALL \
    --output="$run_dir/logs/streptavidin-%A_%a.out" \
    --error="$run_dir/logs/streptavidin-%A_%a.err" \
    /dev/stdin "$data_checkout" "$simple_build" "$streptavidin_dir" <<'SBATCH' &
#!/usr/bin/env bash
set -euo pipefail
checkout=$1
export SIMPLE_PATH=$2
printf -v task_dir '%s/restart_%02d' "$3" "$SLURM_ARRAY_TASK_ID"
mkdir "$task_dir"
export STREPTAVIDIN_RUN_DIR="$task_dir" STREPTAVIDIN_RESTARTS=1
export PATH="$SIMPLE_PATH/bin:$SIMPLE_PATH/scripts:$PATH"
export SIMPLE_QSYS=local
export OMP_NUM_THREADS=4 OMP_THREAD_LIMIT=32 OMP_WAIT_POLICY=PASSIVE OPENBLAS_NUM_THREADS=1
# Separate reproducible starting draws even when all tasks start simultaneously.
export SIMPLE_SEED=$((20261020 + SLURM_ARRAY_TASK_ID))
echo "Job $SLURM_ARRAY_JOB_ID task $SLURM_ARRAY_TASK_ID host $(hostname) seed $SIMPLE_SEED"
bash "$checkout/streptav4.sh" > "$task_dir/LOG" 2>&1
# The solve3D restart wrapper can return zero after a failed reconstruction.
restart_log="$task_dir/SOLVE3D_OUTPUT_RESTART1"
grep -q 'SIMPLE_SOLVE3D NORMAL STOP' "$restart_log"
if grep -qE '^ERROR!|ERROR STOP' "$restart_log"; then exit 1; fi
mapfile -t volumes < <(find "$task_dir" -mindepth 2 -maxdepth 2 -type f -name rec_final_state01.mrc)
if [[ ${#volumes[@]} -ne 1 || ! -s "${volumes[0]}" ]]; then
    echo "Restart $SLURM_ARRAY_TASK_ID did not produce one final volume" >&2
    exit 1
fi
SBATCH
wait_pids+=("$!")
wait_labels+=(streptavidin)
fi

if [[ "$selected_system" == streptavidin_pose_errors ]]; then
submit_and_wait streptavidin_pose_errors --parsable --partition="$partition" --nodes=1 --ntasks=1 \
    --cpus-per-task=32 --mem="${SIMPLE_TEST_MEMORY:-32G}" \
    --time="${SIMPLE_TEST_TIME:-24:00:00}" "${account_args[@]}" \
    --job-name=simple-streptavidin-pose-errors --chdir="$run_dir" --export=ALL \
    --output="$run_dir/logs/streptavidin_pose_errors-%j.out" \
    --error="$run_dir/logs/streptavidin_pose_errors-%j.err" \
    /dev/stdin "$data_checkout" "$simple_build" "$run_dir/streptavidin_pose_errors" <<'SBATCH' &
#!/usr/bin/env bash
set -euo pipefail
checkout=$1
export SIMPLE_PATH=$2
export simple_exec="$SIMPLE_PATH/bin/simple_exec"
export PATH="$SIMPLE_PATH/bin:$SIMPLE_PATH/scripts:$PATH"
export SIMPLE_QSYS=local SIMPLE_SEED="${SIMPLE_SEED:-20261022}"
export STREPTAVIDIN_POSE_NPARTS=8 STREPTAVIDIN_POSE_NTHR=4
exec bash "$checkout/streptav4_pose_errors.sh" "$3"
SBATCH
wait_pids+=("$!")
wait_labels+=(streptavidin_pose_errors)
fi

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
