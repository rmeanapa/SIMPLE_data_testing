# SIMPLE Data Testing

- [Streptavidin report](https://rmeanapa.github.io/SIMPLE_data_testing/streptavidin/)
- [Betagal pose-continuous report](https://rmeanapa.github.io/SIMPLE_data_testing/betagal_pose_cont/)
- [Streptavidin pose-continous report](https://rmeanapa.github.io/SIMPLE_data_testing/streptavidin_pose_errors/)
- [Top-k reconstruction comparison](https://rmeanapa.github.io/SIMPLE_data_testing/topk_comparison/)
- [Three-state SNR 0.05 nightly benchmark](https://rmeanapa.github.io/SIMPLE_data_testing/snr005_nightly/)
- [Dataset reports](https://rmeanapa.github.io/SIMPLE_data_testing/)

The SNR 0.05 nightly uses one execution path:
`snr005_nightly_test.yml` → `submit_data_testing.sh snr005` → `snr005.sh`.
It imports the existing package stack with true CTF and zeroed poses, runs
`solve2D ncls=30 nthr=16`, then full `solve3D nstates=3 nparts=2 nthr=8 print_states=yes`.
A fixed `SIMPLE_SEED=20261113` makes nightly comparisons reproducible; the five
historical package runs used unset seeds and a shared solve2D result. Each nightly
builds its own solve2D result. No shortened stage ladder is requested.

The report scores the last iteration assignment against `data/labels_f05.txt`
with the package's `tools/acc3.py`. Separated means accuracy ≥0.90 and every recall
≥0.75; partial means accuracy ≥0.75 or exactly two recovered states. Both are
accepted as label-recovery outcomes. Incomplete runs and failed classifications
fail the report command. This acceptance rule is provisional: the package asks
for a 20-seed profile before setting a robustness floor, and the chosen fixed
seed has not yet been validated by a completed scientific run here.

**Label recovery does not establish map correctness.** The nightly does not dock
maps against the truth or measure per-state pose errors. The map comparison and
per-stage timing reference tables are historical measurements from the package,
not fresh nightly measurements. Runtime executable path, SHA-256, seed and
solve3D wall time are retained in `snr005/runtime.tsv` and linked from the report.
The workflow uses the existing build at `/home/meanapanedar2/SIMPLE/build` on its
runner; it does not rebuild this checkout.

Generate reference tables with `bash make_report.sh snr005` when no local
`snr005/` run exists, or pass the package directory explicitly. Set `SNR005_PACKAGE`
for a different package location. Pass the nightly `snr005/` run directory to
show its measured results and reference tables together. Generated pages go to
`build/` (or `REPORT_SITE_DIR`).
