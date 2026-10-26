#!/usr/bin/env bash
# Small deterministic fixtures: no SIMPLE jobs or real volumes are needed.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/math.awk" <<'AWK'
function check(ok,message) {if(!ok){print "FAIL: " message > "/dev/stderr";exit 1}}
BEGIN {
    rotation(0,0,0,a);rotation(0,0,45,b);check((angle(a,b)-45)^2<1e-12,"known 45 degree rotation")
    rotation(31,77,13,a)
    for(s=1;s<=4;s++){for(j=1;j<=9;j++)b[j]=a[j]*sym[s,(j-1)%3+1];check(angle(a,b)<0.00001,"D2 equivalent rotation")}
    for(j=1;j<=4;j++)data["test",j]=10*(j-1)
    stats("test","initial",data,4);check(med["test","initial"]==15 && pctl["test","initial"]==30,"median and nearest rank P90")
}
AWK
gawk -f "$script_dir/streptavidin_pose_diagnostics.awk" -f "$work/math.awk" </dev/null
mkdir -p "$work/run/preparation"
printf 'e1=0 e2=0 e3=0 x=0 y=0 state=1 eo=1 indstk=1\n' > "$work/run/preparation/original_poses.txt"
printf 'testing_commit\tabc123\nstatus\tCOMPLETED\nexit_code\t0\n' > "$work/run/RUN_METADATA.tsv"
printf 'requested_maxits\tautomatic\n' > "$work/run/inputs.tsv"
for angle in 5 10 15 20 25; do
    dir="$work/run/01_refine3D_auto_pose_error_$angle"
    mkdir -p "$dir/initial" "$dir/BENCH"
    printf 'e1=0 e2=0 e3=20 x=3 y=0 state=1 eo=1 indstk=1\n' > "$dir/initial/poses.txt"
    printf 'e1=0 e2=0 e3=10 x=1 y=0 state=1 eo=1 indstk=1\n' > "$dir/final_poses.txt"
    cat > "$dir/LOG" <<'LOG'
SIMPLE Git Commit: abcdef123
>>> REFINE3D_AUTO MAXITS: 2
>>> ITERATION 1
RESOLUTION @ FSC=0.5 AVG/SDEV/MIN/MAX: 4.0 0 0 0
RESOLUTION @ FSC=0.143 AVG/SDEV/MIN/MAX: 3.2D0 0 0 0
(cFAR) STATE 1: 0.8
>>> CONVERGED: yes, continuing until minimum iteration count (1/2)
>>> CONVERGED: no
>>> ITERATION 2
RESOLUTION @ FSC=0.5 AVG/SDEV/MIN/MAX: 3.8 0 0 0
RESOLUTION @ FSC=0.143 AVG/SDEV/MIN/MAX: 3.0 0 0 0
(cFAR) STATE 1: 0.9
>>> CONVERGED: yes
RESOLUTION @ FSC=0.5 AVG/SDEV/MIN/MAX: 99 0 0 0
SIMPLE_REFINE3D NORMAL STOP
Execution time: 4.2D0 seconds
LOG
    printf 'phase\tstarted_epoch\tfinished_epoch\telapsed_seconds\texit_code\nreconstruct\t0\t2\t2\t0\nrefine\t2\t7\t5\t0\n' > "$dir/STEP_TIMING.tsv"
    printf '*** BENCHMARK RECORD ***\nmatch3D refine mode : cont\nmatch3D cont calls : 12\n' > "$dir/BENCH/REFINE3D_BENCH_PART1.txt"
    printf '0\n' > "$dir/EXIT_CODE_JOB_1"
    touch "$dir/initial/recvol_state01.mrc" "$dir/rec_final_state01.mrc" "$dir/recvol_state01_iter01_lp.mrc" "$dir/recvol_state01_iter02_lp.mrc"
done
cat > "$work/compare.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'resolution_angstrom,fsc\n10,0.9\n5,0.4\n2,0.1\n' > "$4/truth_fsc.csv"
printf '0.8|0.9|mirrored|6|3\n'
MOCK
touch "$work/truth.mrc"
bash "$script_dir/streptavidin_pose_diagnostics.sh" "$work/run" "$work/report" "$work/compare.sh" "$work/truth.mrc" > "$work/collector.log"
[[ $(cat "$work/report/status.txt") == complete ]]
[[ $(wc -l < "$work/report/summary.csv") == 6 ]]
gawk -F, 'NR>1 {if($2!=2 || $5!=1 || $6!="\"yes\"" || $8!=5 || $9!=2)exit 1}' "$work/report/summary.csv"
gawk -F, 'NR>1 {if(($4-20)^2>1e-10 || ($5-10)^2>1e-10 || $9!=100)exit 1}' "$work/report/pose_summary.csv"
gawk -F, 'NR>1 {if($3>4 || $4>4)exit 1}' "$work/report/internal_iterations.csv"
[[ $(find "$work/report" -maxdepth 1 -name '*.svg' | wc -l) == 5 ]]
# Entirely below and entirely above a threshold must not be reported as crossings.
printf 'resolution_angstrom,fsc\n10,0.1\n2,0.08\n' > "$work/curve.csv"
result=$(gawk -v mode=curve -v curve="$work/curve.csv" -f "$script_dir/streptavidin_pose_diagnostics.awk")
[[ $result == no_downward_crossing_in_sampled_range$'\t'no_downward_crossing_in_sampled_range$'\t'2 ]]
printf 'resolution_angstrom,fsc\n10,0.9\n2,0.8\n' > "$work/curve.csv"
result=$(gawk -v mode=curve -v curve="$work/curve.csv" -f "$script_dir/streptavidin_pose_diagnostics.awk")
[[ $result == above_threshold_through_endpoint$'\t'above_threshold_through_endpoint$'\t'2 ]]
# One case loses optional diagnostics; independent pose/reference evidence survives.
sed -i '/cFAR/d' "$work/run/01_refine3D_auto_pose_error_5/LOG"
rm "$work/run/01_refine3D_auto_pose_error_5/BENCH/REFINE3D_BENCH_PART1.txt" "$work/run/01_refine3D_auto_pose_error_5/EXIT_CODE_JOB_1"
bash "$script_dir/streptavidin_pose_diagnostics.sh" "$work/run" "$work/partial" "$work/compare.sh" "$work/truth.mrc" > "$work/partial.log"
[[ $(cat "$work/partial/status.txt") == partial ]]
[[ $(wc -l < "$work/partial/pose_summary.csv") == 6 ]]
rg -q 'cFAR unavailable' "$work/partial/diagnostic_notices.csv"
# Missing evidence still produces identity, five case rows and placeholder figures.
mkdir -p "$work/empty"
bash "$script_dir/streptavidin_pose_diagnostics.sh" "$work/empty" "$work/missing" "$work/compare.sh" "$work/truth.mrc"
[[ $(cat "$work/missing/status.txt") == partial ]]
[[ $(wc -l < "$work/missing/summary.csv") == 6 ]]
rg -q 'Run identity and timing' "$work/missing/fragment.html"
echo 'Pose diagnostics shell/awk checks passed.'
