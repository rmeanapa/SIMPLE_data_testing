#!/usr/bin/env bash
# Offline regression checks for recovered/live FSC history and table rendering.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$script_dir/../.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# Load only the report's history functions, without running scientific reports.
source <(awk '/^fsc_snapshot_header\(\)/ {copy=1} /^write_pages_site\(\)/ {copy=0} copy' "$root/make_report.sh")
fsc_history_header > "$work/seed.tsv"
for day in $(seq -w 1 12); do
    printf 'gha-%s-1\tbetagal\t4.0\t3.0\tPASS\t2026-10-%s 01:00:00 UTC\tabcdef12\n' "$day" "$day" >> "$work/seed.tsv"
done
fsc_history_header > "$work/live.tsv"
# Same measurement under a legacy snapshot identity, with corrected values.
printf 'snapshot-old\tbetagal\t3.8\t2.9\tPASS\t2026-10-12 01:00:00 UTC\tabcdef12\n' >> "$work/live.tsv"
merge_fsc_history "$work/seed.tsv" "$work/live.tsv" "$work/merged.tsv"
valid_fsc_history "$work/merged.tsv" || fail 'Invalid merged history'
[[ $(wc -l < "$work/merged.tsv") == 13 ]] || fail 'Duplicate snapshot/Actions measurement'
grep -q $'snapshot-old\tbetagal\t3.8\t2.9' "$work/merged.tsv" || fail 'Live correction lost'
merge_fsc_history "$work/seed.tsv" "$work/merged.tsv" "$work/again.tsv"
cmp "$work/merged.tsv" "$work/again.tsv" || fail 'Merge is not idempotent'
fsc_snapshot_header > "$work/current.tsv"
printf 'betagal\t3.8\t2.9\tPASS\t2026-10-12 01:00:00 UTC\tabcdef12\n' >> "$work/current.tsv"
write_fsc_comparison_table "$work/current.tsv" "$work/merged.tsv" > "$work/latest.html"
[[ $(grep -o 'scope="col"' "$work/latest.html" | wc -l) == 20 ]] || fail 'Default does not show ten runs per metric'
! grep -q '2026-10-01' "$work/latest.html" || fail 'Default retained more than ten displayed runs'
REPORT_FSC_HISTORY_LIMIT=0 write_fsc_comparison_table "$work/current.tsv" "$work/merged.tsv" > "$work/all.html"
[[ $(grep -o 'scope="col"' "$work/all.html" | wc -l) == 24 ]] || fail 'All-runs mode dropped history'
valid_fsc_history "$root/.github/data/fsc_history.tsv" || fail 'Recovered repository data invalid'
merge_fsc_history "$root/.github/data/fsc_history.tsv" "$root/.github/data/fsc_history.tsv" "$work/recovered.tsv"
cmp "$root/.github/data/fsc_history.tsv" "$work/recovered.tsv" || fail 'Recovered repository data not canonical'
# Exercise the real report entrypoint with a tiny import log and no SIMPLE jobs.
mkdir -p "$work/betagal/1_import_movies"
printf '%s\n' ' >>> PROGRAM: import_movies' 'TOTAL NUMBER OF MOVIES: 1' \
    'SIMPLE_IMPORT_MOVIES NORMAL STOP' > "$work/betagal/LOG"
GITHUB_ACTIONS=false REPORT_OUTPUT="$work/report.html" REPORT_SITE_DIR="$work/site" \
    REPORT_PREVIOUS_FSC_FILE= REPORT_FSC_HISTORY_FILE= \
    REPORT_PREVIOUS_FSC_URL= REPORT_FSC_HISTORY_URL= \
    bash "$root/make_report.sh" "$work/betagal" > "$work/report.log" 2>&1
valid_fsc_history "$work/site/fsc_history.tsv" || fail 'Real report wrote invalid history'
awk 'NR==FNR {if(FNR>1)expected[$0]=1;next}
    FNR>1 {delete expected[$0]}
    END {for(row in expected)exit 1}' \
    "$root/.github/data/fsc_history.tsv" "$work/site/fsc_history.tsv" || fail 'Real report dropped recovered data'
# Report-only publication restores missing history without creating a new run.
cp "$work/site/fsc_history.tsv" "$work/expected-history.tsv"
cp "$work/site/fsc_summary.tsv" "$work/expected-summary.tsv"
cp "$work/site/reports/report_betagal.html" "$work/expected-report.html"
{ head -n 1 "$work/expected-history.tsv"; tail -n 1 "$work/expected-history.tsv"; } > "$work/site/fsc_history.tsv"
bash "$root/make_report.sh" --recover-fsc-history "$work/site" > "$work/recover.log" 2>&1
cmp "$work/expected-history.tsv" "$work/site/fsc_history.tsv" || fail 'Report-only recovery dropped or invented runs'
cmp "$work/expected-summary.tsv" "$work/site/fsc_summary.tsv" || fail 'Report-only recovery changed current measurements'
cmp "$work/expected-report.html" "$work/site/reports/report_betagal.html" || fail 'Report-only recovery changed a dataset report'
cp "$work/site/index.html" "$work/expected-index.html"
bash "$root/make_report.sh" --recover-fsc-history "$work/site" >> "$work/recover.log" 2>&1
cmp "$work/expected-index.html" "$work/site/index.html" || fail 'Report-only recovery is not idempotent'
# Refuse an unrecognized index before replacing its history or HTML.
sed 's/class="fsc-summary"/class="unknown-summary"/' "$work/site/index.html" > "$work/site/broken.html"
mv "$work/site/broken.html" "$work/site/index.html"
if bash "$root/make_report.sh" --recover-fsc-history "$work/site" > "$work/error.log" 2>&1; then
    fail 'Report-only recovery accepted a missing table section'
fi
cmp "$work/expected-history.tsv" "$work/site/fsc_history.tsv" || fail 'Failed report-only recovery changed history'
echo 'Dataset FSC recovery, correction precedence, deduplication, ordering, and display checks passed.'
