#!/usr/bin/env bash
# Collect native SIMPLE evidence; GNU awk calculates statistics and renders HTML/SVG.
set -euo pipefail
if (( $# != 4 )); then
    echo "Usage: $0 RUN_ROOT OUTPUT_DIR MAKE_REPORT REFERENCE" >&2
    exit 2
fi
command -v gawk >/dev/null || { echo 'Pose diagnostics require GNU awk (gawk).' >&2; exit 1; }
root=$(realpath "$1")
mkdir -p "$2"
out=$(realpath "$2")
report=$(realpath "$3")
truth=$(realpath "$4")
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
awk_script="$script_dir/streptavidin_pose_diagnostics.awk"
: > "$out/case_index.tsv"
: > "$out/worker_files.tsv"
: > "$out/collector_notices.tsv"
: > "$out/references.tsv"
shopt -s nullglob

notice() { printf '%s\t%s\n' "$case_name" "$1" >> "$out/collector_notices.tsv"; }

compare_map() {
    local iteration=$1 kind=$2 volume=$3 work result direct mirrored hand f05 f143 crossing
    if [[ ! -f $volume ]]; then
        notice "Reference FSC unavailable: missing $volume"
        return
    fi
    work="$out/$case_name/${iteration}_${kind}"
    mkdir -p "$work"
    echo "Reference FSC: $case_name $kind iteration $iteration"
    if ! bash "$report" --compare-volume "$volume" "$truth" "$work" > "$work/comparison.log" 2>&1; then
        notice "Reference comparison failed; see $work/comparison.log"
        return
    fi
    result=$(tail -n 1 "$work/comparison.log")
    if [[ $result != *'|'*'|'*'|'*'|'* ]]; then
        notice "Incomplete reference comparison; see $work/comparison.log"
        return
    fi
    IFS='|' read -r direct mirrored hand f05 f143 <<< "$result"
    crossing=$(gawk -v mode=curve -v curve="$work/truth_fsc.csv" -f "$awk_script")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$case_name" "$iteration" "$kind" "$volume" "$direct" "$mirrored" "$hand" "$f05" "$f143" "$crossing" >> "$out/references.tsv"
}

for angle in 5 10 15 20 25; do
    candidates=("$root/"*_refine3D_auto_pose_error_"$angle")
    case_name="pose_error_$angle"
    if (( ${#candidates[@]} != 1 )) || [[ ! -d ${candidates[0]} ]]; then
        printf '%s\t-\n' "$case_name" >> "$out/case_index.tsv"
        continue
    fi
    dir=${candidates[0]}
    printf '%s\t%s\n' "$case_name" "$dir" >> "$out/case_index.tsv"
    for path in "$dir"/EXIT_CODE_JOB_*; do
        [[ ${path##*/} =~ ^EXIT_CODE_JOB_[0-9]+$ ]] || continue
        printf '%s\texit\t%s\n' "$case_name" "$path" >> "$out/worker_files.tsv"
    done
    for path in "$dir"/BENCH/REFINE3D_BENCH_PART*.txt; do
        printf '%s\tbench\t%s\n' "$case_name" "$path" >> "$out/worker_files.tsv"
    done
    last_iteration=0
    if [[ -f $dir/LOG ]]; then
        last_iteration=$(gawk '/>>> ITERATION +[0-9]+ *$/ {n=$NF} END {print n+0}' "$dir/LOG")
    fi
    compare_map 0 initial_raw "$dir/initial/recvol_state01.mrc"
    maps=("$dir"/recvol_state01_iter*_lp.mrc)
    # Version sort keeps iter2 before iter10, with or without zero padding.
    if (( ${#maps[@]} )); then
        while IFS= read -r path; do
            name=${path##*/}
            [[ $name =~ ^recvol_state01_iter([0-9]+)_lp.mrc$ ]] || continue
            iteration=$((10#${BASH_REMATCH[1]}))
            compare_map "$iteration" iteration_lp "$path"
        done < <(printf '%s\n' "${maps[@]}" | sort -V)
    fi
    compare_map "$last_iteration" final_raw "$dir/rec_final_state01.mrc"
done

gawk -v root="$root" -v out="$out" -v reporttime="$(date -u +%Y-%m-%dT%H:%M:%SZ)" -f "$awk_script"
