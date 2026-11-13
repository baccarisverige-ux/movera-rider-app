#!/usr/bin/env python3
"""Firebase Test Lab device run: scrub the downloaded results, then summarise.

Owner 2026-11-12 ("U need find problems! So whats the point of test"): the
staging device test (integration_test/staging_device_test.dart) prints one
line per check to logcat ("MOVERA-TL CHECK <id> PASS|FAIL|SKIP ...") and
writes summary.json into the app's files folder, which Test Lab pulls.

Usage (from .github/workflows/android-test-apk.yml, plain Python 3):
  TL_NUMBERS=<secret> TL_CODE=<secret> python3 -I tool/testlab_summary.py driver OUT
      pick ONE test driver (se.d38, the dedicated big-test driver, else
      browser.SE.driver), normalise it to E.164, check number and code,
      ::add-mask:: every spelling, write OUT/phone, OUT/code, OUT/scrub
      (mode 600). Never prints a value; exit 1 on any problem.
  TL_NUMBERS=<secret> TL_CODE=<secret> python3 -I tool/testlab_summary.py trip OUT
      as `driver`, plus ONE big-test rider for the trip lifecycle test
      (se.r35, else se.r36; never a base number), written to OUT/rider_phone;
      every spelling of both numbers is masked and goes into OUT/scrub.
  TL_NUMBERS=<secret> TL_CODE=<secret> python3 -I tool/testlab_summary.py rider-trip OUT
      G31 rider (the rider app's device suite; this file is shared with the
      driver app's repo): ONE big-test rider for the rider app ON THE PHONE
      (se.r35, else se.r36; never a base number) -> OUT/phone, and ONE
      big-test driver the test plays over HTTP (se.d38 only: a base
      number signed in over HTTP would sign the owner's own phone out) ->
      OUT/peer_phone; the same pair as `trip`, sides swapped. Refuses
      equal numbers; every spelling of both and the code masked and in
      OUT/scrub. Never prints a value.
  TL_SCRUB="<value>\\n<value>" python3 tool/testlab_summary.py scrub DIR
      replace every listed value (phone number in any spelling: E.164,
      national, spaced, dashed, bracketed; sign-in code) with [REDACTED] in
      every text file under DIR, then re-scan every file (text and binary).
      Fails safe: exit 1 when the value list is empty, and exit 1 AND delete
      DIR when a value is still found. Values come from the environment,
      never from the command line.
  python3 tool/testlab_summary.py summary DIR
      print passed/failed per check, JUnit totals and crash lines from
      logcat; also into $GITHUB_STEP_SUMMARY when set. Exit 0 (the
      `verdict` below decides the job).
  python3 -I tool/testlab_summary.py count-runs FILE
      G31 rider lock step: FILE is a GitHub "list workflow runs" answer;
      prints its total_count (a whole number >= 0). Exit 1, printing
      nothing, when the answer is not that shape (the workflow then counts
      the read as failed: fail-closed).
  RC=<gcloud exit code> python3 -I tool/testlab_summary.py verdict DIR
      the job's pass/fail, run on the SCRUBBED results after the upload.
      Run 6 (2026-11-12) was a false pass: gcloud exit 0 and Test Lab
      "Passed" while the test hung, timed out, and JUnit had 0 tests. So
      exit 1 with one ::error:: per reason when ANY of: RC is not 0; JUnit
      has 0 tests; no "MOVERA-TL END" line, or no SUMMARY-JSON line and no
      summary.json (unless a "MOVERA-TL SKIP" line explains it); any
      "MOVERA-TL CHECK <id> FAIL" line; logcat has "Test timed out after";
      gcloud.txt has "non-retryable error"; the testlab.json outcome is not
      "Passed". Prints no value (check ids only; the files are scrubbed).
"""
import glob
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET

