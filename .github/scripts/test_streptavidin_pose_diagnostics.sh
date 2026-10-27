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
[[ $(find "$work/report" -maxdepth 1 -name '*.svg' | wc -l) == 10 ]]
# Scatter points preserve paired values and original particle rows; no sorting/decimation.
cat > "$work/scatter.awk" <<'AWK'
BEGIN {
    compared["paired"]=3; recovery["paired"]=100/3
    ai["paired",1]=20; af["paired",1]=10; pose_row["paired",1]=2
    ai["paired",2]=5; af["paired",2]=25; pose_row["paired",2]=7
    ai["paired",3]=15; af["paired",3]=15; pose_row["paired",3]=9
    draw_pose_scatter("paired", scatter, 30)
    draw_pose_scatter("missing", missing, 30)
}
AWK
gawk -v scatter="$work/scatter.svg" -v missing="$work/no_pairs.svg" -f "$script_dir/streptavidin_pose_diagnostics.awk" -f "$work/scatter.awk" </dev/null
[[ $(grep -c 'class="pose-particle"' "$work/scatter.svg") == 3 ]]
grep -q 'data-particle-row="2" cx="315.000" cy="310.000".*fill="#0072b2"' "$work/scatter.svg"
grep -q 'data-particle-row="7" cx="135.000" cy="130.000".*fill="#d55e00"' "$work/scatter.svg"
grep -q 'data-particle-row="9" cx="255.000" cy="250.000".*fill="#777777"' "$work/scatter.svg"
grep -q 'no valid particle pairs' "$work/no_pairs.svg"
for angle in 5 10 15 20 25; do
    grep -q 'pose_angle_scatter_pose_error_'"$angle"'.svg' "$work/report/fragment.html"
    [[ $(grep -c 'class="pose-particle"' "$work/report/pose_angle_scatter_pose_error_$angle.svg") == 1 ]]
done
# Exercise native pose loading, active-row filtering and shared limits end to end.
# The independently ordered pairs would expose accidental percentile sorting.
printf 'e1=0 e2=0 e3=0 x=0 y=0 state=0\ne1=0 e2=0 e3=0 x=0 y=0 state=1\ne1=0 e2=0 e3=0 x=0 y=0 state=1\ne1=0 e2=0 e3=0 x=0 y=0 state=1\n' > "$work/run/preparation/original_poses.txt"
for angle in 5 10 15 20 25; do
    dir="$work/run/01_refine3D_auto_pose_error_$angle"
    initial=20
    [[ $angle != 25 ]] || initial=40
    printf 'e1=0 e2=0 e3=0 x=0 y=0 state=0\ne1=0 e2=0 e3=%s x=0 y=0 state=1\ne1=0 e2=0 e3=5 x=0 y=0 state=1\ne1=0 e2=0 e3=15 x=0 y=0 state=1\n' "$initial" > "$dir/initial/poses.txt"
    printf 'e1=0 e2=0 e3=0 x=0 y=0 state=0\ne1=0 e2=0 e3=10 x=0 y=0 state=1\ne1=0 e2=0 e3=25 x=0 y=0 state=1\ne1=0 e2=0 e3=15 x=0 y=0 state=1\n' > "$dir/final_poses.txt"
done
bash "$script_dir/streptavidin_pose_diagnostics.sh" "$work/run" "$work/paired" "$work/compare.sh" "$work/truth.mrc" > "$work/paired.log"
[[ $(wc -l < "$work/paired/pose_disagreements.csv") == 16 ]]
for angle in 5 10 15 20 25; do
    svg="$work/paired/pose_angle_scatter_pose_error_$angle.svg"
    [[ $(grep -c 'class="pose-particle"' "$svg") == 3 ]]
    # A 45-degree shared range gives eight SVG units per degree on both axes.
    cx=235
    initial=20
    if [[ $angle == 25 ]]; then cx=395; initial=40; fi
    grep -q 'data-particle-row="2" cx="'"$cx"'.000" cy="350.000".*fill="#0072b2".*Particle row 2: initial '"$initial"' deg, final 10 deg; closer' "$svg"
    grep -q 'data-particle-row="3" cx="115.000" cy="230.000".*fill="#d55e00".*Particle row 3: initial 5 deg, final 25 deg; farther' "$svg"
    grep -q 'data-particle-row="4" cx="195.000" cy="310.000".*fill="#777777".*Particle row 4: initial 15 deg, final 15 deg; unchanged' "$svg"
    grep -q 'text-anchor="end">45</text>' "$svg"
    grep -q 'text-anchor="middle">45</text>' "$svg"
done
gawk -F, 'NR>1 {expected=($1=="\"pose_error_25\"" ? 40 : 20); if(($2==2 && (($3-expected)^2>1e-10 || ($4-10)^2>1e-10)) || ($2==3 && (($3-5)^2>1e-10 || ($4-25)^2>1e-10)) || ($2==4 && (($3-15)^2>1e-10 || ($4-15)^2>1e-10)) || $2<2 || $2>4)exit 1}' "$work/paired/pose_disagreements.csv"
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
for angle in 5 10 15 20 25; do
    svg="$work/missing/pose_angle_scatter_pose_error_$angle.svg"
    grep -q 'no valid particle pairs' "$svg"
    ! grep -q 'class="pose-particle"' "$svg"
done
rg -q 'Run identity and timing' "$work/missing/fragment.html"
echo 'Pose diagnostics shell/awk checks passed.'
