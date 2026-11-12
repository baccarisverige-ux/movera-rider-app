import contextlib
import io
import json
import os
import pathlib
import sys
import tempfile
import unittest
import unittest.mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import testlab_summary  # noqa: E402

# Made-up values in the shape of a phone number and a code (not real ones).
FAKE_PHONE = '+46000000000'
FAKE_CODE = '0000'
# Made-up, digits in a non-trivial order so a wrong digit order is caught
# (national part starts with 0: no real Swedish number looks like this).
FAKE_SPELLED = '+46000097531'
FAKE_SPELLED_CODE = '9876'
# Made-up rider number (national part starts with 0: not a real one).
FAKE_RIDER = '+46000086420'


class TestlabSummaryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        device = self.root / 'driver-device' / 'oriole-33-en_US-portrait'
        device.mkdir(parents=True)
        self.logcat = device / 'logcat'
        self.logcat.write_text('\n'.join([
            'I MoveraTL: run-time values handed to the test: 3',
            'I flutter : MOVERA-TL CHECK SIGN-IN PASS test driver reaches Home: Home is open',
            'I flutter : MOVERA-TL CHECK G24 FAIL position sends are taken: sends=0',
            'E AndroidRuntime: FATAL EXCEPTION: main',
            'E AndroidRuntime: java.lang.SecurityException: Neither user nor current process has android.permission.WAKE_LOCK.',
            'I am_instrument: -e movera_tl_phone %s -e movera_tl_code %s' % (FAKE_PHONE, FAKE_CODE),
        ]) + '\n')
        (device / 'test_result_1.xml').write_text(
            '<testsuite><testcase name="staging device checks"><failure>x</failure></testcase></testsuite>')
        self.shot = device / 'shot.png'
        self.shot.write_bytes(b'\x89PNG\0\0no values here')

    def tearDown(self):
        self.tmp.cleanup()

    def test_scrub_removes_values_from_text_files_only(self):
        changed = testlab_summary.scrub(str(self.root), [FAKE_PHONE, FAKE_CODE, '', '12'])
        self.assertEqual(changed, 1)
        text = self.logcat.read_text()
        self.assertNotIn(FAKE_PHONE, text)
        self.assertNotIn(FAKE_CODE, text)
        self.assertIn('[REDACTED]', text)

    def test_scrub_masks_spaced_dashed_and_bracketed_spellings(self):
        spellings = [
            '+46 00 009 75 31',      # as the app shows it (displayPhoneNumber)
            '000-009 75 31',         # Swedish dashed habit
            '000-0097531',
            '00 009 75 31',
            '+46-00-009-75-31',
            '+46 (0)00 009 75 31',
            '(000) 009-75-31',
            '0046000097531',
            '46000097531',
            '000097531',
        ]
        self.logcat.write_text(''.join(
            'E flutter : Exception: phone %s rejected, code %s\n' % (x, FAKE_SPELLED_CODE)
            for x in spellings))
        rc, message = testlab_summary.scrub_or_fail(
            str(self.root), testlab_summary.secret_values(FAKE_SPELLED, FAKE_SPELLED_CODE))
        self.assertEqual(rc, 0, message)
        text = self.logcat.read_text()
        digits_only = ''.join(c for c in text if c.isdigit())
        self.assertNotIn('97531', digits_only)
        self.assertNotIn(FAKE_SPELLED_CODE, text)
        self.assertEqual(text.count('[REDACTED]'), 2 * len(spellings))
        self.assertNotIn(FAKE_SPELLED, message)

    def test_display_forms_cover_the_app_display_and_national_forms(self):
        forms = testlab_summary.display_forms(FAKE_SPELLED)
        for f in ('+46000097531', '46000097531', '000097531', '0000097531',
                  '+46 00 009 75 31', '000 009 75 31', '000-009 75 31', '00-009-75-31'):
            self.assertIn(f, forms)

    def test_scrub_fails_safe_when_the_value_list_is_empty(self):
        for secrets in ([], [''], ['  ', '12']):
            rc, message = testlab_summary.scrub_or_fail(str(self.root), secrets)
            self.assertEqual(rc, 1)
            self.assertIn('no values to scrub', message)
        env = dict(os.environ)
        env.pop('TL_SCRUB', None)
        with unittest.mock.patch.dict(os.environ, env, clear=True), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(testlab_summary.main(['x', 'scrub', str(self.root)]), 1)

    def test_scrub_fails_safe_and_deletes_results_when_a_value_is_left(self):
        # A binary file is not rewritten; a value inside it must stop the upload.
        self.shot.write_bytes(b'\x89PNG\0\0' + FAKE_PHONE.encode())
        rc, message = testlab_summary.scrub_or_fail(str(self.root), [FAKE_PHONE, FAKE_CODE])
        self.assertEqual(rc, 1)
        self.assertIn('deleted', message)
        self.assertNotIn(FAKE_PHONE, message)
        self.assertFalse(self.root.exists())

    def test_scrub_rescan_finds_spaced_value_in_binary(self):
        self.shot.write_bytes(b'\x89PNG\0\0+46 00 009 75 31')
        rc, _ = testlab_summary.scrub_or_fail(str(self.root), [FAKE_SPELLED, FAKE_SPELLED_CODE])
        self.assertEqual(rc, 1)
        self.assertFalse(self.root.exists())

    def _driver(self, numbers, code=FAKE_SPELLED_CODE):
        out = tempfile.TemporaryDirectory()
        self.addCleanup(out.cleanup)
        buf = io.StringIO()
        env = {'TL_NUMBERS': numbers, 'TL_CODE': code}
        with contextlib.redirect_stdout(buf):
            rc = testlab_summary.write_driver(out.name, env)
        return rc, buf.getvalue(), pathlib.Path(out.name)

    def test_driver_prefers_se_d38_and_accepts_any_paste(self):
        doc = json.dumps({'browser': {'SE': {'driver': FAKE_PHONE}},
                          'se': {'d38': '+46 00-009 75 31'}})
        for pasted in (doc, 'MOVERA_TEST_NUMBERS=' + doc, 'OTHER_NAME=' + doc,
                       "'" + doc + "'", json.dumps(doc)[1:-1]):
            rc, printed, out = self._driver(pasted)
            self.assertEqual(rc, 0, printed)
            self.assertEqual((out / 'phone').read_text(), FAKE_SPELLED)
            self.assertEqual((out / 'code').read_text(), FAKE_SPELLED_CODE)
            self.assertIn('se.d38', printed)
            scrub = (out / 'scrub').read_text().splitlines()
            self.assertIn('+46 00 009 75 31', scrub)
            self.assertIn(FAKE_SPELLED_CODE, scrub)
            masked = [l[len('::add-mask::'):] for l in printed.splitlines() if l.startswith('::add-mask::')]
            self.assertEqual(sorted(masked), sorted(scrub))
            # Nothing but mask lines may carry a value.
            for line in printed.splitlines():
                if not line.startswith('::add-mask::'):
                    self.assertNotIn('97531', line.replace(' ', '').replace('-', ''))
                    self.assertNotIn(FAKE_SPELLED_CODE, line)

    def test_driver_falls_back_to_browser_driver(self):
        rc, printed, out = self._driver(json.dumps({'browser': {'SE': {'driver': '+46 00 009 75 31'}}}))
        self.assertEqual(rc, 0, printed)
        self.assertEqual((out / 'phone').read_text(), FAKE_SPELLED)
        self.assertIn('browser.SE.driver', printed)

    def test_driver_rejects_bad_number_or_code_without_printing_them(self):
        cases = [
            (json.dumps({'se': {'d38': '+46 12'}}), FAKE_SPELLED_CODE, 'not a phone number'),
            (json.dumps({'se': {'d38': FAKE_SPELLED}}), '98~7=6', 'not 4-8 digits'),
            (json.dumps({'se': {'d38': FAKE_SPELLED}}), '12', 'not 4-8 digits'),
            (json.dumps({'se': {}}), FAKE_SPELLED_CODE, 'no se.d38'),
            ('not json ' + FAKE_SPELLED, FAKE_SPELLED_CODE, 'is not JSON'),
        ]
        for numbers, code, why in cases:
            rc, printed, out = self._driver(numbers, code)
            self.assertEqual(rc, 1)
            self.assertIn(why, printed)
            self.assertNotIn('::add-mask::', printed)
            self.assertNotIn('97531', printed)
            self.assertNotIn('98~7', printed)
            self.assertFalse((out / 'phone').exists())

    def test_normalise_number_spellings(self):
        for x in ('+46 00 009 75 31', '+46-00-009-75-31', '+46 (0)00 009 75 31', '0046000097531'):
            self.assertEqual(testlab_summary.normalise_number(x), FAKE_SPELLED)

    def test_summary_reads_logcat_checks_crashes_and_junit(self):
        text = testlab_summary.summary_text(str(self.root))
        self.assertIn('| SIGN-IN  | PASS |', text)
        self.assertIn('| G24  | FAIL |', text)
        self.assertIn('SecurityException', text)
        self.assertIn('failures=1', text)
        self.assertNotIn('MOVERA-TL CHECK', text.split('Crash / error lines')[1])

    def test_fail_rows_keep_the_missed_key_and_more_detail(self):
        (self.root / 'driver-device' / 'oriole-33-en_US-portrait' / 'summary.json').write_text(json.dumps([
            {'id': 'ARRIVE', 'title': 'at the pickup', 'outcome': 'fail',
             'detail': 'MISSED: "active-ride-arrived-button" not tappable -- ' + 'x' * 600 + 'END'},
            {'id': 'G24', 'title': 'sends', 'outcome': 'pass', 'detail': 'y' * 600 + 'END'},
        ]))
        text = testlab_summary.summary_text(str(self.root))
        self.assertIn('MISSED: "active-ride-arrived-button" not tappable -- ', text)
        self.assertIn('x' * 600 + 'END', text)
        self.assertNotIn('y' * 600, text)
        self.assertIn('y' * 400, text)

    def test_summary_json_wins_over_logcat(self):
        (self.root / 'summary.json').write_text(json.dumps([
            {'id': 'G17', 'title': 'SOS numbers', 'outcome': 'pass', 'detail': 'zone=Z001'},
        ]))
        text = testlab_summary.summary_text(str(self.root))
        self.assertIn('| G17 SOS numbers | PASS | zone=Z001 |', text)
        self.assertNotIn('G24', text.split('JUnit')[0])

    def test_nothing_found_says_not_checked(self):
        empty = tempfile.TemporaryDirectory()
        self.addCleanup(empty.cleanup)
        self.assertIn('NOT CHECKED', testlab_summary.summary_text(empty.name))

    def test_skip_line_says_not_checked(self):
        self.logcat.write_text('I flutter : MOVERA-TL SKIP all checks: no test number at run time\n')
        self.assertIn('NOT CHECKED: SKIP all checks', testlab_summary.summary_text(str(self.root)))

    def test_workflow_passes_numbers_only_at_run_time(self):
        workflow = pathlib.Path(__file__).resolve().parents[2] / '.github/workflows/android-test-apk.yml'
        text = workflow.read_text()
        job = text.split('  device-checks:', 1)[1]
        self.assertIn('--type instrumentation', job)
        self.assertIn('--environment-variables', job)
        self.assertIn('testlab_summary.py rider-trip "$RUNNER_TEMP/tl"', job)
        tool = (pathlib.Path(__file__).resolve().parents[1] / 'testlab_summary.py').read_text()
        self.assertIn('::add-mask::', tool)
        self.assertIn('testlab_summary.py scrub', job)
        # Fail-safe upload: only after a successful scrub; no `|| true` there.
        self.assertIn('id: scrub', job)
        upload = job.split('actions/upload-artifact', 1)[1].split('\n      - ', 1)[0]
        self.assertIn("steps.scrub.outcome == 'success'", upload)
        scrub_step = job.split('id: scrub', 1)[1].split('\n      - ', 1)[0]
        self.assertNotIn('|| true', scrub_step)
        # a12: no "NAME=" literal of the secret in any workflow.
        self.assertNotIn('MOVERA_TEST_NUMBERS' + '=', text)
        self.assertIn('name: testlab-results', job)
        self.assertIn('--timeout "$TL_TIMEOUT"', job)
        self.assertIn('echo "tl_timeout=25m"', job)  # run 6: Test Lab after the test's own 18m
        # The build lines carry no test number or code.
        build = job.split('flutter build apk --debug', 1)[1].split('mkdir -p out', 1)[0]
        self.assertNotIn('tl/phone', build)
        self.assertNotIn('TL_NUMBERS', build)
        self.assertNotIn('peer', build)
        # APKs are never downloaded (the contract copy holds the staging code).
        self.assertIn("-x '.*\\.apk$'", job)
        on = text.split('jobs:', 1)[0]
        self.assertNotIn('pull_request', on)
        self.assertNotIn('push:', on)

    def _trip(self, numbers, code=FAKE_SPELLED_CODE):
        out = tempfile.TemporaryDirectory()
        self.addCleanup(out.cleanup)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = testlab_summary.write_driver(out.name, {'TL_NUMBERS': numbers, 'TL_CODE': code},
                                              with_rider=True)
        return rc, buf.getvalue(), pathlib.Path(out.name)

    def test_trip_picks_big_test_rider_and_masks_every_spelling(self):
        doc = json.dumps({'browser': {'SE': {'rider': FAKE_PHONE, 'driver': FAKE_PHONE}},
                          'se': {'d38': FAKE_SPELLED, 'r35': '+46 00-008 64 20', 'r36': FAKE_PHONE}})
        rc, printed, out = self._trip(doc)
        self.assertEqual(rc, 0, printed)
        self.assertEqual((out / 'rider_phone').read_text(), FAKE_RIDER)
        self.assertEqual((out / 'phone').read_text(), FAKE_SPELLED)
        self.assertIn('se.r35', printed)
        scrub = (out / 'scrub').read_text().splitlines()
        for f in ('+46 00 008 64 20', '000-008 64 20', '0000086420', FAKE_RIDER, '+46 00 009 75 31'):
            self.assertIn(f, scrub)
        masked = [l[len('::add-mask::'):] for l in printed.splitlines() if l.startswith('::add-mask::')]
        self.assertEqual(sorted(masked), sorted(scrub))
        for line in printed.splitlines():
            if not line.startswith('::add-mask::'):
                digits = ''.join(c for c in line if c.isdigit())
                self.assertNotIn('86420', digits)
                self.assertNotIn('97531', digits)

    def test_trip_rider_fallback_and_never_a_base_number(self):
        rc, printed, out = self._trip(json.dumps({'se': {'d38': FAKE_SPELLED, 'r36': FAKE_RIDER}}))
        self.assertEqual(rc, 0, printed)
        self.assertIn('se.r36', printed)
        rc, printed, out = self._trip(json.dumps(
            {'se': {'d38': FAKE_SPELLED}, 'browser': {'SE': {'rider': FAKE_RIDER}}}))
        self.assertEqual(rc, 1)
        self.assertIn('no se.r35 or se.r36 entry', printed)
        self.assertNotIn('::add-mask::', printed)
        self.assertFalse((out / 'rider_phone').exists())
        rc, printed, _ = self._trip(json.dumps({'se': {'d38': FAKE_SPELLED, 'r35': FAKE_SPELLED}}))
        self.assertEqual(rc, 1)
        self.assertIn('same number', printed)
        self.assertNotIn('97531', printed)

    def test_scrub_removes_rider_spellings_and_fails_safe_on_leftover(self):
        self.logcat.write_text('E flutter : rider +46 00 008 64 20 / 000-008 64 20 / %s\n' % FAKE_RIDER)
        values = testlab_summary.secret_values(FAKE_SPELLED, FAKE_SPELLED_CODE) + \
            testlab_summary.display_forms(FAKE_RIDER)
        rc, message = testlab_summary.scrub_or_fail(str(self.root), values)
        self.assertEqual(rc, 0, message)
        self.assertNotIn('86420', ''.join(c for c in self.logcat.read_text() if c.isdigit()))
        self.shot.write_bytes(b'\x89PNG\0\0' + FAKE_RIDER.encode())
        rc, _ = testlab_summary.scrub_or_fail(str(self.root), values)
        self.assertEqual(rc, 1)
        self.assertFalse(self.root.exists())

    def test_summary_shows_transitions_table(self):
        rows = [
            {'name': 'offer->trip', 'frames': 40, 'missed': 2, 'worstMs': 31.5, 'gets': 3,
             'recreatedMaps': [], 'loaderSamples': 0, 'blankSamples': 0, 'failedCalls': [],
             'exceptions': [], 'smooth': True, 'reload': False, 'errors': False,
             'build': 'debug build, indicative'},
            {'name': 'done->home', 'frames': 12, 'missed': 9, 'worstMs': 250.0, 'gets': 6,
             'recreatedMaps': ['home (Home came back with a new map)'], 'loaderSamples': 1,
             'blankSamples': 0, 'failedCalls': ['GET /api/v1/x -> 500'], 'exceptions': [],
             'smooth': False, 'reload': True, 'errors': True, 'build': 'debug build, indicative'},
        ]
        (self.root / 'transitions.json').write_text(json.dumps(rows))
        text = testlab_summary.summary_text(str(self.root))
        self.assertIn('### Screen changes', text)
        self.assertIn('| offer->trip | 40 | 2 | 31.5 | 3 | - | 0/0 | - | PASS |', text)
        self.assertIn('FAIL FREEZE RELOAD ERRORS', text)
        self.assertIn('debug build, indicative', text)
        (self.root / 'transitions.json').unlink()
        self.logcat.write_text('I flutter : MOVERA-TL TRANSITIONS-JSON %s\n' % json.dumps(rows[:1]))
        self.assertIn('| offer->trip |', testlab_summary.summary_text(str(self.root)))

    def test_summary_notes_the_5x5_shared_accounts_rule(self):
        text = testlab_summary.summary_text(str(self.root))
        self.assertIn('5x5', text)
        self.assertIn('One device-check run at a time', text)

    def test_workflow_runs_one_device_check_at_a_time(self):
        workflow = pathlib.Path(__file__).resolve().parents[2] / '.github/workflows/android-test-apk.yml'
        job = workflow.read_text().split('  device-checks:', 1)[1].split('    steps:', 1)[0]
        self.assertIn('concurrency:', job)
        self.assertIn('group: movera-device-checks-d38-r35', job)
        self.assertIn('cancel-in-progress: false', job)
        # Concurrency groups hold one repo only: the job also waits for the
        # driver repo's device run (shared se.d38 / se.r35) before Test Lab.
        steps = workflow.read_text().split('  device-checks:', 1)[1]
        lock = steps.index('id: lock')
        self.assertIn('Movera-driver-app/actions/workflows/android-test-apk.yml/runs', steps)
        self.assertLess(lock, steps.index('id: peers'))
        self.assertIn("if: steps.lock.outputs.free == 'true'", steps)

    def test_workflow_trip_passes_peer_driver_only_at_run_time(self):
        workflow = pathlib.Path(__file__).resolve().parents[2] / '.github/workflows/android-test-apk.yml'
        text = workflow.read_text()
        job = text.split('  device-checks:', 1)[1]
        self.assertIn('- trip-lifecycle', text)
        self.assertIn('- trip-scheduled', text)
        self.assertIn('movera_tl_peer_phone=${peer}', job)
        self.assertIn('movera_tl_scenario=${SCENARIO}', job)
        self.assertIn('integration_test/trip_lifecycle_test.dart', job)
        self.assertIn('/sdcard/Android/data/com.movera.rider/files/tl', job)
        self.assertIn('unset phone code peer', job)
        java = (pathlib.Path(__file__).resolve().parents[2] /
                'android/app/src/androidTest/java/com/movera/rider/MainActivityTest.java').read_text()
        for pair in ('{"movera_tl_phone", "MOVERA_TL_PHONE"}', '{"movera_tl_code", "MOVERA_TL_CODE"}',
                     '{"movera_tl_peer_phone", "MOVERA_TL_PEER_PHONE"}',
                     '{"movera_tl_scenario", "MOVERA_TL_SCENARIO"}'):
            self.assertIn(pair, java)
        self.assertIn('package com.movera.rider;', java)
        # Names only, never values, in the runner's log lines.
        for line in java.splitlines():
            if 'Log.' in line:
                self.assertNotIn('value)', line)

    # --- verdict (run 6, 2026-11-12: a FALSE PASS) -------------------------

    def _run_dir(self, logcat_lines, junit_tests, gcloud='', outcome='Passed', summary_json=False):
        """A results folder in the shape Test Lab + the workflow leave it."""
        run = tempfile.TemporaryDirectory()
        self.addCleanup(run.cleanup)
        root = pathlib.Path(run.name)
        device = root / '43292982501-1' / 'oriole-33-en_US-portrait'
        device.mkdir(parents=True)
        (device / 'logcat').write_text('\n'.join(logcat_lines) + '\n')
        cases = ''.join('<testcase name="t%d"/>' % i for i in range(junit_tests))
        (device / 'test_result_1.xml').write_text(
            '<testsuites><testsuite name="" tests="%d" failures="0" errors="0" skipped="0">%s'
            '</testsuite></testsuites>' % (junit_tests, cases))
        if summary_json:
            (device / 'summary.json').write_text('[]')
        (root / 'gcloud.txt').write_text(gcloud)
        (root / 'testlab.json').write_text(json.dumps([
            {'axis_value': 'oriole-33-en_US-portrait', 'outcome': outcome, 'test_details': '--'}]))
        return root

    RUN6_LOGCAT = [
        'I flutter : MOVERA-TL CHECK SIGN-IN PASS test driver reaches Home: Home is open',
        'I flutter : MOVERA-TL CHECK TRANSITION:home->offer:SMOOTH FAIL frames: worst 210 ms',
        'I flutter : MOVERA-TL CHECK TRANSITION:offer->trip:SMOOTH FAIL frames: worst 593 ms',
        'I flutter : MOVERA-TL CHECK TRANSITION:menu-back-1:SMOOTH PASS frames ok',
        'I flutter : 18:00 +0: trip lifecycle [E]  TimeoutException after 0:18:00.000000: '
        'Test timed out after 18 minutes.',
        'I TestRunner: run finished: 0 tests, 0 failed, 0 ignored',
    ]
    RUN6_GCLOUD = ('Test is Running\nStarting attempt 1.\nA non-retryable error occurred.\n'
                   'Test is Pending\nInstrumentation testing complete.\n')

    def test_verdict_fails_run6_false_pass_with_one_error_per_reason(self):
        root = self._run_dir(self.RUN6_LOGCAT, 0, gcloud=self.RUN6_GCLOUD)
        # The old Result step looked only at the gcloud exit code: run 6 had 0.
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = testlab_summary.verdict(str(root), '0')
        self.assertEqual(rc, 1)
        errors = [l for l in out.getvalue().splitlines() if l.startswith('::error::')]
        text = '\n'.join(errors)
        self.assertIn('JUnit has 0 tests', text)
        self.assertIn('no MOVERA-TL END line', text)
        self.assertIn('no SUMMARY-JSON line', text)
        self.assertIn('TRANSITION:home->offer:SMOOTH', text)
        self.assertIn('TRANSITION:offer->trip:SMOOTH', text)
        self.assertNotIn('menu-back-1', text)
        self.assertIn('Test timed out after', text)
        self.assertIn('non-retryable error', text)
        self.assertNotIn('exit code', text)
        self.assertNotIn('outcome', text)
        self.assertEqual(len(errors), 6)

    def test_verdict_main_reads_rc_from_env_and_fails_run6(self):
        root = self._run_dir(self.RUN6_LOGCAT, 0, gcloud=self.RUN6_GCLOUD)
        with unittest.mock.patch.dict(os.environ, {'RC': '0'}), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(testlab_summary.main(['x', 'verdict', str(root)]), 1)

    GOOD_LOGCAT = [
        'I flutter : MOVERA-TL CHECK SIGN-IN PASS test driver reaches Home: Home is open',
        'I flutter : MOVERA-TL CHECK OFFLINE PASS Go offline is taken: server says offline',
        'I flutter : MOVERA-TL SUMMARY passed=2 failed=0 skipped=0',
        'I flutter : MOVERA-TL SUMMARY-JSON []',
        'I flutter : MOVERA-TL END checks=2 failed=0 cleanup=none offline=pass',
    ]

    def test_verdict_passes_a_clean_run(self):
        root = self._run_dir(self.GOOD_LOGCAT, 1, gcloud='Instrumentation testing complete.\n')
        self.assertEqual(testlab_summary.verdict_reasons(str(root), '0'), [])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(testlab_summary.verdict(str(root), '0'), 0)

    def test_verdict_each_reason_alone(self):
        cases = {
            'exit code 10': dict(rc='10'),
            'exit code missing': dict(rc=''),
            'JUnit has 0 tests': dict(tests=0),
            'no MOVERA-TL END line': dict(drop='END '),
            'no SUMMARY-JSON line': dict(drop='SUMMARY-JSON '),
            'check(s) FAIL: RUN': dict(add='I flutter : MOVERA-TL CHECK RUN FAIL hung: no pump returned in SWITCH-1'),
            'Test timed out after': dict(add='I flutter : Test timed out after 18 minutes.'),
            'non-retryable error': dict(gcloud='A non-retryable error occurred.\n'),
            'outcome: Inconclusive': dict(outcome='Inconclusive'),
        }
        for want, c in cases.items():
            with self.subTest(want):
                lines = [l for l in self.GOOD_LOGCAT if not (c.get('drop') and c['drop'] in l)]
                if c.get('add'):
                    lines.append(c['add'])
                root = self._run_dir(lines, c.get('tests', 1), gcloud=c.get('gcloud', ''),
                                     outcome=c.get('outcome', 'Passed'))
                reasons = testlab_summary.verdict_reasons(str(root), c.get('rc', '0'))
                self.assertEqual(len(reasons), 1, reasons)
                self.assertIn(want, reasons[0])

    def test_verdict_summary_json_file_counts_and_skip_explains_no_end(self):
        lines = [l for l in self.GOOD_LOGCAT if 'SUMMARY-JSON' not in l]
        root = self._run_dir(lines, 1, summary_json=True)
        self.assertEqual(testlab_summary.verdict_reasons(str(root), '0'), [])
        skip = self._run_dir(['I flutter : MOVERA-TL SKIP all checks: no test number at run time'], 1)
        self.assertEqual(testlab_summary.verdict_reasons(str(skip), '0'), [])

    def test_verdict_missing_testlab_json_fails(self):
        root = self._run_dir(self.GOOD_LOGCAT, 1)
        (root / 'testlab.json').unlink()
        reasons = testlab_summary.verdict_reasons(str(root), '0')
        self.assertEqual(len(reasons), 1)
        self.assertIn('testlab.json: no outcome', reasons[0])

    def test_workflow_result_runs_verdict_after_scrub_and_upload(self):
        workflow = pathlib.Path(__file__).resolve().parents[2] / '.github/workflows/android-test-apk.yml'
        job = workflow.read_text().split('  device-checks:', 1)[1]
        scrub = job.index('testlab_summary.py scrub testlab-results')
        upload = job.index('actions/upload-artifact@v4')
        result = job.index('- name: Result')
        verdict = job.index('testlab_summary.py verdict testlab-results')
        self.assertLess(scrub, upload)
        self.assertLess(upload, result)
        self.assertLess(result, verdict)
        step = job[result:]
        self.assertNotIn('Device checks passed on Test Lab', step)
        self.assertIn('RC: ${{ steps.run.outputs.rc }}', step)
        self.assertNotIn('always()', step.split('run:', 1)[0])

    def test_workflow_test_lab_timeout_beats_the_trip_test_timeout(self):
        workflow = pathlib.Path(__file__).resolve().parents[2] / '.github/workflows/android-test-apk.yml'
        job = workflow.read_text().split('  device-checks:', 1)[1]
        self.assertIn('echo "tl_timeout=25m"', job)
        test = (pathlib.Path(__file__).resolve().parents[2] /
                'integration_test/staging/trip_run.dart').read_text()
        self.assertIn('testLimit = Duration(minutes: 18)', test)
        self.assertIn('hardAfter = Duration(minutes: 15)', test)

    # --- rider-trip (G31 rider: the rider app on the phone) ----------------

    def _rider_trip(self, numbers, code=FAKE_SPELLED_CODE):
        out = tempfile.TemporaryDirectory()
        self.addCleanup(out.cleanup)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = testlab_summary.write_rider_trip(out.name, {'TL_NUMBERS': numbers, 'TL_CODE': code})
        return rc, buf.getvalue(), pathlib.Path(out.name)

    def test_rider_trip_puts_the_rider_on_the_phone_and_d38_over_http(self):
        doc = json.dumps({'browser': {'SE': {'rider': FAKE_PHONE, 'driver': FAKE_PHONE}},
                          'se': {'d38': '+46 00-009 75 31', 'r35': '+46 00-008 64 20', 'r36': FAKE_PHONE}})
        rc, printed, out = self._rider_trip(doc)
        self.assertEqual(rc, 0, printed)
        self.assertEqual((out / 'phone').read_text(), FAKE_RIDER)
        self.assertEqual((out / 'peer_phone').read_text(), FAKE_SPELLED)
        self.assertEqual((out / 'code').read_text(), FAKE_SPELLED_CODE)
        self.assertFalse((out / 'rider_phone').exists())
        self.assertIn('se.r35', printed)
        self.assertIn('se.d38', printed)
        for name in ('phone', 'peer_phone', 'code', 'scrub'):
            self.assertEqual((out / name).stat().st_mode & 0o777, 0o600)
        scrub = (out / 'scrub').read_text().splitlines()
        for f in ('+46 00 008 64 20', '000-008 64 20', '0000086420', FAKE_RIDER,
                  '+46 00 009 75 31', FAKE_SPELLED, FAKE_SPELLED_CODE):
            self.assertIn(f, scrub)
        masked = [l[len('::add-mask::'):] for l in printed.splitlines() if l.startswith('::add-mask::')]
        self.assertEqual(sorted(masked), sorted(scrub))
        for line in printed.splitlines():
            if not line.startswith('::add-mask::'):
                digits = ''.join(c for c in line if c.isdigit())
                self.assertNotIn('86420', digits)
                self.assertNotIn('97531', digits)
                self.assertNotIn(FAKE_SPELLED_CODE, line)

    def test_rider_trip_never_signs_in_a_base_number_over_http(self):
        # No se.d38: the base browser driver is NOT taken for the HTTP peer.
        rc, printed, out = self._rider_trip(json.dumps(
            {'se': {'r35': FAKE_RIDER}, 'browser': {'SE': {'driver': FAKE_SPELLED}}}))
        self.assertEqual(rc, 1)
        self.assertIn('no se.d38 entry', printed)
        self.assertNotIn('::add-mask::', printed)
        self.assertFalse((out / 'peer_phone').exists())
        # No big-test rider: never the base rider either.
        rc, printed, out = self._rider_trip(json.dumps(
            {'se': {'d38': FAKE_SPELLED}, 'browser': {'SE': {'rider': FAKE_RIDER}}}))
        self.assertEqual(rc, 1)
        self.assertIn('no se.r35 or se.r36 entry', printed)
        self.assertFalse((out / 'phone').exists())
        # Fallback rider se.r36.
        rc, printed, out = self._rider_trip(json.dumps({'se': {'d38': FAKE_SPELLED, 'r36': FAKE_RIDER}}))
        self.assertEqual(rc, 0, printed)
        self.assertIn('se.r36', printed)

    def test_rider_trip_refuses_equal_numbers_and_bad_values_silently(self):
        rc, printed, _ = self._rider_trip(json.dumps({'se': {'d38': FAKE_SPELLED, 'r35': '+46 (0)00-009 75 31'}}))
        self.assertEqual(rc, 1)
        self.assertIn('same number', printed)
        self.assertNotIn('97531', printed)
        rc, printed, _ = self._rider_trip(json.dumps({'se': {'d38': FAKE_SPELLED, 'r35': FAKE_RIDER}}), '12~3')
        self.assertEqual(rc, 1)
        self.assertIn('not 4-8 digits', printed)
        self.assertNotIn('12~3', printed)
        self.assertNotIn('::add-mask::', printed)

    def test_rider_trip_main_dispatch(self):
        out = tempfile.TemporaryDirectory()
        self.addCleanup(out.cleanup)
        env = {'TL_NUMBERS': json.dumps({'se': {'d38': FAKE_SPELLED, 'r35': FAKE_RIDER}}),
               'TL_CODE': FAKE_SPELLED_CODE}
        buf = io.StringIO()
        with unittest.mock.patch.dict(os.environ, env), contextlib.redirect_stdout(buf):
            rc = testlab_summary.main(['testlab_summary.py', 'rider-trip', out.name])
        self.assertEqual(rc, 0, buf.getvalue())
        self.assertTrue((pathlib.Path(out.name) / 'peer_phone').exists())

    def test_scrub_removes_peer_driver_spellings(self):
        self.logcat.write_text('E flutter : driver +46 00 009 75 31 / 000-009 75 31 rider %s code %s\n'
                               % (FAKE_RIDER, FAKE_SPELLED_CODE))
        values = testlab_summary.secret_values(FAKE_RIDER, FAKE_SPELLED_CODE) + \
            testlab_summary.display_forms(FAKE_SPELLED)
        rc, message = testlab_summary.scrub_or_fail(str(self.root), values)
        self.assertEqual(rc, 0, message)
        digits = ''.join(c for c in self.logcat.read_text() if c.isdigit())
        self.assertNotIn('97531', digits)
        self.assertNotIn('86420', digits)
        self.assertNotIn(FAKE_SPELLED_CODE, self.logcat.read_text())


if __name__ == '__main__':
    unittest.main()
