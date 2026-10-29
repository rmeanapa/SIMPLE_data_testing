#!/usr/bin/env bash
# Restore the newest independent reports before a serialized Pages deployment.
set -euo pipefail
site=$1
skip=${2:-}
: "${GH_REPO:?Set GH_REPO to owner/repository}"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mkdir -p "$site"
# Search all pages: a retained report may be older than the first 100 artifacts.
artifacts=$(gh api --paginate --slurp "repos/$GH_REPO/actions/artifacts?per_page=100")
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
for slug in main streptavidin betagal_pose_cont streptavidin_pose_errors topk_comparison; do
    [[ $slug != "$skip" ]] || continue
    artifact=$(jq -r --arg slug "$slug" '
        [.[].artifacts[] | select(.expired == false) |
         select(if $slug == "main" then (.name | startswith("simple-data-sets-report-"))
                else .name == ($slug + "-report-site") end)] |
        max_by([.created_at, .id]) | .id // empty' <<< "$artifacts")
    if [[ -z $artifact ]]; then
        echo "No retained report artifact for $slug" >&2
        continue
    fi
    echo "Restoring $slug report from artifact $artifact"
    gh api "repos/$GH_REPO/actions/artifacts/$artifact/zip" > "$archive"
    target="$site/$slug"
    if [[ $slug == main ]]; then
        target=$site
    else
        rm -rf "$target"
    fi
    bash "$script_dir/package_report_site.sh" "$archive" "$target"
done
if [[ ! -f "$site/index.html" ]]; then
    # First deployment may have independent reports before a main report exists.
    printf '%s\n' '<!doctype html><html lang="en"><meta charset="utf-8"><title>SIMPLE reports</title><h1>SIMPLE reports</h1><ul>' > "$site/index.html"
    for slug in streptavidin betagal_pose_cont streptavidin_pose_errors topk_comparison; do
        if [[ -f "$site/$slug/index.html" || $slug == "$skip" ]]; then
            printf '<li><a href="%s/">%s</a></li>\n' "$slug" "$slug" >> "$site/index.html"
        fi
    done
    printf '%s\n' '</ul></html>' >> "$site/index.html"
fi
