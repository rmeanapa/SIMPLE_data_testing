#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$script_dir/../.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/snr005/3_solve3D/state_exports" "$work/package/data" "$work/package/tools"
printf ' >>> PROGRAM: solve3D\nSIMPLE_SOLVE3D NORMAL STOP\n' > "$work/snr005/LOG"
printf '1\n2\n3\n' > "$work/snr005/3_solve3D/state_exports/states_stage1.txt"
printf '# pind state updatecnt\n1 1 1\n2 2 1\n3 3 1\n' > "$work/snr005/3_solve3D/state_exports/states_iter001.txt"
printf '1\n2\n3\n' > "$work/package/data/labels_f05.txt"
printf '#!/usr/bin/env python3\nimport math\nassert math.comb(5, 2) == 10\nprint("0.9686\\t0.9170\\t0.9902,0.9526,0.9996\\t0:0,1:1,2:1,3:1\\t0\\tseparated")\n' > "$work/package/tools/acc3.py"

# Exercise the same figures and log sections the production nightly publishes.
mkdir -p "$work/snr005/1_import_particles" "$work/snr005/2_solve2D" "$work/package/results"
cat > "$work/snr005/LOG" <<'LOG'
 >>> PROGRAM: import_particles
>>> EXECUTION DIRECTORY: 1_import_particles
**** IMPORT_PARTICLES NORMAL STOP ****
**** Execution time: 7.4 seconds
 >>> PROGRAM: solve2D
>>> EXECUTION DIRECTORY: 2_solve2D
CLASS: 1 RANK: 1 POP: 3 RES: 6.00
**** SIMPLE_SOLVE2D NORMAL STOP ****
**** Execution time: 1610.5 seconds
 >>> PROGRAM: solve3D
>>> EXECUTION DIRECTORY: 3_solve3D
>>> RESOLUTION @ FSC=0.143 AVG/SDEV/MIN/MAX: 7.500 0.100 7.400 7.600
>>> RESOLUTION @ FSC=0.5 AVG/SDEV/MIN/MAX: 8.500 0.100 8.400 8.600
**** SIMPLE_SOLVE3D NORMAL STOP ****
**** SIMPLE Git Commit: 12345678
**** Execution time: 21061.3 seconds
LOG
printf 'run\taccuracy\n1\t0.9962\n' > "$work/package/results/summary.tsv"
cat > "$work/package/README.md" <<'REFERENCE'
| Path | What it is |
|---|---|
| data/labels_f05.txt | Truth labels |

| State | Assembly | Particles |
|---|---|---|
| 1 | 8C9C | 1 |

| Run | Final accuracy | Recall | ARI | Verdict | Wall time |
|---|---|---|---|---|---|
| 1 | 0.9962 | 0.998 / 0.995 / 0.999 | 0.988 | separated | 7 h 27 min |

| Run | Stage 1 |
|---|---|
| 1 | 0.789 |

| Stage | 1 |
|---|---|
| Iterations | 20 |
| Time | 5 min |

| Run | 8C9C (state 1) |
|---|---|
| 1 | wrong (best match cc 0.35) |
REFERENCE
python3 - "$work/snr005" <<'IMAGES'
from pathlib import Path
import sys
root = Path(sys.argv[1])
# JPEG sentinels: the report embeds bytes without decoding them.
for state in range(1, 4):
    for suffix in [''] + ['_stage%02d' % stage for stage in range(1, 6)]:
        for prefix in ('orientations_distribution', 'orthogonal_reprojs'):
            (root / '3_solve3D' / ('%s_state%02d%s.jpg' % (prefix, state, suffix))).write_bytes(b'\xff\xd8\xff\xd9')
(root / '2_solve2D' / 'cavgs_iter030.jpg').write_bytes(b'\xff\xd8\xff\xd9')
IMAGES

printf 'field\tvalue\nseed\t20261113\nsolve3d_seconds\t20400\n' > "$work/snr005/runtime.tsv"
REPORT_SNR005_PACKAGE="$work/package" REPORT_SITE_DIR="$work/site" \
  bash "$root/make_report.sh" "$work/snr005"
