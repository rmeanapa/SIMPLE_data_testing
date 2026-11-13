#!/usr/bin/env bash
set -euo pipefail

package=${SNR005_PACKAGE:-/mnt/beegfs/elmlund/snr005_nightly_package}
for input in data/particles_f05.mrcs data/truth_f05.txt data/labels_f05.txt tools/f05_tables.py; do
    [[ -r "$package/$input" ]] || { echo "Missing benchmark input: $package/$input" >&2; exit 1; }
done

mkdir snr005
cd snr005
export SIMPLE_SEED=${SIMPLE_SEED:-20261113}

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

echo " >>> PROGRAM: solve3D" >> LOG
simple_exec prg=solve3D projfile=2_solve2D/snr005.simple \
    pgrp=c1 mskdiam=300 nstates=3 nparts=2 nthr=8 print_states=yes >> LOG 2>&1

grep -q 'SIMPLE_SOLVE3D NORMAL STOP' LOG
