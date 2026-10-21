#!/usr/bin/env bash
set -euo pipefail

cd "${STREPTAVIDIN_ROOT:-/mnt/beegfs/elmlund/datasets_for_nightly_tests/streptavidin}"
project="$PWD/8_select_particles/streptav4.simple"
selected_particles="$PWD/8_select_particles/selected_particles.mrc"
for input in "$project" "$selected_particles"; do
    [[ -r "$input" ]] || { echo "Input is not readable: $input" >&2; exit 1; }
done
restarts="${STREPTAVIDIN_RESTARTS:-100}"
[[ "$restarts" =~ ^[1-9][0-9]*$ ]] || { echo "STREPTAVIDIN_RESTARTS must be positive" >&2; exit 1; }

if [[ -n "${STREPTAVIDIN_RUN_DIR:-}" ]]; then
    mkdir -p "$STREPTAVIDIN_RUN_DIR"
    cd "$STREPTAVIDIN_RUN_DIR"
fi

# solve3D reads stack paths from its project; relocate them in a separate copy.
runtime_project="$PWD/streptav4_runtime_$(date -u +%Y%m%dT%H%M%SZ)_$$.simple"
simple_exec prg=update_project "projfile=$project" \
    ptcl_old_root=/usr/local/cache/hans/streptav4/8_select_particles \
    "ptcl_new_root=${selected_particles%/*}" "projfile_out=$runtime_project" mkdir=no nthr=1

exec simple_exec prg=solve3D pgrp=d2 cavg_ini=no cenlp=10 mskdiam=80 \
    nthr=4 nparts=8 nthr_ini3D=32 "projfile=$runtime_project" balance=none \
    "nrestarts=$restarts" rec_backend=gridding pcg_solvent=no
