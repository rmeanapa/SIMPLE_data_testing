#!/usr/bin/env bash
# Prepare the streptav4 input used by streptav4.sh, perturb its stored poses,
# reconstruct each perturbed project, then refine it with pose_cont=only
# sequentially (32 CPUs total).
# Angular bounds are per Euler coordinate; x/y offsets are symmetric pixels per axis.
# No ground-truth volume is supplied to refinement.
set -euo pipefail
benchmark_started_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
benchmark_started_epoch=$(date -u +%s)

usage() {
    cat <<'HELP'
Usage: bash streptav4_pose_errors.sh [--prepare-only] [RUN_DIR]

Default RUN_DIR: ./streptavidin_pose_errors (must not already exist).
Uses $simple_exec when set, otherwise simple_exec on PATH. The executable
must support oriops text I/O and update_project path remapping. Requires Bash, awk and GNU coreutils.

STREPTAVIDIN_ROOT       Dataset root, as in streptav4.sh.
SIMPLE_SEED            Reproducible seed (default 20261022).
STREPTAVIDIN_POSE_NPARTS  Refinement partitions (default 8).
STREPTAVIDIN_POSE_NTHR    Threads per partition (default 4).
STREPTAVIDIN_POSE_MAXITS  Optional iteration budget; default uses SIMPLE automatic limits.

An explicit maxits also sets SIMPLE minimum iterations to that budget.
The report distinguishes first convergence detection from the final stop.
No additional diagnostic refinements are launched.
initial/ preserves each reconstruction and project before refinement.
GNU awk (gawk) is required by make_report.sh diagnostics.

Cases (symmetric Euler-coordinate degrees / symmetric added pixels per x,y axis):
5/1, 10/3, 15/5, 20/7, 25/9.

--prepare-only creates the relocated and perturbed projects without refining.
Each arm first reconstructs recvol_state01.mrc using CC without regularization,
then runs refine3D_auto pose_cont=only from that map and the perturbed poses.
The five arms have their own LOG, reconstruct.log, project, maps and FSC files.
runs.tsv records the arm paths, bounds, seed, and completion status.
For the complete report, pass RUN_DIR to make_report.sh.
HELP
}