REDACTED = "[REDACTED]"
PREFIX = "MOVERA-TL "
CRASH_PATTERNS = [
    re.compile(p)
    for p in (
        r"FATAL EXCEPTION",
        r"AndroidRuntime",
        r"SecurityException",
        r"ANR in ",
        r"Unhandled Exception",
        r"EXCEPTION CAUGHT BY",
        r"ForegroundServiceStartNotAllowedException",
        r"\bE[ /]flutter\b",
        r"Process .* has died",
    )
]
MAX_CRASH_LINES = 40


# Country codes of the app's countries (lib/core/auth/phone_country.dart);
# others fall back to the whole number.
_COUNTRY_CODES = ("216", "33", "46")
# Separators the app, Android and people put between digits.
_SEP = r"[\s\-().]*"
NUMBER_RE = re.compile(r"^\+\d{8,15}$")
CODE_RE = re.compile(r"^\d{4,8}$")
# Where the driver is looked up in the MOVERA_TEST_NUMBERS JSON. se.d38 is
# the dedicated big-test driver; browser.SE.driver (a base number, used on a
# real phone by the owner) only as fallback: a new sign-in signs the other
# phone out (one-phone rule, decisions/driver-g1.md).
DRIVER_PATHS = (("se", "d38"), ("browser", "SE", "driver"))
# The rider the trip lifecycle test plays over HTTP: a dedicated big-test
# rider (r35 is d38's pair in the 5x5 screen runs). No base number: a new
# sign-in would sign the owner's own phone out.
RIDER_PATHS = (("se", "r35"), ("se", "r36"))
# G31 rider: the driver the rider app's suite plays over HTTP. Only the
# dedicated big-test driver: no base-number fallback (an HTTP sign-in signs
# the other phone out, and the base numbers are on the owner's phones).
PEER_DRIVER_PATHS = (("se", "d38"),)


class DriverError(Exception):
    """A problem with the secret; the message never holds a value."""


def normalise_number(raw):
    """Any spelling of a number -> "+" and digits (Swedish when no country)."""
    text = str(raw).strip().replace("(0)", "")
    digits = re.sub(r"\D", "", text)
    if text.startswith("+"):
        return "+" + digits
    if digits.startswith("00"):
        return "+" + digits[2:]
    if digits.startswith("0"):
        return "+46" + digits[1:]
    if digits.startswith("46") and len(digits) == 11:
        return "+" + digits
    return "+46" + digits


def split_number(e164):
    """(country code, national digits without the trunk 0)."""
    digits = e164.lstrip("+")
    for cc in _COUNTRY_CODES:
        if digits.startswith(cc) and len(digits) - len(cc) >= 6:
            return cc, digits[len(cc):]
    return "", digits


def display_forms(e164):
    """The spellings the app and people write: as displayPhoneNumber shows it
    ("+46 NN NNN NN NN"), national with the trunk 0, spaced and dashed."""
    cc, nat = split_number(e164)
    if not cc:
        return [e164, e164[1:]]
    if cc == "46" and len(nat) == 9:
        groups = [nat[0:2], nat[2:5], nat[5:7], nat[7:]]
    elif cc == "33" and len(nat) == 9:
        groups = [nat[0], nat[1:3], nat[3:5], nat[5:7], nat[7:]]
    elif cc == "216" and len(nat) == 8:
        groups = [nat[0:2], nat[2:5], nat[5:]]
    else:
        groups = [nat]
    spaced = " ".join(groups)
    trunk = "" if cc == "216" else "0"
    forms = [
        e164, cc + nat, "00" + cc + nat, nat, trunk + nat,
        "+%s %s" % (cc, spaced), spaced, trunk + spaced,
        "+%s-%s" % (cc, "-".join(groups)), "-".join(groups), trunk + "-".join(groups),
        "+%s (0)%s" % (cc, nat), "+%s (0)%s" % (cc, spaced),
    ]
    if len(groups) > 1:
        # Swedish habit: "0NN-NNN NN NN" and "0NN-NNNNNNN".
        forms += [trunk + groups[0] + "-" + " ".join(groups[1:]),
                  trunk + groups[0] + "-" + "".join(groups[1:])]
    out = []
    for f in forms:
        if f and f not in out:
            out.append(f)
    return out


