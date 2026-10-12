"""Run a predeclared, isolated native extraction configuration. No cloud calls."""
import argparse
import hashlib
import json
import pathlib
import platform
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('mode')
parser.add_argument('output', type=pathlib.Path)
parser.add_argument('--cases', required=True)
parser.add_argument('--repeats', type=int, default=1)
parser.add_argument('--purpose', required=True)
parser.add_argument('--ocr-from', type=pathlib.Path)
args = parser.parse_args()
assert 1 <= args.repeats <= 3
project = pathlib.Path(__file__).resolve().parents[2]
assert pathlib.Path.cwd() == project, 'Run from the repository root.'
ids = args.cases.split(',')
assert len(set(ids)) == len(ids)
truth_path = project / 'evals/2026-q3/ground-truth.json'
truth = json.loads(truth_path.read_text())
cases = {c['id']: c for c in truth['cases']}
assert all(i in cases and len(cases[i]['expected']) == 1 for i in ids)
binary = pathlib.Path('/tmp/pfennig-apple-ai-probe')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
args.output.mkdir(parents=True, exist_ok=False)
(args.output / 'Probe.swift').write_bytes((project / 'evals/apple-ai/Probe.swift').read_bytes())
manifest = {
    'mode': args.mode, 'caseIDs': ids, 'repeats': args.repeats,
    'purpose': args.purpose, 'startedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'probeSHA256': sha(project / 'evals/apple-ai/Probe.swift'),
    'binarySHA256': sha(binary), 'truthSHA256': sha(truth_path),
    'system': platform.platform(), 'sampling': 'greedy',
    'ocrFrom': str(args.ocr_from) if args.ocr_from else None,
    'fileSHA256': {f: sha(project / 'evals/2026-q3' / f) for i in ids for f in cases[i]['files']},
    'runs': [],
}

def save():
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

save()  # Declaration exists before the first inference, including unfinished plans.
for case in ids:
    for repetition in range(1, args.repeats + 1):
        folder = args.output / f'{case}-r{repetition}'
        command = [str(binary), 'extract', args.mode, case, str(folder)]
        if args.ocr_from:
            ocr = args.ocr_from / f'{case}-r1/ocr.txt'
            assert ocr.exists(), f'Missing frozen OCR: {ocr}'
            command.append(str(ocr))
        started = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            log, exit_code = result.stdout + result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            partial = lambda value: value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
            log = partial(error.stdout) + partial(error.stderr) + '\nNative probe exceeded the declared 180-second limit.\n'
            exit_code = 124
        folder.mkdir(exist_ok=True)
        (folder / 'run.log').write_text(log)
        record = {'case': case, 'repetition': repetition, 'exitCode': exit_code,
                  'wallSeconds': time.monotonic() - started}
        path = folder / 'result.json'
        if path.exists():
            d = json.loads(path.read_text())
            record.update(error=d.get('error'), mismatches=d.get('mismatches'))
        manifest['runs'].append(record)
        save()
        print(json.dumps(record), flush=True)
manifest['completedAt'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
save()
