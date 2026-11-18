import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool'))

import check_categories_entry as guard  # noqa: E402


class CategoriesEntryGuard(unittest.TestCase):
    def test_lib_opens_categories_only_with_push_categories(self):
        self.assertEqual(guard.offenders(str(ROOT / 'lib')), [])

    def _scan(self, code):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / 'a.dart').write_text(code, encoding='utf-8')
            return guard.offenders(d)

    def test_flags_material_page_route(self):
        self.assertEqual(
            self._scan('x(MaterialPageRoute(builder: (_) => SelectRide(a: 1)));'),
            ['lib/a.dart:1'],
        )

    def test_flags_return_page_and_stage_transition(self):
        code = 'push(RightToLeftTransition(\n  PlanReturnRidePage(o: 1)));\n'
        self.assertEqual(self._scan(code), ['lib/a.dart:2'])

    def test_allows_helper_and_comments(self):
        code = ('// SelectRide(stops:)\n'
                'pushCategories<Object?>(\n  context,\n  SelectRide(a: 1),\n);\n')
        self.assertEqual(self._scan(code), [])


if __name__ == '__main__':
    unittest.main()