def parse_numbers(raw):
    """The secret as JSON, however it was pasted (NAME= prefix, outer or
    escaped quotes). DriverError says only the shape, never the value."""
    raw = (raw or "").strip()
    # Any leading NAME= (JSON never starts with a letter).
    raw = re.sub(r"^[A-Z][A-Z0-9_]*=", "", raw).strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
        raw = raw[1:-1].strip()
    if raw.startswith('{\\"') or raw.startswith('[\\"'):
        raw = raw.replace('\\"', '"')
    try:
        return json.loads(raw)
    except ValueError as err:
        def kind(c):
            if c in "{}[]":
                return "brace"
            if c in "'\"":
                return "quote"
            if c.isalpha():
                return "letter"
            if c.isdigit():
                return "digit"
            return "other"
        raise DriverError(
            "secret length %d, starts with a %s, ends with a %s; JSON error at char %s; "
            "the MOVERA_TEST_NUMBERS secret is not JSON (same value as the cloud environment variable)"
            % (len(raw), kind(raw[:1] or " "), kind(raw[-1:] or " "), getattr(err, "pos", "?")))


def pick_driver(numbers, paths=DRIVER_PATHS, who="driver"):
    """(E.164 number, path name) of ONE test account; the first path wins."""
    for path in paths:
        value = numbers
        for key in path:
            value = value.get(key) if isinstance(value, dict) else None
        if isinstance(value, str) and value.strip():
            e164 = normalise_number(value)
            if not NUMBER_RE.match(e164):
                raise DriverError("the %s entry is not a phone number (needs 8-15 digits)" % ".".join(path))
            return e164, ".".join(path)
    raise DriverError("the MOVERA_TEST_NUMBERS secret has no %s entry (the test %s)"
                      % (" or ".join(".".join(p) for p in paths), who))


def pick_rider(numbers):
    return pick_driver(numbers, RIDER_PATHS, "rider")


def check_code(code):
    code = str(code or "").strip()
    if not CODE_RE.match(code):
        raise DriverError("the sign-in code is not 4-8 digits")
    return code


def secret_values(e164, code):
    return display_forms(e164) + [code]


def number_pattern(value):
    """A regex for a number in any spelling, or None when value is no number:
    the national digits with optional separators between them, after an
    optional +CC / 00CC / (0) / 0 lead."""
    if not NUMBER_RE.match(value):
        return None
    cc, nat = split_number(value)
    body = _SEP.join(re.escape(d) for d in nat)
    lead = ""
    if cc:
        cc_re = _SEP.join(cc)
        lead = r"(?:(?:\+|00)?%s%s(?:\(?0\)?%s)?|0%s)?" % (cc_re, _SEP, _SEP, _SEP)
    return re.compile(lead + body)


def _patterns(secrets):
    out = []
    for s in secrets:
        p = number_pattern(s)
        if p is not None and p.pattern not in [q.pattern for q in out]:
            out.append(p)
    return out


def _is_text(data):
    return b"\0" not in data[:8192]


def scrub(root, secrets):
    """Replaces each secret in every text file under root; returns files changed."""
    values = sorted({s for s in secrets if len(s) >= 4}, key=len, reverse=True)
    patterns = _patterns(values)
    changed = 0
    for path in glob.glob(os.path.join(root, "**", "*"), recursive=True):
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        if not _is_text(data):
            continue
        text = data.decode("utf-8", errors="surrogateescape")
        new = text
        for pattern in patterns:
            new = pattern.sub(REDACTED, new)
        for value in values:
            new = new.replace(value, REDACTED)
        if new != text:
            with open(path, "wb") as fh:
                fh.write(new.encode("utf-8", errors="surrogateescape"))
            changed += 1
    return changed


