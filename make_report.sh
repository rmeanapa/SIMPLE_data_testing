#!/usr/bin/env bash
#
# Usage:
#   ./make_report.sh <root_dir> [output.html]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <root_dir> [output.html]" >&2
  exit 1
fi

ROOT="$1"
OUTPUT="${2:-$(pwd)/report.html}"

if [[ ! -d "$ROOT" ]]; then
  echo "Input directory does not exist: $ROOT" >&2
  exit 1
fi

ROOT=$(cd "$ROOT" && pwd -P)

relative_to_root() {
  local path="$1"
  local root="${ROOT%/}"

  case "$path" in
    "$root")
      printf '.\n'
      ;;
    "$root"/*)
      printf '%s\n' "${path#$root/}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

base64_one_line() {
  local file="$1"

  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0 "$file"
  else
    base64 -i "$file" | tr -d '\n'
  fi
}

max_iter_for_dir() {
  local dir="$1"
  local mode="$2"
  local candidate
  local base
  local iter
  local max=""

  while IFS= read -r candidate; do
    base=$(basename "$candidate")
    if [[ "$base" =~ iter([0-9]+) ]]; then
      iter=$((10#${BASH_REMATCH[1]}))
      if [[ "$mode" == "ranked" && "$base" == *ranked*.jpg ]]; then
        if [[ -z "$max" || $iter -gt $max ]]; then
          max=$iter
        fi
      elif [[ "$mode" == "regular" && "$base" != *ranked*.jpg ]]; then
        if [[ -z "$max" || $iter -gt $max ]]; then
          max=$iter
        fi
      fi
    fi
  done < <(find "$dir" -maxdepth 1 -name "*.jpg" | sort)

  if [[ -n "$max" ]]; then
    printf '%s\n' "$max"
  fi

  return 0
}

ALL_JPGS=()
while IFS= read -r jpg; do
  ALL_JPGS+=("$jpg")
done < <(find "$ROOT" -name "*.jpg" | sort)

if [[ ${#ALL_JPGS[@]} -eq 0 ]]; then
  echo "No matching .jpg files found under $ROOT" >&2
  exit 1
fi

JPGS=()
for jpg in "${ALL_JPGS[@]}"; do
  dir=$(dirname "$jpg")
  base=$(basename "$jpg")
  keep=1

  if [[ -f "$dir/shaped_ranked_cavgs.jpg" && "$base" == cavgs_iter*.jpg ]]; then
    keep=0
  fi

  if [[ "$base" =~ iter([0-9]+) ]]; then
    iter=$((10#${BASH_REMATCH[1]}))
    ranked_max=$(max_iter_for_dir "$dir" ranked)
    regular_max=$(max_iter_for_dir "$dir" regular)
    if [[ -n "$ranked_max" ]]; then
      if [[ "$base" != *ranked*.jpg || $iter -ne $ranked_max ]]; then
        keep=0
      fi
    else
      if [[ "$base" == *ranked*.jpg || -z "$regular_max" || $iter -ne $regular_max ]]; then
        keep=0
      fi
    fi
  fi

  if [[ $keep -eq 1 ]]; then
    JPGS+=("$jpg")
  fi
done

if [[ ${#JPGS[@]} -eq 0 ]]; then
  echo "No matching .jpg files found under $ROOT after iteration filtering" >&2
  exit 1
fi

# Sort selected JPGs so directories are shown in decreasing numeric order
# (e.g. 4_* first, then 3_*, then 2_*).
SORTED_JPGS=()
while IFS='|' read -r _rank _section jpg; do
  SORTED_JPGS+=("$jpg")
done < <(
  for jpg in "${JPGS[@]}"; do
    dir=$(dirname "$jpg")
    section=$(relative_to_root "$dir")
    top_section="${section%%/*}"
    rank=0
    if [[ "$top_section" =~ ^([0-9]+) ]]; then
      rank="${BASH_REMATCH[1]}"
    fi
    printf '%09d|%s|%s\n' "$rank" "$section" "$jpg"
  done | sort -t'|' -k1,1nr -k2,2 -k3,3
)
JPGS=("${SORTED_JPGS[@]}")

SYSTEM_NAME=$(basename "$ROOT")

cat > "$OUTPUT" <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SIMPLE Test Report - $SYSTEM_NAME</title>
  <style>
    body { font-family: sans-serif; background: #f4f4f4; margin: 0; padding: 8px; }
    h1   { color: #333; }
    h2   { color: #555; border-bottom: 1px solid #ccc; padding-bottom: 4px; margin-top: 32px; }
    .grid {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 12px;
    }
    .card {
      background: #fff;
      border: 1px solid #ddd;
      border-radius: 6px;
      padding: 6px;
      text-align: center;
      max-width: 240px;
      box-sizing: border-box;
    }
    .card img  { width: 200px; height: 200px; object-fit: contain; display: block; }
    .card.cavgs {
      width: 100%;
      max-width: 100%;
      flex: 0 0 100%;
      padding: 0;
      border: none;
      background: transparent;
      margin: 0;
    }
    .card.cavgs img {
      width: 100vw;
      max-width: 100vw;
      height: auto;
      max-height: 95vh;
      margin-left: calc(-8px);
    }
    .card.reproj-fullscreen {
      width: 100%;
      max-width: 100%;
      flex: 0 0 100%;
      padding: 0;
      border: none;
      background: #000;
      margin: 0;
      position: relative;
    }
    .card.reproj-fullscreen img {
      width: 100vw;
      max-width: 100vw;
      height: 100vh;
      max-height: 100vh;
      object-fit: contain;
      display: block;
      margin-left: calc(-8px);
      background: #000;
    }
    .card.reproj-fullscreen span {
      position: absolute;
      left: 8px;
      bottom: 8px;
      max-width: calc(100% - 16px);
      background: rgba(0, 0, 0, 0.65);
      color: #f9fafb;
      border-radius: 4px;
      padding: 4px 6px;
    }
    .card span { font-size: 12px; color: #666; word-break: break-all; }
    .log-tail {
      background: #111827;
      color: #e5e7eb;
      border-radius: 6px;
      margin-top: 14px;
      padding: 10px 12px;
    }
    .log-tail h3 {
      color: #f9fafb;
      font-size: 14px;
      margin: 0 0 8px;
    }
    .log-tail pre {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
      font-size: 12px;
      line-height: 1.35;
      margin: 0;
      overflow-x: auto;
      white-space: pre-wrap;
    }
  </style>
</head>
<body>
<h1>SIMPLE TEST Report - $SYSTEM_NAME</h1>
HTML_HEAD

printf '<p>SIMPLE test run</p>\n' >> "$OUTPUT"

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

log_program_for_section() {
  local section="$1"
  local log_file="$ROOT/LOG"

  [[ -f "$log_file" ]] || return 1

  awk -v section="$section" '
    /^[[:space:]]*>>> PROGRAM[[:space:]]*:/ {
      program = $0
      sub(/^[[:space:]]*>>> PROGRAM[[:space:]]*:[[:space:]]*/, "", program)
    }
    /^[[:space:]]*>>> EXECUTION DIRECTORY:/ {
      dir = $0
      sub(/^[[:space:]]*>>> EXECUTION DIRECTORY:[[:space:]]*/, "", dir)
      if (dir == section) {
        print program
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$log_file"
}

log_block_for_section() {
  local section="$1"
  local log_file="$ROOT/LOG"

  [[ -f "$log_file" ]] || return 1

  awk -v section="$section" '
    function reset_block() {
      delete lines
      n = 0
      block_section = ""
    }

    function flush_block() {
      if (block_section == section) {
        for (i = 1; i <= n; i++) {
          print lines[i]
        }
        found = 1
      }
      reset_block()
    }

    /^[[:space:]]*>>> PROGRAM[[:space:]]*:/ {
      if (n > 0) {
        flush_block()
        if (found) {
          exit
        }
      }
    }

    /^[[:space:]]*>>> EXECUTION DIRECTORY:/ {
      new_section = $0
      sub(/^[[:space:]]*>>> EXECUTION DIRECTORY:[[:space:]]*/, "", new_section)
      if (n > 0 && block_section != "" && new_section != block_section) {
        flush_block()
        if (found) {
          exit
        }
      }
    }

    {
      lines[++n] = $0
      if ($0 ~ /^[[:space:]]*>>> EXECUTION DIRECTORY:/) {
        block_section = $0
        sub(/^[[:space:]]*>>> EXECUTION DIRECTORY:[[:space:]]*/, "", block_section)
      }
    }

    END {
      if (!found && n > 0) {
        flush_block()
      }
      if (!found) {
        exit 1
      }
    }
  ' "$log_file"
}

log_summary_for_section() {
  local section="$1"
  local program="$2"

  case "$program" in
    import_movies)
      log_block_for_section "$section" | awk '
        /IMPORTED/ || /TOTAL NUMBER/ || /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/
      '
      ;;
    motion_correct)
      log_block_for_section "$section" | awk '
        /100\.[[:space:]]*percent of .* processed/ {
          seen_100 = 1
          delete after_lines
          after_n = 0
          next
        }

        seen_100 {
          after_lines[++after_n] = $0
        }

        /QSYS/ || /qsys/ || /job partitions/ || /dispatch slots/ || /max concurrent jobs/ ||
        /threads per job/ || /effective thread-slot demand/ || /OpenMP detected processors/ ||
        /WARNING/ || /suggested ncunits/ || /PROCESSING MOVIE/ ||
        /AVERAGE PATCH & FRAMES CORRELATION/ || /percent of the movies processed/ ||
        /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
          fallback_lines[++fallback_n] = $0
        }

        END {
          if (seen_100) {
            print "Lines after final 100. percent processed marker:"
            start = after_n > 40 ? after_n - 39 : 1
            for (i = start; i <= after_n; i++) {
              print after_lines[i]
            }
          } else {
            print "100. percent marker not found; recent motion-correction diagnostics:"
            start = fallback_n > 40 ? fallback_n - 39 : 1
            for (i = start; i <= fallback_n; i++) {
              print fallback_lines[i]
            }
          }
        }
      '
      ;;
    ctf_estimate)
      log_block_for_section "$section" | awk '
        /100\.[[:space:]]*percent of .* processed/ {
          seen_100 = 1
          delete after_lines
          after_n = 0
          next
        }

        seen_100 {
          after_lines[++after_n] = $0
        }

        /CTF/ || /percent of .* processed/ || /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
          fallback_lines[++fallback_n] = $0
        }

        END {
          if (seen_100) {
            print "Lines after final 100. percent processed marker:"
            start = after_n > 40 ? after_n - 39 : 1
            for (i = start; i <= after_n; i++) {
              print after_lines[i]
            }
          } else {
            print "100. percent marker not found; recent CTF diagnostics:"
            start = fallback_n > 40 ? fallback_n - 39 : 1
            for (i = start; i <= fallback_n; i++) {
              print fallback_lines[i]
            }
          }
        }
      '
      ;;
    mini_stream)
      {
        printf 'Final class ranking and status:\n'
        log_block_for_section "$section" | awk '
          /CLASS:[[:space:]]+/ && /RANK:[[:space:]]+/ {
            if ($0 ~ /RANK:[[:space:]]+1[[:space:]]/) {
              delete class_lines
              class_n = 0
            }
            class_lines[++class_n] = $0
          }
          /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
            status_lines[++status_n] = $0
          }
          END {
            for (i = 1; i <= class_n; i++) {
              print class_lines[i]
            }
            print ""
            status_start = status_n > 10 ? status_n - 9 : 1
            for (i = status_start; i <= status_n; i++) {
              print status_lines[i]
            }
          }
        '
      }
      ;;
    pick)
      log_block_for_section "$section" | awk '
        /100\.[[:space:]]*percent of the micrographs processed/ {
          seen_100 = 1
          delete after_lines
          after_n = 0
          next
        }

        seen_100 {
          after_lines[++after_n] = $0
        }

        /PICK/ || /percent of the micrographs processed/ || /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
          fallback_lines[++fallback_n] = $0
        }

        END {
          if (seen_100) {
            print "Lines after the last 100. percent of the micrographs processed:"
            for (i = 1; i <= after_n; i++) {
              print after_lines[i]
            }
          } else {
            print "100. percent micrographs marker not found; recent pick diagnostics:"
            start = fallback_n > 40 ? fallback_n - 39 : 1
            for (i = start; i <= fallback_n; i++) {
              print fallback_lines[i]
            }
          }
        }
      '
      ;;
    extract)
      log_block_for_section "$section" | awk '
        /EXTRACT/ || /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
          lines[++n] = $0
        }
        END {
          start = n > 40 ? n - 39 : 1
          for (i = start; i <= n; i++) {
            print lines[i]
          }
        }
      '
      ;;
    abinitio2D)
      {
        printf 'Final class ranking and status:\n'
        log_block_for_section "$section" | awk '
          /CLASS:[[:space:]]+/ && /RANK:[[:space:]]+/ {
            if ($0 ~ /RANK:[[:space:]]+1[[:space:]]/) {
              delete class_lines
              class_n = 0
            }
            class_lines[++class_n] = $0
          }
          END {
            for (i = 1; i <= class_n; i++) {
              print class_lines[i]
            }
          }
        '
        printf '\nStatus:\n'
        log_block_for_section "$section" | awk '
          /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
            lines[++n] = $0
          }
          END {
            start = n > 12 ? n - 11 : 1
            for (i = start; i <= n; i++) {
              print lines[i]
            }
          }
        '
      }
      ;;
    abinitio3D)
      {
        printf 'Recent FSC=0.143 resolution estimates:\n'
        log_block_for_section "$section" | awk '
          /RESOLUTION @ FSC=0.143/ {
            lines[++n] = $0
          }
          END {
            start = n > 20 ? n - 19 : 1
            for (i = start; i <= n; i++) {
              print lines[i]
            }
          }
        '
        printf '\nStatus:\n'
        log_block_for_section "$section" | awk '
          /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
            lines[++n] = $0
          }
          END {
            start = n > 16 ? n - 15 : 1
            for (i = start; i <= n; i++) {
              print lines[i]
            }
          }
        '
      }
      ;;
    *)
      log_block_for_section "$section" | awk '
        {
          lines[++n] = $0
        }
        END {
          start = n > 40 ? n - 39 : 1
          for (i = start; i <= n; i++) {
            print lines[i]
          }
        }
      '
      ;;
  esac
}

