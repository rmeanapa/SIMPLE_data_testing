#!/usr/bin/env python3
"""Bounded random pose errors using SIMPLE's existing text orientation I/O.

SIMPLE encodes/decodes every particle field. Only its ptcl3D payload is copied
into an otherwise byte-identical project. The 800-byte binoris header consists
of 20 records of five native int64 values (simple_binoris.f90). Refuse unknown
layouts or any lossy native text round trip, rather than rewrite other fields.
No third-party Python modules or modified SIMPLE executable are needed.
"""
import math
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
import tempfile

POSE_KEYS = ('e1', 'e2', 'e3', 'x', 'y')
HEADER_BYTES = 800
PTCL3D_INDEX = 5  # zero-based segment 6, as defined by SIMPLE


def particle_payload(data):
    """Validate the native binoris directory; return the complete 3D segment."""
    if len(data) < HEADER_BYTES:
        raise ValueError('Project is shorter than the SIMPLE binary header')
    entries = [struct.unpack_from('=5q', data, i * 40) for i in range(20)]
    intervals = []
    for first, last, width, count, start in entries:
        if count == 0:
            continue
        if (count < 0 or first != 1 or last != count or width <= 0
                or start <= HEADER_BYTES or start - 1 + count * width > len(data)):
            raise ValueError('Unsupported or invalid SIMPLE segment layout')
        intervals.append((start - 1, start - 1 + count * width))
    intervals.sort()
    if any(a[1] > b[0] for a, b in zip(intervals, intervals[1:])):
        raise ValueError('Overlapping SIMPLE project segments')
    first, last, width, count, start = entries[PTCL3D_INDEX]
    if count < 1 or width % 4:
        raise ValueError('Project must contain complete ptcl3D particle records')
    offset = start - 1
    return offset, width, count, data[offset:offset + width * count]


def read_rows(path):
    rows = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        tokens = line.split()
        if not tokens or any('=' not in token for token in tokens):
            raise ValueError('Invalid orientation text at line {}'.format(number))
        row = dict(token.split('=', 1) for token in tokens)
        if len(row) != len(tokens) or any(key not in row for key in POSE_KEYS):
            raise ValueError('Duplicate or missing pose fields at line {}'.format(number))
        for key in POSE_KEYS:
            if not math.isfinite(float(row[key])):
                raise ValueError('Non-finite pose value at line {}'.format(number))
        if not 0 <= float(row['e2']) <= 180:
            raise ValueError('Polar Euler angle must lie in [0,180]')
        rows.append(row)
    if not rows:
        raise ValueError('No particle orientations found')
    return rows


def write_rows(path, rows):
    path.write_text(''.join(' '.join('{}={}'.format(k, v) for k, v in row.items())
                            + '\n' for row in rows))


def perturb(rows, maximum, seed):
    rng = random.Random(seed + maximum)
    changed = []
    for original in rows:
        row = dict(original)
        for key in POSE_KEYS:
            value = float(original[key])
            if key in ('x', 'y'):
                value += rng.uniform(0, maximum)
            elif key == 'e2':
                # Truncate the permitted interval at the poles; do not wrap
                # across a pole, which could change the direction by ~180 deg.
                value = rng.uniform(max(0, value - maximum), min(180, value + maximum))
            else:
                value = (value + rng.uniform(-maximum, maximum)) % 360
            row[key] = format(value, '.9g')  # enough digits for SIMPLE float32
        changed.append(row)
    return changed


def verify_rows(original, expected, actual, maximum):
    if len(actual) != len(original):
        raise ValueError('SIMPLE changed the particle count')
    for old, wanted, got in zip(original, expected, actual):
        if got.keys() != old.keys():
            raise ValueError('SIMPLE changed the orientation field names')
        for key in old:
            if key not in POSE_KEYS:
                if got[key] != old[key]:
                    raise ValueError('SIMPLE changed a non-pose field: ' + key)
                continue
            # Compare the expected and decoded native single-precision values.
            if struct.pack('=f', float(got[key])) != struct.pack('=f', float(wanted[key])):
                raise ValueError('Pose did not survive native import: ' + key)
            delta = float(got[key]) - float(old[key])
            if key in ('e1', 'e3'):
                delta = (delta + 180) % 360 - 180
            tolerance = 1e-4  # float32 serialization at degree/pixel magnitudes
            low = 0 if key in ('x', 'y') else -maximum
            if not low - tolerance <= delta <= maximum + tolerance:
                raise ValueError('Pose perturbation exceeds requested bound: ' + key)