def leftovers(root, secrets):
    """Files under root (text AND binary) that still hold a value; [] = clean."""
    values = [s.encode("utf-8") for s in {s for s in secrets if len(s) >= 4}]
    patterns = [re.compile(p.pattern.encode("ascii")) for p in _patterns(secrets)]
    hits = []
    for path in glob.glob(os.path.join(root, "**", "*"), recursive=True):
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        if any(v in data for v in values) or any(p.search(data) for p in patterns):
            hits.append(path)
    return sorted(hits)


def scrub_or_fail(root, secrets):
    """Scrub, then re-scan. Returns (exit code, message without values)."""
    secrets = [s.strip() for s in secrets if s and s.strip()]
    if not any(len(s) >= 4 for s in secrets):
        return 1, "::error::no values to scrub (the test driver file is missing or empty); nothing may be uploaded"
    changed = scrub(root, secrets)
    left = leftovers(root, secrets)
    if left:
        # File names only (relative paths), never contents or values.
        names = ", ".join(os.path.relpath(p, root) for p in left[:10])
        shutil.rmtree(root, ignore_errors=True)
        return 1, ("::error::%d file(s) still held the test number or code after scrubbing (%s); "
                   "the results folder was deleted and nothing is uploaded" % (len(left), names))
    return 0, "scrubbed %d file(s); re-scan clean" % changed


