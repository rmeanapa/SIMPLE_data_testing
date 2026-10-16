mkdir -p betagal_pose_cont; cd betagal_pose_cont
simple_exec prg=new_project projname=betagal dir=./ > LOG 2>&1
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/betagal/movies >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=1.4 fraca=0.1 kv=200 smpd=0.885 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
simple_exec prg=motion_correct nparts=24 nthr=1 gainref=/mnt/beegfs/elmlund/testing-datasets/betagal/gain/gain.mrc total_dose=30.65 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=24 nthr=1 projfile=2_motion_correct/betagal.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/betagal.simple nparts=24 nthr=1 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=24 nthr=1 projfile=4_pick/betagal.simple >> LOG 2>&1
echo " >>> PROGRAM: solve2D" >> LOG 2>&1
simple_exec prg=solve2D ncls=90 mskdiam=180 nthr=20 nparts=4 >> LOG 2>&1
echo " >>> PROGRAM: model_cavgs_rejection" >> LOG 2>&1
simple_exec prg=model_cavgs_rejection mskdiam=180 nthr=20 >> LOG 2>&1
echo " >>> PROGRAM: solve3D_cavgs" >> LOG 2>&1
simple_exec prg=solve3D_cavgs pgrp=d2 mskdiam=180 nthr=40 >> LOG 2>&1
echo " >>> PROGRAM: solve3D" >> LOG 2>&1
simple_exec prg=solve3D pgrp=d2 mskdiam=180 nthr=8 nparts=10 cavg_ini_ext=yes >> LOG 2>&1
grep -q 'SIMPLE_SOLVE3D NORMAL STOP' LOG || {
    echo "ERROR: solve3D did not complete normally; inspect $PWD/LOG" >&2
    exit 1
}

# Copy the same solve3D project into each arm; share the input volumes.
set -euo pipefail
source_root=$(pwd -P)
# SIMPLE stage numbers define the latest output, rather than modification time.
solve_dir=""
latest_stage=-1
for candidate in "$source_root"/*_solve3D; do
    [[ -d "$candidate" ]] || continue
    stage=${candidate##*/}
    stage=${stage%_solve3D}
    [[ "$stage" =~ ^[0-9]+$ ]] || continue
    if (( 10#$stage > latest_stage )); then
        latest_stage=$((10#$stage))
        solve_dir="$candidate"
    fi
done
[[ -n "$solve_dir" ]] || {
    echo "ERROR: no numbered solve3D output directory found" >&2
    exit 1
}
for input in betagal.simple recvol_state01.mrc; do
    [[ -s "$solve_dir/$input" ]] || {
        echo "ERROR: latest solve3D output is missing or empty: $solve_dir/$input" >&2
        exit 1
    }
done
echo "Using solve3D output: $solve_dir"
arms_root="$source_root"
for arm in 10_pose_cont_default 11_pose_cont_yes 12_pose_cont_only; do
    mkdir "$arms_root/$arm"
    cp -p "$solve_dir/betagal.simple" "$arms_root/$arm/betagal.simple"
done

cd "$arms_root/10_pose_cont_default"
echo " >>> PROGRAM: refine3D_auto" > LOG 2>&1
simple_exec prg=refine3D_auto pgrp=d2 mskdiam=180 nparts=10 nthr=8 \
    projfile="betagal.simple" vol1="$solve_dir/recvol_state01.mrc" mkdir=no >> LOG 2>&1

cd "$arms_root/11_pose_cont_yes"
echo " >>> PROGRAM: refine3D_auto" > LOG 2>&1
simple_exec prg=refine3D_auto pose_cont=yes pgrp=d2 mskdiam=180 nparts=10 nthr=8 \
    projfile="betagal.simple" vol1="$solve_dir/recvol_state01.mrc" mkdir=no >> LOG 2>&1
    
cd "$arms_root/12_pose_cont_only"
echo " >>> PROGRAM: refine3D_auto" > LOG 2>&1
simple_exec prg=refine3D_auto pose_cont=only pgrp=d2 mskdiam=180 nparts=10 nthr=8 \
    projfile="betagal.simple" vol1="$solve_dir/recvol_state01.mrc" mkdir=no >> LOG 2>&1
