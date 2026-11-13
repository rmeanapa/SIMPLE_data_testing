#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$script_dir/../.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/snr005/3_solve3D" "$work/package/data" "$work/package/tools"
printf ' >>> PROGRAM: solve3D\nSIMPLE_SOLVE3D NORMAL STOP\n' > "$work/snr005/LOG"
printf '1\n2\n3\n' > "$work/snr005/3_solve3D/states_stage1.txt"
printf '# pind state updatecnt\n1 1 1\n2 2 1\n3 3 1\n' > "$work/snr005/3_solve3D/states_iter001.txt"
printf '1\n2\n3\n' > "$work/package/data/labels_f05.txt"
printf '#!/usr/bin/env python3\nprint("0.9686\\t0.9170\\t0.9902,0.9526,0.9996\\t0:0,1:1,2:1,3:1\\t0\\tseparated")\n' > "$work/package/tools/acc3.py"

REPORT_SNR005_PACKAGE="$work/package" REPORT_SITE_DIR="$work/site" \
  bash "$root/make_report.sh" "$work/snr005"
grep -q 'Three-state recovery against simulation truth' "$work/site/index.html"
grep -q '0.9686' "$work/site/index.html"
grep -q 'stage 1' "$work/site/index.html"
grep -q 'separated' "$work/site/index.html"
[[ -f "$work/site/comparisons/snr005/results.tsv" ]]

printf '#!/usr/bin/env python3\nprint("0.5000\\t0.1000\\t0.5,0.5,0.5\\t0:0,1:1,2:1,3:1\\t0\\tfailed")\n' > "$work/package/tools/acc3.py"
if REPORT_SNR005_PACKAGE="$work/package" REPORT_SITE_DIR="$work/failed-site" \
    bash "$root/make_report.sh" "$work/snr005"; then
  echo 'FAIL: failed scientific classification did not fail make_report.sh' >&2
  exit 1
fi
grep -q 'failed' "$work/failed-site/index.html"

if (( BASH_VERSINFO[0] >= 4 )); then
  mkdir -p "$work/build/bin" "$work/submission"
  ln -s "$(type -P true)" "$work/build/bin/simple_exec"
  export MOCK_SBATCH_ARGS="$work/sbatch-args.txt"
  sbatch() {
    printf '%s\n' "$*" > "$MOCK_SBATCH_ARGS"
    printf '4242\n'
  }
  export -f sbatch
  (
    cd "$work/submission"
    SIMPLE_PATH="$work/build" bash "$root/submit_data_testing.sh" snr005
  )
  grep -q -- '--partition=norm' "$MOCK_SBATCH_ARGS"
  grep -q -- '--cpus-per-task=16' "$MOCK_SBATCH_ARGS"
  grep -q -- '--mem=64G' "$MOCK_SBATCH_ARGS"
  grep -q -- '--time=12:00:00' "$MOCK_SBATCH_ARGS"
  grep -q 'snr005 4242' "$work/submission/jobs.txt"
fi
echo 'SNR005 make_report integration checks passed.'
