#!/usr/bin/env bash
#
# Usage:
#   ./make_report.sh <system_dir> [system_dir ...]
#
# By default this writes build/index.html plus per-system reports in
# build/reports/. Set REPORT_SITE_DIR to choose a different output directory.

set -euo pipefail

PAGES_OUTPUT_DIR="${REPORT_SITE_DIR:-build}"
SIMPLE_SOURCE_DIR="${SIMPLE_SOURCE_DIR:-/home/meanapanedar2/SIMPLE}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <system_dir> [system_dir ...]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=""
MOVIE_IMAGE_SAMPLE_LIMIT=10
MOVIE_IMAGE_SAMPLE_THRESHOLD=100
FINAL_RESOLUTION_THRESHOLD_ANGSTROM="${REPORT_FINAL_RESOLUTION_MAX_ANGSTROM:-6.0}"
SINGLE_WORKFLOW_RESOLUTION_THRESHOLD_ANGSTROM="${REPORT_SINGLE_WORKFLOW_RESOLUTION_MAX_ANGSTROM:-5.0}"

if ! awk -v value="$FINAL_RESOLUTION_THRESHOLD_ANGSTROM" 'BEGIN {
  exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value > 0)
}'; then
  echo "REPORT_FINAL_RESOLUTION_MAX_ANGSTROM must be a positive number" >&2
  exit 1
fi

if ! awk -v value="$SINGLE_WORKFLOW_RESOLUTION_THRESHOLD_ANGSTROM" 'BEGIN {
  exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value > 0)
}'; then
  echo "REPORT_SINGLE_WORKFLOW_RESOLUTION_MAX_ANGSTROM must be a positive number" >&2
  exit 1
fi

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

display_name_for_root() {
  case "$(basename "$1")" in
    test_single_workflow_fcc)
      printf '%s\n' 'SINGLE workflow — FCC Pt'
      ;;
    test_single_workflow_wurtzite)
      printf '%s\n' 'SINGLE workflow — wurtzite CdSe'
      ;;
    *)
      basename "$1"
      ;;
  esac
}

has_ground_truth_for_root() {
  case "$(basename "$1")" in
    test_simulated_workflow_*|test_single_workflow|test_single_workflow_*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

html_metric_value() {
  local value="$1"
  local suffix="${2:-}"
  local escaped

  if [[ -n "$value" ]]; then
    escaped=$(printf '%s' "$value" | html_escape)
    printf '<strong>%s%s</strong>' "$escaped" "$suffix"
  else
    printf '<strong class="metric-missing">not found</strong>'
  fi
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

log_file_for_root() {
  local direct_log="$ROOT/LOG"
  local root_name
  local workflow_log

  if [[ -f "$direct_log" ]]; then
    printf '%s\n' "$direct_log"
    return 0
  fi

  root_name=$(basename "$ROOT")
  case "$root_name" in
    test_simulated_workflow_*)
      workflow_log="$(dirname "$ROOT")/LOG_${root_name#test_simulated_workflow_}"
      ;;
    test_single_workflow)
      workflow_log="$(dirname "$ROOT")/LOG_single"
      ;;
    test_single_workflow_*)
      workflow_log="$(dirname "$ROOT")/LOG_single_${root_name#test_single_workflow_}"
      ;;
  esac

  if [[ -n "${workflow_log:-}" && -f "$workflow_log" ]]; then
    printf '%s\n' "$workflow_log"
    return 0
  fi

  printf '%s\n' "$direct_log"
}

