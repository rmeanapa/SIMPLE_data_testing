#!/usr/bin/env bash
# Submit three independent top-k campaigns using the existing SIMPLE build.
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 NEW_OUTPUT_DIRECTORY" >&2; exit 2; }
: "${SIMPLE_PATH:?Set SIMPLE_PATH to the SIMPLE build directory}"
checkout=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
simple_build=$(cd -- "$SIMPLE_PATH" && pwd -P)
[[ -x "$simple_build/bin/simple_exec" ]] || { echo 'Missing simple_exec' >&2; exit 1; }
command -v sbatch >/dev/null
output=$(realpath -m -- "$1")
mkdir -p -- "$(dirname -- "$output")"
mkdir -- "$output" # Refuse an existing campaign before any submission.
mkdir "$output/logs"
account=()
[[ -z ${SIMPLE_TEST_ACCOUNT:-} ]] || account=(--account="$SIMPLE_TEST_ACCOUNT")
pids=()
datasets=(betagal apof proteasome)
for dataset in "${datasets[@]}"; do
    (
        sbatch --wait --parsable --partition="${SIMPLE_TEST_PARTITION:-norm}" \
            --nodes=1 --ntasks=1 --cpus-per-task=80 \
            --mem="${SIMPLE_TEST_MEMORY:-128G}" --time="${SIMPLE_TEST_TIME:-24:00:00}" \
            "${account[@]}" --job-name="simple-topk-$dataset" --export=ALL \
            --chdir="$checkout" --output="$output/logs/$dataset-%j.out" \
            --error="$output/logs/$dataset-%j.err" \
            /dev/stdin "$checkout" "$simple_build" "$output/$dataset" "$dataset" <<'SBATCH' |
#!/usr/bin/env bash
set -euo pipefail
export SIMPLE_PATH=$2
export PATH="$SIMPLE_PATH/bin:$SIMPLE_PATH/scripts:$PATH"
export SIMPLE_QSYS=local
echo "Dataset: $4; job: $SLURM_JOB_ID; host: $(hostname)"
exec bash "$1/run_topk_comparison.sh" "$3" --checkout "$1" --build "$2" --datasets "$4"
SBATCH
        while IFS= read -r job; do
            printf '%s\t%s\n' "$dataset" "$job" | tee -a "$output/jobs.tsv"
        done
    ) &
    pids+=("$!")
done
failed=0
for index in "${!pids[@]}"; do
    if wait "${pids[$index]}"; then
        echo "Completed: ${datasets[$index]}"
    else
        echo "Failed: ${datasets[$index]} (submission or job failure)" >&2
        failed=1
    fi
done
exit "$failed"
