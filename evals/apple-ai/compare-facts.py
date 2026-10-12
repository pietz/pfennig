"""Score native document facts and saved public Luna bookings, without model calls."""
import argparse
import hashlib
import json
import pathlib
import statistics
from decimal import Decimal

def cents(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        scaled = Decimal(value) * 100
        if not scaled.is_finite():
            return None
        return int(scaled) if scaled == scaled.to_integral_value() else None
    except Exception:
        return None


def normalize(value):
    return ''.join(c for c in value.lower() if c.isalnum()) if isinstance(value, str) else ''


def rate(value):
    return str(Decimal(str(value)).normalize())


def _facts_from_booking(booking):
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


def facts_from_booking(booking):
    try:
        return _facts_from_booking(booking)
    except (KeyError, TypeError, ValueError, ArithmeticError):
        return {}


def checks(facts, want):
    if not isinstance(facts, dict):
        facts = {}
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

def reconciliation(facts):
    """Diagnostics only: never repair facts or change the frozen seven-check score."""
    if not isinstance(facts, dict):
        return []
    net, tax, gross = (cents(facts.get(k)) for k in ['net', 'tax', 'gross'])
    errors = []
    if None not in [net, tax, gross] and net + tax != gross:
        errors.append('net + tax != gross')
    groups = facts.get('vat', [])
    if isinstance(groups, list) and groups:
        for key, total in [('net', net), ('tax', tax)]:
            values = [cents(g.get(key)) if isinstance(g, dict) else None for g in groups]
            if total is not None and all(v is not None for v in values) and sum(values) != total:
                errors.append(f'VAT group {key} sum != total {key}')
    return errors


def summarize(rows, ids):
    return {'passed': sum(r['pass'] for r in rows), 'runs': len(rows),
            'correctChecks': sum(sum(r['checks'].values()) for r in rows),
            'totalChecks': sum(len(r['checks']) for r in rows),
            'byCase': {id: {'passed': sum(r['pass'] for r in rows if r['case'] == id),
                           'runs': sum(r['case'] == id for r in rows)} for id in ids},
            'byField': {field: sum(r['checks'][field] for r in rows)
                        for field in rows[0]['checks']} if rows else {}}


def compare(output, luna_path):
    project = pathlib.Path(__file__).resolve().parents[2]
    truth_path = project / 'evals/2026-q3/ground-truth.json'
    truth = json.loads(truth_path.read_text())
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    truth_hash = sha(truth_path)
    luna = json.loads(luna_path.read_text())
    assert truth_hash == luna['truthSHA256'], 'Historical truth differs.'
    manifest_path = output / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    ids = manifest['caseIDs'] if manifest else ['09', '17', '42']
    repeats = manifest['repeats'] if manifest else 3
    mode = manifest['mode'] if manifest else 'ocr-lines-core-units'
    if manifest:
        assert manifest['truthSHA256'] == truth_hash, 'Native truth differs.'
        for file, digest in manifest['fileSHA256'].items():
            assert sha(project / 'evals/2026-q3' / file) == digest, 'Native input changed.'
    expected = {c['id']: c['expected'][0] for c in truth['cases'] if c['id'] in ids}
    assert set(expected) == set(ids)
    outgoing = [i for i in ids if expected[i]['richtung'] == 'einnahme']
    primary_ids = [i for i in ids if i not in outgoing]

    def comparable_checks(value, id):
        fields = checks(value, expected[id])
        if id in outgoing:
            # An outgoing booking stores the customer; it cannot label document issuer.
            del fields['issuer']
        return fields
    attempts = {(r['case'], r['repetition']): r for r in manifest.get('runs', [])} if manifest else {}
    apple_rows = []
    for id in ids:
        for repetition in range(1, repeats + 1):
            path = output / f'{id}-r{repetition}/result.json'
            d = json.loads(path.read_text()) if path.exists() else {'error': 'Missing result'}
            if path.exists():
                assert d['mode'] == mode and d['case'] == id, 'Mixed configuration or case.'
            attempt = attempts.get((id, repetition))
            execution_error = d.get('error')
            if attempt and attempt['exitCode'] != 0:
                execution_error = execution_error or f"Process exited {attempt['exitCode']}"
            fields = comparable_checks(d.get('facts', {}), id)
            apple_rows.append({'case': id, 'repetition': repetition, 'checks': fields,
                               'pass': all(fields.values()) and not execution_error,
                               'error': execution_error, 'reconciliationErrors': reconciliation(d.get('facts')),
                               'modelSeconds': d.get('seconds'),
                               'totalProbeSeconds': d.get('totalProbeSeconds'),
                               'artifact': str(path.relative_to(output))})
    actual = set(output.glob('*/result.json'))
    planned = {output / f'{id}-r{r}/result.json' for id in ids for r in range(1, repeats + 1)}
    assert actual <= planned, 'Unplanned results must not be silently omitted.'
    luna_rows = []
    for c in luna['cases']:
        if c['id'] not in ids:
            continue
        for file, digest in c['fileSHA256'].items():
            assert sha(project / 'evals/2026-q3' / file) == digest, 'Historical input changed.'
        booking = c['bookings'][0] if len(c['bookings']) == 1 else None
        fields = comparable_checks(facts_from_booking(booking), c['id'])
        # Facts in saved state do not establish successful end-to-end completion.
        luna_rows.append({'case': c['id'], 'repetition': c['repetition'], 'checks': fields,
                          'pass': all(fields.values()), 'wholeAgentSeconds': c['seconds']})
    assert set(r['case'] for r in luna_rows) == set(ids), 'Historical cases missing.'
    def mean(key):
        values = [r[key] for r in apple_rows if r[key] is not None]
        return statistics.mean(values) if values else None
    return {'scope': 'Seven document-fact checks on expenses; outgoing six-check diagnostics separate. Not whole-agent parity.',
            'appleMode': mode, 'appleResults': str(output), 'truthSHA256': truth_hash,
            'nativePlanCompleted': (manifest.get('completedAt') is not None and
                                    set(attempts) == {(i, r) for i in ids for r in range(1, repeats + 1)})
                                   if manifest else actual == planned,
            'lunaReport': str(luna_path), 'lunaGeneratedAt': luna['generatedAt'],
            'lunaModel': luna['model'], 'lunaEffort': luna['effort'],
            'apple': summarize([r for r in apple_rows if r['case'] in primary_ids], primary_ids),
            'historicalLuna': summarize([r for r in luna_rows if r['case'] in primary_ids], primary_ids),
            'outgoingDiagnostics': {
                'scope': 'Six comparable checks only. Issuer is unscored: outgoing bookings store the customer.',
                'apple': summarize([r for r in apple_rows if r['case'] in outgoing], outgoing),
                'historicalLuna': summarize([r for r in luna_rows if r['case'] in outgoing], outgoing)},
            'appleMeanModelSeconds': mean('modelSeconds'),
            'appleMeanTotalProbeSeconds': mean('totalProbeSeconds'),
            'appleRuns': apple_rows, 'historicalLunaRuns': luna_rows,
            'limitations': ['Historical Luna bookings are not a fresh endpoint benchmark.',
                            'Field checks are correlated, not independent samples.',
                            'Greedy repeats establish observed repeatability only.',
                            'Extraction excludes classification, payments, matching and persistence.',
                            'Model component and whole-agent timings are not comparable.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apple_results', type=pathlib.Path)
    parser.add_argument('luna_report', type=pathlib.Path)
    args = parser.parse_args()
    print(json.dumps(compare(args.apple_results.resolve(), args.luna_report.resolve()),
                     ensure_ascii=False, indent=2))
