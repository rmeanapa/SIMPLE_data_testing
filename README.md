# SIMPLE Data Testing

- [Streptavidin report](https://rmeanapa.github.io/SIMPLE_data_testing/streptavidin/)
- [Betagal pose-continuous report](https://rmeanapa.github.io/SIMPLE_data_testing/betagal_pose_cont/)
- [Streptavidin pose-continous report](https://rmeanapa.github.io/SIMPLE_data_testing/streptavidin_pose_errors/)
- [Top-k reconstruction comparison](https://rmeanapa.github.io/SIMPLE_data_testing/topk_comparison/)
- [Dataset reports](https://rmeanapa.github.io/SIMPLE_data_testing/)


The dataset FSC history includes recovered reports from October 23 through
November 3, 2026 in `.github/data/fsc_history.tsv`. `make_report.sh` merges this
baseline with the local or published history automatically, preserving live
corrections and removing duplicate snapshots. The generated history remains in
`build/fsc_history.tsv`; the default table shows the latest ten runs. Set
`REPORT_FSC_HISTORY_LIMIT=0` to display every saved run. Run
`bash .github/scripts/test_dataset_fsc_history.sh` for offline merge/display checks.

To republish the recovered history without running datasets, manually dispatch
**Recover and publish dataset FSC history** (`publish_dataset_history.yml`). It
updates the latest dataset report, archives the corrected report for subsequent
publishers, restores all independent reports, and deploys the complete Pages site.
The local equivalent is `bash make_report.sh --recover-fsc-history REPORT_SITE`.