def main():
    source = Path(sys.argv[1]).resolve()
    seed = int(sys.argv[2])
    executable = sys.argv[3]
    outputs = [source.with_name(source.stem + '_err{}deg_{}px.simple'.format(m, m))
               for m in (5, 10, 15)]
    for output in outputs:
        for target in (output, output.with_suffix('.log')):
            if os.path.lexists(str(target)):
                raise ValueError('Refusing to overwrite: ' + str(target))
    original_data = source.read_bytes()
    offset, width, count, original_payload = particle_payload(original_data)
    print('Random seed: {} (Python seed + error maximum for each arm).'.format(seed), flush=True)
    with tempfile.TemporaryDirectory(prefix='.pose-errors-', dir=str(source.parent)) as name:
        work = Path(name)
        # Never pass the input project to SIMPLE: it may record CLI job history.
        working_copy = work / 'input.simple'
        working_copy.write_bytes(original_data)

        def run(log, **args):
            command = [executable] + ['{}={}'.format(k, v) for k, v in args.items()]
            command += ['mkdir=no', 'nthr=1']
            log.write('>>> ' + ' '.join(command) + '\n')
            log.flush()
            result = subprocess.run(command, cwd=str(work), stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, universal_newlines=True)
            log.write(result.stdout)
            log.flush()
            if result.returncode or re.search(r'ERROR!|ERROR STOP|Fortran runtime error', result.stdout):
                raise RuntimeError('SIMPLE {} failed; see {}'.format(args['prg'], log.name))
            if args['prg'] == 'oriops' and 'SIMPLE_oriops NORMAL STOP' not in result.stdout:
                raise RuntimeError('Incomplete oriops command; see ' + str(log.name))

        def export(project, text, log):
            run(log, prg='oriops', oritab=project, outfile=text, oritype='ptcl3D')
            return read_rows(text)

        def encode(text, project, log):
            run(log, prg='oriops', oritab=text, outfile=project,
                oritype='ptcl3D', nptcls=count)
            _, new_width, new_count, payload = particle_payload(project.read_bytes())
            if (new_width, new_count) != (width, count):
                raise ValueError('Native record layout differs from input; no output written')
            return payload

        # Export once; require byte-exact native import before touching copies.
        baseline_log = work / 'baseline.log'
        try:
            with baseline_log.open('w') as log:
                baseline_text = work / 'baseline.txt'
                rows = export(working_copy, baseline_text, log)
                if len(rows) != count:
                    raise ValueError('Exported particle count differs from header')
                baseline_payload = encode(baseline_text, work / 'baseline.simple', log)
                if baseline_payload != original_payload:
                    raise ValueError('Native text round trip is lossy for this project; no output written')
        except Exception:
            # Temporary setup logs would otherwise disappear on failure.
            sys.stderr.write(baseline_log.read_text())
            raise
        for maximum, output in zip((5, 10, 15), outputs):
            logfile = output.with_suffix('.log')
            print('Creating ' + str(output), flush=True)
            with logfile.open('x') as log:
                log.write('SIMPLE_SEED={}\nANGLE_MAX_DEG={}\nSHIFT_MAX_PX={}\n'.format(seed, maximum, maximum))
                log.write(baseline_log.read_text())
                expected = perturb(rows, maximum, seed)
                text = work / 'changed.txt'
                write_rows(text, expected)
                partial = work / 'changed.simple'
                partial.unlink(missing_ok=True)
                payload = encode(text, partial, log)
                actual = export(partial, work / 'decoded.txt', log)
                verify_rows(rows, expected, actual, maximum)
                # The entire header and all other segments remain byte-identical.
                candidate = original_data[:offset] + payload + original_data[offset + len(payload):]
                created = False
                try:
                    with output.open('xb') as stream:
                        created = True
                        stream.write(candidate)
                    run(log, prg='update_project', projfile=output)
                    if particle_payload(output.read_bytes())[3] != payload:
                        raise ValueError('Project identity update changed particle records')
                except Exception:
                    # Do not leave an apparently usable but unverified project.
                    if created:
                        output.unlink(missing_ok=True)
                    raise
                log.write('PASS: native pose round trip, bounds, count, and non-pose fields verified\n')
    if source.read_bytes() != original_data:
        raise ValueError('Input project changed during preparation')


if __name__ == '__main__':
    if sys.version_info < (3, 8):
        sys.exit('Pose perturbation requires Python 3.8 or newer')
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit('Pose perturbation failed: ' + str(error))