append_log_tail() {
  local section="$1"
  local program=""
  local section_program=""
  local log_summary=""

  program=$(log_program_for_section "$section" || true)
  section_program="${section%%/*}"
  section_program="${section_program#*_}"
  if [[ -z "$program" || "$program" != "$section_program" ]]; then
    program="$section_program"
  fi
  log_summary=$(log_summary_for_section "$section" "$program" || true)

  [[ -n "$log_summary" ]] || return 0

  {
    printf '<section class="log-tail">\n'
    if [[ -n "$program" ]]; then
      printf '<h3>LOG summary: PROGRAM %s</h3>\n' "$(printf '%s' "$program" | html_escape)"
    else
      printf '<h3>LOG summary</h3>\n'
    fi
    printf '<pre>'
    printf '%s\n' "$log_summary" | html_escape
    printf '</pre>\n'
    printf '</section>\n'
  } >> "$OUTPUT"
}

close_section() {
  local section

  [[ -n "$current_dir" ]] || return 0

  echo '  </div>' >> "$OUTPUT"
  section=$(relative_to_root "$current_dir")
  append_log_tail "$section"
}

current_dir=""
for jpg in "${JPGS[@]}"; do
  dir=$(dirname "$jpg")
  if [[ "$dir" != "$current_dir" ]]; then
    close_section
    section=$(relative_to_root "$dir")
    printf '<h2>%s</h2>\n<div class="grid">\n' "$section" >> "$OUTPUT"
    current_dir="$dir"
  fi

  b64=$(base64_one_line "$jpg")
  fname=$(basename "$jpg")

  card_class="card"
  fname_lc=$(printf '%s' "$fname" | tr '[:upper:]' '[:lower:]')
  if [[ "$fname" == *cavgs*.jpg ]]; then
    card_class="card cavgs"
  fi
  if [[ "$fname_lc" == *ortho* && "$fname_lc" == *reproj* && "$fname_lc" == *state01* ]]; then
    card_class="card reproj-fullscreen"
  fi

  cat >> "$OUTPUT" <<HTML_CARD
  <div class="${card_class}">
    <img src="data:image/jpeg;base64,${b64}" alt="${fname}">
    <span>${fname}</span>
</div>
HTML_CARD
done

close_section

cat >> "$OUTPUT" <<'HTML_FOOT'
</body>
</html>
HTML_FOOT

echo "Report written to: $OUTPUT"