def write_driver(out, env, with_rider=False):
    """The `driver` / `trip` command; returns an exit code. Prints no value."""
    rider = rider_path = None
    try:
        numbers = parse_numbers(env.get("TL_NUMBERS", ""))
        e164, path = pick_driver(numbers)
        if with_rider:
            rider, rider_path = pick_rider(numbers)
            if rider == e164:
                raise DriverError("the rider and the driver entry are the same number")
        code = env.get("TL_CODE", "").strip()
        if not code:
            with open("contracts/contract.json", encoding="utf-8") as fh:
                code = str(json.load(fh)["auth"]["testSignIn"]["code"]).strip()
        code = check_code(code)
    except DriverError as err:
        print("::error::" + str(err))
        return 1
    values = secret_values(e164, code)
    if rider:
        values += [f for f in display_forms(rider) if f not in values]
    for value in values:
        print("::add-mask::" + value)
    sys.stdout.flush()

    def write(name, text):
        fd = os.open(os.path.join(out, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh:
            fh.write(text)

    write("phone", e164)
    write("code", code)
    if rider:
        write("rider_phone", rider)
    write("scrub", "\n".join(values) + "\n")
    print("test driver ready: %s (number and code masked)" % path)
    if rider:
        print("test rider ready: %s (number masked)" % rider_path)
    return 0


def write_rider_trip(out, env):
    """The `rider-trip` command (G31 rider); returns an exit code. The rider
    app is on the phone (OUT/phone), the driver is played over HTTP
    (OUT/peer_phone). Prints no value."""
    try:
        numbers = parse_numbers(env.get("TL_NUMBERS", ""))
        rider, rider_path = pick_rider(numbers)
        peer, peer_path = pick_driver(numbers, PEER_DRIVER_PATHS, "driver played over HTTP")
        if rider == peer:
            raise DriverError("the rider and the driver entry are the same number")
        code = env.get("TL_CODE", "").strip()
        if not code:
            with open("contracts/contract.json", encoding="utf-8") as fh:
                code = str(json.load(fh)["auth"]["testSignIn"]["code"]).strip()
        code = check_code(code)
    except DriverError as err:
        print("::error::" + str(err))
        return 1
    values = secret_values(rider, code)
    values += [f for f in display_forms(peer) if f not in values]
    for value in values:
        print("::add-mask::" + value)
    sys.stdout.flush()

    def write(name, text):
        fd = os.open(os.path.join(out, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh:
            fh.write(text)

    write("phone", rider)
    write("code", code)
    write("peer_phone", peer)
    write("scrub", "\n".join(values) + "\n")
    print("test rider (app on the phone) ready: %s (number and code masked)" % rider_path)
    print("test driver (played over HTTP) ready: %s (number masked)" % peer_path)
    return 0


def _logcat_files(root):
    out = []
    for path in glob.glob(os.path.join(root, "**", "*"), recursive=True):
        name = os.path.basename(path).lower()
        if os.path.isfile(path) and ("logcat" in name or name.endswith(".log")):
            out.append(path)
    return sorted(out)


def _lines(path):
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8", errors="replace").splitlines()


def checks_from(root):
    """The check list: summary.json if pulled, else the logcat SUMMARY-JSON line."""
    for path in sorted(glob.glob(os.path.join(root, "**", "summary.json"), recursive=True)):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            if isinstance(data, list):
                return data, path
        except (OSError, ValueError):
            continue
    found = None
    checks = []
    for path in _logcat_files(root):
        for line in _lines(path):
            at = line.find(PREFIX + "SUMMARY-JSON ")
            if at >= 0:
                try:
                    found = json.loads(line[at + len(PREFIX + "SUMMARY-JSON "):])
                except ValueError:
                    pass
                continue
            at = line.find(PREFIX + "CHECK ")
            if at >= 0:
                parts = line[at + len(PREFIX + "CHECK "):].split(" ", 2)
                if len(parts) == 3:
                    checks.append({"id": parts[0], "outcome": parts[1].lower(),
                                   "title": "", "detail": parts[2]})
    if isinstance(found, list):
        return found, "logcat SUMMARY-JSON"
    if checks:
        return checks, "logcat CHECK lines"
    return [], None


def skipped_from(root):
    for path in _logcat_files(root):
        for line in _lines(path):
            at = line.find(PREFIX + "SKIP ")
            if at >= 0:
                return line[at + len(PREFIX):].strip()
    return None


def junit_from(root):
    totals = {"tests": 0, "failures": 0, "errors": 0, "skipped": 0}
    failed = []
    for path in glob.glob(os.path.join(root, "**", "*.xml"), recursive=True):
        try:
            tree = ET.parse(path)
        except ET.ParseError:
            continue
        for case in tree.iter("testcase"):
            totals["tests"] += 1
            if case.find("failure") is not None:
                totals["failures"] += 1
                failed.append(case.get("name", "?"))
            elif case.find("error") is not None:
                totals["errors"] += 1
                failed.append(case.get("name", "?"))
            elif case.find("skipped") is not None:
                totals["skipped"] += 1
    return totals, failed


def crash_lines(root):
    seen = []
    for path in _logcat_files(root):
        for line in _lines(path):
            if PREFIX in line:
                continue
            if any(p.search(line) for p in CRASH_PATTERNS):
                short = line.strip()[:300]
                if short not in seen:
                    seen.append(short)
                if len(seen) >= MAX_CRASH_LINES:
                    return seen
    return seen


def transitions_from(root):
    """Rows of the trip test's transitions.json (or its logcat line)."""
    for path in sorted(glob.glob(os.path.join(root, "**", "transitions.json"), recursive=True)):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            if isinstance(data, list):
                return data
        except (OSError, ValueError):
            continue
    marker = PREFIX + "TRANSITIONS-JSON "
    for path in _logcat_files(root):
        for line in _lines(path):
            at = line.find(marker)
            if at >= 0:
                try:
                    data = json.loads(line[at + len(marker):])
                    if isinstance(data, list):
                        return data
                except ValueError:
                    pass
    return []


def transitions_text(rows):
    if not rows:
        return []
    out = ["", "### Screen changes (FAIL: a frame > 200 ms, > 20% missed frames with >= 10 frames, "
           "a map created again, a full-screen loader or blank frame, a failed call or exception)", "",
           "| Change | Frames | Missed | Worst ms | GET reads | Maps re-created | Loader/blank | Errors | Result |",
           "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if not isinstance(r, dict):
            continue
        bad = [k for k, v in (("FREEZE", not r.get("smooth", True)), ("RELOAD", r.get("reload")),
                              ("ERRORS", r.get("errors"))) if v]
        errors = list(r.get("failedCalls") or []) + list(r.get("exceptions") or [])
        out.append("| %s | %s | %s | %s | %s | %s | %s/%s | %s | %s |" % (
            str(r.get("name", "?")).replace("|", "/"), r.get("frames"), r.get("missed"), r.get("worstMs"),
            r.get("gets"), ", ".join(r.get("recreatedMaps") or []) or "-", r.get("loaderSamples"),
            r.get("blankSamples"), "; ".join(str(e) for e in errors).replace("|", "/")[:200] or "-",
            "FAIL " + " ".join(bad) if bad else "PASS"))
    build = next((r.get("build") for r in rows if isinstance(r, dict) and r.get("build")), None)
    if build:
        out += ["", "Frame numbers: %s." % build]
    return out


# Supervisor 2026-11-12 (5x5 rule): the device checks share se.d38 / se.r35
# with the 5x5 screen runs. Said in every summary so nobody overlaps them.
SHARED_ACCOUNTS_NOTE = (
    "Shared test accounts: se.d38 (driver) and se.r35 (rider) are also the 5x5 "
    "screen runs' pair. One device-check run at a time (workflow concurrency "
    "group); never dispatch one while a 5x5 screen run is going."
)


def summary_text(root):
    checks, source = checks_from(root)
    totals, failed_cases = junit_from(root)
    crashes = crash_lines(root)
    out = ["## Test Lab device checks (staging)", ""]
    skipped = skipped_from(root)
    if skipped:
        out += ["NOT CHECKED: " + skipped, ""]
    if checks:
        out.append("| Check | Result | Detail |")
        out.append("|---|---|---|")
        for c in checks:
            # A FAIL keeps more: its line starts with what the test missed
            # (key / route), which the next diagnosis needs first.
            limit = 800 if str(c.get("outcome", "")).lower() == "fail" else 400
            detail = str(c.get("detail", "")).replace("|", "/")[:limit]
            title = c.get("title") or ""
            out.append("| %s %s | %s | %s |" % (c.get("id"), title, str(c.get("outcome", "")).upper(), detail))
        out += ["", "(from %s)" % source]
    elif not skipped:
        out.append("NOT CHECKED: no check results found (the test did not start or its output was not pulled).")
    out += transitions_text(transitions_from(root))
    out += ["", "JUnit: tests=%(tests)d failures=%(failures)d errors=%(errors)d skipped=%(skipped)d" % totals]
    if failed_cases:
        out.append("Failed JUnit cases: " + ", ".join(failed_cases))
    out += ["", SHARED_ACCOUNTS_NOTE]
    out += ["", "Crash / error lines in logcat: %d" % len(crashes)]
    if crashes:
        out.append("```")
        out += crashes
        out.append("```")
    return "\n".join(out) + "\n"


_CHECK_FAIL_RE = re.compile(re.escape(PREFIX) + r"CHECK (\S+) FAIL\b")


def _logcat_has(root, needle):
    return any(needle in line for path in _logcat_files(root) for line in _lines(path))


def _outcomes(root):
    """Every `outcome` in testlab.json (gcloud --format=json); [] = none."""
    out = []
    for path in glob.glob(os.path.join(root, "**", "testlab.json"), recursive=True):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        rows = data if isinstance(data, list) else [data]
        out += [str(r.get("outcome")) for r in rows if isinstance(r, dict) and "outcome" in r]
    return out


def verdict_reasons(root, rc):
    """Why the device run did NOT pass; [] = passed. Never a value."""
    reasons = []
    if str(rc).strip() != "0":
        reasons.append("Test Lab exit code %s (0 = passed, 10 = a test failed, 15 = inconclusive)"
                       % (str(rc).strip() or "missing"))
    totals, _ = junit_from(root)
    if totals["tests"] == 0:
        reasons.append("JUnit has 0 tests: the test never reported (timed out or hung; run 6)")
    skipped = skipped_from(root)
    if not skipped:
        if not _logcat_has(root, PREFIX + "END "):
            reasons.append("no MOVERA-TL END line: the test did not reach its end (results, clean-up, offline)")
        has_json = bool(glob.glob(os.path.join(root, "**", "summary.json"), recursive=True))
        if not has_json and not _logcat_has(root, PREFIX + "SUMMARY-JSON "):
            reasons.append("no SUMMARY-JSON line and no summary.json: the check results were never written")
    failed = []
    for path in _logcat_files(root):
        for line in _lines(path):
            m = _CHECK_FAIL_RE.search(line)
            if m and m.group(1) not in failed:
                failed.append(m.group(1))
    if failed:
        reasons.append("%d check(s) FAIL: %s" % (len(failed), ", ".join(failed[:20])))
    if _logcat_has(root, "Test timed out after"):
        reasons.append("logcat: \"Test timed out after\" (the test's own time limit ended it)")
    gcloud = os.path.join(root, "gcloud.txt")
    if os.path.isfile(gcloud) and any("non-retryable error" in line for line in _lines(gcloud)):
        reasons.append("gcloud.txt: \"non-retryable error\" (Test Lab had a problem with the run)")
    outcomes = _outcomes(root)
    if not outcomes:
        reasons.append("testlab.json: no outcome (missing or not readable)")
    elif any(o != "Passed" for o in outcomes):
        reasons.append("testlab.json outcome: %s (not Passed)" % ", ".join(sorted(set(outcomes))))
    return reasons


def verdict(root, rc):
    """The `verdict` command; returns an exit code."""
    reasons = verdict_reasons(root, rc)
    for reason in reasons:
        print("::error::Device checks did not pass: " + reason)
    if reasons:
        print("Device checks FAILED (%d reason(s)); see the summary above and the "
              "testlab-results artifact." % len(reasons))
        return 1
    print("Device checks passed on Test Lab (exit 0, JUnit tests, END line, no FAIL, outcome Passed).")
    return 0


def count_runs(path):
    """total_count of a GitHub workflow-runs answer, or None when FILE is
    not one (missing, not JSON, no whole total_count >= 0)."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    n = data.get("total_count")
    if isinstance(n, bool) or not isinstance(n, int) or n < 0:
        return None
    if not isinstance(data.get("workflow_runs", []), list):
        return None
    return n


def main(argv):
    if len(argv) != 3 or argv[1] not in ("driver", "trip", "rider-trip", "count-runs", "scrub",
                                         "summary", "verdict"):
        print(__doc__)
        return 2
    root = argv[2]
    if argv[1] == "rider-trip":
        return write_rider_trip(root, os.environ)
    if argv[1] == "count-runs":
        n = count_runs(root)
        if n is None:
            return 1
        print(n)
        return 0
    if argv[1] in ("driver", "trip"):
        return write_driver(root, os.environ, with_rider=argv[1] == "trip")
    if argv[1] == "scrub":
        secrets = os.environ.get("TL_SCRUB", "").splitlines()
        rc, message = scrub_or_fail(root, secrets)
        print(message)
        return rc
    if argv[1] == "verdict":
        return verdict(root, os.environ.get("RC", ""))
    text = summary_text(root)
    print(text)
    step = os.environ.get("GITHUB_STEP_SUMMARY")
    if step:
        with open(step, "a", encoding="utf-8") as fh:
            fh.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
