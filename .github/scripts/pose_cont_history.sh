#!/usr/bin/env bash
# Recover Actions metrics (including legacy LOGs) and add the FSC history report.
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 REPORT_SITE_DIRECTORY" >&2; exit 2; }
: "${GH_REPO:?Set GH_REPO to owner/repository}"
export GH_TOKEN=${GH_TOKEN:-${GITHUB_TOKEN:-}}
: "${GH_TOKEN:?Set GH_TOKEN or GITHUB_TOKEN to read Actions history}"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
site=$(realpath -- "$1")
[[ -f $site/index.html ]] || { echo 'Current report is missing' >&2; exit 1; }
for target in "$site/index.html" "$site/reports/report_betagal_pose_cont.html"; do
    [[ ! -f $target ]] || grep -qF '<p>SIMPLE test run</p>' "$target" || {
        echo "Report insertion point missing: $target" >&2; exit 1;
    }
done
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
api_root="${GITHUB_API_URL:-https://api.github.com}/repos/$GH_REPO"
# gh handles signed archive redirects without forwarding the API token.
pages() { gh api --paginate --slurp "$api_root/$1"; }
metrics_json() {
    jq -Rn '[inputs | split("\t") | select(.[0]=="default" or .[0]=="yes" or .[0]=="only") |
        {key:.[0],value:{fsc05:(if .[1]=="" then null else .[1] end),
                        fsc0143:(if .[2]=="" then null else .[2] end)}}] | from_entries' "$1"
}
# Stream only known members; never extract archive paths into the filesystem.
member() {
    local archive=$1 name=$2
    [[ $name != *[\\\*\?\[\]]* && $name != *[[:cntrl:]]* ]] || return 1
    unzip -p "$archive" "$name"
}
legacy_metrics() {
    local artifacts=$1 directory=$2 artifact name arm
    mkdir -p "$directory/betagal_pose_cont"
    artifact=$(jq -r '[.[] | select(.name|startswith("betagal_pose_cont-")) |
        select(.name!="betagal_pose_cont-report-site")] | first | .id // empty' "$artifacts")
    if [[ -z $artifact ]]; then printf '{}\n'; return; fi
    gh api "$api_root/actions/artifacts/$artifact/zip" > "$directory/legacy.zip" || return
    unzip -Z -1 "$directory/legacy.zip" > "$directory/members" || return
    while IFS= read -r name; do
        for arm in default yes only; do
            case $name in
                *_refine3D_auto_pose_cont_"$arm"/LOG)
                    mkdir -p "$directory/betagal_pose_cont/00_refine3D_auto_pose_cont_$arm"
                    member "$directory/legacy.zip" "$name" > "$directory/betagal_pose_cont/00_refine3D_auto_pose_cont_$arm/LOG" || return;;
            esac
        done
    done < "$directory/members"
    bash "$script_dir/../../make_report.sh" --pose-cont-metrics "$directory/betagal_pose_cont" > "$directory/metrics.tsv" || return
    metrics_json "$directory/metrics.tsv"
}
pages 'actions/workflows/betagal_pose_cont_test.yml/runs?status=success&per_page=100' > "$work/run-pages.json"
jq '[.[].workflow_runs[]]' "$work/run-pages.json" > "$work/runs.json"
printf '{}\n' > "$work/records.json"
jq -c '.[] | {id,run_number,run_attempt,created_at,head_sha,html_url}' "$work/runs.json" > "$work/run-rows.jsonl"
while IFS= read -r row; do
    key=$(jq -r '.id' <<< "$row")
    attempt=$(jq -r '.run_attempt' <<< "$row")
    # A cached earlier attempt must not suppress recovery for the current one.
    jq --arg key "$key" --argjson attempt "$attempt" '
        if .[$key]!=null and .[$key].run_attempt!=$attempt then del(.[$key]) else . end' \
        "$work/records.json" > "$work/checked.json"
    mv -- "$work/checked.json" "$work/records.json"
    if jq -e --arg key "$key" --argjson attempt "$attempt" \
        '.[$key] | (.metrics|length)>0 and .run_attempt==$attempt' "$work/records.json" >/dev/null; then continue; fi
    directory="$work/run-$key"
    mkdir "$directory"
    if pages "actions/runs/$key/artifacts?per_page=100" > "$directory/artifact-pages.json"; then
        jq '[.[].artifacts[] | select(.expired==false)]' "$directory/artifact-pages.json" > "$directory/artifacts.json"
        report=$(jq -r '[.[] | select(.name=="betagal_pose_cont-report-site")] | first | .id // empty' "$directory/artifacts.json")
        if [[ -n $report ]]; then
            if gh api "$api_root/actions/artifacts/$report/zip" > "$directory/report.zip" && unzip -Z -1 "$directory/report.zip" > "$directory/members"; then
                if grep -qxF pose_cont_history.json "$directory/members"; then
                    member "$directory/report.zip" pose_cont_history.json > "$directory/previous.json"
                    if jq -e . "$directory/previous.json" >/dev/null; then
                        jq --slurpfile previous "$directory/previous.json" --slurpfile runs "$work/runs.json" '
                            reduce ($previous[0].successful_runs[]?) as $row (.;
                                .[($row.id|tostring)] //= $row) |
                            $previous[0].current_run as $candidate |
                            if $candidate!=null and any($runs[0][]; .id==$candidate.id and .run_attempt==$candidate.run_attempt)
                            then .[($candidate.id|tostring)]=$candidate else . end' \
                            "$work/records.json" > "$directory/merged.json"
                        mv -- "$directory/merged.json" "$work/records.json"
                    else echo "::warning::Invalid cached history for successful run $key" >&2; fi
                fi
                if grep -qxF pose_cont_metrics.tsv "$directory/members"; then
                    member "$directory/report.zip" pose_cont_metrics.tsv > "$directory/metrics.tsv"
                    recovered=$(metrics_json "$directory/metrics.tsv")
                    row=$(jq -c --argjson metrics "$recovered" '.metrics=$metrics' <<< "$row")
                fi
            else echo "::warning::Cannot recover report archive for successful run $key" >&2; fi
        fi
        if ! jq -e '(.metrics|length)>0' <<< "$row" >/dev/null &&
           ! jq -e --arg key "$key" '(.[$key].metrics|length)>0' "$work/records.json" >/dev/null; then
            if recovered=$(legacy_metrics "$directory/artifacts.json" "$directory/legacy"); then
                row=$(jq -c --argjson metrics "$recovered" '.metrics=$metrics' <<< "$row")
            else echo "::warning::Cannot recover legacy metrics for successful run $key" >&2; fi
        fi
    else echo "::warning::Cannot list artifacts for successful run $key" >&2; fi
    jq --arg key "$key" --argjson row "$row" '
        if .[$key]==null or ($row.metrics|length)>0 then .[$key]=$row else . end' \
        "$work/records.json" > "$directory/updated.json"
    mv -- "$directory/updated.json" "$work/records.json"
done < "$work/run-rows.jsonl"
# Discard cached results from earlier attempts of rerun workflows.
jq --slurpfile runs "$work/runs.json" 'with_entries(. as $entry |
    select(all($runs[0][]; (.id|tostring)!=$entry.key or .run_attempt==$entry.value.run_attempt)))' \
    "$work/records.json" > "$work/filtered.json"
