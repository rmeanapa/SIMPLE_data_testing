#!/usr/bin/env bash
# Create three full project copies with random errors in all five pose variables.
# Euler errors: uniform [-M,+M] degrees, truncated at the polar [0,180] limits.
# Added x/y errors: independent uniform [0,M] pixels. M = 5, 10, 15.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 || ${1:-} == --help ]]; then
    echo "Usage: bash $0 INPUT.simple [SEED]"
    echo 'Uses $simple_exec when set, otherwise simple_exec on PATH; requires Python 3.8+.'
    echo 'Uses existing oriops text I/O and update_project; no SIMPLE changes required.'
    echo 'Creates INPUT_err5deg_5px.simple, INPUT_err10deg_10px.simple,'
    echo 'and INPUT_err15deg_15px.simple beside INPUT.simple.'
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi
simple_executable=$(command -v "${simple_exec:-simple_exec}") || {
    echo 'Cannot find $simple_exec or simple_exec on PATH.' >&2; exit 1;
}
simple_executable=$(cd -- "$(dirname -- "$simple_executable")" && pwd -P)/$(basename -- "$simple_executable")
[[ $1 == *.simple && -f $1 ]] || { echo 'Input must be an existing .simple project.' >&2; exit 2; }
seed=${2:-${SIMPLE_SEED:-$(($(date +%s) + RANDOM))}}
[[ $seed =~ ^[0-9]+$ && ${#seed} -le 18 ]] || {
    echo 'SEED must be a nonnegative integer with at most 18 digits.' >&2; exit 2;
}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec python3 "$script_dir/perturb_project_poses.py" "$1" "$seed" "$simple_executable"