grep -q 'Three-state recovery against simulation truth' "$work/site/index.html"
grep -q '0.9686' "$work/site/index.html"
grep -q 'stage 1' "$work/site/index.html"
grep -q 'separated' "$work/site/index.html"
[[ -f "$work/site/comparisons/snr005/results.tsv" ]]
[[ -f "$work/site/comparisons/snr005/score_errors.log" ]]
[[ ! -s "$work/site/comparisons/snr005/score_errors.log" ]]
grep -q 'Scorer diagnostic' "$work/site/index.html"
grep -q '5h 40m' "$work/site/index.html"
grep -q 'comparisons/snr005/runtime.tsv' "$work/site/index.html"
cmp "$work/snr005/runtime.tsv" "$work/site/comparisons/snr005/runtime.tsv"

# Figure and log preservation must hold in the uploaded webpage assets too.
bash "$script_dir/package_report_site.sh" "$work/site" "$work/webpage"
python3 - "$work/site/index.html" "$work/site/reports/report_snr005.html" "$work/webpage/index.html" <<'CHECK'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Report(HTMLParser):
    def __init__(self):
        super().__init__()
        self.images = []
    def handle_starttag(self, tag, attrs):
        if tag == 'img':
            attrs = dict(attrs)
            assert attrs.get('src', '').startswith('data:image/jpeg;base64,')
            self.images.append(attrs.get('alt', ''))

for filename in sys.argv[1:]:
    text = Path(filename).read_text()
    report = Report()
    report.feed(text)
    assert len(report.images) == 37, (filename, len(report.images))
    assert len(set(report.images)) == 37
    assert 'cavgs_iter030.jpg' in report.images
    last_reference = text.index('Reference maps against the truth')
    details = text.index('Nightly run details')
    assert last_reference < details < text.index('Execution times')
    for content in ('21061.3 seconds', '1610.5 seconds', '7.4 seconds',
                    'FSC=0.143 resolution: 7.500 A', 'FSC=0.5 resolution: 8.500 A',
                    'CLASS: 1 RANK: 1 POP: 3 RES: 6.00', 'SIMPLE Git Commit: 12345678',
                    'LOG summary: PROGRAM import_particles', 'LOG summary: PROGRAM solve2D',
                    'LOG summary: PROGRAM solve3D'):
        assert content in text, (filename, content)
        assert text.index(content) > details, (filename, content)
print('Nightly details survive generation and packaging: 37 figures, all step timings, FSC and log summaries.')
CHECK

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

# A retained high-scoring iteration must not certify an interrupted run.
printf '#!/usr/bin/env python3\nprint("0.9686\\t0.9170\\t0.99,0.95,1.0\\t0:0,1:1,2:1,3:1\\t0\\tseparated")\n' > "$work/package/tools/acc3.py"
cp "$work/snr005/LOG" "$work/complete-log"
printf ' >>> PROGRAM: solve3D\n' > "$work/snr005/LOG"
if REPORT_SNR005_PACKAGE="$work/package" REPORT_SITE_DIR="$work/incomplete-site" \
    bash "$root/make_report.sh" "$work/snr005"; then
    echo 'FAIL: incomplete run was accepted' >&2; exit 1
fi
grep -q 'INCOMPLETE' "$work/incomplete-site/index.html"
! grep -q $'^final\t' "$work/incomplete-site/comparisons/snr005/results.tsv"
cp "$work/complete-log" "$work/snr005/LOG"

printf ' >>> PROGRAM: solve3D\nERROR STOP\nSIMPLE_SOLVE3D NORMAL STOP\n' > "$work/snr005/LOG"
if REPORT_SNR005_PACKAGE="$work/package" REPORT_SITE_DIR="$work/error-site" \
    bash "$root/make_report.sh" "$work/snr005"; then
    echo 'FAIL: error log with a normal-stop marker was accepted' >&2; exit 1
fi
! grep -q $'^final\t' "$work/error-site/comparisons/snr005/results.tsv"
