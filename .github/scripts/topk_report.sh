#!/usr/bin/env bash
# Report all 24 expected arms, including failed or missing results.
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 CAMPAIGN NEW_SITE_DIRECTORY" >&2; exit 2; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
campaign=$(realpath -m -- "$1")
site=$(realpath -m -- "$2")
mkdir -p -- "$(dirname -- "$site")"
mkdir -- "$site" # Refuse an existing report.
mkdir "$site/logs"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
: > "$work/rows.jsonl"
printf '{}\n' > "$work/manifests.json"
positive() {
    jq -cn --arg value "$1" '$value | gsub("[dD]";"e") |
        try (tonumber | if isfinite and . > 0 then . else "" end) catch ""'
}
for dataset in betagal apof proteasome; do
    manifest="$campaign/$dataset/campaign.json"
    if [[ -f $manifest ]]; then
        cp -- "$manifest" "$site/$dataset-campaign.json"
    else
        printf '{}\n' > "$work/absent.json"
        manifest="$work/absent.json"
    fi
    jq --arg dataset "$dataset" --slurpfile manifest "$manifest" \
        '.[$dataset]=$manifest[0]' "$work/manifests.json" > "$work/next.json"
    mv -- "$work/next.json" "$work/manifests.json"
    for program in solve3D refine3D_auto; do
        for k in 1 3 5 10; do
            record=$(jq -c --arg program "$program" --argjson k "$k" \
                '[.results[]? | select(.program==$program and .topk==$k)] | last // {}' "$manifest")
            status=missing; fsc05='""'; fsc0143='""'; link=''
            [[ $record == '{}' ]] || status=complete
            arm="$campaign/$dataset/$dataset/$program/topk$k"
            if [[ -f $arm/LOG ]]; then
                link="logs/$dataset-$program-topk$k.log"
                cp -- "$arm/LOG" "$site/$link"
                if [[ $record == '{}' ]]; then
                    status=incomplete
                    [[ $(jq -r '.status // ""' "$manifest") != failed ]] || status=failed
                fi
                if metrics=$(bash "$script_dir/../../make_report.sh" --final-metrics "$arm"); then
                    IFS='|' read -r -a values <<< "$metrics"
                    if [[ ${#values[@]} == 18 && ${values[17]} == 1 && $record != '{}' ]]; then
                        fsc05=$(positive "${values[0]}")
                        fsc0143=$(positive "${values[1]}")
                    fi
                fi
            fi
            if [[ $record != '{}' && ( $fsc05 == '""' || $fsc0143 == '""' ) ]]; then
                status='complete; FSC unavailable'
            fi
            jq -cn --arg dataset "$dataset" --arg program "$program" --argjson k "$k" \
                --argjson record "$record" --arg status "$status" --arg log "$link" \
                --argjson fsc05 "$fsc05" --argjson fsc0143 "$fsc0143" \
                '{dataset:$dataset,program:$program,topk:$k,status:$status,
                  seconds:($record.seconds // ""),fsc05:$fsc05,fsc0143:$fsc0143,log:$log}' >> "$work/rows.jsonl"
        done
    done
    for kind in prepare preprocessing; do
        source="$campaign/$dataset/PREPARE_LOG"
        [[ $kind != preprocessing ]] || source="$campaign/$dataset/$dataset/$dataset/LOG"
        [[ ! -f $source ]] || cp -- "$source" "$site/logs/$dataset-$kind.log"
    done
done
jq -n --arg generated "$(date -u +%FT%TZ)" --slurpfile manifests "$work/manifests.json" \
    --slurpfile rows "$work/rows.jsonl" \
    '{generated_at:$generated,campaigns:$manifests[0],results:$rows}' > "$site/results.json"
jq -r '["dataset","program","topk","status","seconds","fsc05","fsc0143","log"],
    (.results[] | [.dataset,.program,.topk,.status,.seconds,.fsc05,.fsc0143,.log]) | @tsv' \
    "$site/results.json" > "$site/metrics.tsv"
jq -r --arg server "${GITHUB_SERVER_URL:-https://github.com}" \
    --arg repo "${GITHUB_REPOSITORY:-}" --arg run "${GITHUB_RUN_ID:-}" '
    def esc: tostring | @html;
    def show: if .=="" or .==null then "unavailable" else tostring end | @html;
    . as $report |
    "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<title>SIMPLE top-k reconstruction comparison</title>",
    "<style>body{font:16px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#172033}table{border-collapse:collapse;width:100%;margin:1rem 0}th,td{padding:.65rem;text-align:left;border-bottom:1px solid #ddd}.incomplete{background:#fff0ef}.scroll{overflow-x:auto}a{color:#185abc}code{overflow-wrap:anywhere}</style>",
    "<a href=\"../\">All SIMPLE reports</a><h1>Top-k reconstruction comparison</h1>",
    "<p>β-galactosidase, apoferritin, and proteasome; topk=1, 3, 5, 10. Both solve3D and refine3D_auto use the gridding backend.</p>",
    "<p>Each dataset is prepared once. The solve3D arms share prepared input; every refinement arm starts from the topk=1 solve3D project. The initial seed is shared; extra pose draws can change later random draws.</p>",
    "<p>FSC resolutions are final logged half-map estimates in Å (lower is better). Missing values are shown explicitly. Times include the complete invocation.</p>",
    "<p>Generated \(.generated_at|esc). <a href=\"metrics.tsv\">Download metrics</a> · <a href=\"results.json\">Run metadata</a></p>",
    (if $repo!="" and $run!="" then "<p><a href=\"\($server|esc)/\($repo|esc)/actions/runs/\($run|esc)\">Actions run and scheduler logs</a></p>" else empty end),
    (["betagal","apof","proteasome"][] as $dataset |
        $report.campaigns[$dataset] as $manifest |
        [$report.results[] | select(.dataset==$dataset)] as $rows |
        "<h2>\($dataset) — \([$rows[]|select(.status|startswith("complete"))]|length)/8 completed</h2>",
        "<p>Campaign status: \($manifest.status // "not started"|esc). \($manifest.error // ""|esc)</p>",
        (if $manifest!={} then "<p>Seed \($manifest.seed|esc); binary SHA-256 <code>\($manifest.binary_sha256|esc)</code>. <a href=\"\($dataset)-campaign.json\">Campaign manifest</a></p>" else empty end),
        "<div class=\"scroll\"><table><thead><tr><th>Workflow</th><th>topk</th><th>Status</th><th>FSC=0.5 (Å)</th><th>FSC=0.143 (Å)</th><th>Time (min)</th><th>Log</th></tr></thead><tbody>",
        ($rows[] | "<tr\(if .status=="complete" then "" else " class=\"incomplete\"" end)>" +
          ([.program,.topk,.status,(.fsc05|show),(.fsc0143|show),
            (if .seconds=="" then "unavailable" else (.seconds/60*100|round)/100 end)] |
            to_entries | map(if .key==3 or .key==4 then "<td>\(.value)</td>" else "<td>\(.value|esc)</td>" end) | join("")) +
          (if .log!="" then "<td><a href=\"\(.log|esc)\">Log</a></td>" else "<td>unavailable</td>" end) + "</tr>"),
        "</tbody></table></div>"),
    empty' "$site/results.json" > "$site/index.html"
# Link preparation diagnostics only when they exist.
for log in "$site"/logs/*-prepare.log "$site"/logs/*-preprocessing.log; do
    [[ ! -f $log ]] || printf '<p><a href="logs/%s">%s</a></p>\n' "${log##*/}" "${log##*/}" >> "$site/index.html"
done
printf '%s\n' '</html>' >> "$site/index.html"
