# SIMPLE Data Testing

- [Streptavidin report](https://rmeanapa.github.io/SIMPLE_data_testing/streptavidin/)
- [Betagal pose-continuous report](https://rmeanapa.github.io/SIMPLE_data_testing/betagal_pose_cont/)
- [Streptavidin pose-continous report](https://rmeanapa.github.io/SIMPLE_data_testing/streptavidin_pose_errors/)
- [Top-k reconstruction comparison](https://rmeanapa.github.io/SIMPLE_data_testing/topk_comparison/)
- [Three-state SNR 0.05 nightly benchmark](https://rmeanapa.github.io/SIMPLE_data_testing/snr005_nightly/)
- [Dataset reports](https://rmeanapa.github.io/SIMPLE_data_testing/)

The scheduled simulated molecular workflow runs `suite=6vxx`. The `1jxy`
simulated workflow was removed from SIMPLE and is excluded from submissions
and report inputs until it is reintroduced. Archived FSC history is retained.

## SIMPLE log format compatibility

SIMPLE commit `86babf86b` (November 15, 2026) changed its iteration log labels
from `AVG/SDEV/MIN/MAX:` to `AVG/SDEV/MIN/MAX`. The dataset workflows completed,
but this repository's report parser still required the colon. Consequently,
runs #65 and #66 displayed empty experimental FSC columns and `NOT EVALUATED`.

The report parser and regression fixtures now accommodate SIMPLE's changed
output while continuing to read archived logs with a colon. This adapts the
test-reporting tools to SIMPLE; the scientific tests and quality thresholds
are unchanged. Existing published reports need regeneration from retained
logs to repair their missing values.

Run the offline FSC parsing and history regression checks with:

```sh
bash .github/scripts/test_dataset_fsc_history.sh
```
