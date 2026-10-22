#!/usr/bin/env bash
# Create three perturbed copies of a project using the bounded oriops mode.
# Angular errors: uniform [-M,+M] degrees per Euler coordinate (polar interval
# truncated to [0,180]); x/y errors: independent uniform [0,M] pixel offsets.
# These are coordinate bounds, not a bound on the combined 3D rotation or shift.
# Outputs stay beside the source so relative dataset paths continue to resolve.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ${1:-} == --help ]]; then
    echo "Usage: $0 INPUT.simple [SEED]"
    echo 'Uses $simple_exec when set, otherwise simple_exec on PATH.'
    echo "Requires an executable with orierr_mode=bounded support."
    echo "Creates INPUT_err5deg_5px.simple, INPUT_err10deg_10px.simple,"
    echo "and INPUT_err15deg_15px.simple beside INPUT.simple."
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi

simple_executable=$(command -v "${simple_exec:-simple_exec}") || {
    echo 'Cannot find the executable specified by $simple_exec or simple_exec on PATH.' >&2
    exit 1
}
simple_executable=$(cd -- "$(dirname -- "$simple_executable")" && pwd)/$(basename -- "$simple_executable")
input_dir=$(cd -- "$(dirname -- "$1")" && pwd)
input_name=$(basename -- "$1")
[[ $input_name == *.simple && -f $input_dir/$input_name ]] || {
    echo "Input must be an existing .simple project." >&2
    exit 2
}
seed=${2:-${SIMPLE_SEED:-$(($(date +%s) + RANDOM))}}
[[ $seed =~ ^[0-9]+$ && ${#seed} -le 18 ]] || {
    echo "SEED must be a nonnegative integer with at most 18 digits." >&2
    exit 2
}
cd -- "$input_dir"
base=${input_name%.simple}
for maximum in 5 10 15; do
    output="${base}_err${maximum}deg_${maximum}px.simple"
    for target in "$output" "${output%.simple}.log"; do
        [[ ! -e $target && ! -L $target ]] || {
            echo "Refusing to overwrite: $input_dir/$target" >&2
            exit 1
        }
    done
done
echo "Random seed: $seed (reuse it to reproduce the same draws)."
export SIMPLE_SEED=$seed
for maximum in 5 10 15; do
    output="${base}_err${maximum}deg_${maximum}px.simple"
    logfile="${output%.simple}.log"
    echo "Creating $input_dir/$output"
    printf 'SIMPLE_SEED=%s\n' "$seed" >"$logfile"
    # SIMPLE records job history in its named input: work only on a new copy.
    # Copy the original for every level so errors do not accumulate.
    cp -- "$input_name" "$output"
    if ! "$simple_executable" prg=oriops "projfile=$output" \
        "oritab=$output" "outfile=$output" oritype=ptcl3D \
        orierr_mode=bounded "angerr=$maximum" "sherr=$maximum" \
        mkdir=no nthr=1 >>"$logfile" 2>&1; then
        echo "oriops failed; see $input_dir/$logfile" >&2
        exit 1
    fi
    [[ -s $output ]] || { echo "Missing output; see $logfile" >&2; exit 1; }
    # Give each copy its own identity for subsequent SIMPLE commands.
    if ! "$simple_executable" prg=update_project "projfile=$output" \
        mkdir=no nthr=1 >>"$logfile" 2>&1; then
        echo "Project identity update failed; see $input_dir/$logfile" >&2
        exit 1
    fi
done
