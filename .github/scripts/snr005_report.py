#!/usr/bin/env python3
"""Render the benchmark package's historical tables independently of nightly scores."""
import html
import re
from pathlib import Path
import shutil
import sys


def esc(value):
    return html.escape(str(value), quote=True)


def reference_tables(package: Path, site: Path) -> list:
    """Keep the package's documented tables, including stopped-run caveats."""
    readme = package / "README.md"
    if not (package / "results" / "summary.tsv").is_file() or not readme.is_file():
        return ['<p>Reference package tables are unavailable. Set <code>SNR005_PACKAGE</code> to the benchmark package.</p>']
    text = readme.read_text(encoding="utf-8", errors="replace")
    titles = {
        "Path": "Package contents", "State": "Truth populations",
        "Run|Final accuracy": "Reference runs: final accuracy, recall, ARI, verdict and wall time",
        "Run|Stage 1": "Reference accuracy by stage",
        "Stage": "Reference iterations and time per stage (run 4)",
        "Run|8C9C": "Reference maps against the truth",
    }
    output = ['<h2>Benchmark reference results</h2>',
              '<p>Historical reference runs from the benchmark package (HEAD 1c12bb4eb), '
              'not measurements of this nightly build. Run 5 was stopped at iteration 82; '
              'its scores are provisional. Label separation alone does not establish map correctness: '
              'runs 1 and 3 have a wrong state-1 map.</p>',
              '<p><a href="reference_README.txt">Full benchmark description and caveats</a> · '
              '<a href="reference_summary.tsv">Reference measurements (TSV)</a></p>']
    shutil.copyfile(readme, site / "reference_README.txt")
    shutil.copyfile(package / "results" / "summary.tsv", site / "reference_summary.tsv")
    lines = text.splitlines()
    index = 0
    while index + 1 < len(lines):
        if not lines[index].startswith("|") or not re.fullmatch(r"[| :\-]+", lines[index + 1]):
            index += 1
            continue
        headers = [cell.strip() for cell in lines[index].strip("|").split("|")]
        title = next((value for key, value in titles.items()
                      if "|".join(headers).startswith(key)), "Reference measurements")
        output.append(f'<h3>{esc(title)}</h3><div class="scroll"><table><thead><tr>' +
                      ''.join(f'<th>{esc(cell)}</th>' for cell in headers) + '</tr></thead><tbody>')
        index += 2
        while index < len(lines) and lines[index].startswith("|"):
            cells = [cell.strip() for cell in lines[index].strip("|").split("|")]
            output.append('<tr>' + ''.join(f'<td>{esc(cell)}</td>' for cell in cells) + '</tr>')
            index += 1
        output.append('</tbody></table></div>')
    return output


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--reference-tables":
        print("\n".join(reference_tables(Path(sys.argv[2]), Path(sys.argv[3]))))
        return
    if len(sys.argv) != 3:
        raise SystemExit("Usage: snr005_report.py PACKAGE NEW_SITE_DIRECTORY")
    package, site = map(Path, sys.argv[1:])
    if not (package / "results" / "summary.tsv").is_file() or not (package / "README.md").is_file():
        raise SystemExit("Missing reference package README or results/summary.tsv")
    site.mkdir(parents=True, exist_ok=False)
    page = ['<!doctype html><html lang="en"><meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width,initial-scale=1">',
            '<title>SNR 0.05 benchmark reference</title>',
            '<style>body{font:16px/1.45 system-ui;max-width:1100px;margin:auto;padding:2rem;color:#172033}'
            'table{border-collapse:collapse;width:100%;margin:1rem 0}th,td{border:1px solid #ccd3dc;padding:.55rem;text-align:left}'
            'th{background:#eef2f7}.scroll{overflow-x:auto}</style>',
            '<h1>Three-state SNR 0.05 benchmark</h1>']
    page.extend(reference_tables(package, site))
    page.append('</html>')
    (site / "index.html").write_text("\n".join(page) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
