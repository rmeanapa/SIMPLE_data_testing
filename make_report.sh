#!/usr/bin/env bash
#
# Usage:
#   ./make_report.sh <system_dir> [system_dir ...]
#
# By default this writes report_<system_dir>.html. Multiple input directories
# are joined into a single report_<system1>_<system2>.html file.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <system_dir> [system_dir ...]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=""
MOVIE_IMAGE_SAMPLE_LIMIT=10
MOVIE_IMAGE_SAMPLE_THRESHOLD=100

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

report_name_part=""
for system_root in "${SYSTEM_ROOTS[@]}"; do
  system_name="$(basename "$system_root")"
  system_name="${system_name//[^A-Za-z0-9._-]/_}"
  if [[ -z "$report_name_part" ]]; then
    report_name_part="$system_name"
  else
    report_name_part="${report_name_part}_${system_name}"
  fi
done
OUTPUT="${REPORT_OUTPUT:-$(pwd)/report_${report_name_part}.html}"

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

log_lookup_section() {
  local section="$1"
  local base
  local log_file="$ROOT/LOG"

  if [[ "$section" == */* && -f "$log_file" ]]; then
    base=${section##*/}
    if grep -q "^[[:space:]]*>>> EXECUTION DIRECTORY:[[:space:]]*$base[[:space:]]*$" "$log_file"; then
      printf '%s\n' "$base"
      return 0
    fi
  fi

  printf '%s\n' "$section"
}

resolve_report_section() {
  local section="$1"
  local match=""

  if [[ "$section" != */* && -d "$ROOT/4_track_particles" ]]; then
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      relative_to_root "$match"
      return 0
    done < <(find "$ROOT/4_track_particles" -type d -name "$section" | sort)
  fi

  printf '%s\n' "$section"
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
  section=$(log_lookup_section "$section")

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
  section=$(log_lookup_section "$section")

  awk -v section="$section" '
    BEGIN {
      section_program = section
      sub(/\/.*/, "", section_program)
      sub(/^[0-9]+_/, "", section_program)
    }

    function reset_block() {
      delete lines
      n = 0
      block_section = ""
      block_program = ""
    }

    function flush_block() {
      if (block_section == section || (block_section == "" && block_program == section_program)) {
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
      if ($0 ~ /^[[:space:]]*>>> PROGRAM[[:space:]]*:/) {
        block_program = $0
        sub(/^[[:space:]]*>>> PROGRAM[[:space:]]*:[[:space:]]*/, "", block_program)
      }
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

is_movie_image_section() {
  local section="$1"
  local section_program

  section_program="${section%%/*}"
  section_program="${section_program#*_}"

  [[ "$section_program" == "motion_correct" || "$section_program" == *_motion_correct || "$section_program" == "movies" || "$section" == *movie* || "$section" == *movies* ]]
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
  local candidate_section
  local top_section
  local rank
  local all_jpgs=()
  local jpgs=()
  local selected_jpgs=()
  local movie_sections=()
  local movie_section_jpgs=()
  local sampled_jpgs=()

  while IFS= read -r jpg; do
    all_jpgs+=("$jpg")
  done < <(find "$ROOT" -name "*.jpg" | sort)

  if [[ ${#all_jpgs[@]} -eq 0 ]]; then
    return 0
  fi

  for jpg in "${all_jpgs[@]}"; do
    dir=${jpg%/*}
    base=${jpg##*/}
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

  for jpg in "${jpgs[@]}"; do
    dir=${jpg%/*}
    section=${dir#"$ROOT"/}
    if is_movie_image_section "$section"; then
      if [[ ${#movie_sections[@]} -eq 0 ]]; then
        movie_sections+=("$section")
      else
        keep=1
        for candidate_section in "${movie_sections[@]}"; do
          if [[ "$candidate_section" == "$section" ]]; then
            keep=0
            break
          fi
        done
        if [[ $keep -eq 1 ]]; then
          movie_sections+=("$section")
        fi
      fi
    else
      selected_jpgs+=("$jpg")
    fi
  done

  if [[ ${#movie_sections[@]} -gt 0 ]]; then
    for section in "${movie_sections[@]}"; do
      movie_section_jpgs=()
      for jpg in "${jpgs[@]}"; do
        dir=${jpg%/*}
        if [[ "${dir#"$ROOT"/}" == "$section" ]]; then
          movie_section_jpgs+=("$jpg")
        fi
      done

      if [[ ${#movie_section_jpgs[@]} -gt $MOVIE_IMAGE_SAMPLE_THRESHOLD ]]; then
        sampled_jpgs=()
        while IFS= read -r jpg; do
          sampled_jpgs+=("$jpg")
        done < <(printf '%s\n' "${movie_section_jpgs[@]}" | sample_images)
        if [[ ${#sampled_jpgs[@]} -gt 0 ]]; then
          selected_jpgs+=("${sampled_jpgs[@]}")
        fi
      else
        selected_jpgs+=("${movie_section_jpgs[@]}")
      fi
    done

    jpgs=("${selected_jpgs[@]}")
  fi

  {
    for jpg in "${jpgs[@]}"; do
      dir=${jpg%/*}
      section=${dir#"$ROOT"/}
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

filesystem_sections_for_root() {
  local dir
  local name

  while IFS= read -r dir; do
    name=$(basename "$dir")
    if [[ "$name" =~ ^[0-9]+_ ]]; then
      printf '%s\n' "$name"
    fi
  done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
}

sort_sections() {
  awk '
    function numeric_sort_key(section, parts, n, i, base, rank, rank_count, key, max_levels) {
      max_levels = 8
      n = split(section, parts, "/")
      rank_count = 0
      key = ""

      for (i = 1; i <= n && rank_count < max_levels; i++) {
        base = parts[i]
        if (match(base, /^[0-9]+_/)) {
          rank = substr(base, RSTART, RLENGTH - 1) + 0
          key = key sprintf("%09d", 999999999 - rank)
          rank_count++
        }
      }

      for (i = rank_count + 1; i <= max_levels; i++) {
        key = key "999999999"
      }

      return key
    }

    !seen[$0]++ {
      section = $0
      printf "%s|%s\n", numeric_sort_key(section), section
    }
  ' | sort -t'|' -k1,1 -k2,2 | awk -F'|' '{print $2}'
}

should_sample_movie_images() {
  local section="$1"
  local image_count="$2"

  [[ $image_count -gt $MOVIE_IMAGE_SAMPLE_THRESHOLD ]] || return 1
  is_movie_image_section "$section"
}

sample_images() {
  awk 'BEGIN { srand() } { printf "%.12f\t%s\n", rand(), $0 }' |
    sort -n |
    head -n "$MOVIE_IMAGE_SAMPLE_LIMIT" |
    cut -f2-
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
  local sampled_images=()
  local has_images
  local original_image_count
  local sampled_movie_images
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

    candidate_section=$(resolve_report_section "$candidate_section")

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
      dir=${jpg%/*}
      add_section_once "${dir#"$ROOT"/}"
    done
  fi

  while IFS= read -r candidate; do
    add_section_once "$candidate"
  done < <(filesystem_sections_for_root)

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
        dir=${jpg%/*}
        if [[ "${dir#"$ROOT"/}" == "$section" ]]; then
          section_images+=("$jpg")
        fi
      done
    fi

    original_image_count=${#section_images[@]}
    sampled_movie_images=0
    if should_sample_movie_images "$section" "$original_image_count"; then
      sampled_images=()
      while IFS= read -r jpg; do
        sampled_images+=("$jpg")
      done < <(printf '%s\n' "${section_images[@]}" | sample_images)
      section_images=("${sampled_images[@]}")
      sampled_movie_images=1
    fi

    printf '<h2>%s</h2>\n' "$(printf '%s' "$section" | html_escape)" >> "$OUTPUT"

    if [[ $sampled_movie_images -eq 1 ]]; then
      printf '<p class="image-note">Showing %s random movie JPEGs out of %s.</p>\n' \
        "$MOVIE_IMAGE_SAMPLE_LIMIT" "$original_image_count" >> "$OUTPUT"
    fi

    has_images=0
    if [[ ${#section_images[@]} -gt 0 ]]; then
      has_images=1
      printf '<div class="grid">\n' >> "$OUTPUT"
    fi

    if [[ ${#section_images[@]} -gt 0 ]]; then
      for jpg in "${section_images[@]}"; do
        b64=$(base64_one_line "$jpg")
        fname=${jpg##*/}
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
    .image-note { color: #555; font-size: 13px; margin: 8px 0 0; }
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
