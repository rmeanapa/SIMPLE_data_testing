#!/usr/bin/env bash
# Offline checks for the active nightly runner and historical reference tables.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$script_dir/../.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/package/tools" "$work/package/data"
printf '1\n2\n3\n' > "$work/package/data/labels_f05.txt"
printf '# scorer validated by the report suite\n' > "$work/package/tools/acc3.py"
# The active runner must use the documented settings and propagate failures.
printf x > "$work/package/data/particles_f05.mrcs"
printf x > "$work/package/data/truth_f05.txt"
cat > "$work/package/tools/f05_tables.py" <<'TABLES'
import os, sys
out = sys.argv[2]
open(os.path.join(out, 'labels_f05.txt'), 'w').write('1\n2\n3\n')
open(os.path.join(out, 'oritab_zero.txt'), 'w').write('e1=0 e2=0 e3=0 x=0 y=0 state=1\n')
TABLES
export MOCK_COMMANDS="$work/commands" MOCK_MODE=success
# Record the actual arguments; create the project chain the next command reads.
simple_exec() {
    printf '%s\n' "$*" >> "$MOCK_COMMANDS"
    case $1 in
        prg=new_project) printf project > snr005.simple ;;
        prg=import_particles)
            [[ -s snr005.simple && -s oritab_zero.txt ]] || return 1
            mkdir 1_import_particles
            cp snr005.simple 1_import_particles/snr005.simple ;;
        prg=solve2D)
            [[ -s 1_import_particles/snr005.simple ]] || return 1
            mkdir 2_solve2D
            cp snr005.simple 2_solve2D/snr005.simple ;;
        prg=solve3D)
            [[ -s 2_solve2D/snr005.simple ]] || return 1
            [[ $MOCK_MODE != command_failure ]] || return 7
            mkdir -p 3_solve3D/state_exports
            if [[ $MOCK_MODE != missing_states ]]; then
                printf '# pind state updatecnt\n1 1 1\n2 2 1\n3 3 1\n' > 3_solve3D/state_exports/states_iter085.txt
            fi
            [[ $MOCK_MODE != error_log ]] || echo 'ERROR STOP'
            [[ $MOCK_MODE != skipped_rec ]] || echo '>>> FINAL ALL-PARTICLE RECONSTRUCTION SKIPPED'
            [[ $MOCK_MODE == incomplete ]] || echo 'SIMPLE_SOLVE3D NORMAL STOP' ;;
    esac
}
export -f simple_exec
# Shell-function mocks work on runners whose /tmp is mounted noexec.
sha256sum() { printf '%064d  %s\n' 0 "$1"; }
export -f sha256sum
for mode in success command_failure error_log skipped_rec incomplete missing_states; do
    mkdir "$work/runner-$mode"
    if (
        cd "$work/runner-$mode"
        export MOCK_MODE=$mode SNR005_PACKAGE="$work/package" SIMPLE_SEED=20261113
        bash "$root/snr005.sh"
    ); then
        [[ $mode == success ]] || { echo "FAIL: runner accepted $mode" >&2; exit 1; }
    else
        [[ $mode != success ]] || { echo 'FAIL: documented runner failed' >&2; exit 1; }
    fi
done
grep -Fq 'prg=solve2D projfile=1_import_particles/snr005.simple ncls=30 mskdiam=300 nthr=16' "$MOCK_COMMANDS"
grep -Fq 'prg=solve3D projfile=2_solve2D/snr005.simple pgrp=c1 mskdiam=300 nstates=3 nparts=2 nthr=8 print_states=yes' "$MOCK_COMMANDS"
grep -q $'^seed\t20261113$' "$work/runner-success/snr005/runtime.tsv"
grep -q $'^simple_exec_sha256\t' "$work/runner-success/snr005/runtime.tsv"
! grep -q '^finished_utc' "$work/runner-error_log/snr005/runtime.tsv"
echo 'SNR005 active runner and incomplete-run checks passed.'

mkdir "$work/package/results"
printf 'run\taccuracy\n1\t0.9962\n' > "$work/package/results/summary.tsv"
cat > "$work/package/README.md" <<'REFERENCE'
# Retained benchmark reference

| Run | Final accuracy | Recall (1 / 2 / 3) | ARI | Verdict | Wall time |
|---|---|---|---|---|---|
| 1 | 0.9962 | 0.998 / 0.995 / 0.999 | 0.988 | separated | 7 h 27 min |
| 5 | 0.9692 at iteration 82 (stopped) | 0.990 / 0.954 / 1.000 | 0.919 | separated so far | – |

| Run | Stage 1 (30 Å) | Stage 2 |
|---|---|---|
| 1 | 0.789 | 0.665 |

| Stage | 1 | 2 |
|---|---|---|
| Iterations | 20 | 20 |
| Time | 5 min | 14 min |

| Run | 8C9C (state 1) | 8C96 (state 2) |
|---|---|---|
| 1 | **wrong** (best match cc 0.35) | cc 0.995 |
REFERENCE
SNR005_PACKAGE="$work/package" REPORT_SITE_DIR="$work/reference-site" \
    bash "$root/make_report.sh" "$work/package"
for expected in 'Final accuracy' 'Wall time' '7 h 27 min' 'stopped' 'Stage 1' 'Iterations' 'cc 0.995' 'wrong'; do
    grep -q "$expected" "$work/reference-site/index.html" || { echo "Missing reference $expected" >&2; exit 1; }
done
cmp "$work/package/README.md" "$work/reference-site/snr005_nightly/reference_README.txt"
echo 'SNR005 historical-reference checks passed.'
