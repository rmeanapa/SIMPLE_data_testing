#!/usr/bin/env bash
# Offline fixtures: no GitHub access, SIMPLE runs or real scientific volumes.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
package() { bash "$script_dir/package_report_site.sh" "$@"; }
source_dir="$work/source"
mkdir -p "$source_dir/comparisons/1" "$source_dir/figures with spaces"
printf '%s\n' '<img src="figures with spaces/scatter.svg">' > "$source_dir/index.html"
printf '%s\n' figure > "$source_dir/figures with spaces/scatter.svg"
printf '%s\n' 'shell,fsc' '1,0.8' > "$source_dir/comparisons/1/truth_fsc.csv"
printf '%s\n' correlation > "$source_dir/comparisons/1/direct.txt"
printf '%s\n' log > "$source_dir/comparisons/1/LOG"
printf '%s\n' history > "$source_dir/fsc_history.tsv"
printf '%s\n' 'plot()' > "$source_dir/plots.js"
for name in mirrored_input.mrc docked_direct.mrc docked_mirrored.MRC particles.mrcs project.simple work.bin; do
    printf '%s\n' binary > "$source_dir/comparisons/1/$name"
done
(cd "$source_dir" && zip -qr "$work/legacy.zip" .)
for kind in directory zip; do
    incoming=$source_dir
    [[ $kind != zip ]] || incoming="$work/legacy.zip"
    package "$incoming" "$work/web-$kind"
    [[ $(find "$work/web-$kind" -type f | wc -l) == 7 ]] || fail 'Unexpected web asset count'
    for name in index.html 'figures with spaces/scatter.svg' comparisons/1/truth_fsc.csv comparisons/1/direct.txt comparisons/1/LOG fsc_history.tsv plots.js; do
        cmp "$source_dir/$name" "$work/web-$kind/$name"
    done
    [[ ! -e $work/web-$kind/comparisons/1/docked_direct.mrc ]] || fail 'Volume leaked into webpage'
done
[[ -f $source_dir/comparisons/1/docked_direct.mrc ]] || fail 'Source volume removed'
mkdir "$work/missing"
if package "$work/missing" "$work/missing-web" > "$work/error" 2>&1; then fail 'Missing index accepted'; fi
grep -q 'no index.html' "$work/error"
# A stub stat checks the 1 GB guard without creating a large test file.
stat() { printf '%s\n' 1000000001; }
export -f stat
if package "$source_dir" "$work/oversized" > "$work/error" 2>&1; then fail 'Oversized site accepted'; fi
unset -f stat
grep -q '1 GB' "$work/error"
[[ ! -e $work/oversized ]] || fail 'Failed package left a destination'
# Exercise traversal rejection with a ZIP filename containing a parent component.
mkdir -p "$work/unsafe/nested"
printf escape > "$work/unsafe/escape.html"
(cd "$work/unsafe/nested" && zip -q "$work/unsafe.zip" ../escape.html)
if package "$work/unsafe.zip" "$work/unsafe-web" > "$work/error" 2>&1; then fail 'Unsafe ZIP accepted'; fi
grep -q 'Unsafe artifact path' "$work/error"

# Two pages of unsorted API metadata, including newer expired and older live copies.
printf '[{"artifacts":[]},{"artifacts":[' > "$work/artifacts.json"
separator=''
id=10
for slug in main streptavidin betagal_pose_cont streptavidin_pose_errors topk_comparison; do
    name="$slug-report-site"
    [[ $slug != main ]] || name=simple-data-sets-report-42
    printf '%s{"id":%s,"name":"%s","expired":true,"created_at":"2026-10-28"},' "$separator" "$((id+100))" "$name" >> "$work/artifacts.json"
    printf '{"id":%s,"name":"%s","expired":false,"created_at":"2026-10-20"},' "$((id+200))" "$name" >> "$work/artifacts.json"
    printf '{"id":%s,"name":"%s","expired":false,"created_at":"2026-10-27"}' "$id" "$name" >> "$work/artifacts.json"
    mkdir "$work/fixture-$id"
    printf 'latest %s\n' "$slug" > "$work/fixture-$id/index.html"
    printf volume > "$work/fixture-$id/docked_direct.mrc"
    (cd "$work/fixture-$id" && zip -qr "$work/$id.zip" .)
    separator=,
    id=$((id+1))
done
printf ']}]\n' >> "$work/artifacts.json"
MOCK_GITHUB=$work
GH_REPO=example/testing
export MOCK_GITHUB GH_REPO
# Export a Bash function so the mock also works on systems with noexec /tmp.
gh() {
    if [[ " $* " == *' --paginate '* ]]; then
        [[ " $* " == *' --slurp '* ]] || return 1
        cat "$MOCK_GITHUB/artifacts.json"
    else
        local endpoint=${!#} artifact_id
        artifact_id=${endpoint%/zip}; artifact_id=${artifact_id##*/}
        cat "$MOCK_GITHUB/$artifact_id.zip"
    fi
}
export -f gh
index=0
for own in main main streptavidin betagal_pose_cont streptavidin_pose_errors topk_comparison; do
    site="$work/site-$index"
    if [[ $own == main ]]; then
        mkdir "$site"
        printf 'current main\n' > "$site/index.html"
    fi
    bash "$script_dir/restore_report_sites.sh" "$site" "$own"
    if [[ $own != main ]]; then
        mkdir -p "$site/$own"
        printf 'current %s\n' "$own" > "$site/$own/index.html"
    fi
    package "$site" "$work/pages-$index"
    expected='latest main'; [[ $own != main ]] || expected='current main'
    [[ $(cat "$work/pages-$index/index.html") == "$expected" ]] || fail 'Incorrect main report'
    for slug in streptavidin betagal_pose_cont streptavidin_pose_errors topk_comparison; do
        expected="latest $slug"; [[ $own != "$slug" ]] || expected="current $slug"
        [[ $(cat "$work/pages-$index/$slug/index.html") == "$expected" ]] || fail "Lost $slug"
    done
    [[ -z $(find "$work/pages-$index" -name '*.mrc' -print -quit) ]] || fail 'Legacy volume restored'
    index=$((index+1))
done
printf '[{"artifacts":[]}]\n' > "$work/artifacts.json"
bash "$script_dir/restore_report_sites.sh" "$work/first" streptavidin
grep -q 'href="streptavidin/"' "$work/first/index.html"
printf '[{"artifacts":[{"id":99,"name":"streptavidin-report-site","expired":false,"created_at":"2026-10-27"}]}]\n' > "$work/artifacts.json"
if bash "$script_dir/restore_report_sites.sh" "$work/failed" main > "$work/error" 2>&1; then
    fail 'Failed download allowed publication'
fi
echo 'Report packaging and all publisher restoration checks passed.'
