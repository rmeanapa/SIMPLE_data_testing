#!/usr/bin/env python3
"""Offline fixtures for paired starts, failures, and published FSC metrics."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reporter = load('topk_report', ROOT / '.github/scripts/topk_report.py')


class ComparisonTests(unittest.TestCase):
    def test_real_recipes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _, build = self.fixture(root)
            result = subprocess.run(['bash', str(ROOT / 'run_topk_comparison.sh'),
                str(root / 'dry'), '--build', str(build), '--dry-run'],
                check=True, capture_output=True, text=True)
            manifest = json.loads(result.stdout)
            self.assertEqual(manifest['datasets'], list(reporter.DATASETS))
            self.assertEqual(manifest['topk'], [1, 3, 5, 10])
            self.assertFalse((root / 'dry').exists())

    def fixture(self, root):
        checkout = root / 'recipes'
        checkout.mkdir()
        (checkout / 'betagal.sh').write_text(
            'mkdir -p betagal; cd betagal\n'
            'simple_exec prg=solve3D_cavgs pgrp=d2 >> LOG 2>&1\n'
            'simple_exec prg=solve3D pgrp=d2 >> LOG 2>&1\n'
            'simple_exec prg=refine3D_auto pgrp=d2 >> LOG 2>&1\n')
        build = root / 'build'
        (build / 'bin').mkdir(parents=True)
        (build / 'bin/simple_exec').symlink_to('/usr/bin/true')
        return checkout, build

    def test_paired_starts_and_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            checkout, build = self.fixture(root)
            output = root / 'output'
            calls = root / 'calls.tsv'
            mock = r'''simple_exec() {
              local word program=''
              for word in "$@"; do
                case $word in prg=*) program=${word#prg=};; esac
              done
              printf '%s\t%s\n' "$SIMPLE_SEED" "$*" >> "$MOCK_CALLS"
              if [[ ${MOCK_FAIL:-no} == yes && " $* " == *' topk=3 '* ]]; then
                echo 'fixture failure'; return 7
              fi
              mkdir "1_$program"
              printf project > "1_$program/betagal.simple"
              printf map > "1_$program/rec_final_state01.mrc"
              if [[ $program == solve3D ]]; then
                echo 'SIMPLE_SOLVE3D NORMAL STOP'
              else
                echo 'SIMPLE_REFINE3D NORMAL STOP'
              fi
            }
            export -f simple_exec
            bash "$@"
            '''
            arguments = ['bash', '-c', mock, 'fixture', str(ROOT / 'run_topk_comparison.sh'),
                         str(output), '--checkout', str(checkout), '--build', str(build),
                         '--datasets', 'betagal']
            environment = dict(os.environ, MOCK_CALLS=str(calls))
            result = subprocess.run(arguments, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / 'campaign.json').read_text())
            self.assertEqual(manifest['status'], 'complete')
            self.assertEqual(len(manifest['results']), 8)
            lines = calls.read_text().splitlines()
            arm_args = [dict(a.split('=', 1) for a in line.split('\t')[1].split()) for line in lines[1:]]
            self.assertEqual([a['topk'] for a in arm_args], ['1', '3', '5', '10'] * 2)
            self.assertEqual(len({a['projfile'] for a in arm_args[:4]}), 1)
            self.assertEqual(len({a['projfile'] for a in arm_args[4:]}), 1)
            self.assertEqual(arm_args[4]['projfile'], manifest['results'][0]['project'])
            self.assertTrue(all(a['rec_backend'] == 'gridding' for a in arm_args))
            self.assertEqual(len({line.split('\t')[0] for line in lines}), 1)
            # Existing outputs are refused before any SIMPLE call.
            count = len(lines)
            result = subprocess.run(arguments, env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(calls.read_text().splitlines()), count)
            arguments[5] = str(root / 'failed')
            result = subprocess.run(arguments, env=dict(environment, MOCK_FAIL='yes'),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            failed = json.loads((root / 'failed/campaign.json').read_text())
            self.assertEqual(failed['status'], 'failed')
            self.assertIn('error', failed)
            self.assertEqual(len(failed['results']), 1)

    def test_report_success_failure_and_missing_fsc(self):
        with tempfile.TemporaryDirectory() as tmp:
            campaign = Path(tmp) / 'campaign'
            root = campaign / 'betagal'
            root.mkdir(parents=True)
            records = []
            for k in (1, 3, 5):
                arm = root / 'betagal/solve3D' / f'topk{k}'
                arm.mkdir(parents=True)
                text = ('>>> PROGRAM: solve3D\n'
                        'RESOLUTION AT FSC=0.500 DETERMINED TO: 4.25\n'
                        'RESOLUTION AT FSC=0.143 DETERMINED TO: 3.50\n'
                        'SIMPLE_SOLVE3D NORMAL STOP\n')
                if k == 3:
                    text += 'ERROR STOP fixture failure\n'
                if k == 5:
                    text = 'SIMPLE_SOLVE3D NORMAL STOP\n'
                (arm / 'LOG').write_text(text)
                if k != 3:
                    records.append(dict(program='solve3D', topk=k, seconds=120))
            (root / 'campaign.json').write_text(json.dumps(dict(
                status='failed', error='<fixture>', seed=20261029,
                binary_sha256='fixture-hash', results=records)))
            site = Path(tmp) / 'site'
            reporter.report(campaign, site)
            data = json.loads((site / 'results.json').read_text())['results']
            self.assertEqual(len(data), 24)
            self.assertEqual(data[0]['fsc05'], 4.25)
            self.assertEqual(data[0]['fsc0143'], 3.5)
            self.assertEqual(data[1]['status'], 'failed')
            self.assertEqual(data[1]['fsc05'], '')
            self.assertEqual(data[2]['status'], 'complete; FSC unavailable')
            self.assertEqual(data[3]['status'], 'missing')
            html = (site / 'index.html').read_text()
            self.assertIn('&lt;fixture&gt;', html)
            self.assertIn('2/8 completed', html)
            self.assertFalse(list(site.rglob('*.mrc')))
            empty_site = Path(tmp) / 'empty-site'
            reporter.report(Path(tmp) / 'absent', empty_site)
            self.assertIn('0/8 completed', (empty_site / 'index.html').read_text())

    def test_scheduler_submits_and_propagates_failure(self):
        # Bash function mocks work with noexec /tmp and need no Slurm installation.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            checkout, build = self.fixture(root)
            output = root / 'submitted'
            mock = r'''sbatch() {
              [[ " $* " == *' --wait '* && " $* " == *' --cpus-per-task=80 '* ]] || return 9
              cat > /dev/null
              printf '12345\n'
              [[ " $* " != *' --job-name=simple-topk-apof '* ]]
            }
            export -f sbatch
            bash "$1" "$2"
            '''
            result = subprocess.run(['bash', '-c', mock, 'fixture', str(ROOT / 'submit_topk_comparison.sh'), str(output)],
                                    env=dict(os.environ, SIMPLE_PATH=str(build)), capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(len((output / 'jobs.tsv').read_text().splitlines()), 3)
            self.assertIn('Failed: apof', result.stderr)


if __name__ == '__main__':
    unittest.main()