printf 'null\n' > "$work/current.json"
if [[ -n ${GITHUB_RUN_ID:-} ]]; then
    gh api "$api_root/actions/runs/$GITHUB_RUN_ID" > "$work/current-run.json"
    current_metrics='{}'
    [[ ! -f $site/pose_cont_metrics.tsv ]] || current_metrics=$(metrics_json "$site/pose_cont_metrics.tsv")
    jq --argjson metrics "$current_metrics" '{id,run_number,run_attempt,created_at,head_sha,html_url,metrics:$metrics}' \
        "$work/current-run.json" > "$work/current.json"
fi
jq -n --slurpfile records "$work/filtered.json" --slurpfile current "$work/current.json" \
    '{successful_runs:($records[0]|[.[]]),current_run:$current[0]}' > "$site/pose_cont_history.json"
# Numeric graph input is sanitized here; text/URLs are escaped for HTML/SVG.
jq -r '
    def positive: try (tonumber | if isfinite and .>0 then . else null end) catch null;
    .current_run as $current |
    [.successful_runs[] | select($current==null or .id!=$current.id)] +
        (if $current==null then [] else [$current] end) |
    sort_by(.created_at)[] |
    [.run_number,.run_attempt,(.created_at|@html),(.head_sha[0:8]|@html),(.html_url|@html),
      (.created_at|fromdateiso8601),
      (.metrics.default.fsc05|positive),(.metrics.yes.fsc05|positive),(.metrics.only.fsc05|positive),
      (.metrics.default.fsc0143|positive),(.metrics.yes.fsc0143|positive),(.metrics.only.fsc0143|positive)] | @tsv' \
    "$site/pose_cont_history.json" > "$work/graph.tsv"
