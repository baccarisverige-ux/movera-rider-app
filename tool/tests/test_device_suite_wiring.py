"""Static wiring guards for the Test Lab device suite (integration_test/).

Moved here from test/device_suite (Dart tests that read source count as
legacy grep-style tests in CI's Test integrity step). These only read the
harness source; the behaviour is tested in test/device_suite/.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
STAGING = ROOT / 'integration_test' / 'staging'


def flat(path):
    # Without white space: the formatter may break a line anywhere.
    return re.sub(r'\s+', '', path.read_text(encoding='utf-8'))


class TransitionWatchUsesSmoothVerdict(unittest.TestCase):
    def setUp(self):
        self.watch = flat(STAGING / 'transition_watch.dart')

    def test_smooth_goes_through_the_build_mode_verdict(self):
        self.assertIn('SmoothVerdict.judge(stats)', self.watch)
        self.assertIn("log.smooth('TRANSITION:$name:SMOOTH',outcome,", self.watch)

    def test_rows_carry_outcome_p90_and_jank_budget(self):
        for part in ("'smoothOutcome':outcome.name", "'p90Ms':", "'jankMs':"):
            self.assertIn(part, self.watch)

    def test_reload_and_errors_stay_pass_fail(self):
        self.assertIn("check('RELOAD',reloadOk", self.watch)
        self.assertIn("check('ERRORS',errorsOk", self.watch)
        self.assertNotIn("check('SMOOTH'", self.watch)
        self.assertIn('ok?log.pass(id,title,detail):log.fail(id,title,detail)',
                      self.watch)


class DeviceSuiteNeverUsesTheTestKeyboard(unittest.TestCase):
    # Driver profile run 44965447102: tester.enterText does not type on a
    # profile build; the suite types through type_text.dart.
    def test_no_enter_text_outside_type_text(self):
        files = [p for p in STAGING.glob('*.dart')] + [
            ROOT / 'integration_test' / 'trip_lifecycle_test.dart',
            ROOT / 'integration_test' / 'staging_device_test.dart',
        ]
        files = [f for f in files if f.exists()]
        self.assertGreater(len(files), 5)
        for f in files:
            if f.name == 'type_text.dart':
                continue
            code = '\n'.join(
                line for line in f.read_text(encoding='utf-8').splitlines()
                if not line.lstrip().startswith('//'))
            self.assertNotIn('.enterText(', code, f)
            self.assertNotIn('testTextInput', code, f)


if __name__ == '__main__':
    unittest.main()
