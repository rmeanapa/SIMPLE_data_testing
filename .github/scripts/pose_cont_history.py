#!/usr/bin/env python3
"""Add successful pose-continuation Actions history to the existing HTML report."""

import csv
from datetime import datetime, timezone
import html
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
from urllib.error import URLError
from urllib.request import Request, build_opener
import zipfile


ARMS = ("default", "yes", "only")
REPO = os.environ["GH_REPO"]
SOURCE = Path(__file__).resolve().parents[2]


def api(endpoint):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise RuntimeError("Set GH_TOKEN or GITHUB_TOKEN to read Actions history")
    base = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    request = Request("{}/repos/{}/{}".format(base, REPO, endpoint), headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "SIMPLE-pose-cont-history",
    })
    # Artifact downloads redirect to signed storage URLs. Keep the token on
    # the initial API request, never on the redirected storage request.
    request.add_unredirected_header("Authorization", "Bearer " + token)
    with build_opener().open(request, timeout=60) as response:
        return response.read()


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
            universal_newlines=True)
        return metrics(output)


def history_graph(records):
    """Render a small, self-contained SVG without adding runner dependencies."""
    ordered = sorted(records.values(), key=lambda row: row["created_at"])
    times = [datetime.strptime(row["created_at"], "%Y-%m-%dT%H:%M:%SZ")
             .replace(tzinfo=timezone.utc).timestamp()
             for row in ordered]
    colors = ("#2563eb", "#d97706", "#15803d")
    esc = lambda value: html.escape(str(value), quote=True)
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 330" '
           'role="img" aria-labelledby="fsc-trend-title fsc-trend-desc" '
           'style="display:block;width:100%;max-width:820px;height:auto;background:white">',
           '<title id="fsc-trend-title">FSC resolution over time</title>',
           '<desc id="fsc-trend-desc">Two plots show resolution at FSC 0.5 and 0.143 '
           'for successful Actions runs. Lower resolution in Angstrom is better. '
           'Missing values interrupt lines. Each point links to its Actions run.</desc>',
           '<g font-family="sans-serif" font-size="11" fill="#374151">',
           '<text x="12" y="18" font-size="14">FSC resolution over time — lower is better</text>']
    for index, arm in enumerate(ARMS):
        x = 460 + 110 * index
        out.append(f'<line x1="{x}" y1="14" x2="{x+22}" y2="14" '
                   f'stroke="{colors[index]}" stroke-width="2" '
                   f'stroke-dasharray="{("none", "6 3", "2 3")[index]}"/>'
                   f'<text x="{x+28}" y="18">{arm}</text>')
    for panel, (key, criterion) in enumerate((("fsc05", "0.5"), ("fsc0143", "0.143"))):
        left, top, width, height = 62 + panel * 410, 60, 325, 205
        out.append(f'<text x="{left}" y="44" font-size="13">FSC={criterion} (Å)</text>')
        series = []
        for arm in ARMS:
            values = []
            for row in ordered:
                try:
                    value = float(row.get("metrics", {}).get(arm, {}).get(key))
                    values.append(value if math.isfinite(value) and value > 0 else None)
                except (TypeError, ValueError):
                    values.append(None)
            series.append(values)
        valid = [value for values in series for value in values if value is not None]
        if not valid:
            out.append(f'<text x="{left+30}" y="{top+100}">No successful FSC values available</text>')
            continue
        low, high = min(valid), max(valid)
        padding = max((high - low) * 0.15, high * 0.005, 0.01)
        low, high = max(0, low - padding), high + padding
        span = times[-1] - times[0]
        xs = [left + width * (stamp - times[0]) / span if span else left + width / 2
              for stamp in times]
        for tick in range(5):
            value = low + (high - low) * tick / 4
            y = top + height * (1 - tick / 4)
            out.append(f'<line x1="{left}" y1="{y:.2f}" x2="{left+width}" y2="{y:.2f}" '
                       f'stroke="#e5e7eb"/><text x="{left-8}" y="{y+4:.2f}" '
                       f'text-anchor="end">{value:.3f}</text>')
        out.append(f'<path d="M {left} {top} V {top+height} H {left+width}" '
                   'fill="none" stroke="#9ca3af"/>')
        for tick in range(3 if span else 1):
            fraction = tick / 2 if span else 0.5
            x = left + width * fraction
            stamp = times[0] + span * fraction
            label = datetime.fromtimestamp(stamp, timezone.utc).strftime("%Y-%m-%d %H:%M")
            anchor = "start" if fraction == 0 else "end" if fraction == 1 else "middle"
            out.append(f'<text x="{x:.2f}" y="{top+height+20}" text-anchor="{anchor}" '
                       f'font-size="9">{label}</text>')
        out.append(f'<text x="{left+width/2}" y="315" text-anchor="middle">Run started (UTC)</text>')
        for index, values in enumerate(series):
            previous = None
            for row, x, value in zip(ordered, xs, values):
                if value is None:
                    previous = None
                    continue
                y = top + height * (high - value) / (high - low)
                if previous is not None:
                    out.append(f'<line x1="{previous[0]:.2f}" y1="{previous[1]:.2f}" '
                               f'x2="{x:.2f}" y2="{y:.2f}" stroke="{colors[index]}" '
                               f'stroke-width="2" stroke-dasharray="{("none", "6 3", "2 3")[index]}"/>')
                previous = (x, y)
                title = (f'Run #{row["run_number"]}, {ARMS[index]}, '
                         f'{row["created_at"]}: FSC={criterion} at {value:g} Å')
                out.append(f'<a href="{esc(row["html_url"])}"><title>{esc(title)}</title>')
                # Different marker sizes/shapes keep identical arm values visible.
                if index == 0:
                    marker = f'<circle cx="{x:.2f}" cy="{y:.2f}" r="6"'
                elif index == 1:
                    marker = f'<rect x="{x-4:.2f}" y="{y-4:.2f}" width="8" height="8"'
                else:
                    marker = f'<path d="M {x:.2f} {y-3:.2f} L {x-3:.2f} {y+3:.2f} L {x+3:.2f} {y+3:.2f} Z"'
                out.append(marker + f' fill="white" stroke="{colors[index]}" stroke-width="1.5"/></a>')
    out.append('</g></svg>')
    return "\n".join(out)