TZ=UTC LC_ALL=C awk -f "$script_dir/pose_cont_history.awk" "$work/graph.tsv" > "$site/pose_cont_fsc_history.svg"
{
    printf '%s\n' '<section id="pose-cont-history"><h2>Actions history</h2>' \
        '<p>Final resolution in Å (lower is better). Each arm uses its final logged FSC estimate. Missing results are shown explicitly.</p>'
    cat "$site/pose_cont_fsc_history.svg"
    printf '%s\n' '<p><a href="pose_cont_fsc_history.svg" download>Download graph (SVG)</a></p>' \
        '<div style="overflow-x:auto"><table><thead><tr><th>Run / attempt</th><th>Started (UTC)</th><th>Commit</th><th>Comparison</th><th>FSC=0.5 (Å)</th><th>FSC=0.143 (Å)</th></tr></thead><tbody>'
    jq -r '
        def esc:tostring|@html;
        def show:if .==null or .=="" then "unavailable" else tostring end|@html;
        .current_run as $current |
        ([.successful_runs[]|select($current==null or .id!=$current.id)] +
          (if $current==null then [] else [$current] end) | sort_by(.created_at)|reverse) as $rows |
        if ($rows|length)==0 then "<tr><td colspan=\"6\">No FSC results found.</td></tr>" else
        $rows[] as $row | ["default","yes","only"][] as $arm |
        "<tr><td><a href=\"\($row.html_url|esc)\">#\($row.run_number|esc) / \($row.run_attempt|esc)</a></td><td>\($row.created_at|esc)</td><td>\($row.head_sha[0:8]|esc)</td><td>\($arm)</td><td>\($row.metrics[$arm].fsc05|show)</td><td>\($row.metrics[$arm].fsc0143|show)</td></tr>" end' "$site/pose_cont_history.json"
    printf '%s\n' '</tbody></table></div></section>'
} > "$work/fragment.html"
for target in "$site/index.html" "$site/reports/report_betagal_pose_cont.html"; do
    [[ -f $target ]] || continue
    fragment="$work/fragment.html"
    if [[ $target == */reports/* ]]; then
        sed 's/href="pose_cont_fsc_history.svg"/href="..\/pose_cont_fsc_history.svg"/g' "$fragment" > "$work/nested.html"
        fragment="$work/nested.html"
    fi
    awk -v fragment="$fragment" '
        /<section id="pose-cont-history">/ {skip=1}
        skip {if(/<\/section>/)skip=0;next}
        {marker="<p>SIMPLE test run</p>";position=index($0,marker);
         if(position && !inserted){print substr($0,1,position+length(marker)-1);
           while((getline line < fragment)>0)print line;close(fragment);inserted=1;
           print substr($0,position+length(marker));}else print}
    ' "$target" > "$work/document.html"
    cat "$work/document.html" > "$target"
done
printf 'Reported FSC history for %s successful Actions runs\n' "$(jq 'length' "$work/filtered.json")"