log_lookup_section() {
  local section="$1"
  local base
  local log_file

  log_file=$(log_file_for_root)

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

  if [[ "$section" != */* && -d "$ROOT/simulated_workflow/$section" ]]; then
    relative_to_root "$ROOT/simulated_workflow/$section"
    return 0
  fi

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

index_volume_preview_for_root() {
  local system_root="$1"
  local candidate
  local relative
  local component
  local component_lc
  local priority
  local rank
  local best=""
  local best_priority=-1
  local best_rank=-1
  local parts=()

  while IFS= read -r candidate; do
    relative=${candidate#"$system_root"/}
    priority=1
    rank=0
    IFS='/' read -r -a parts <<< "$relative"
    for component in "${parts[@]}"; do
      component_lc=$(printf '%s' "$component" | tr '[:upper:]' '[:lower:]')
      if [[ "$component_lc" == *autorefine3d* || "$component_lc" == *refine3d_auto* ]]; then
        priority=3
      elif [[ $priority -lt 3 && "$component_lc" == *solve3d* ]]; then
        priority=2
      fi
      if [[ "$component" =~ ^([0-9]+)_ && $((10#${BASH_REMATCH[1]})) -gt $rank ]]; then
        rank=$((10#${BASH_REMATCH[1]}))
      fi
    done

    if [[ $priority -gt $best_priority || \
          ( $priority -eq $best_priority && $rank -gt $best_rank ) || \
          ( $priority -eq $best_priority && $rank -eq $best_rank && "$candidate" > "$best" ) ]]; then
      best=$candidate
      best_priority=$priority
      best_rank=$rank
    fi
  done < <(find "$system_root" -type f -iname '*ortho*reproj*.jpg' ! -path '*/Trash/*' | sort)

  if [[ -n "$best" ]]; then
    printf '%s\n' "$best"
  fi
}

final_volume_for_root() {
  local system_root="$1"
  local preview
  local preview_dir
  local candidate
  local relative
  local component
  local component_lc
  local priority
  local rank
  local best=""
  local best_priority=-1
  local best_rank=-1
  local parts=()

  preview=$(index_volume_preview_for_root "$system_root" || true)
  if [[ -n "$preview" ]]; then
    preview_dir=${preview%/*}
    if [[ -f "$preview_dir/rec_final_state01.mrc" ]]; then
      printf '%s\n' "$preview_dir/rec_final_state01.mrc"
      return 0
    fi
  fi

  while IFS= read -r candidate; do
    relative=${candidate#"$system_root"/}
    priority=1
    rank=0
    IFS='/' read -r -a parts <<< "$relative"
    for component in "${parts[@]}"; do
      component_lc=$(printf '%s' "$component" | tr '[:upper:]' '[:lower:]')
      if [[ "$component_lc" == *autorefine3d* || "$component_lc" == *refine3d_auto* ]]; then
        priority=3
      elif [[ $priority -lt 3 && "$component_lc" == *solve3d* ]]; then
        priority=2
      fi
      if [[ "$component" =~ ^([0-9]+)_ && $((10#${BASH_REMATCH[1]})) -gt $rank ]]; then
        rank=$((10#${BASH_REMATCH[1]}))
      fi
    done

    if [[ $priority -gt $best_priority || \
          ( $priority -eq $best_priority && $rank -gt $best_rank ) || \
          ( $priority -eq $best_priority && $rank -eq $best_rank && "$candidate" > "$best" ) ]]; then
      best=$candidate
      best_priority=$priority
      best_rank=$rank
    fi
  done < <(find "$system_root" -type f -name 'rec_final_state01.mrc' ! -path '*/Trash/*' | sort)

  [[ -z "$best" ]] || printf '%s\n' "$best"
}

volume_header_metrics() {
  local volume="$1"
  local info_exec=""
  local info_output

  if [[ -n "${SIMPLE_PATH:-}" && -x "$SIMPLE_PATH/bin/simple_exec" ]]; then
    info_exec="$SIMPLE_PATH/bin/simple_exec"
  elif command -v simple_exec >/dev/null 2>&1; then
    info_exec=$(command -v simple_exec)
  else
    return 1
  fi

  info_output=$("$info_exec" prg=info_image fname="$volume" stats=no vis=no 2>&1) || return 1
  printf '%s\n' "$info_output" | awk '
    /Number of columns, rows, sections:/ {
      value = $0
      sub(/^.*Number of columns, rows, sections:[[:space:]]*/, "", value)
      split(value, dims, /[[:space:]]+/)
      box = dims[1]
    }
    /Pixel size[[:space:]]*:/ {
      value = $0
      sub(/^.*Pixel size[[:space:]]*:[[:space:]]*/, "", value)
      split(value, fields, /[[:space:]]+/)
      smpd = fields[1]
    }
    END {
      if (box + 0 > 0 && smpd + 0 > 0) {
        printf "%s|%s\n", box, smpd
      } else {
        exit 1
      }
    }
  '
}

symmetry_for_root() {
  local system_root="$1"
  local system_name
  local workflow_script
  local symmetry=""

  system_name=$(basename "$system_root")
  workflow_script="$SCRIPT_DIR/$system_name.sh"
  if [[ -f "$workflow_script" ]]; then
    symmetry=$(awk '
      /^[[:space:]]*#/ { next }
      /prg=(solve3D|refine3D_auto|autorefine3D_nano)/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^pgrp=/) {
            value = $i
            sub(/^pgrp=/, "", value)
            gsub(/["'\"']/, "", value)
            pgrp = value
          }
        }
      }
      END {
        if (pgrp != "") print pgrp
      }
    ' "$workflow_script")
  fi

  if [[ -z "$symmetry" ]]; then
    case "$system_name" in
      test_simulated_workflow_6vxx) symmetry="c3" ;;
      test_simulated_workflow_1jxy|test_single_workflow|test_single_workflow_*) symmetry="c1" ;;
    esac
  fi

  [[ -z "$symmetry" ]] || printf '%s\n' "$symmetry"
}

original_sampling_for_root() {
  local system_root="$1"
  local system_name
  local workflow_script
  local smpd=""

  system_name=$(basename "$system_root")
  workflow_script="$SCRIPT_DIR/$system_name.sh"
  if [[ -f "$workflow_script" ]]; then
    smpd=$(awk '
      /^[[:space:]]*#/ { next }
      /prg=(import_movies|tseries_import)/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^smpd=/) {
            value = $i
            sub(/^smpd=/, "", value)
            import_smpd = value
          }
        }
      }
      END {
        if (import_smpd != "") print import_smpd
      }
    ' "$workflow_script")
  fi

  if [[ -z "$smpd" ]]; then
    case "$system_name" in
      test_simulated_workflow_6vxx|test_simulated_workflow_1jxy)
        smpd="1.3"
        ;;
      test_single_workflow|test_single_workflow_*)
        smpd="0.358"
        ;;
    esac
  fi

  [[ -z "$smpd" ]] || printf '%s\n' "$smpd"
}

