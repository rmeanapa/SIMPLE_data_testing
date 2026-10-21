#!/usr/bin/env python3
"""Add successful pose-continuation Actions history to the existing HTML report."""

import csv
import html
import io
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
import zipfile


ARMS = ("default", "yes", "only")
REPO = os.environ["GH_REPO"]
SOURCE = Path(__file__).resolve().parents[2]


def api(endpoint):
    return subprocess.check_output(["gh", "api", f"repos/{REPO}/{endpoint}"])


def pages(endpoint, key):
    page = 1
    while True:
        data = json.loads(api(f"{endpoint}&per_page=100&page={page}"))[key]
        yield from data
        if len(data) < 100:
            return
        page += 1


def metrics(text):
    return {row["arm"]: {key: row[key] or None for key in ("fsc05", "fsc0143")}
            for row in csv.DictReader(io.StringIO(text), delimiter="\t")}


def archive(artifact):
    return zipfile.ZipFile(io.BytesIO(api(f"actions/artifacts/{artifact['id']}/zip")))


def legacy_metrics(artifacts):
    """Extract only the three arm LOGs and use the existing report parser."""
    artifact = next((a for a in artifacts if a["name"].startswith("betagal_pose_cont-")
                     and a["name"] != "betagal_pose_cont-report-site"), None)
    if artifact is None:
        return {}
    with archive(artifact) as saved, tempfile.TemporaryDirectory() as directory:
        root = Path(directory) / "betagal_pose_cont"
        root.mkdir()
        for name in saved.namelist():
            path = PurePosixPath(name)
            if path.name != "LOG":
                continue
            for arm in ARMS:
                if path.parent.name.endswith(f"_refine3D_auto_pose_cont_{arm}"):
                    target = root / f"00_refine3D_auto_pose_cont_{arm}" / "LOG"
                    target.parent.mkdir(exist_ok=True)
                    target.write_bytes(saved.read(name))
        output = subprocess.check_output(
            ["bash", str(SOURCE / "make_report.sh"), "--pose-cont-metrics", str(root)],
            text=True)
        return metrics(output)


def render(records, current):
    esc = lambda value: html.escape(str(value), quote=True)
    out = ['<section id="pose-cont-history"><h2>Successful Actions history</h2>',
           '<p>Final resolution in Å (lower is better). Each arm uses its final logged '
           'FSC estimate. Missing results are shown explicitly. The current run is '
           'listed separately until GitHub confirms success.</p>',
           '<div style="overflow-x:auto"><table><thead><tr><th>Run / attempt</th>'
           '<th>Started (UTC)</th><th>Commit</th><th>Comparison</th>'
           '<th>FSC=0.5 (Å)</th><th>FSC=0.143 (Å)</th></tr></thead><tbody>']
    ordered = sorted(records.values(), key=lambda row: row["created_at"], reverse=True)
    if not ordered:
        out.append('<tr><td colspan="6">No previous successful runs found.</td></tr>')
    for row in ([current] if current else []) + ordered:
        label = f"#{row['run_number']} / {row['run_attempt']}"
        if row is current:
            label += " (current; success pending)"
        for arm in ARMS:
            values = row.get("metrics", {}).get(arm, {})
            out.append(f'<tr><td><a href="{esc(row["html_url"])}">{esc(label)}</a></td>'
                       f'<td>{esc(row["created_at"])}</td><td>{esc(row["head_sha"][:8])}</td>'
                       f'<td>{esc(arm)}</td><td>{esc(values.get("fsc05") or "unavailable")}</td>'
                       f'<td>{esc(values.get("fsc0143") or "unavailable")}</td></tr>')
    out.append('</tbody></table></div></section>')
    return "\n".join(out)


def main():
    site = Path(sys.argv[1])
    if not (site / "index.html").is_file():
        raise RuntimeError("Current report is missing; cannot add Actions history")
    records = {}
    runs = list(pages("actions/workflows/betagal_pose_cont_test.yml/runs?status=success",
                      "workflow_runs"))
    successful = {str(run["id"]): run for run in runs}
    for run in runs:
        key = str(run["id"])
        if (key in records and records[key].get("metrics")
                and records[key]["run_attempt"] == run["run_attempt"]):
            continue
        row = {field: run[field] for field in
               ("id", "run_number", "run_attempt", "created_at", "head_sha", "html_url")}
        try:
            artifacts = [a for a in pages(f"actions/runs/{key}/artifacts?", "artifacts")
                         if not a["expired"]]
            report = next((a for a in artifacts
                           if a["name"] == "betagal_pose_cont-report-site"), None)
            if report:
                with archive(report) as saved:
                    if "pose_cont_history.json" in saved.namelist():
                        previous = json.loads(saved.read("pose_cont_history.json"))
                        # These rows were confirmed successful by earlier reports.
                        for recorded in previous["successful_runs"]:
                            records.setdefault(str(recorded["id"]), recorded)
                        candidate = previous.get("current_run")
                        if candidate and str(candidate["id"]) in successful:
                            metadata = successful[str(candidate["id"])]
                            if candidate["run_attempt"] == metadata["run_attempt"]:
                                records[str(candidate["id"])] = candidate
                    if "pose_cont_metrics.tsv" in saved.namelist():
                        row["metrics"] = metrics(saved.read("pose_cont_metrics.tsv").decode())
            if not row.get("metrics") and not records.get(key, {}).get("metrics"):
                row["metrics"] = legacy_metrics(artifacts)
        except (subprocess.CalledProcessError, OSError, ValueError, KeyError,
                zipfile.BadZipFile) as error:
            print(f"::warning::Cannot recover FSC values for successful run {key}: {error}")
        if key not in records or row.get("metrics"):
            records[key] = row
    # A rerun may have changed outcome or attempt since an earlier report.
    for key in list(records):
        if key in successful and records[key]["run_attempt"] != successful[key]["run_attempt"]:
            del records[key]
    current = None
    if os.environ.get("GITHUB_RUN_ID"):
        run = json.loads(api(f"actions/runs/{os.environ['GITHUB_RUN_ID']}"))
        current = {field: run[field] for field in
                   ("id", "run_number", "run_attempt", "created_at", "head_sha", "html_url")}
        metric_file = site / "pose_cont_metrics.tsv"
        current["metrics"] = metrics(metric_file.read_text()) if metric_file.exists() else {}
    (site / "pose_cont_history.json").write_text(json.dumps(
        {"successful_runs": list(records.values()), "current_run": current}, indent=2) + "\n")
    fragment = render(records, current)
    for target in (site / "index.html", site / "reports/report_betagal_pose_cont.html"):
        if target.is_file():
            document = target.read_text()
            marker = '<p>SIMPLE test run</p>'
            if marker not in document:
                raise RuntimeError(f"Report insertion point missing: {target}")
            target.write_text(document.replace(marker, marker + "\n" + fragment, 1))
    print(f"Reported FSC history for {len(records)} successful Actions runs")


if __name__ == "__main__":
    main()
