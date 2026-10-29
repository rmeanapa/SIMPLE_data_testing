#!/usr/bin/env bash
# Offline fixtures: no Slurm, GitHub access, or scientific data required.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$script_dir/../.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$work/build/bin" "$work/recipes"
ln -s /usr/bin/true "$work/build/bin/simple_exec"
cat > "$work/recipes/betagal.sh" <<'RECIPE'
mkdir -p betagal; cd betagal
simple_exec prg=solve3D_cavgs pgrp=d2 >> LOG 2>&1
simple_exec prg=solve3D pgrp=d2 >> LOG 2>&1
simple_exec prg=refine3D_auto pgrp=d2 >> LOG 2>&1
RECIPE
bash "$root/run_topk_comparison.sh" "$work/dry" --build "$work/build" --dry-run > "$work/dry.json"
jq -e '.datasets==["betagal","apof","proteasome"] and .topk==[1,3,5,10]' "$work/dry.json" >/dev/null
[[ ! -e $work/dry ]] || fail 'Dry run created output'
simple_exec() {
    local word program=''
    for word in "$@"; do case $word in prg=*) program=${word#prg=};; esac; done
    printf '%s\t%s\n' "$SIMPLE_SEED" "$*" >> "$MOCK_CALLS"
    if [[ ${MOCK_FAIL:-no} == yes && " $* " == *' topk=3 '* ]]; then
        echo 'fixture failure'; return 7
    fi
    mkdir "1_$program"
    printf project > "1_$program/betagal.simple"
    printf map > "1_$program/rec_final_state01.mrc"
    if [[ $program == solve3D ]]; then echo 'SIMPLE_SOLVE3D NORMAL STOP'
    else echo 'SIMPLE_REFINE3D NORMAL STOP'; fi
}
export -f simple_exec
export MOCK_CALLS="$work/calls.tsv"
bash "$root/run_topk_comparison.sh" "$work/output" --checkout "$work/recipes" --build "$work/build" --datasets betagal > "$work/run.log" 2>&1
jq -e '.status=="complete" and (.results|length)==8 and
    [.results[].topk]==[1,3,5,10,1,3,5,10]' "$work/output/campaign.json" >/dev/null
# Check actual command arguments, shared starts, backend, and seed.
awk -F '\t' '
  NR==1 {seed=$1; next}
  {if($1!=seed)exit 1; n++; split($2,args," "); source=""; backend="";
   for(i in args){if(args[i]~/^projfile=/)source=args[i];if(args[i]=="rec_backend=gridding")backend=1}
   if(!backend || source=="")exit 1;
   group=n<=4?1:2;if(!(group in starts))starts[group]=source;else if(starts[group]!=source)exit 1}
  END {if(n!=8)exit 1}
' "$MOCK_CALLS" || fail 'Incorrect paired starts, seed, or backend'
baseline=$(jq -r '.results[0].project' "$work/output/campaign.json")
grep -F "projfile=$baseline" "$MOCK_CALLS" | [[ $(wc -l) == 4 ]] || fail 'Refinement did not share topk=1 solve'
count=$(wc -l < "$MOCK_CALLS")
if bash "$root/run_topk_comparison.sh" "$work/output" --checkout "$work/recipes" --build "$work/build" --datasets betagal > "$work/reused.log" 2>&1; then fail 'Old output reused'; fi
[[ $(wc -l < "$MOCK_CALLS") == "$count" ]] || fail 'Reuse ran commands'
if MOCK_FAIL=yes bash "$root/run_topk_comparison.sh" "$work/failed" --checkout "$work/recipes" --build "$work/build" --datasets betagal > "$work/failed.log" 2>&1; then fail 'Failed arm accepted'; fi
jq -e '.status=="failed" and has("error") and (.results|length)==1' "$work/failed/campaign.json" >/dev/null
# Report fixtures: completed, failed, missing FSC, and an absent dataset.
for k in 1 3 5; do
    arm="$work/campaign/betagal/betagal/solve3D/topk$k"
    mkdir -p "$arm"
    cat > "$arm/LOG" <<'LOG'
>>> PROGRAM: solve3D
RESOLUTION AT FSC=0.500 DETERMINED TO: 4.25
RESOLUTION AT FSC=0.143 DETERMINED TO: 3.50
SIMPLE_SOLVE3D NORMAL STOP
LOG
    if [[ $k == 3 ]]; then echo 'ERROR STOP fixture failure' >> "$arm/LOG"; fi
    if [[ $k == 5 ]]; then echo 'SIMPLE_SOLVE3D NORMAL STOP' > "$arm/LOG"; fi
done
jq -n '{status:"failed",error:"<fixture>",seed:20261029,binary_sha256:"fixture-hash",
    results:[{program:"solve3D",topk:1,seconds:120},{program:"solve3D",topk:5,seconds:120}]}' > "$work/campaign/betagal/campaign.json"
bash "$script_dir/topk_report.sh" "$work/campaign" "$work/site"
jq -e '(.results|length)==24 and .results[0].fsc05==4.25 and .results[0].fsc0143==3.5 and
    .results[1].status=="failed" and .results[1].fsc05=="" and
    .results[2].status=="complete; FSC unavailable" and .results[3].status=="missing"' "$work/site/results.json" >/dev/null
grep -q '&lt;fixture&gt;' "$work/site/index.html"
grep -q '2/8 completed' "$work/site/index.html"
[[ -z $(find "$work/site" -name '*.mrc' -print -quit) ]] || fail 'Volume copied to webpage'
bash "$script_dir/topk_report.sh" "$work/absent" "$work/empty-site"
grep -q '0/8 completed' "$work/empty-site/index.html"
# Submission waits and propagates a failed job, without requiring installed Slurm.
sbatch() {
    [[ " $* " == *' --wait '* && " $* " == *' --cpus-per-task=80 '* ]] || return 9
    cat > /dev/null
    printf '12345\n'
    [[ " $* " != *' --job-name=simple-topk-apof '* ]]
}
export -f sbatch
if SIMPLE_PATH="$work/build" bash "$root/submit_topk_comparison.sh" "$work/submitted" > "$work/submitted.log" 2>&1; then fail 'Failed Slurm job accepted'; fi
[[ $(wc -l < "$work/submitted/jobs.tsv") == 3 ]] || fail 'Did not submit three datasets'
grep -q 'Failed: apof' "$work/submitted.log"
echo 'Top-k recipes, paired starts, failure handling, reports, and Slurm checks passed.'
