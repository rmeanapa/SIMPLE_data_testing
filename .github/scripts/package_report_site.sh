#!/usr/bin/env bash
# Stage display assets from a report directory or legacy artifact ZIP.
# Scientific binaries stay in the run directory and diagnostic artifacts.
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 SOURCE_DIRECTORY_OR_ZIP DESTINATION" >&2; exit 2; }
source_path=$(realpath -- "$1")
destination=$(realpath -m -- "$2")
fail() { echo "$*" >&2; exit 1; }
[[ "$source_path/" != "$destination/"* && "$destination/" != "$source_path/"* ]] ||
    fail 'Source and destination must be separate directories'
if [[ -e $destination ]]; then
    [[ -d $destination && -z $(find "$destination" -mindepth 1 -print -quit) ]] ||
        fail "Destination must be empty: $destination"
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/site"
size=0
count=0
is_web_asset() {
    case ${1##*/} in LOG|.nojekyll) return 0;; esac
    case ${1,,} in
        *.html|*.css|*.js|*.json|*.csv|*.tsv|*.txt|*.log|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.woff|*.woff2|*.ttf|*.pdf) return 0;;
        *) return 1;;
    esac
}
check_size() {
    local bytes
    bytes=$(stat -c %s -- "$1")
    size=$((size + bytes))
    (( size <= 1000000000 )) || fail "Webpage assets exceed the 1 GB Pages limit: $size bytes"
    count=$((count + 1))
    chmod 644 -- "$1"
}
if [[ -d $source_path ]]; then
    [[ -f $source_path/index.html && ! -L $source_path/index.html ]] || fail "Report has no index.html: $source_path"
    # find does not follow symlinks; NUL delimiters preserve spaces in paths.
    find "$source_path" -type f -print0 > "$work/files"
    while IFS= read -r -d '' path; do
        relative=${path#"$source_path/"}
        is_web_asset "$relative" || continue
        mkdir -p -- "$work/site/$(dirname -- "$relative")"
        cp -- "$path" "$work/site/$relative"
        check_size "$work/site/$relative"
    done < "$work/files"
else
    unzip -Z -1 "$source_path" > "$work/files"
    while IFS= read -r relative; do
        # unzip -p treats its filename argument as a pattern. Reject metacharacters
        # and unsafe paths before streaming entries as regular files (no links).
        case "/${relative%/}/" in
            *'/../'*|*'/./'*|*'//'*) fail "Unsafe artifact path: $relative";;
        esac
        [[ $relative != *[\\\*\?\[\]]* && $relative != *[[:cntrl:]]* ]] ||
            fail "Unsupported artifact path: $relative"
        [[ $relative != */ ]] || continue
        is_web_asset "$relative" || continue
        mkdir -p -- "$work/site/$(dirname -- "$relative")"
        unzip -p "$source_path" "$relative" > "$work/site/$relative"
        check_size "$work/site/$relative"
    done < "$work/files"
    [[ -f $work/site/index.html ]] || fail "Report has no index.html: $source_path"
fi
mkdir -p -- "$destination"
cp -R -- "$work/site/." "$destination/"
echo "Packaged $count web assets ($size bytes): $destination"
