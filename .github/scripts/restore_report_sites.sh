#!/usr/bin/env bash
# Restore the newest independent reports before a serialized Pages deployment.
set -euo pipefail
site=$1
skip=${2:-}
: "${GH_REPO:?Set GH_REPO to owner/repository}"
mkdir -p "$site"
artifacts=$(gh api "repos/$GH_REPO/actions/artifacts?per_page=100")
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
for slug in streptavidin betagal_pose_cont streptavidin_pose_errors; do
    [[ $slug != "$skip" ]] || continue
    artifact=$(jq -r --arg name "$slug-report-site" \
        '.artifacts | map(select(.expired == false and .name == $name)) | first | .id // empty' <<< "$artifacts")
    [[ -n $artifact ]] || continue
    gh api "repos/$GH_REPO/actions/artifacts/$artifact/zip" > "$archive"
    rm -rf "$site/$slug"
    mkdir -p "$site/$slug"
    unzip -q "$archive" -d "$site/$slug"
done
