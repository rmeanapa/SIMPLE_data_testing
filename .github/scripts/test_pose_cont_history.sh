#!/usr/bin/env bash
# Offline Actions fixtures: pagination, cached/legacy metrics, reruns, SVG gaps.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$work/site/reports" "$work/report" "$work/legacy"
printf '%s\n' '<html><p>SIMPLE test run</p></html>' > "$work/site/index.html"
cp "$work/site/index.html" "$work/site/reports/report_betagal_pose_cont.html"
row() {
    jq -cn --argjson id "$1" --argjson attempt "$2" --arg date "$3" \
        '{id:$id,run_number:$id,run_attempt:$attempt,created_at:$date,head_sha:"abcdef123456",
          html_url:("https://example.test/runs/"+($id|tostring)+"?a=1&b=2")}'
}
row 101 1 2026-10-27T00:00:00Z > "$work/run101.json"
row 102 2 2026-10-28T00:00:00Z > "$work/run102.json"
row 103 1 2026-10-28T12:00:00Z > "$work/run103.json"
row 200 1 2026-10-29T00:00:00Z > "$work/current.json"
jq -n --slurpfile a "$work/run101.json" --slurpfile b "$work/run102.json" --slurpfile c "$work/run103.json" \
    '[{workflow_runs:$a},{workflow_runs:($b+$c)}]' > "$work/runs.json"
jq -n --slurpfile candidate "$work/run101.json" \
    '{successful_runs:[{id:90,run_number:90,run_attempt:1,created_at:"2026-10-26T00:00:00Z",
       head_sha:"old12345",html_url:"https://example.test/90",metrics:{default:{fsc05:"6",fsc0143:"5"}}},
      {id:102,run_number:102,run_attempt:1,metrics:{default:{fsc05:"99"}}}],
      current_run:($candidate[0]+{metrics:{default:{fsc05:"9"}}})}' > "$work/report/pose_cont_history.json"
printf 'arm\tfsc05\tfsc0143\ndefault\t4\t3\nyes\t5\t4\nonly\t6\t5\n' > "$work/report/pose_cont_metrics.tsv"
(cd "$work/report" && zip -q "$work/11.zip" pose_cont_history.json pose_cont_metrics.tsv)
for arm in default yes only; do
    mkdir "$work/legacy/00_refine3D_auto_pose_cont_$arm"
    cat > "$work/legacy/00_refine3D_auto_pose_cont_$arm/LOG" <<'LOG'
>>> PROGRAM: refine3D_auto
RESOLUTION AT FSC=0.500 DETERMINED TO: 3.25
RESOLUTION AT FSC=0.143 DETERMINED TO: 2.75
SIMPLE_REFINE3D NORMAL STOP
LOG
done
# An absent arm value must break the plotted line, rather than becoming zero.
printf 'SIMPLE_REFINE3D NORMAL STOP\n' > "$work/legacy/00_refine3D_auto_pose_cont_default/LOG"
(cd "$work/legacy" && zip -qr "$work/12.zip" .)
printf corrupt > "$work/13.zip"
printf 'arm\tfsc05\tfsc0143\ndefault\t3\t2.5\nyes\t3.5\t3\nonly\t4\t3.5\n' > "$work/site/pose_cont_metrics.tsv"
export MOCK_GITHUB="$work" GH_REPO=example/testing GH_TOKEN=fixture GITHUB_RUN_ID=200
# Exported functions work even when /tmp is mounted noexec.
gh() {
    local endpoint=${!#}
    case $endpoint in
        */actions/workflows/*/runs\?*)
            [[ " $* " == *' --paginate '* && " $* " == *' --slurp '* ]] || return 1
            cat "$MOCK_GITHUB/runs.json";;
        */actions/runs/101/artifacts\?*) printf '[{"artifacts":[{"id":11,"name":"betagal_pose_cont-report-site","expired":false}]}]\n';;
        */actions/runs/102/artifacts\?*) printf '[{"artifacts":[]},{"artifacts":[{"id":12,"name":"betagal_pose_cont-legacy","expired":false}]}]\n';;
        */actions/runs/103/artifacts\?*) printf '[{"artifacts":[{"id":13,"name":"betagal_pose_cont-report-site","expired":false}]}]\n';;
        */actions/artifacts/11/zip) cat "$MOCK_GITHUB/11.zip";;
        */actions/artifacts/12/zip) cat "$MOCK_GITHUB/12.zip";;
        */actions/artifacts/13/zip) cat "$MOCK_GITHUB/13.zip";;
        */actions/runs/200) cat "$MOCK_GITHUB/current.json";;
        *) echo "Unexpected API request: $*" >&2; return 1;;
    esac
}
export -f gh
bash "$script_dir/pose_cont_history.sh" "$work/site" > "$work/history.log" 2>&1 || { cat "$work/history.log"; fail 'History helper failed'; }
jq -e '(.successful_runs|length)==4 and .current_run.id==200 and
    ([.successful_runs[]|select(.id==101)][0].metrics.default.fsc05)=="4" and
    ([.successful_runs[]|select(.id==102)][0] | .run_attempt==2 and .metrics.yes.fsc05=="3.25" and .metrics.default.fsc05==null) and
    ([.successful_runs[]|select(.id==90)]|length)==1' "$work/site/pose_cont_history.json" >/dev/null
grep -q '::warning::Cannot recover report archive for successful run 103' "$work/history.log"
grep -q '&amp;b=2' "$work/site/pose_cont_fsc_history.svg"
grep -q 'href="../pose_cont_fsc_history.svg"' "$work/site/reports/report_betagal_pose_cont.html"
[[ $(grep -c 'stroke="#2563eb" stroke-width="2"' "$work/site/pose_cont_fsc_history.svg") == 3 ]] || fail 'Missing FSC did not interrupt lines'
[[ $(grep -c '<tr><td>' "$work/site/index.html") == 15 ]] || fail 'History table lost runs'
# Adding history again must replace the section, rather than duplicate it.
bash "$script_dir/pose_cont_history.sh" "$work/site" > "$work/repeat.log" 2>&1
[[ $(grep -c '<section id="pose-cont-history">' "$work/site/index.html") == 1 ]] || fail 'Repeated history duplicated'
# No successful runs and no current Actions ID still produce a valid empty graph.
printf '[{"workflow_runs":[]}]\n' > "$work/runs.json"
mkdir "$work/empty"
printf '<html><p>SIMPLE test run</p></html>\n' > "$work/empty/index.html"
env -u GITHUB_RUN_ID bash -c 'bash "$1" "$2"' fixture "$script_dir/pose_cont_history.sh" "$work/empty" > "$work/empty.log" 2>&1
jq -e '.successful_runs==[] and .current_run==null' "$work/empty/pose_cont_history.json" >/dev/null
grep -q 'No FSC values available' "$work/empty/pose_cont_fsc_history.svg"
grep -q 'No FSC results found' "$work/empty/index.html"
echo 'Pose history pagination, cached/legacy recovery, reruns, graph gaps, and empty-history checks passed.'
