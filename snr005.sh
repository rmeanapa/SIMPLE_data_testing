#!/usr/bin/env bash
set -euo pipefail

package=${SNR005_PACKAGE:-/mnt/beegfs/elmlund/snr005_nightly_package}
for input in data/particles_f05.mrcs data/truth_f05.txt data/labels_f05.txt tools/f05_tables.py tools/acc3.py; do
    [[ -r "$package/$input" ]] || { echo "Missing benchmark input: $package/$input" >&2; exit 1; }
done

seed=${SIMPLE_SEED:-20261113}
[[ $seed =~ ^[0-9]+$ ]] || { echo "SIMPLE_SEED must be a nonnegative integer" >&2; exit 2; }
executable=$(command -v simple_exec)
mkdir snr005
cd snr005
export SIMPLE_SEED=$seed
export OPENBLAS_NUM_THREADS=1 OMP_WAIT_POLICY=PASSIVE
printf 'field\tvalue\nseed\t%s\nexecutable\t%s\n' "$seed" "$executable" > runtime.tsv
printf 'simple_exec_sha256\t%s\n' "$(sha256sum "$executable" | awk '{print $1}')" >> runtime.tsv
printf 'started_utc\t%s\nhost\t%s\n' "$(date -u +%FT%TZ)" "$(hostname)" >> runtime.tsv

python3 -I "$package/tools/f05_tables.py" "$package/data/truth_f05.txt" . > LOG 2>&1
cmp "$package/data/labels_f05.txt" labels_f05.txt

echo " >>> PROGRAM: new_project" >> LOG
simple_exec prg=new_project projname=snr005 dir=./ >> LOG 2>&1

echo " >>> PROGRAM: import_particles" >> LOG
simple_exec prg=import_particles projfile=snr005.simple \
    stk="$package/data/particles_f05.mrcs" oritab=oritab_zero.txt \
    ctf=yes smpd=3 kv=300 cs=2.7 fraca=0.07 >> LOG 2>&1

echo " >>> PROGRAM: solve2D" >> LOG
simple_exec prg=solve2D projfile=1_import_particles/snr005.simple \
    ncls=30 mskdiam=300 nthr=16 >> LOG 2>&1

solve3d_start=$SECONDS
echo " >>> PROGRAM: solve3D" >> LOG
simple_exec prg=solve3D projfile=2_solve2D/snr005.simple \
    pgrp=c1 mskdiam=300 nstates=3 nparts=2 nthr=8 print_states=yes >> LOG 2>&1

grep -q 'SIMPLE_SOLVE3D NORMAL STOP' LOG
if grep -qE '^ERROR!|ERROR STOP|FINAL ALL-PARTICLE RECONSTRUCTION SKIPPED' LOG; then
    echo 'solve3D reported an error or skipped final reconstruction' >&2
    exit 1
fi
final_state=$(find 3_solve3D -type f -name 'states_iter*.txt' -size +0c -print -quit)
[[ -n $final_state ]] || { echo 'Missing final iteration state assignments' >&2; exit 1; }
printf 'solve3d_seconds\t%s\nfinished_utc\t%s\n' \
    "$((SECONDS - solve3d_start))" "$(date -u +%FT%TZ)" >> runtime.tsv
