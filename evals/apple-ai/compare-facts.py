import argparse
import copy
import hashlib
import json
import pathlib
import statistics
from decimal import Decimal

parser = argparse.ArgumentParser(description='Score the fixed nine-run native fact pilot against saved Luna outputs. No model calls.')
parser.add_argument('apple_results', type=pathlib.Path)
parser.add_argument('luna_report', type=pathlib.Path)
args = parser.parse_args()
project = pathlib.Path(__file__).resolve().parents[2]
output = args.apple_results.resolve()
truth_path = project / 'evals/2026-q3/ground-truth.json'
truth = json.loads(truth_path.read_text())
truth_hash = hashlib.sha256(truth_path.read_bytes()).hexdigest()
luna_path = args.luna_report.resolve()
luna = json.loads(luna_path.read_text())
assert truth_hash == luna['truthSHA256']
ids = ['09', '17', '42']
expected = {c['id']: c['expected'][0] for c in truth['cases'] if c['id'] in ids}


def cents(value):
    if value is None:
        return None
    try:
        scaled = Decimal(value) * 100
        return int(scaled) if scaled == scaled.to_integral_value() else None
    except Exception:
        return None


def normalize(value):
    return ''.join(c for c in (value or '').lower() if c.isalnum())


def rate(value):
    return str(Decimal(str(value)).normalize())


def facts_from_booking(booking):
    if booking is None:
        return {}
    groups = {}
    for position in booking['positionen']:
        key = rate(position['steuersatz'])
        net, tax = groups.get(key, (0, 0))
        groups[key] = (net + position['netto'], tax + position['steuer'])
    net = sum(p['netto'] for p in booking['positionen'])
    tax = sum(p['steuer'] for p in booking['positionen'])
    return {'date': booking.get('datum'), 'issuer': booking.get('gegenparteiName'),
            'number': booking.get('belegnummer'), 'net': str(Decimal(net)/100),
            'tax': str(Decimal(tax)/100), 'gross': str(Decimal(net+tax)/100),
            'vat': [{'rate': key, 'net': str(Decimal(n)/100), 'tax': str(Decimal(t)/100)}
                    for key, (n,t) in groups.items()]}


def checks(facts, want):
    names = [want['gegenpartei_name']] + want.get('accepted_counterparties', [])
    numbers = [want['belegnummer']] + want.get('accepted_receipt_numbers', [])
    wanted_vat = sorted((rate(p['steuersatz']), p['netto_cents'], p['steuer_cents'])
                        for p in want['positionen_nach_satz'])
    try:
        actual_vat = sorted((rate(p['rate']), cents(p.get('net')), cents(p.get('tax')))
                            for p in facts.get('vat', []))
    except Exception:
        actual_vat = None
    return {'date': facts.get('date') == want['datum'],
            'issuer': normalize(facts.get('issuer')) in [normalize(n) for n in names],
            'receipt_number': facts.get('number') in numbers,
            'net': cents(facts.get('net')) == want['netto_cents'],
            'tax': cents(facts.get('tax')) == want['steuer_cents'],
            'gross': cents(facts.get('gross')) == want['brutto_cents'],
            'vat_groups': actual_vat == wanted_vat}

# Verify the scorer using truth-derived facts, without requiring Luna to pass.
want = expected['09']
probe = {'date': want['datum'], 'issuer': want['gegenpartei_name'],
         'number': want['belegnummer'], 'net': str(Decimal(want['netto_cents']) / 100),
         'tax': str(Decimal(want['steuer_cents']) / 100),
         'gross': str(Decimal(want['brutto_cents']) / 100),
         'vat': [{'rate': p['steuersatz'], 'net': str(Decimal(p['netto_cents']) / 100),
                  'tax': str(Decimal(p['steuer_cents']) / 100)} for p in want['positionen_nach_satz']]}
assert all(checks(probe, expected['09']).values())
bad = copy.deepcopy(probe); bad['date'] = '2026-08-03'; bad['tax'] = '5.59'
assert not checks(bad, expected['09'])['date'] and not checks(bad, expected['09'])['tax']
assert not any(checks({}, expected['09']).values())

apple_rows = []
for path in sorted(output.glob('*/result.json')):
    d = json.loads(path.read_text()); fields = checks(d.get('facts', {}), expected[d['case']])
    assert d['mode'] == 'ocr-lines-core-units', 'Compare one fixed extraction configuration.'
    assert sum(not v for v in fields.values()) == len(d['mismatches'])
    apple_rows.append({'case': d['case'], 'repetition': int(path.parent.name.split('-r')[1]),
                       'checks': fields, 'pass': all(fields.values()) and not d.get('error'),
                       'modelSeconds': d['seconds'], 'totalProbeSeconds': d['totalProbeSeconds'],
                       'artifact': str(path.relative_to(output))})
assert len(apple_rows)==9
assert {(r['case'], r['repetition']) for r in apple_rows} == {(id, rep) for id in ids for rep in range(1, 4)}
luna_rows = []
for c in luna['cases']:
    if c['id'] not in ids: continue
    for file, sha in c['fileSHA256'].items():
        assert hashlib.sha256((project / 'evals/2026-q3' / file).read_bytes()).hexdigest()==sha
    booking = c['bookings'][0] if len(c['bookings']) == 1 else None
    fields = checks(facts_from_booking(booking), expected[c['id']])
    luna_rows.append({'case': c['id'], 'repetition': c['repetition'], 'checks': fields,
                      'pass': all(fields.values()), 'wholeAgentSeconds': c['seconds']})
assert len(luna_rows)==6
assert {(r['case'], r['repetition']) for r in luna_rows} == {(id, rep) for id in ids for rep in range(1, 3)}


def summarize(rows):
    return {'passed': sum(r['pass'] for r in rows), 'runs': len(rows),
            'correctChecks': sum(sum(r['checks'].values()) for r in rows),
            'totalChecks': 7*len(rows),
            'byCase': {id: {'passed': sum(r['pass'] for r in rows if r['case']==id),
                           'runs': sum(r['case']==id for r in rows)} for id in ids},
            'byField': {field: sum(r['checks'][field] for r in rows)
                        for field in rows[0]['checks']}}

report = {'scope': 'Seven essential factual checks, one fixed native extraction configuration; not full booking parity.',
          'appleMode': 'ocr-lines-core-units', 'appleResults': str(output),
          'truthSHA256': truth_hash, 'lunaReport': str(luna_path), 'lunaGeneratedAt': luna['generatedAt'],
          'lunaModel': luna['model'], 'lunaEffort': luna['effort'],
          'apple': summarize(apple_rows), 'historicalLuna': summarize(luna_rows),
          'appleMeanModelSeconds': statistics.mean(r['modelSeconds'] for r in apple_rows),
          'appleMeanTotalProbeSeconds': statistics.mean(r['totalProbeSeconds'] for r in apple_rows),
          'appleRuns': apple_rows, 'historicalLunaRuns': luna_rows,
          'limitations': ['Three document cases, two underlying transactions; hotel PDF and scan depict the same invoice.',
                         'Apple: three new repeats per case; Luna: two historical repeats, not a new endpoint benchmark.',
                         'Apple emits facts only and derives tax using Core; Luna completed a broader bookkeeping task.',
                         'No field score for classification, payments, matching, SQL or lifecycle.',
                         'No end-to-end speed comparison; native component timings and historical whole-agent timings differ.']}
print(json.dumps(report, ensure_ascii=False, indent=2))
