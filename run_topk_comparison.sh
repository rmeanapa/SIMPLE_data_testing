#!/usr/bin/env bash
# Matched topk=1,3,5,10 solve3D and refine3D_auto campaigns.
# Prepare each dataset once; every refinement starts from its topk=1 solve.
set -Eeuo pipefail
usage() {
    echo "Usage: $0 NEW_OUTPUT [--build BUILD] [--checkout RECIPES] [--datasets betagal apof proteasome] [--mode both|solve3D] [--seed INTEGER] [--dry-run]"
}
[[ $# -gt 0 ]] || { usage >&2; exit 2; }
[[ $1 != --help && $1 != -h ]] || { usage; exit 0; }
output=$(realpath -m -- "$1")
shift
checkout=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
build=${SIMPLE_PATH:-$HOME/SIMPLE/build}
datasets=(betagal apof proteasome)
mode=both
seed=20261029
dry_run=0
while (( $# )); do
    case $1 in
        --build|--checkout|--mode|--seed)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            case $1 in
                --build) build=$2;;
                --checkout) checkout=$2;;
                --mode) mode=$2;;
                --seed) seed=$2;;
            esac
            shift 2;;
        --datasets)
            shift
            datasets=()
            while (( $# )) && [[ $1 != --* ]]; do datasets+=("$1"); shift; done
            (( ${#datasets[@]} )) || { usage >&2; exit 2; };;
        --dry-run) dry_run=1; shift;;
        *) usage >&2; exit 2;;
    esac
done
[[ $mode == both || $mode == solve3D ]] || { echo 'Invalid mode' >&2; exit 2; }
[[ $seed =~ ^[0-9]+$ ]] || { echo 'Seed must be a nonnegative integer' >&2; exit 2; }
command -v jq >/dev/null
build=$(cd -- "$build" && pwd -P)
checkout=$(cd -- "$checkout" && pwd -P)
executable="$build/bin/simple_exec"
[[ -x $executable ]] || { echo "Not executable: $executable" >&2; exit 2; }
declare -A seen=()
for dataset in "${datasets[@]}"; do
    case $dataset in betagal|apof|proteasome) ;; *) echo "Unknown dataset: $dataset" >&2; exit 2;; esac
    [[ ! ${seen[$dataset]+yes} ]] || { echo "Duplicate dataset: $dataset" >&2; exit 2; }
    seen[$dataset]=1
    recipe="$checkout/$dataset.sh"
    [[ -r $recipe ]] || { echo "Missing recipe: $recipe" >&2; exit 2; }
    for program in solve3D solve3D_cavgs refine3D_auto; do
        [[ $(grep -cE "^simple_exec prg=$program([[:space:]]|$)" "$recipe") == 1 ]] || {
            echo "Expected one $program command in $recipe" >&2; exit 2;
        }
    done
done
binary_sha256=$(sha256sum "$executable")
binary_sha256=${binary_sha256%% *}
dataset_json=$(jq -cn --args '$ARGS.positional' "${datasets[@]}")
initial_manifest=$(jq -n --arg build "$build" --arg checkout "$checkout" \
    --arg hash "$binary_sha256" --arg mode "$mode" --argjson seed "$seed" \
    --argjson datasets "$dataset_json" --arg started "$(date -u +%FT%TZ)" \
    '{build:$build, checkout:$checkout, binary_sha256:$hash, mode:$mode, seed:$seed,
      datasets:$datasets, topk:[1,3,5,10], rec_backend:"gridding", started_at:$started,
      refinement_start:"common topk=1 solve3D project", status:"prepared", results:[]}')
if (( dry_run )); then printf '%s\n' "$initial_manifest"; exit 0; fi
mkdir -p -- "$(dirname -- "$output")"
mkdir -- "$output" # Never reuse a previous campaign.
manifest="$output/campaign.json"
printf '%s\n' "$initial_manifest" > "$manifest"
update_manifest() {
    jq "$@" "$manifest" > "$manifest.tmp"
    mv -- "$manifest.tmp" "$manifest"
}
error=''
fail() { error=$*; echo "$error" >&2; return 1; }
on_error() {
    local code=$1 line=$2
    trap - ERR
    update_manifest --arg error "${error:-Command failed at line $line (exit $code)}" \
        --arg finished "$(date -u +%FT%TZ)" \
        '.status="failed" | .error=$error | .finished_at=$finished'
    exit "$code"
}
trap 'on_error "$?" "$LINENO"' ERR
export SIMPLE_PATH="$build" SIMPLE_QSYS=local SIMPLE_SEED="$seed"
export OPENBLAS_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE
export PATH="$build/bin:$build/scripts:$PATH"
# Set project_result directly so errors reach the campaign trap in this shell.
latest_project() {
    local parent=$1 program=$2 dataset=$3 candidate stage latest=-1 chosen=''
    for candidate in "$parent"/*_"$program"; do
        [[ -d $candidate ]] || continue
        stage=${candidate##*/}; stage=${stage%%_*}
        [[ $stage =~ ^[0-9]+$ ]] || continue
        if (( 10#$stage > latest )); then latest=$((10#$stage)); chosen=$candidate; fi
    done
    [[ -n $chosen ]] || fail "No $program output in $parent"
    project_result="$chosen/$dataset.simple"
    [[ -s $project_result ]] || fail "Missing project: $project_result"
}
run_logged() {
    local directory=$1 log=$2
    shift 2
    printf 'Running in %s:' "$directory"; printf ' %q' "$@"; printf '\n'
    (
        cd -- "$directory"
        printf 'Command:'; printf ' %q' "$@"; printf '\n'
        SIMPLE_SEED="$seed" "$@"
    ) > "$log" 2>&1
}
for dataset in "${datasets[@]}"; do
    case $dataset in betagal) pgrp=d2;; apof) pgrp=o;; proteasome) pgrp=d7;; esac
    root="$output/$dataset"
    mkdir -- "$root"
    cp -p -- "$checkout/$dataset.sh" "$root/source_recipe.sh"
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\n'
        awk '/^simple_exec prg=solve3D([[:space:]]|$)/ {exit} {print}' "$root/source_recipe.sh"
    } > "$root/prepare.sh"
    update_manifest --arg status "preparing $dataset" '.status=$status'
    run_logged "$root" "$root/PREPARE_LOG" bash "$root/prepare.sh"
    latest_project "$root/$dataset" solve3D_cavgs "$dataset"
    prepared=$project_result
    baseline=''
    for program in solve3D refine3D_auto; do
        [[ $program != refine3D_auto || $mode == both ]] || continue
        for k in 1 3 5 10; do
            arm="$root/$program/topk$k"
            mkdir -p -- "$arm"
            source=$prepared
            marker='SIMPLE_SOLVE3D NORMAL STOP'
            arguments=("prg=$program" "pgrp=$pgrp" mskdiam=180 nthr=8 nparts=10)
            if [[ $program == solve3D ]]; then
                arguments+=(cavg_ini_ext=yes)
            else
                source=$baseline
                marker='SIMPLE_REFINE3D NORMAL STOP'
            fi
            arguments+=("topk=$k" rec_backend=gridding "projfile=$source" mkdir=yes)
            update_manifest --arg status "running $dataset $program topk=$k" '.status=$status'
            started=$SECONDS
            run_logged "$arm" "$arm/LOG" simple_exec "${arguments[@]}"
            elapsed=$((SECONDS - started))
            grep -qF "$marker" "$arm/LOG" || fail "Missing normal completion; inspect $arm/LOG"
            if grep -qE 'ERROR!|ERROR STOP' "$arm/LOG"; then fail "Error reported; inspect $arm/LOG"; fi
            latest_project "$arm" "$program" "$dataset"
            project=$project_result
            [[ -s ${project%/*}/rec_final_state01.mrc ]] || fail "Missing final reconstruction in ${project%/*}"
            if [[ $program == solve3D && $k == 1 ]]; then baseline=$project; fi
            update_manifest --arg dataset "$dataset" --arg program "$program" --argjson k "$k" \
                --argjson seconds "$elapsed" --arg project "$project" --arg log "$arm/LOG" \
                '.results += [{dataset:$dataset,program:$program,topk:$k,seconds:$seconds,project:$project,log:$log}]'
        done
    done
done
update_manifest --arg finished "$(date -u +%FT%TZ)" '.status="complete" | .finished_at=$finished'
trap - ERR