def render(records, current):
    esc = lambda value: html.escape(str(value), quote=True)
    out = ['<section id="pose-cont-history"><h2>Successful Actions history</h2>',
           '<p>Final resolution in Å (lower is better). Each arm uses its final logged '
           'FSC estimate. Missing results are shown explicitly. The current run is '
           'listed separately until GitHub confirms success.</p>',
           history_graph(records),
           '<p><a href="pose_cont_fsc_history.svg" download>Download graph (SVG)</a></p>',
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
        except (subprocess.CalledProcessError, OSError, URLError, ValueError, KeyError,
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
        current["metrics"] = metrics(metric_file.read_text(encoding="utf-8")) if metric_file.exists() else {}
    (site / "pose_cont_history.json").write_text(json.dumps(
        {"successful_runs": list(records.values()), "current_run": current}, indent=2) + "\n",
        encoding="utf-8")
    (site / "pose_cont_fsc_history.svg").write_text(history_graph(records) + "\n", encoding="utf-8")
    fragment = render(records, current)
    for target in (site / "index.html", site / "reports/report_betagal_pose_cont.html"):
        if target.is_file():
            document = target.read_text(encoding="utf-8")
            marker = '<p>SIMPLE test run</p>'
            if marker not in document:
                raise RuntimeError(f"Report insertion point missing: {target}")
            report_fragment = fragment
            if target.parent.name == "reports":
                report_fragment = fragment.replace('href="pose_cont_fsc_history.svg"',
                                                   'href="../pose_cont_fsc_history.svg"')
            target.write_text(document.replace(marker, marker + "\n" + report_fragment, 1), encoding="utf-8")
    print(f"Reported FSC history for {len(records)} successful Actions runs")


if __name__ == "__main__":
    main()
