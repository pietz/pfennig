"""Offline checks for score integrity; synthetic state only, no model calls."""
import copy
import hashlib
import importlib.util
import json
import pathlib
import tempfile
import unittest
from decimal import Decimal

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location('facts', HERE / 'compare-facts.py')
facts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(facts)
TRUTH = HERE.parent / '2026-q3/ground-truth.json'
WANT = next(c['expected'][0] for c in json.loads(TRUTH.read_text())['cases'] if c['id'] == '09')


def correct():
    euros = lambda value: str(Decimal(value) / 100)
    return {'date': WANT['datum'], 'issuer': WANT['gegenpartei_name'],
            'number': WANT['belegnummer'], 'net': euros(WANT['netto_cents']),
            'tax': euros(WANT['steuer_cents']), 'gross': euros(WANT['brutto_cents']),
            'vat': [{'rate': p['steuersatz'], 'net': euros(p['netto_cents']),
                     'tax': euros(p['steuer_cents'])} for p in WANT['positionen_nach_satz']]}


class ScoringTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = pathlib.Path(self.temp.name)
        self.luna = self.output / 'luna.json'
        self.luna.write_text(json.dumps({
            'truthSHA256': hashlib.sha256(TRUTH.read_bytes()).hexdigest(),
            'generatedAt': 'historical', 'model': 'saved', 'effort': 'high',
            'cases': [{'id': '09', 'repetition': 1, 'fileSHA256': {}, 'seconds': 0, 'bookings': []}]}))
        self.manifest = {'caseIDs': ['09'], 'repeats': 2, 'mode': 'test',
                         'truthSHA256': hashlib.sha256(TRUTH.read_bytes()).hexdigest(),
                         'fileSHA256': {}, 'runs': []}
        self.save_manifest()

    def save_manifest(self):
        (self.output / 'manifest.json').write_text(json.dumps(self.manifest))

    def result(self, rep=1, mode='test', error=None):
        folder = self.output / f'09-r{rep}'
        folder.mkdir()
        (folder / 'result.json').write_text(json.dumps({
            'case': '09', 'mode': mode, 'facts': correct(), 'error': error}))

    def report(self):
        return facts.compare(self.output, self.luna)

    def test_independent_fact_errors_and_signed_money(self):
        self.assertTrue(all(facts.checks(correct(), WANT).values()))
        wrong = copy.deepcopy(correct())
        wrong['date'] = '2026-01-01'
        wrong['tax'] = '5.59'
        checks = facts.checks(wrong, WANT)
        self.assertFalse(checks['date'])
        self.assertFalse(checks['tax'])
        self.assertTrue(checks['gross'])
        self.assertEqual(facts.cents('-0.34'), -34)
        for bad in ['NaN', 'Infinity', '1.001', True, {}, '4,69']:
            self.assertIsNone(facts.cents(bad))

    def test_reconciliation_diagnoses_without_repair(self):
        value = correct()
        self.assertEqual(facts.reconciliation(value), [])
        value['vat'][0]['net'] = value['gross']
        original = copy.deepcopy(value)
        self.assertEqual(facts.reconciliation(value), ['VAT group net sum != total net'])
        self.assertEqual(value, original)

    def test_missing_and_malformed_bookings_fail_independently(self):
        for booking in [None, {}, {'positionen': [{}]}]:
            self.assertFalse(any(facts.checks(facts.facts_from_booking(booking), WANT).values()))
        self.assertEqual(self.report()['historicalLuna']['passed'], 0)

    def test_partial_run_keeps_planned_denominator(self):
        self.result()
        report = self.report()
        self.assertEqual(report['apple']['passed'], 1)
        self.assertEqual(report['apple']['runs'], 2)
        self.assertFalse(report['nativePlanCompleted'])
        self.assertEqual(report['appleRuns'][1]['error'], 'Missing result')

    def test_extra_and_mixed_results_rejected(self):
        self.result(mode='different')
        with self.assertRaises(AssertionError):
            self.report()
        (self.output / '09-r1/result.json').unlink()
        self.result(rep=3)
        with self.assertRaises(AssertionError):
            self.report()

    def test_error_does_not_pass_with_correct_facts(self):
        self.result(error='model error')
        self.result(rep=2)
        self.manifest.update(completedAt='done', runs=[
            {'case': '09', 'repetition': 1, 'exitCode': 0},
            {'case': '09', 'repetition': 2, 'exitCode': 124}])
        self.save_manifest()
        report = self.report()
        self.assertTrue(report['nativePlanCompleted'])
        self.assertEqual(report['apple']['passed'], 0)

    def test_outgoing_issuer_contract_is_explicitly_separate(self):
        self.manifest['caseIDs'] = ['05']
        self.save_manifest()
        d = json.loads(self.luna.read_text())
        d['cases'][0]['id'] = '05'
        self.luna.write_text(json.dumps(d))
        report = self.report()
        self.assertEqual(report['apple']['runs'], 0)
        self.assertEqual(report['outgoingDiagnostics']['apple']['runs'], 2)
        self.assertEqual(report['outgoingDiagnostics']['apple']['totalChecks'], 12)
        self.assertNotIn('issuer', report['appleRuns'][0]['checks'])

    def test_legacy_missing_results_are_incomplete(self):
        (self.output / 'manifest.json').unlink()
        # A minimal historical record for each default pilot case is enough here.
        d = json.loads(self.luna.read_text())
        d['cases'] = [dict(d['cases'][0], id=id) for id in ['09', '17', '42']]
        self.luna.write_text(json.dumps(d))
        report = self.report()
        self.assertFalse(report['nativePlanCompleted'])
        self.assertEqual(report['apple']['runs'], 9)
        self.assertEqual(report['apple']['passed'], 0)


if __name__ == '__main__':
    unittest.main()