input_sampling_label_for_root() {
  case "$(basename "$1")" in
    test_single_workflow|test_single_workflow_*)
      printf '%s\n' 'Particle sampling'
      ;;
    *)
      printf '%s\n' 'Movie import sampling'
      ;;
  esac
}

resolution_threshold_for_root() {
  local system_name

  system_name=$(basename "$1")
  if [[ "$system_name" == "test_single_workflow" || "$system_name" == test_single_workflow_* ]]; then
    printf '%s\n' "$SINGLE_WORKFLOW_RESOLUTION_THRESHOLD_ANGSTROM"
  else
    printf '%s\n' "$FINAL_RESOLUTION_THRESHOLD_ANGSTROM"
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
  local log_file

  log_file=$(log_file_for_root)

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
  local log_file

  log_file=$(log_file_for_root)

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

execution_time_for_section() {
  local section="$1"

  log_block_for_section "$section" | awk '
    /Execution[[:space:]]+time:[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*seconds/ {
      value = $0
      sub(/^.*Execution[[:space:]]+time:[[:space:]]*/, "", value)
      sub(/[[:space:]]*seconds.*$/, "", value)
      if (value ~ /^[0-9]+([.][0-9]+)?$/) {
        elapsed = value
        found = 1
      }
    }
    END {
      if (found) {
        print elapsed
      } else {
        exit 1
      }
    }
  '
}

format_duration() {
  local seconds="$1"

  awk -v total="$seconds" 'BEGIN {
    hours = int(total / 3600)
    minutes = int((total - (hours * 3600)) / 60)
    secs = total - (hours * 3600) - (minutes * 60)

    if (hours > 0) {
      printf "%dh %02dm %04.1fs", hours, minutes, secs
    } else if (minutes > 0) {
      printf "%dm %04.1fs", minutes, secs
    } else {
      printf "%.1fs", secs
    }
  }'
}

format_timed_step_count() {
  local count="$1"

  if [[ $count -eq 1 ]]; then
    printf '1 timed test step'
  else
    printf '%s timed test steps' "$count"
  fi
}

timing_stats_for_sections() {
  local section
  local seconds
  local count=0
  local total=0

  for section in "$@"; do
    seconds=$(execution_time_for_section "$section" || true)
    [[ -n "$seconds" ]] || continue
    count=$((count + 1))
    total=$(awk -v total="$total" -v seconds="$seconds" 'BEGIN { printf "%.10g", total + seconds }')
  done

  printf '%s|%s\n' "$count" "$total"
}

final_volume_metrics_for_root() {
  local log_file

  log_file=$(log_file_for_root)
  [[ -f "$log_file" ]] || return 1

  awk '
    function reset_parameters() {
      smpd = ""
      box = ""
      pgrp = ""
      nptcls = ""
    }

    function numeric(value) {
      return value ~ /^[-+]?[0-9]+([.][0-9]*)?([EeDd][-+]?[0-9]+)?$/
    }

    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*>>> PROGRAM[[:space:]]*:/ {
      block++
      program = $0
      sub(/^[[:space:]]*>>> PROGRAM[[:space:]]*:[[:space:]]*/, "", program)
      section = ""
      reset_parameters()
      next
    }

    /^[[:space:]]*>>> EXECUTION DIRECTORY[[:space:]]*:/ {
      section = $0
      sub(/^[[:space:]]*>>> EXECUTION DIRECTORY[[:space:]]*:[[:space:]]*/, "", section)
      next
    }

    /^[[:space:]]*>>>[[:space:]]+[[:alnum:]_]+[[:space:]]+/ {
      key = tolower($2)
      sub(/:$/, "", key)
      if (key == "smpd") smpd = $3
      else if (key == "box") box = $3
      else if (key == "pgrp") pgrp = $3
      else if (key == "nptcls") nptcls = $3
    }

    /(PROJECT VOLUME|CURRENT RUN|INPUT VOLUME) BOX\/SMPD:/ {
      value = $0
      sub(/^.*BOX\/SMPD:[[:space:]]*/, "", value)
      gsub(/[[:space:]]/, "", value)
      split(value, pair, "/")
      if (numeric(pair[1]) && numeric(pair[2])) {
        box = pair[1]
        smpd = pair[2]
      }
    }

    /POINT GROUP:/ {
      value = $0
      sub(/^.*POINT GROUP:[[:space:]]*/, "", value)
      split(value, fields, /[[:space:]]+/)
      if (fields[1] != "") pgrp = fields[1]
    }

    /% PARTICLES SAMPLED THIS ITERATION/ {
      value = $0
      sub(/^.*\(/, "", value)
      sub(/\).*$/, "", value)
      gsub(/[[:space:]]/, "", value)
      split(value, pair, "/")
      if (numeric(pair[2]) && pair[2] + 0 > 0) nptcls = pair[2]
    }

    /RESOLUTION @ FSC=0[.]143[[:space:]]+AVG\/SDEV\/MIN\/MAX:/ {
      values = $0
      sub(/^.*AVG\/SDEV\/MIN\/MAX:[[:space:]]*/, "", values)
      count = split(values, field, /[[:space:]]+/)
      if (count >= 1 && numeric(field[1])) {
        pending_fsc0143 = field[1]
      }
      next
    }

    /RESOLUTION @ FSC=0[.]5[[:space:]]+AVG\/SDEV\/MIN\/MAX:/ {
      values = $0
      sub(/^.*AVG\/SDEV\/MIN\/MAX:[[:space:]]*/, "", values)
      count = split(values, field, /[[:space:]]+/)
      if (count >= 1 && numeric(field[1])) {
        final_avg = field[1]
        final_fsc0143 = pending_fsc0143
        pending_fsc0143 = ""
        final_program = program
        final_section = section
        final_smpd = smpd
        final_box = box
        final_pgrp = pgrp
        final_nptcls = nptcls
        metric_block = block
        found = 1
      }
      next
    }

    /RESOLUTION AT FSC=0[.]500 DETERMINED TO:/ {
      value = $0
      sub(/^.*DETERMINED TO:[[:space:]]*/, "", value)
      split(value, field, /[[:space:]]+/)
      if (numeric(field[1])) {
        final_avg = field[1]
        final_fsc0143 = ""
        final_program = program
        final_section = section
        final_smpd = smpd
        final_box = box
        final_pgrp = pgrp
        final_nptcls = nptcls
        metric_block = block
        awaiting_direct_fsc0143 = 1
        found = 1
      }
      next
    }

    /RESOLUTION AT FSC=0[.]143 DETERMINED TO:/ {
      value = $0
      sub(/^.*DETERMINED TO:[[:space:]]*/, "", value)
      split(value, field, /[[:space:]]+/)
      if (awaiting_direct_fsc0143 && block == metric_block && numeric(field[1])) {
        final_fsc0143 = field[1]
        awaiting_direct_fsc0143 = 0
      }
      next
    }

    /workflow_reconstruction docking correlation: direct=/ {
      value = $0
      sub(/^.*direct=[[:space:]]*/, "", value)
      split(value, pair, /,[[:space:]]*mirrored=[[:space:]]*/)
      dock_direct = pair[1]
      dock_mirrored = pair[2]
      if (numeric(dock_direct) && numeric(dock_mirrored)) {
        if (dock_direct >= dock_mirrored) {
          dock_selected = dock_direct
          dock_hand = "direct"
        } else {
          dock_selected = dock_mirrored
          dock_hand = "mirrored"
        }
      }
      next
    }

    /Selected docking correlation:/ && /; band/ {
      value = $0
      sub(/^.*correlation:[[:space:]]*/, "", value)
      split(value, fields, /;[[:space:]]*band[[:space:]]*/)
      if (numeric(fields[1])) dock_selected = fields[1]
      split(fields[2], band, /-/)
      dock_hp = trim(band[1])
      dock_lp = trim(band[2])
      sub(/[[:space:]]+A.*$/, "", dock_lp)
      next
    }

    /Registered whole-volume Pearson correlation:/ {
      value = $0
      sub(/^.*correlation:[[:space:]]*/, "", value)
      split(value, fields, /;[[:space:]]*minimum[[:space:]]*/)
      if (numeric(fields[1])) final_corr = fields[1]
      if (numeric(fields[2])) final_corr_min = fields[2]
      corr_basis = "whole volume"
      next
    }

    /Registered soft-masked band correlation to/ {
      value = $0
      sub(/^.*correlation to[[:space:]]*/, "", value)
      split(value, lp_fields, /[[:space:]]+A:[[:space:]]*/)
      split(lp_fields[2], fields, /;[[:space:]]*minimum[[:space:]]*/)
      if (numeric(fields[1])) final_corr = fields[1]
      if (numeric(fields[2])) final_corr_min = fields[2]
      corr_basis = "soft mask; low-pass " lp_fields[1] " A"
      next
    }

    /Masked truth FSC: 0[.]500 at/ && /0[.]143 at/ {
      value = $0
      sub(/^.*0[.]500 at[[:space:]]*/, "", value)
      split(value, fsc_fields, /[[:space:]]+A;[[:space:]]*0[.]143 at[[:space:]]*/)
      split(fsc_fields[2], fsc0143_fields, /[[:space:]]+A;/)
      final_avg = fsc_fields[1]
      final_fsc0143 = fsc0143_fields[1]
      if (numeric(final_avg) && numeric(final_fsc0143)) {
        final_section = "final-volume validation"
        final_smpd = smpd
        final_box = box
        final_pgrp = pgrp
        final_nptcls = nptcls
        metric_block = block
        found = 1
      }
      next
    }

    /NORMAL STOP/ {
      normal_stop[block] = 1
    }

    /ERROR STOP/ {
      error_stop[block] = 1
    }

    END {
      if (!found) exit 1
      normal = normal_stop[metric_block] && !error_stop[metric_block] ? 1 : 0
      printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d\n", \
        final_avg, final_fsc0143, final_program, final_section, final_smpd, \
        final_box, final_pgrp, final_nptcls, \
        final_corr, final_corr_min, corr_basis, dock_direct, dock_mirrored, \
        dock_selected, dock_hand, dock_hp, dock_lp, normal
    }
  ' "$log_file"
}

append_timing_summary() {
  local section
  local section_label
  local program
  local program_label
  local seconds
  local formatted
  local stats
  local count
  local total

  stats=$(timing_stats_for_sections "$@")
  count=${stats%%|*}
  total=${stats#*|}
  [[ $count -gt 0 ]] || return 0

  {
    printf '<section class="timing-summary">\n'
    printf '<div class="timing-heading"><h2>Execution times</h2><div class="timing-total"><strong>%s</strong><span>Total across %s</span></div></div>\n' \
      "$(format_duration "$total")" "$(format_timed_step_count "$count")"
    printf '<div class="timing-table-wrap"><table class="timing-table">\n'
    printf '<thead><tr><th scope="col">Test step</th><th scope="col">Program</th><th scope="col">Duration</th></tr></thead><tbody>\n'
  } >> "$OUTPUT"

  for section in "$@"; do
    seconds=$(execution_time_for_section "$section" || true)
    [[ -n "$seconds" ]] || continue

    program=$(log_program_for_section "$section" || true)
    if [[ -z "$program" ]]; then
      program="${section%%/*}"
      program="${program#*_}"
    fi
    section_label=$(printf '%s' "$section" | html_escape)
    program_label=$(printf '%s' "$program" | html_escape)
    formatted=$(format_duration "$seconds")
    printf '<tr><td>%s</td><td>%s</td><td><strong>%s</strong><span class="raw-seconds">%s seconds</span></td></tr>\n' \
      "$section_label" "$program_label" "$formatted" "$seconds" >> "$OUTPUT"
  done

  {
    printf '</tbody></table></div>\n'
    printf '<p class="timing-note">Total is the sum of execution times recorded by SIMPLE in this test LOG.</p>\n'
    printf '</section>\n'
  } >> "$OUTPUT"
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
    solve2D)
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
    solve3D)
      {
        printf 'Recent FSC resolution estimates:\n'
        log_block_for_section "$section" | awk '
          /RESOLUTION @ FSC=0.143|RESOLUTION @ FSC=0.5/ {
            criterion = $0 ~ /FSC=0.143/ ? "0.143" : "0.5"
            value = $0
            sub(/^.*AVG\/SDEV\/MIN\/MAX:[[:space:]]*/, "", value)
            split(value, fields, /[[:space:]]+/)
            if (fields[1] != "") {
              lines[++n] = "FSC=" criterion " resolution: " fields[1] " A"
            }
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
  local log_file

  log_file=$(log_file_for_root)

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
  local system_label
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
  local section_seconds
  local candidate
  local existing

  ROOT="$system_root"
  system_name=$(basename "$ROOT")
  system_label=$(display_name_for_root "$ROOT")

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
    printf '<h1>SIMPLE Test Report - %s</h1>\n' "$(printf '%s' "$system_label" | html_escape)"
    printf '<p>SIMPLE test run</p>\n'
  } >> "$OUTPUT"

  append_timing_summary "${sorted_sections[@]}"

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

    printf '<h2 class="section-heading"><span>%s</span>' "$(printf '%s' "$section" | html_escape)" >> "$OUTPUT"
    if section_seconds=$(execution_time_for_section "$section" || true); [[ -n "$section_seconds" ]]; then
      printf '<span class="duration-badge">%s</span>' "$(format_duration "$section_seconds")" >> "$OUTPUT"
    fi
    printf '</h2>\n' >> "$OUTPUT"

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
        if [[ "$fname_lc" == *reproj*.jpg ]]; then
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

write_report_html() {
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
    .section-heading {
      align-items: baseline;
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: space-between;
    }
    .duration-badge {
      background: #d1fae5;
      border: 1px solid #a7f3d0;
      border-radius: 999px;
      color: #065f46;
      font-size: 13px;
      font-weight: 700;
      padding: 3px 9px;
      white-space: nowrap;
    }
    .timing-summary {
      background: #fff;
      border: 1px solid #d1d5db;
      border-radius: 8px;
      margin: 24px 0 32px;
      padding: 16px;
    }
    .timing-heading {
      align-items: center;
      display: flex;
      gap: 16px;
      justify-content: space-between;
    }
    .timing-heading h2 {
      border: 0;
      margin: 0;
      padding: 0;
    }
    .timing-total {
      text-align: right;
    }
    .timing-total strong {
      color: #065f46;
      display: block;
      font-size: 1.35rem;
    }
    .timing-total span,
    .timing-note,
    .raw-seconds {
      color: #6b7280;
      font-size: 12px;
    }
    .timing-table-wrap {
      margin-top: 14px;
      overflow-x: auto;
    }
    .timing-table {
      border-collapse: collapse;
      width: 100%;
    }
    .timing-table th,
    .timing-table td {
      border-top: 1px solid #e5e7eb;
      padding: 8px;
      text-align: left;
      vertical-align: top;
    }
    .timing-table th {
      color: #4b5563;
      font-size: 12px;
      text-transform: uppercase;
    }
    .timing-table td:last-child,
    .timing-table th:last-child {
      text-align: right;
      white-space: nowrap;
    }
    .raw-seconds {
      display: block;
    }
    .timing-note {
      margin: 10px 0 0;
    }
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
}

write_pages_site() {
  local output_dir="$1"
  local reports_dir="$output_dir/reports"
  local generated_at
  local simple_commit="unavailable"
  local system_root
  local system_name
  local system_label
  local report_file
  local preview
  local preview_name
  local preview_name_safe
  local preview_b64
  local preview_count
  local sections
  local timing_stats
  local timing_count
  local timing_total
  local timing_label
  local final_metrics
  local final_resolution
  local final_resolution_0143
  local resolution_threshold
  local final_program
  local final_section
  local final_smpd
  local final_box
  local final_pgrp
  local final_nptcls
  local final_normal_stop
  local final_volume
  local volume_metrics
  local volume_box
  local volume_smpd
  local fallback_symmetry
  local original_smpd
  local original_smpd_label
  local result_status
  local result_class
  local has_ground_truth
  local original_output="$OUTPUT"
  local original_roots=("${SYSTEM_ROOTS[@]}")

  mkdir -p "$reports_dir"

  for system_root in "${original_roots[@]}"; do
    system_name="$(basename "$system_root")"
    system_name="${system_name//[^A-Za-z0-9._-]/_}"
    report_file="$reports_dir/report_${system_name}.html"
    SYSTEM_ROOTS=("$system_root")
    OUTPUT="$report_file"
    write_report_html
  done

  SYSTEM_ROOTS=("${original_roots[@]}")
  OUTPUT="$original_output"
  generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  if git -C "$SIMPLE_SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    simple_commit="$(git -C "$SIMPLE_SOURCE_DIR" rev-parse HEAD)"
  fi

  cat > "$output_dir/index.html" <<HTML_INDEX_HEAD
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SIMPLE data testing reports</title>
  <style>
    body {
      color: #111827;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.5;
      margin: 0;
      padding: 2rem;
    }
    main {
      margin: 0 auto;
      max-width: 960px;
    }
    h1 {
      font-size: 2rem;
      margin-bottom: 0.25rem;
    }
    .timestamp {
      color: #4b5563;
      margin-bottom: 2rem;
    }
    ul {
      list-style: none;
      padding: 0;
    }
    li + li {
      border-top: 1px solid #e5e7eb;
    }
    .report-row {
      align-items: center;
      display: flex;
      gap: 1rem;
      justify-content: space-between;
      min-height: 120px;
      padding: 0.75rem 0;
    }
    .report-info {
      display: flex;
      flex: 0 0 auto;
      flex-direction: column;
      gap: 0.2rem;
    }
    .report-timing {
      color: #4b5563;
      font-size: 0.9rem;
    }
    .result-line {
      align-items: center;
      display: flex;
      flex-wrap: wrap;
      gap: 0.35rem 0.6rem;
      margin-top: 0.35rem;
    }
    .result-badge {
      border-radius: 999px;
      display: inline-block;
      font-size: 0.78rem;
      font-weight: 750;
      padding: 0.15rem 0.55rem;
    }
    .result-pass {
      background: #dcfce7;
      color: #166534;
    }
    .result-fail {
      background: #fee2e2;
      color: #991b1b;
    }
    .result-missing {
      background: #fef3c7;
      color: #92400e;
    }
    .final-metrics {
      color: #374151;
      display: flex;
      flex-wrap: wrap;
      font-size: 0.82rem;
      gap: 0.2rem 0.75rem;
      margin-top: 0.3rem;
      max-width: 440px;
    }
    .final-metrics strong {
      color: #111827;
    }
    .final-metrics .metric-missing {
      color: #9a3412;
      font-weight: 650;
    }
    a {
      color: #0f766e;
      font-size: 1.1rem;
      font-weight: 650;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    .volume-previews {
      align-items: center;
      display: flex;
      flex: 1;
      gap: 0.5rem;
      justify-content: flex-end;
      min-width: 0;
    }
    .volume-previews img {
      background: #000;
      border: 1px solid #d1d5db;
      height: 108px;
      max-width: 260px;
      object-fit: contain;
      width: min(32vw, 260px);
    }
    .no-preview {
      color: #6b7280;
      font-size: 0.9rem;
    }
    @media (max-width: 640px) {
      .report-row {
        align-items: flex-start;
        flex-direction: column;
      }
      .volume-previews {
        justify-content: flex-start;
        width: 100%;
      }
      .volume-previews img {
        width: 100%;
      }
    }
  </style>
</head>
<body>
  <main>
    <h1>SIMPLE data testing reports</h1>
    <p class="timestamp">Generated ${generated_at} · SIMPLE commit <code>${simple_commit}</code></p>
    <ul>
HTML_INDEX_HEAD

  for system_root in "${original_roots[@]}"; do
    system_name="$(basename "$system_root")"
    system_name="${system_name//[^A-Za-z0-9._-]/_}"
    system_label="$(display_name_for_root "$system_root" | html_escape)"
    has_ground_truth=0
    if has_ground_truth_for_root "$system_root"; then
      has_ground_truth=1
    fi

    ROOT="$system_root"
    resolution_threshold=$(resolution_threshold_for_root "$system_root")
    sections=()
    while IFS= read -r section; do
      sections+=("$section")
    done < <(log_sections_for_root | sort_sections)
    timing_stats=$(timing_stats_for_sections "${sections[@]}")
    timing_count=${timing_stats%%|*}
    timing_total=${timing_stats#*|}
    if [[ $timing_count -gt 0 ]]; then
      timing_label="$(format_duration "$timing_total") total · $(format_timed_step_count "$timing_count")"
    else
      timing_label="No execution times recorded"
    fi

    final_metrics=$(final_volume_metrics_for_root || true)
    final_resolution=""
    final_resolution_0143=""
    final_program=""
    final_section=""
    final_smpd=""
    final_box=""
    final_pgrp=""
    final_nptcls=""
    final_corr=""
    final_corr_min=""
    final_corr_basis=""
    final_dock_direct=""
    final_dock_mirrored=""
    final_dock_selected=""
    final_dock_hand=""
    final_dock_hp=""
    final_dock_lp=""
    final_normal_stop=0
    if [[ -n "$final_metrics" ]]; then
      IFS='|' read -r final_resolution final_resolution_0143 final_program final_section \
        final_smpd final_box final_pgrp final_nptcls final_corr \
        final_corr_min final_corr_basis final_dock_direct final_dock_mirrored \
        final_dock_selected final_dock_hand final_dock_hp final_dock_lp \
        final_normal_stop <<< "$final_metrics"
    fi

    if [[ -z "$final_box" || -z "$final_smpd" ]]; then
      final_volume=$(final_volume_for_root "$system_root" || true)
      if [[ -n "$final_volume" ]]; then
        volume_metrics=$(volume_header_metrics "$final_volume" || true)
        volume_box=""
        volume_smpd=""
        if [[ -n "$volume_metrics" ]]; then
          IFS='|' read -r volume_box volume_smpd <<< "$volume_metrics"
          [[ -n "$final_box" ]] || final_box="$volume_box"
          [[ -n "$final_smpd" ]] || final_smpd="$volume_smpd"
        fi
      fi
    fi

    if [[ -z "$final_pgrp" ]]; then
      fallback_symmetry=$(symmetry_for_root "$system_root" || true)
      [[ -z "$fallback_symmetry" ]] || final_pgrp="$fallback_symmetry"
    fi

    original_smpd=$(original_sampling_for_root "$system_root" || true)
    original_smpd_label=$(input_sampling_label_for_root "$system_root")

    if [[ -z "$final_resolution" ]]; then
      result_status="NOT EVALUATED"
      result_class="result-missing"
    elif [[ "$final_normal_stop" != 1 ]]; then
      result_status="FAIL"
      result_class="result-fail"
    elif awk -v resolution="$final_resolution" \
      -v limit="$resolution_threshold" \
      'BEGIN { exit !(resolution <= limit) }'; then
      result_status="PASS"
      result_class="result-pass"
    else
      result_status="FAIL"
      result_class="result-fail"
    fi

    printf '      <li class="report-row"><div class="report-info"><a href="reports/report_%s.html">%s</a><span class="report-timing">%s</span>' \
      "$system_name" "$system_label" "$(printf '%s' "$timing_label" | html_escape)" >> "$output_dir/index.html"
    printf '<div class="result-line"><span class="result-badge %s">%s</span>' \
      "$result_class" "$result_status" >> "$output_dir/index.html"
    if [[ -n "$final_resolution" ]]; then
      printf '<span>Final resolution <strong>%s Å</strong> at FSC=0.5; required ≤ %s Å</span>' \
        "$(printf '%s' "$final_resolution" | html_escape)" \
        "$(printf '%s' "$resolution_threshold" | html_escape)" >> "$output_dir/index.html"
    else
      printf '<span>No final FSC=0.5 resolution was found</span>' >> "$output_dir/index.html"
    fi
    printf '</div>' >> "$output_dir/index.html"

    printf '<div class="final-metrics">' >> "$output_dir/index.html"
    printf '<span>FSC criterion: <strong>0.5</strong></span>' >> "$output_dir/index.html"
    printf '<span>Resolution limit: %s</span>' \
      "$(html_metric_value "$resolution_threshold" ' Å')" >> "$output_dir/index.html"
    if [[ -n "$final_resolution" || $has_ground_truth -eq 1 ]]; then
      printf '<span>FSC=0.5 resolution: %s</span>' \
        "$(html_metric_value "$final_resolution" ' Å')" >> "$output_dir/index.html"
    fi
    if [[ -n "$final_resolution_0143" || $has_ground_truth -eq 1 ]]; then
      printf '<span>FSC=0.143 resolution: %s</span>' \
        "$(html_metric_value "$final_resolution_0143" ' Å')" >> "$output_dir/index.html"
    fi
    if [[ $has_ground_truth -eq 1 ]]; then
      printf '<span>Map correlation: %s</span>' \
        "$(html_metric_value "$final_corr")" >> "$output_dir/index.html"
      printf '<span>Correlation minimum: %s</span>' \
        "$(html_metric_value "$final_corr_min")" >> "$output_dir/index.html"
      printf '<span>Correlation basis: %s</span>' \
        "$(html_metric_value "$final_corr_basis")" >> "$output_dir/index.html"
      printf '<span>Selected docking correlation: %s (%s)</span>' \
        "$(html_metric_value "$final_dock_selected")" \
        "$(printf '%s' "${final_dock_hand:-not found}" | html_escape)" >> "$output_dir/index.html"
      printf '<span>Docking correlation, direct: %s</span>' \
        "$(html_metric_value "$final_dock_direct")" >> "$output_dir/index.html"
      printf '<span>Docking correlation, mirrored: %s</span>' \
        "$(html_metric_value "$final_dock_mirrored")" >> "$output_dir/index.html"
      if [[ -n "$final_dock_hp" && -n "$final_dock_lp" ]]; then
        printf '<span>Docking band: <strong>%s–%s Å</strong></span>' \
          "$(printf '%s' "$final_dock_hp" | html_escape)" \
          "$(printf '%s' "$final_dock_lp" | html_escape)" >> "$output_dir/index.html"
      else
        printf '<span>Docking band: %s</span>' "$(html_metric_value '')" >> "$output_dir/index.html"
      fi
    fi
    if [[ -n "$final_program" || $has_ground_truth -eq 1 ]]; then
      printf '<span>Program: %s</span>' \
        "$(html_metric_value "$final_program")" >> "$output_dir/index.html"
    fi
    if [[ -n "$final_section" || $has_ground_truth -eq 1 ]]; then
      printf '<span>Stage: %s</span>' \
        "$(html_metric_value "$final_section")" >> "$output_dir/index.html"
    fi
    if [[ -n "$original_smpd" || $has_ground_truth -eq 1 ]]; then
      printf '<span>%s: %s</span>' \
        "$(printf '%s' "$original_smpd_label" | html_escape)" \
        "$(html_metric_value "$original_smpd" ' Å/px')" >> "$output_dir/index.html"
    fi
    if [[ -n "$final_smpd" || $has_ground_truth -eq 1 ]]; then
      printf '<span>Final map sampling: %s</span>' \
        "$(html_metric_value "$final_smpd" ' Å/px')" >> "$output_dir/index.html"
    fi
    if [[ -n "$final_box" || $has_ground_truth -eq 1 ]]; then
      printf '<span>Box: %s</span>' \
        "$(html_metric_value "$final_box" ' px')" >> "$output_dir/index.html"
    fi
    if [[ -n "$final_pgrp" || $has_ground_truth -eq 1 ]]; then
      printf '<span>Symmetry: %s</span>' \
        "$(html_metric_value "$final_pgrp")" >> "$output_dir/index.html"
    fi
    if [[ -n "$final_nptcls" || $has_ground_truth -eq 1 ]]; then
      printf '<span>Final active particles: %s</span>' \
        "$(html_metric_value "$final_nptcls")" >> "$output_dir/index.html"
    fi
    printf '</div>' >> "$output_dir/index.html"
    printf '</div><div class="volume-previews">' >> "$output_dir/index.html"

    preview_count=0
    while IFS= read -r preview; do
      preview_count=$((preview_count + 1))
      preview_name="$(basename "$preview")"
      preview_name_safe="$(printf '%s' "$preview_name" | html_escape)"
      preview_b64="$(base64_one_line "$preview")"
      printf '<img src="data:image/jpeg;base64,%s" alt="%s %s">' \
        "$preview_b64" "$system_label" "$preview_name_safe" >> "$output_dir/index.html"
    done < <(index_volume_preview_for_root "$system_root")

    if [[ $preview_count -eq 0 ]]; then
      printf '<span class="no-preview">No volume preview</span>' >> "$output_dir/index.html"
    fi

    printf '</div></li>\n' >> "$output_dir/index.html"
  done

  cat >> "$output_dir/index.html" <<'HTML_INDEX_FOOT'
    </ul>
  </main>
</body>
</html>
HTML_INDEX_FOOT

  echo "Pages index written to: $output_dir/index.html"
}

write_pages_site "$PAGES_OUTPUT_DIR"
