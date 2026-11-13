#!/usr/bin/env python3
"""Rule 0 check: a pull request names all 5 parts (owner 2026-11-13).

Owner order 2026-11-13 ("Any work must be on all repo!"): a pull request
fails unless its description has a filled "## Rule 0" table with exactly
these 5 rows: Contract, Server, Admin (incl. setting), Driver, Rider.

The status cell (2nd column) of each row must hold one of:
  * a PR reference: #123, repo#123, owner/repo#123 or a github.com/.../pull/123 link
  * "this PR"
  * "not affected" plus a file:line proof (a path with :<number>)
An empty cell, "TBD" or "?" fails.

The same file is in all 5 code repos (contracts, server, admin, driver,
rider). Plain Python 3, no dependencies, no network.

Usage
  RULE0_BODY="$body" python3 tools/rule0_check.py   (CI: body from an env var)
  python3 tools/rule0_check.py body.md              (local: body from a file)
  python3 tools/rule0_check.py - < body.md          (local: body from stdin)
Exit 0 = pass, 1 = fail.
"""
import os
import re
import sys

PARTS = ["Contract", "Server", "Admin (incl. setting)", "Driver", "Rider"]

HEADING = re.compile(r"^\s{0,3}##\s+Rule\s*0\b", re.IGNORECASE)
NEXT_HEADING = re.compile(r"^\s{0,3}#{1,2}\s")
SEPARATOR = re.compile(r"^:?-{3,}:?$")
PR_REF = re.compile(r"(?<![\w/#.-])(?:[\w.-]+/)?[\w.-]*#\d+\b"
                    r"|github\.com/[\w.-]+/[\w.-]+/pull/\d+")
THIS_PR = re.compile(r"\bthis\s+PR\b", re.IGNORECASE)
NOT_AFFECTED = re.compile(r"\bnot\s+affected\b", re.IGNORECASE)
# file:line proof: a path (has a "/" or a ".") followed by :<number>, e.g.
# src/app.ts:12, lib/a/b.dart:82-87, render.yaml:14
FILE_LINE = re.compile(r"(?<![\w/.-])[\w.-]*[\w-](?:[./][\w.-]*)*:\d+\b")
BLOCKED = re.compile(r"\bTBD\b|\?", re.IGNORECASE)


def _norm(name):
    name = re.sub(r"[*_`]", "", name)
    name = re.sub(r"\s+", " ", name).strip().lower()
    return name.replace("incl setting", "incl. setting")


def _cells(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|") and not line.endswith("\\|"):
        line = line[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", line)]


def _has_file_line(text):
    for m in FILE_LINE.finditer(text):
        path = m.group(0).rsplit(":", 1)[0]
        if "/" in path or "." in path.strip("."):
            return True
    return False


def check_cell(cell):
    """Return None when the status cell is OK, else the reason it fails."""
    text = re.sub(r"<!--.*?-->", "", cell, flags=re.DOTALL).strip()
    if not text:
        return "empty status cell"
    if BLOCKED.search(text):
        return 'status cell has "TBD" or "?"'
    if PR_REF.search(text) or THIS_PR.search(text):
        return None
    if NOT_AFFECTED.search(text):
        if _has_file_line(text):
            return None
        return '"not affected" needs a file:line proof (path:<number>)'
    return 'status must be a PR (#123 or owner/repo#123), "this PR", ' \
           'or "not affected" + file:line'


def check_body(body):
    """Return a list of error strings (empty list = pass)."""
    body = re.sub(r"<!--.*?-->", "", body or "", flags=re.DOTALL)
    lines = body.replace("\r\n", "\n").split("\n")
    start = next((i for i, l in enumerate(lines) if HEADING.match(l)), None)
    if start is None:
        return ['no "## Rule 0" heading in the PR description']
    section = []
    in_fence = False
    for line in lines[start + 1:]:
        if line.strip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if NEXT_HEADING.match(line):
            break
        section.append(line)
    rows = [_cells(l) for l in section if l.strip().startswith("|")]
    sep = next((i for i, r in enumerate(rows)
                if r and all(SEPARATOR.match(c.replace(" ", "")) for c in r)),
               None)
    if sep is None:
        return ['no table under "## Rule 0" (need a header row, a '
                '|---| row and 5 rows: ' + ", ".join(PARTS) + ")"]
    data = rows[sep + 1:]
    errors = []
    wanted = {_norm(p): p for p in PARTS}
    seen = {}
    for r in data:
        key = _norm(r[0]) if r else ""
        if key not in wanted:
            errors.append('unknown row "%s" (rows must be exactly: %s)'
                          % (r[0] if r else "", ", ".join(PARTS)))
            continue
        part = wanted[key]
        if part in seen:
            errors.append('row "%s" appears twice' % part)
            continue
        seen[part] = r
        status = r[1] if len(r) > 1 else ""
        reason = check_cell(status)
        if reason:
            errors.append("%s: %s" % (part, reason))
    for p in PARTS:
        if p not in seen:
            errors.append('missing row "%s"' % p)
    return errors


def main(argv):
    if len(argv) > 1:
        body = sys.stdin.read() if argv[1] == "-" else open(
            argv[1], encoding="utf-8").read()
    else:
        body = os.environ.get("RULE0_BODY", "")
    errors = check_body(body)
    if errors:
        for e in errors:
            print("::error title=Rule 0::%s" % e)
        print("FAIL: the PR description needs a filled Rule 0 table "
              "(see .github/pull_request_template.md).")
        return 1
    print("OK: Rule 0 table names all 5 parts.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
