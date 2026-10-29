#!/usr/bin/env python3
"""Report all 24 expected top-k arms, including failed and missing results."""
import argparse
import csv
from datetime import datetime, timezone
import html
import json
import math
import os
from pathlib import Path
import shutil
import subprocess

DATASETS = ('betagal', 'apof', 'proteasome')
PROGRAMS = ('solve3D', 'refine3D_auto')
TOPK = (1, 3, 5, 10)


def positive(value):
    try:
        number = float(value.replace('D', 'E').replace('d', 'e'))
        return number if math.isfinite(number) and number > 0 else None
    except (ValueError, AttributeError):
        return None


def report(campaign, site):
    site.mkdir(parents=True, exist_ok=False)
    logs = site / 'logs'
    logs.mkdir()
    parser = Path(__file__).resolve().parents[2] / 'make_report.sh'
    esc = lambda value: html.escape(str(value), quote=True)
    rows, manifests = [], {}
    for dataset in DATASETS:
        manifest_path = campaign / dataset / 'campaign.json'
        manifest = {}
        if manifest_path.is_file():
            manifest = json.loads(manifest_path.read_text())
            shutil.copy2(manifest_path, site / f'{dataset}-campaign.json')
        manifests[dataset] = manifest
        records = {(r['program'], r['topk']): r for r in manifest.get('results', [])}
        for program in PROGRAMS:
            for k in TOPK:
                record = records.get((program, k), {})
                arm = campaign / dataset / dataset / program / f'topk{k}'
                log = arm / 'LOG'
                row = dict(dataset=dataset, program=program, topk=k,
                           status='complete' if record else 'missing', seconds=record.get('seconds', ''),
                           fsc05='', fsc0143='', log='')
                if log.is_file():
                    destination = logs / f'{dataset}-{program}-topk{k}.log'
                    shutil.copy2(log, destination)
                    row['log'] = destination.relative_to(site).as_posix()
                    if not record:
                        row['status'] = 'failed' if manifest.get('status') == 'failed' else 'incomplete'
                    result = subprocess.run(['bash', str(parser), '--final-metrics', str(arm)],
                                            capture_output=True, text=True)
                    if result.returncode == 0:
                        values = result.stdout.strip().split('|')
                        if len(values) == 18 and values[-1] == '1' and record:
                            for key, value in zip(('fsc05', 'fsc0143'), values):
                                number = positive(value)
                                if number is not None:
                                    row[key] = number
                if record and (row['fsc05'] == '' or row['fsc0143'] == ''):
                    row['status'] = 'complete; FSC unavailable'
                rows.append(row)
        for name, source in (('prepare', campaign / dataset / 'PREPARE_LOG'),
                             ('preprocessing', campaign / dataset / dataset / dataset / 'LOG')):
            if source.is_file():
                shutil.copy2(source, logs / f'{dataset}-{name}.log')

    with (site / 'metrics.tsv').open('w', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]), delimiter='\t')
        writer.writeheader()
        writer.writerows(rows)
    summary = {'generated_at': datetime.now(timezone.utc).isoformat(),
               'campaigns': manifests, 'results': rows}
    (site / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
    content = ['<!doctype html><html lang="en"><meta charset="utf-8">',
               '<meta name="viewport" content="width=device-width,initial-scale=1">',
               '<title>SIMPLE top-k reconstruction comparison</title>',
               '<style>body{font:16px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#172033}'
               'table{border-collapse:collapse;width:100%;margin:1rem 0}th,td{padding:.65rem;text-align:left;'
               'border-bottom:1px solid #ddd}.incomplete{background:#fff0ef}.scroll{overflow-x:auto}'
               'a{color:#185abc}code{overflow-wrap:anywhere}</style>',
               '<a href="../">All SIMPLE reports</a><h1>Top-k reconstruction comparison</h1>',
               '<p>β-galactosidase, apoferritin, and proteasome; topk=1, 3, 5, 10. '
               'Both solve3D and refine3D_auto use the gridding backend.</p>',
               '<p>Each dataset is prepared once. The solve3D arms share prepared input; '
               'every refinement arm starts from the topk=1 solve3D project. The initial seed '
               'is shared; extra pose draws can change later random draws.</p>',
               '<p>FSC resolutions are final logged half-map estimates in Å (lower is better). '
               'Missing values are shown explicitly. Times include the complete invocation.</p>',
               f'<p>Generated {esc(summary["generated_at"])}. '
               '<a href="metrics.tsv">Download metrics</a> · <a href="results.json">Run metadata</a></p>']
    actions_url = os.environ.get('GITHUB_SERVER_URL', 'https://github.com')
    repository, run_id = os.environ.get('GITHUB_REPOSITORY'), os.environ.get('GITHUB_RUN_ID')
    if repository and run_id:
        content.append(f'<p><a href="{esc(actions_url)}/{esc(repository)}/actions/runs/{esc(run_id)}">Actions run and scheduler logs</a></p>')
    for dataset in DATASETS:
        manifest = manifests[dataset]
        completed = sum(r['dataset'] == dataset and r['status'].startswith('complete') for r in rows)
        content.append(f'<h2>{esc(dataset)} — {completed}/8 completed</h2>')
        content.append(f'<p>Campaign status: {esc(manifest.get("status", "not started"))}. '
                       f'{esc(manifest.get("error", ""))}</p>')
        if manifest:
            content.append(f'<p>Seed {esc(manifest["seed"])}; binary SHA-256 '
                           f'<code>{esc(manifest["binary_sha256"])}</code>. '
                           f'<a href="{dataset}-campaign.json">Campaign manifest</a></p>')
        for kind in ('prepare', 'preprocessing'):
            if (logs / f'{dataset}-{kind}.log').is_file():
                content.append(f'<a href="logs/{dataset}-{kind}.log">{kind} log</a> ')
        content.append('<div class="scroll"><table><thead><tr><th>Workflow</th><th>topk</th>'
                       '<th>Status</th><th>FSC=0.5 (Å)</th><th>FSC=0.143 (Å)</th>'
                       '<th>Time (min)</th><th>Log</th></tr></thead><tbody>')
        for row in (r for r in rows if r['dataset'] == dataset):
            values = [row['program'], row['topk'], row['status'],
                      row['fsc05'] if row['fsc05'] != '' else 'unavailable',
                      row['fsc0143'] if row['fsc0143'] != '' else 'unavailable',
                      f'{row["seconds"] / 60:.2f}' if row['seconds'] != '' else 'unavailable']
            css = '' if row['status'] == 'complete' else ' class="incomplete"'
            content.append(f'<tr{css}>' + ''.join(f'<td>{esc(v)}</td>' for v in values)
                           + (f'<td><a href="{esc(row["log"])}">Log</a></td>' if row['log'] else '<td>unavailable</td>') + '</tr>')
        content.append('</tbody></table></div>')
    content.append('</html>')
    (site / 'index.html').write_text('\n'.join(content) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign', type=Path)
    parser.add_argument('site', type=Path)
    args = parser.parse_args()
    report(args.campaign.resolve(), args.site.resolve())
