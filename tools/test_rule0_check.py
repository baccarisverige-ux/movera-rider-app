"""Unit tests for tools/rule0_check.py. Run: python3 -m unittest tools/test_rule0_check.py"""
import contextlib
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rule0_check  # noqa: E402

HEAD = "## Change\n\nSomething.\n\n## Rule 0\n\n| Part | Status | Notes |\n|---|---|---|\n"


def body(rows, tail="\n## Checklist\n\n- [ ] done\n"):
    return HEAD + "".join("| %s | %s | |\n" % r for r in rows) + tail


GOOD = [
    ("Contract", "movera-contracts#123"),
    ("Server", "#212"),
    ("Admin (incl. setting)", "this PR"),
    ("Driver", "not affected: lib/core/api/client.dart:82"),
    ("Rider", "not affected (reads only /healthz) lib/a/b.dart:10-12"),
]


class Rule0CheckTest(unittest.TestCase):
    def test_good_body_passes(self):
        self.assertEqual(rule0_check.check_body(body(GOOD)), [])

    def test_bold_names_and_pr_link_pass(self):
        rows = [("**%s**" % p, s) for p, s in GOOD]
        rows[1] = ("Server", "https://github.com/o/movera-server/pull/214")
        self.assertEqual(rule0_check.check_body(body(rows)), [])

    def test_no_heading_fails(self):
        errs = rule0_check.check_body("## Change\n\nx\n")
        self.assertIn("heading", errs[0])

    def test_no_table_fails(self):
        errs = rule0_check.check_body("## Rule 0\n\nServer only.\n")
        self.assertIn("no table", errs[0])

    def test_missing_row_fails(self):
        errs = rule0_check.check_body(body(GOOD[:4]))
        self.assertEqual(errs, ['missing row "Rider"'])

    def test_extra_or_duplicate_row_fails(self):
        self.assertTrue(rule0_check.check_body(body(GOOD + [("Docs", "this PR")])))
        self.assertTrue(rule0_check.check_body(body(GOOD + [GOOD[0]])))

    def test_empty_cell_fails(self):
        rows = list(GOOD)
        rows[2] = ("Admin (incl. setting)", "")
        self.assertEqual(rule0_check.check_body(body(rows)),
                         ["Admin (incl. setting): empty status cell"])

    def test_tbd_and_question_mark_fail(self):
        for bad in ("TBD", "?", "#12 ?", "tbd"):
            rows = list(GOOD)
            rows[0] = ("Contract", bad)
            self.assertTrue(rule0_check.check_body(body(rows)), bad)

    def test_not_affected_without_file_line_fails(self):
        for bad in ("not affected", "not affected: src/app.ts",
                    "not affected since 12:30", "not affected Server:3"):
            rows = list(GOOD)
            rows[3] = ("Driver", bad)
            errs = rule0_check.check_body(body(rows))
            self.assertEqual(len(errs), 1, bad)
            self.assertIn("file:line", errs[0])

    def test_free_text_fails(self):
        rows = list(GOOD)
        rows[1] = ("Server", "no change needed")
        self.assertTrue(rule0_check.check_body(body(rows)))

    def test_table_after_next_heading_does_not_count(self):
        text = "## Rule 0\n\nsee below\n\n## Other\n\n| Part | Status |\n|---|---|\n" + \
            "".join("| %s | %s |\n" % r for r in GOOD)
        self.assertIn("no table", rule0_check.check_body(text)[0])

    def test_html_comment_hints_are_ignored(self):
        rows = list(GOOD)
        rows[4] = ("Rider", "<!-- this PR / #123 -->")
        self.assertEqual(rule0_check.check_body(body(rows)),
                         ["Rider: empty status cell"])

    def test_template_fails_until_filled(self):
        here = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(here, "..", ".github", "pull_request_template.md")
        if not os.path.exists(path):
            self.skipTest("no template")
        errs = rule0_check.check_body(open(path, encoding="utf-8").read())
        self.assertEqual(len(errs), 5, errs)

    def test_main_reads_env_and_exit_code(self):
        os.environ["RULE0_BODY"] = body(GOOD)
        out = io.StringIO()  # keep "::error" lines out of the CI log
        try:
            with contextlib.redirect_stdout(out):
                self.assertEqual(rule0_check.main(["x"]), 0)
                os.environ["RULE0_BODY"] = "$(touch /tmp/pwned) `id`"
                self.assertEqual(rule0_check.main(["x"]), 1)
            self.assertIn("::error title=Rule 0::", out.getvalue())
        finally:
            del os.environ["RULE0_BODY"]


if __name__ == "__main__":
    unittest.main()
