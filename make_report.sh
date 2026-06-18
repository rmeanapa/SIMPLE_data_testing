#!/usr/bin/env bash
#
# Usage:
#   ./make_report.sh <system_dir> [system_dir ...]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <system_dir> [system_dir ...]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
OUTPUT="$(pwd)/report.html"
ROOT=""

SYSTEM_ROOTS=()
for root_arg in "$@"; do
  if [[ -d "$root_arg" ]]; then
    SYSTEM_ROOTS+=("$(cd "$root_arg" && pwd -P)")
  elif [[ -d "$SCRIPT_DIR/$root_arg" ]]; then
    SYSTEM_ROOTS+=("$(cd "$SCRIPT_DIR/$root_arg" && pwd -P)")
  else
    echo "Input directory does not exist: $root_arg" >&2
    exit 1
  fi
done

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

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
    mini_stream|selection)
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
        /100\.[[:space:]]*percent of the micrographs processed/ {
          seen_100 = 1
          delete after_lines
          after_n = 0
          next
        }

        seen_100 {
          after_lines[++after_n] = $0
        }

        /EXTRACT/ || /percent of the micrographs processed/ || /NORMAL STOP/ || /SIMPLE Git Commit/ || /Execution time/ {
          fallback_lines[++fallback_n] = $0
        }

        END {
          if (seen_100) {
            print "Lines after the last 100. percent of the micrographs processed:"
            for (i = 1; i <= after_n; i++) {
              print after_lines[i]
            }
          } else {
            print "100. percent micrographs marker not found; recent extract diagnostics:"
            start = fallback_n > 40 ? fallback_n - 39 : 1
            for (i = start; i <= fallback_n; i++) {
              print fallback_lines[i]
            }
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

selected_jpgs_for_root() {
  local jpg
  local dir
  local base
  local iter
  local ranked_max
  local regular_max
  local keep
  local section
  local top_section
  local rank
  local all_jpgs=()
  local jpgs=()

  while IFS= read -r jpg; do
    all_jpgs+=("$jpg")
  done < <(find "$ROOT" -name "*.jpg" | sort)

  if [[ ${#all_jpgs[@]} -eq 0 ]]; then
    return 0
  fi

  for jpg in "${all_jpgs[@]}"; do
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
      jpgs+=("$jpg")
    fi
  done

  if [[ ${#jpgs[@]} -eq 0 ]]; then
    return 0
  fi

  {
    for jpg in "${jpgs[@]}"; do
      dir=$(dirname "$jpg")
      section=$(relative_to_root "$dir")
      top_section="${section%%/*}"
      rank=0
      if [[ "$top_section" =~ ^([0-9]+) ]]; then
        rank="${BASH_REMATCH[1]}"
      fi
      printf '%09d|%s|%s\n' "$rank" "$section" "$jpg"
    done
  } | sort -t'|' -k1,1nr -k2,2 -k3,3 | awk -F'|' '{print $3}'
}

log_sections_for_root() {
  local log_file="$ROOT/LOG"

  [[ -f "$log_file" ]] || return 0

  awk '
    /^[[:space:]]*>>> EXECUTION DIRECTORY:/ {
      section = $0
      sub(/^[[:space:]]*>>> EXECUTION DIRECTORY:[[:space:]]*/, "", section)
      if (section != "" && !seen[section]++) {
        print section
      }
    }
  ' "$log_file"
}

sort_sections() {
  awk '
    !seen[$0]++ {
      section = $0
      top = section
      sub(/\/.*/, "", top)
      rank = 0
      if (match(top, /^[0-9]+/)) {
        rank = substr(top, RSTART, RLENGTH)
      }
      printf "%09d|%s\n", rank, section
    }
  ' | sort -t'|' -k1,1nr -k2,2 | awk -F'|' '{print $2}'
}

append_system_report() {
  local system_root="$1"
  local system_name
  local jpg
  local dir
  local section
  local b64
  local fname
  local fname_lc
  local safe_fname
  local card_class
  local jpgs=()
  local sections=()
  local sorted_sections=()
  local section_images=()
  local has_images
  local candidate
  local existing

  ROOT="$system_root"
  system_name=$(basename "$ROOT")

  while IFS= read -r jpg; do
    jpgs+=("$jpg")
  done < <(selected_jpgs_for_root)

  add_section_once() {
    local candidate_section="$1"
    local existing_section

    if [[ ${#sections[@]} -gt 0 ]]; then
      for existing_section in "${sections[@]}"; do
        if [[ "$existing_section" == "$candidate_section" ]]; then
          return 0
        fi
      done
    fi

    sections+=("$candidate_section")
  }

  if [[ ${#jpgs[@]} -gt 0 ]]; then
    for jpg in "${jpgs[@]}"; do
      dir=$(dirname "$jpg")
      add_section_once "$(relative_to_root "$dir")"
    done
  fi

  while IFS= read -r candidate; do
    add_section_once "$candidate"
  done < <(log_sections_for_root)

  if [[ ${#sections[@]} -eq 0 ]]; then
    echo "No reportable .jpg files or LOG sections found under $ROOT" >&2
    return 1
  fi

  while IFS= read -r candidate; do
    sorted_sections+=("$candidate")
  done < <(printf '%s\n' "${sections[@]}" | sort_sections)

  {
    printf '<section class="system-report">\n'
    printf '<h1>SIMPLE Test Report - %s</h1>\n' "$(printf '%s' "$system_name" | html_escape)"
    printf '<p>SIMPLE test run</p>\n'
  } >> "$OUTPUT"

  for section in "${sorted_sections[@]}"; do
    section_images=()
    if [[ ${#jpgs[@]} -gt 0 ]]; then
      for jpg in "${jpgs[@]}"; do
        dir=$(dirname "$jpg")
        if [[ "$(relative_to_root "$dir")" == "$section" ]]; then
          section_images+=("$jpg")
        fi
      done
    fi

    printf '<h2>%s</h2>\n' "$(printf '%s' "$section" | html_escape)" >> "$OUTPUT"

    has_images=0
    if [[ ${#section_images[@]} -gt 0 ]]; then
      has_images=1
      printf '<div class="grid">\n' >> "$OUTPUT"
    fi

    if [[ ${#section_images[@]} -gt 0 ]]; then
      for jpg in "${section_images[@]}"; do
        b64=$(base64_one_line "$jpg")
        fname=$(basename "$jpg")
        safe_fname=$(printf '%s' "$fname" | html_escape)

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
    <img src="data:image/jpeg;base64,${b64}" alt="${safe_fname}">
    <span>${safe_fname}</span>
  </div>
HTML_CARD
      done
    fi

    if [[ $has_images -eq 1 ]]; then
      printf '</div>\n' >> "$OUTPUT"
    fi

    append_log_tail "$section"
  done

  printf '</section>\n' >> "$OUTPUT"
}

cat > "$OUTPUT" <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SIMPLE Test Report</title>
  <style>
    body { font-family: sans-serif; background: #f4f4f4; margin: 0; padding: 8px; }
    h1   { color: #333; }
    h2   { color: #555; border-bottom: 1px solid #ccc; padding-bottom: 4px; margin-top: 32px; }
    .system-report {
      margin-bottom: 48px;
    }
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
HTML_HEAD

for system_root in "${SYSTEM_ROOTS[@]}"; do
  append_system_report "$system_root"
done

cat >> "$OUTPUT" <<'HTML_FOOT'
</body>
</html>
HTML_FOOT

echo "Report written to: $OUTPUT"