prepare_only=0
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if [[ ${1:-} == --prepare-only ]]; then prepare_only=1; shift; fi
if (( $# > 1 )); then usage >&2; exit 2; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
perturb_script="$script_dir/perturb_project_poses.sh"
[[ -r "$perturb_script" ]] || { echo "Missing $perturb_script" >&2; exit 1; }
simple_executable=$(command -v "${simple_exec:-simple_exec}") || {
    echo 'Cannot find $simple_exec or simple_exec on PATH.' >&2; exit 1;
}
simple_executable=$(cd -- "$(dirname -- "$simple_executable")" && pwd -P)/$(basename -- "$simple_executable")
export simple_exec="$simple_executable"
# Distributed children must resolve beside the selected executable as well.
export PATH="${simple_executable%/*}:$PATH"
dataset_root=$(cd -- "${STREPTAVIDIN_ROOT:-/mnt/beegfs/elmlund/datasets_for_nightly_tests/streptavidin}" && pwd -P)
source_project="$dataset_root/8_select_particles/streptav4.simple"
selected_particles="$dataset_root/8_select_particles/selected_particles.mrc"
for input in "$source_project" "$selected_particles"; do
    [[ -r "$input" ]] || { echo "Input is not readable: $input" >&2; exit 1; }
done
seed=${SIMPLE_SEED:-20261022}
nparts=${STREPTAVIDIN_POSE_NPARTS:-8}
nthr=${STREPTAVIDIN_POSE_NTHR:-4}
maxits=${STREPTAVIDIN_POSE_MAXITS:-}
[[ -z $maxits || $maxits =~ ^[1-9][0-9]*$ ]] || {
    echo 'STREPTAVIDIN_POSE_MAXITS must be a positive integer.' >&2; exit 2;
}
[[ $seed =~ ^[0-9]+$ && ${#seed} -le 18 ]] || {
    echo 'SIMPLE_SEED must be a nonnegative integer with at most 18 digits.' >&2; exit 2;
}
for count in "$nparts" "$nthr"; do
    [[ $count =~ ^[1-9][0-9]*$ ]] || { echo 'Partition/thread counts must be positive integers.' >&2; exit 2; }
done

run_dir=${1:-$PWD/streptavidin_pose_errors}
[[ ! -e "$run_dir" && ! -L "$run_dir" ]] || {
    echo "Refusing an existing run directory: $run_dir" >&2; exit 1;
}
mkdir -p -- "$(dirname -- "$run_dir")"
mkdir -- "$run_dir"
run_dir=$(cd -- "$run_dir" && pwd -P)
# Record benchmark timing, not filesystem modification or report-generation time.
testing_commit=$(git -C "$script_dir" rev-parse HEAD 2>/dev/null || echo unavailable)
testing_dirty=unavailable
if git -C "$script_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    testing_dirty=no
    [[ -z $(git -C "$script_dir" status --porcelain -- \
        streptav4_pose_errors.sh perturb_project_poses.sh make_report.sh \
        .github/scripts/streptavidin_pose_diagnostics.sh .github/scripts/streptavidin_pose_diagnostics.awk .github/workflows/streptavidin_pose_errors_test.yml) ]] || testing_dirty=yes
fi
write_run_metadata() {
    local ended="$1" elapsed="$2" status="$3" exit_code="$4"
    {
        printf 'started_utc\t%s\nfinished_utc\t%s\nelapsed_seconds\t%s\n' \
            "$benchmark_started_utc" "$ended" "$elapsed"
        printf 'status\t%s\nexit_code\t%s\ntesting_commit\t%s\ntesting_dirty\t%s\n' \
            "$status" "$exit_code" "$testing_commit" "$testing_dirty"
        printf 'github_repository\t%s\ngithub_run_id\t%s\ngithub_run_attempt\t%s\n' \
            "${GITHUB_REPOSITORY:-}" "${GITHUB_RUN_ID:-}" "${GITHUB_RUN_ATTEMPT:-}"
    } > "$run_dir/.RUN_METADATA.tsv.tmp"
    mv -- "$run_dir/.RUN_METADATA.tsv.tmp" "$run_dir/RUN_METADATA.tsv"
}
finish_run_metadata() {
    local code=$? state=FAILED
    trap - EXIT
    if (( code == 0 )); then
        state=COMPLETED
        (( ! prepare_only )) || state=PREPARED_ONLY
    fi
    write_run_metadata "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "$(( $(date -u +%s) - benchmark_started_epoch ))" "$state" "$code" || \
        { echo 'ERROR: could not finalize RUN_METADATA.tsv' >&2; exit 1; }
    exit "$code"
}
write_run_metadata '' '' RUNNING ''
trap finish_run_metadata EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$run_dir/preparation"
export SIMPLE_SEED=$seed SIMPLE_QSYS=local
export OMP_NUM_THREADS=$nthr OMP_THREAD_LIMIT=$((nparts * nthr))
export OMP_WAIT_POLICY=PASSIVE OPENBLAS_NUM_THREADS=1
printf 'Run directory: %s\nExecutable: %s\nSeed: %s\n' "$run_dir" "$simple_executable" "$seed"
printf 'source_project\t%s\nselected_particles\t%s\nexecutable\t%s\nseed\t%s\nnparts\t%s\nnthr\t%s\n' \
    "$source_project" "$selected_particles" "$simple_executable" "$seed" "$nparts" "$nthr" > "$run_dir/inputs.tsv"
printf 'requested_maxits\t%s\nshift_error_mode\tsymmetric\n' "${maxits:-automatic}" >> "$run_dir/inputs.tsv"
sha256sum "$simple_executable" "$source_project" "$selected_particles" > "$run_dir/INPUT_SHA256SUMS"
printf 'testing_commit\t%s\n' "${GITHUB_SHA:-$(git -C "$script_dir" rev-parse HEAD 2>/dev/null || echo unavailable)}" >> "$run_dir/inputs.tsv"

# SIMPLE records jobs in the CLI-named input project, including update_project.
# Never pass the shared dataset project to a writing command.
cp -- "$source_project" "$run_dir/preparation/source_project.simple"
runtime_project="$run_dir/preparation/streptav4_runtime.simple"
echo 'Preparing relocated runtime project...'
(
    cd "$run_dir/preparation"
    "$simple_executable" prg=update_project projfile=source_project.simple \
        ptcl_old_root=/usr/local/cache/hans/streptav4/8_select_particles \
        "ptcl_new_root=${selected_particles%/*}" "projfile_out=$runtime_project" mkdir=no nthr=1
) > "$run_dir/preparation/LOG" 2>&1 || {
    echo "Project relocation failed; see $run_dir/preparation/LOG" >&2; exit 1;
}
echo 'Creating the five random pose perturbations...'
bash "$perturb_script" "$runtime_project" "$seed" >> "$run_dir/preparation/LOG" 2>&1 || {
    echo "Pose perturbation failed; see $run_dir/preparation/LOG" >&2; exit 1;
}

maxima=(5 10 15 20 25)
shift_maxima=(1 3 5 7 9)
arms=()
statuses=(PREPARED PREPARED PREPARED PREPARED PREPARED)
for i in "${!maxima[@]}"; do
    maximum=${maxima[$i]}
    printf -v name '%02d_refine3D_auto_pose_error_%d' "$((i + 1))" "$maximum"
    arm="$run_dir/$name"
    mkdir "$arm"
    cp -- "$run_dir/preparation/streptav4_runtime_err${maximum}deg_${shift_maxima[$i]}px.simple" "$arm/streptav4.simple"
    (
        cd "$arm"
        "$simple_executable" prg=update_project projfile=streptav4.simple mkdir=no nthr=1
    ) > "$arm/prepare.log" 2>&1 || { echo "Identity update failed; see $arm/prepare.log" >&2; exit 1; }
    arms+=("$arm")
done
write_manifest() {
    local index
    printf 'angle_max_deg\tshift_max_px\tseed\tstatus\tproject\tlog\tfinal_volume\tshift_min_px\n' > "$run_dir/runs.tsv"
    for index in "${!maxima[@]}"; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${maxima[$index]}" "${shift_maxima[$index]}" "$seed" "${statuses[$index]}" \
            "${arms[$index]}/streptav4.simple" "${arms[$index]}/LOG" \
            "${arms[$index]}/rec_final_state01.mrc" "-${shift_maxima[$index]}" >> "$run_dir/runs.tsv"
    done
}
write_manifest
if (( prepare_only )); then
    echo "Prepared five projects; no refinements run. Manifest: $run_dir/runs.tsv"
    exit 0
fi

# Export via a disposable project: native commands can append job history.
export_poses() (
    cd "$1" || exit 1
    cp -- "$2" pose_export.simple || exit 1
    "$simple_executable" prg=oriops oritab=pose_export.simple "outfile=$3" \
        oritype=ptcl3D mkdir=no nthr=1 > "$3.log" 2>&1 || exit 1
    grep -q 'SIMPLE_oriops NORMAL STOP' "$3.log" || exit 1
    test -s "$3" || exit 1
    rm -- pose_export.simple
)
export_poses "$run_dir/preparation" streptav4_runtime.simple original_poses.txt

# Keep timing and exit codes beside each case, even when a command fails.
run_science_step() {
    local phase=$1 started finished code=0
    shift
    started=$(date -u +%s)
    "$simple_executable" "$@" || code=$?
    finished=$(date -u +%s)
    printf '%s\t%s\t%s\t%s\t%s\n' "$phase" "$started" "$finished" "$((finished-started))" "$code" >> STEP_TIMING.tsv
    return "$code"
}
refinement_budget=()
[[ -z $maxits ]] || refinement_budget=("maxits=$maxits")

failed=0
for i in "${!maxima[@]}"; do
    arm=${arms[$i]}
    echo "Starting reconstruction and continuous-only refinement: ${maxima[$i]} degrees / ${shift_maxima[$i]} pixels"
    statuses[$i]=RUNNING
    write_manifest
    status=0
    (
        cd "$arm" || exit 1
        project=streptav4.simple
        printf 'phase\tstarted_epoch\tfinished_epoch\telapsed_seconds\texit_code\n' > STEP_TIMING.tsv
        printf '>>> PROGRAM: reconstruct3D\n'
        run_science_step reconstruct prg=reconstruct3D "projfile=$project" \
            pgrp=d2 mskdiam=80 "nthr=$nthr" "nparts=$nparts" \
            rec_backend=gridding objfun=cc ml_reg=no postprocess=no mkdir=no \
            > reconstruct.log 2>&1 || { cat reconstruct.log; exit 1; }
        cat reconstruct.log
        if [[ ! -s recvol_state01.mrc ]] || \
            ! grep -q 'SIMPLE_RECONSTRUCT3D NORMAL STOP' reconstruct.log || \
            grep -qE '^ERROR!|ERROR STOP' reconstruct.log; then
            echo 'ERROR! Starting reconstruction failed or did not produce recvol_state01.mrc' >&2
            exit 1
        fi
        # Immutable input checkpoint, including unfiltered map and available halves.
        mkdir initial || exit 1
        cp -- "$project" initial/streptav4.simple || exit 1
        cp -- recvol_state01*.mrc initial/ || exit 1
        sha256sum initial/* > INITIAL_SHA256SUMS || exit 1
        export_poses "$arm/initial" streptav4.simple poses.txt || exit 1
        printf '>>> PROGRAM: refine3D_auto\n'
        # Reuse this arm's directory so final maps and FSCs stay at the paths
        # consumed by the report; retain the requested intermediate volumes.
        run_science_step refine prg=refine3D_auto pose_cont=only \
            pgrp=d2 mskdiam=80 cenlp=10 "nthr=$nthr" "nparts=$nparts" \
            "projfile=$project" vol1=recvol_state01.mrc "${refinement_budget[@]}" \
            ref_pose_init=none regpass=no rec_backend=gridding pcg_solvent=no \
            keepvol=yes mkdir=no
    ) > "$arm/LOG" 2>&1 || status=$?
    actual_iterations=$(awk '/>>> ITERATION[[:space:]]+[0-9]+[[:space:]]*$/ {n=$NF} END {print n+0}' "$arm/LOG")
    if (( status == 0 )) && [[ -s "$arm/rec_final_state01.mrc" ]] && \
        grep -q 'SIMPLE_REFINE3D NORMAL STOP' "$arm/LOG" && \
        ! grep -qE '^ERROR!|ERROR STOP' "$arm/LOG"; then
        statuses[$i]=PASS
    else
        statuses[$i]=FAIL
        failed=1
        echo "Refinement failed (exit $status, iterations $actual_iterations, budget ${maxits:-automatic}, or incomplete products); see $arm/LOG" >&2
    fi
    if [[ ${statuses[$i]} == PASS ]]; then
        if ! export_poses "$arm" streptav4.simple final_poses.txt; then
            statuses[$i]=FAIL; failed=1
            echo "Final pose export failed: $arm/final_poses.txt.log" >&2
        fi
    fi
    write_manifest
    echo "Finished ${maxima[$i]} case: ${statuses[$i]}"
done
echo "Run manifest: $run_dir/runs.tsv"
exit "$failed"
