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
      Build mode (owner 2026-11-22): the harness prints "MOVERA-TL BUILD
      mode=debug|profile|release". The frame check (TRANSITION:<name>:SMOOTH)
      counts on a profile build (release speed): FAIL = a frame > 200 ms, or
      > 35% missed frames with >= 60 frames; WARN = > 20% missed frames
      (driver profile runs 45 / 46: the 20% limit alone failed a different
      set each run). On a debug build every slow change is only a WARN. The
      harness writes a WARN as "CHECK <id> WARN"; the summary lists it and
      it does not fail the verdict (printed as ::warning::). A WARN for any
      check other than SMOOTH DOES fail, and so does a transitions row over
      the FAIL limit that has no FAIL line. With TL_BUILD=debug|profile
      (the build the workflow asked for) the verdict also fails when the
      phone ran another build. p90 and the jank budget are shown, not judged.
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
# FTL-H4 (Rules audits/impact/firebase-trip-run-2026-11-16.md row 5): run
# 43900906554 lost every "EXCEPTION CAUGHT BY" line because the phone's
# start-up noise (AndroidRuntime am/content launches, Play services
# SecurityException) filled the 40 crash lines first. Real crash lines now
# come first; the noise only fills what is left, and at most NOISE_LINES.
CRASH_PATTERNS = [
    re.compile(p)
    for p in (
        r"FATAL EXCEPTION",
        r"ANR in ",
        r"Unhandled Exception",
        r"EXCEPTION CAUGHT BY",
        r"ForegroundServiceStartNotAllowedException",
        r"\bE[ /]flutter\b",
        r"Process .* has died",
    )
]
NOISE_PATTERNS = [re.compile(p) for p in (r"AndroidRuntime", r"SecurityException")]
MAX_CRASH_LINES = 40
NOISE_LINES = 10
# Flutter error blocks ("══╡ EXCEPTION CAUGHT BY ... ╞══"): every block is
# kept (up to MAX_FLUTTER_BLOCKS), each with its message lines (at most
# BLOCK_MESSAGE_LINES) and the first BLOCK_FRAMES stack frames.
FLUTTER_BLOCK_START = re.compile(r"EXCEPTION CAUGHT BY")
MAX_FLUTTER_BLOCKS = 20
BLOCK_MESSAGE_LINES = 12
BLOCK_FRAMES = 3
_FRAME_RE = re.compile(r"^#\d+\s")
# logcat line heads: "11-16 07:58:01.123  1234  1234 I flutter : ", "I/flutter (1234): "
_LOGCAT_HEAD = re.compile(
    r"^(?:\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+\d+\s+\d+\s+)?[VDIWEF][ /]\s*flutter\s*(?:\(\s*\d+\))?\s*:\s?")


# FTL-H4 (supervisor review 2026-11-16) + FTL MF-1 (post-merge read, same
# day): the summary prints app text from logcat into a PUBLIC job log
# (Flutter error blocks, "STEP app exception" lines, crash lines) next to
# the harness's own text (check details, SKIP, failed calls). `scrub` has
# already removed the run's own numbers and code; mask_generic also removes
# anything SHAPED like a secret, so a value nobody listed (another number,
# a session id, a password in an error text) is never printed. The same
# rules as the rider harness's integration_test/staging/mask_text.dart, and
# one table for both: tool/tests/mask_probes.json.
#
# Between a phone number's digits: up to 3 of space (also no-break / thin),
# dot, dash, slash, bracket: "070-123 45 67", "070 - 123", "070/123",
# "+33 (0)6 12", "06.12.34.56.78".
_DIGIT_SEP = "[ \u00a0\u202f\u2009.\\-/()]{0,3}"
# A digit: also the Arabic and the full-width ones (the same set in
# mask_text.dart, where \d is 0-9 only).
_D = "[0-9\u0660-\u0669\u06f0-\u06f9\uff10-\uff19]"
# 8 or more digits, with or without a lead, also right after ":" or "."
# ("tel:070", ":20 123 456", "12:070-123"); two numbers side by side go as
# one. No colon or comma between the digits, so a time ("07:58:01"), a
# source position ("x.dart:1080:33") and a size ("1080.0, 2400.0") stay.
_PHONE_SHAPE = re.compile("(?<!%s)\\+?\\(?%s(?:%s%s){7,40}(?!%s)" % (_D, _D, _DIGIT_SEP, _D, _D))
_LONG_DIGITS = re.compile("%s{8,}" % _D)
# MF-1 round 2: a phone number written with "_", "," or ":" between its
# digit groups ("070_123_45_67", "+46:70:123:45:67"): it starts with + or 0,
# the same separator each time, 4+ groups, 8+ digits. A time ("07:58:01"),
# a size and a source position have fewer groups or no lead 0.
_PHONE_JOINED = re.compile(
    "(?<!%s)(?<![.:,_])(?:\\+|0)%s{0,3}([,:_])%s{2,4}(?:\\1%s{2,4}){2,}(?!%s|[.:,_]%s)" % (_D, _D, _D, _D, _D, _D))
# MF-1 round 2: a code written in digit groups ("482 913", "48 29 13",
# "4 8 2 9 1 3", "48.29"), masked whole on a line about a code or a
# sign-in: 4-8 digits in all. Not a date, not a decimal like "1080.0".
_SPACED_CODE = re.compile(
    "(?<![A-Za-z0-9_#+])(?<!%s)(?<!%s[.:,])%s{1,4}(?:[ \u00a0.\\-]{1,3}%s{1,4})+(?!%s|[A-Za-z0-9_]|[.:,]%s)"
    % (_D, _D, _D, _D, _D, _D))
_DATE = re.compile(r"^\d{4}-\d\d-\d\d$")
# MF-1 round 2: a code glued to its name: "PIN4829", "OTP482913", "code482913".
_GLUED_CODE = re.compile(r"(?<![A-Za-z])((?:pin|otp|code|kod|sms)[_\-]?)(%s{4,8})(?!%s)" % (_D, _D), re.I)
# MF-1 round 2: a secret type's text, "OtpSession(id: ...)", "Session(...)".
_CALL = re.compile(r"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\(")
_CAMEL = re.compile(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])")
_CALL_WORDS = frozenset((
    "session", "token", "tokens", "otp", "pin", "credential", "credentials", "secret", "password"))
# MF-1 round 2: the secret words of the three markets that are not one
# Latin name: French, Arabic, Russian. A password to the end of the line,
# a code one value.
_NOT_LETTER = r"(?<![A-Za-z\u00c0-\u024f\u0400-\u04ff\u0600-\u06ff])"
_PHRASE_SEP = r"(\s*[:=]\s*|\s+(?:est|\u00e4r|is|\u0647\u0648|\u0647\u064a)\s*[:=]?\s*)"
_PHRASE_LINE = re.compile(
    _NOT_LETTER + r"(mot\s+de\s+passe|mdp|\u0643\u0644\u0645\u0629\s+(?:\u0627\u0644\u0645\u0631\u0648\u0631|\u0627\u0644\u0633\u0631)"
    r"|[\u041f\u043f]\u0430\u0440\u043e\u043b[\u044c\u044f])(?![A-Za-z\u0400-\u04ff\u0600-\u06ff])" + _PHRASE_SEP + r"([^\n]+)")
_PHRASE_CODE = re.compile(
    _NOT_LETTER + r"(code\s+de\s+(?:v[\u00e9e]rification|confirmation|validation)"
    r"|\u0631\u0645\u0632(?:\s+(?:\u0627\u0644\u062a\u062d\u0642\u0642|\u0627\u0644\u062a\u0623\u0643\u064a\u062f|\u0627\u0644\u062f\u062e\u0648\u0644|\u0627\u0644\u062a\u0641\u0639\u064a\u0644))?"
    r"|\u0627\u0644\u0631\u0645\u0632|[\u041a\u043a]\u043e\u0434(?:\s+\u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043d\u0438\u044f)?)"
    r"(?![A-Za-z\u0400-\u04ff\u0600-\u06ff])" + _PHRASE_SEP + r"""([^\s"',;}&)]+)""")
# "Bearer abc", "bearer:abc", "Basic = abc".
_BEARER = re.compile(r"\b(Bearer|Basic)(?:\s*[:=]\s*|\s+)[A-Za-z0-9\-._~+/=]+", re.I)
_JWT = re.compile(r"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)?")
# MF-1 round 2: also a URL-coded "@" (%40).
_EMAIL = re.compile(r"[A-Za-z0-9._%+\-]+(?:@|%40)[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
# A name and what follows it: `name: value`, `"name":"value"`, `name=value`,
# `name => value`, `name -> value` (also inside an escaped JSON text:
# \"name\":\"value\").
_KEY = re.compile(r"""(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\\?["']?\s*(?:=>|->|[:=])\s*)""")
# name + "is" / "was" + value, and name + space + value.
_KEY_IS = re.compile(
    r"(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\s+(?:is|was|are|were|\u00e4r|var|est|ist)(?:\s*[:=]\s*|\s+))", re.I)
_KEY_SPACE = re.compile(
    r"""(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\s+)([^\s"',;}&)]*%s[^\s"',;}&)]*)""" % _D)
_HAS_DIGIT = re.compile(_D)
# Names whose value is masked to the end of the value: the closing quote,
# or the end of the line (a password may hold spaces and & , ; ) ).
_NAME_LINE = re.compile(
    r"passw(?:or)?d|passphrase|pwd|secret|authorization|cookie|l[o\u00f6]senord|^(?:pass|pw|psw|auth)$|[_\-]auth$", re.I)
# Names whose value is one token (or a quoted text).
_NAME_SECRET = re.compile(
    r"token|api[_\-]?key|private[_\-]?key|access[_\-]?key|session|credential|signature|code|jwt|nonce|^key$|[_\-]key$", re.I)
# Short words that count only as a word of their own inside a name
# ("pickupPin", "ride_pin", "otpCode", "sid", "PIN"), not as letters of a
# longer word ("mapping", "inside", "spinner").
_WORD_PART = (
    r"(?:(?<![A-Za-z])(?:pin|Pin|PIN|otp|Otp|OTP|sid|Sid|SID|kod|Kod|KOD|sms|Sms|SMS)"
    r"|(?<=[a-z])(?:Pin|PIN|Otp|OTP|Sid|SID|Sms|SMS))(?![a-z])")
_NAME_PART = re.compile(_WORD_PART)
# Names that carry an error / status / country code: a readable value stays.
_PLAIN_NAMES = frozenset((
    "code", "errorcode", "errcode", "statuscode", "httpcode", "responsecode", "exitcode",
    "resultcode", "reasoncode", "countrycode", "languagecode", "currencycode", "localecode",
    "keycode"))
# One-word error codes; a snake_case word ("invalid_body") is readable too.
_CODE_WORDS = frozenset((
    "ok", "error", "unauthorized", "unauthenticated", "forbidden", "conflict", "invalid",
    "expired", "timeout", "unavailable", "internal", "unknown", "cancelled", "canceled",
    "failed", "denied", "blocked", "missing", "duplicate", "null", "none"))
_SNAKE = re.compile(r"^[a-z]+(?:_[a-z]+)+$")
_SHORT_PLAIN = re.compile(r"^(?:[0-9]{1,3}|[A-Za-z]{2,3})$")
_VALUE_QUOTED = re.compile(r'''\\"((?:[^\\\n]|\\(?!"))*)\\"|"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)\'''')
_VALUE_TOKEN = re.compile(r"""[^\s"',;}&)]+""")
# A quote that opens a value and is never closed (a cut line).
_OPEN_QUOTE = re.compile(r"""\\?["']""")
_VALUE_LINE = re.compile(r"[^\n]*")
# A source position is no secret: "EnterCode:file:///b/lib/x.dart:120:14".
_SOURCE_REF = re.compile(r"^(?:file:|package:|dart:)|\.dart(?::\d+){0,2}\)?$")
# "password is required": not a value.
_NOT_A_VALUE = re.compile(
    r"(?:required|missing|invalid|incorrect|wrong|too|empty|not|null|weak|short|long|"
    r"expired|blank|the|a|an|no|set|needed|mandatory)\b", re.I)
# A long opaque value (32+ letters and digits, at least one digit), and
# base64 with + or / (24+, with a digit, a capital and a small letter) or
# with = padding.
_OPAQUE = re.compile(r"(?=[A-Za-z_\-]*\d)[A-Za-z0-9_\-]{32,}")
_BASE64 = re.compile(
    r"(?<![A-Za-z0-9+/])(?:(?=[A-Za-z0-9+/]*\d)(?=[A-Za-z0-9+/]*[A-Z])(?=[A-Za-z0-9+/]*[a-z])"
    r"(?:(?=[A-Za-z0-9]*[+/])[A-Za-z0-9+/]{24,}={0,2}|[A-Za-z0-9+/]{16,}={1,2})(?![A-Za-z0-9+/=]))")
# A line that talks about a code, a sign-in or a secret: every 4-8 digit
# number standing alone on it is masked ("482913 is your code", "PIN 4829").
_AUTH_LINE = re.compile(
    r"code|kod|verif|passw|passphrase|l[o\u00f6]senord|token|secret|api[_\-]?key|sign[ _\-]?in|log[ _\-]?in|auth|"
    r"credential|mot de passe|\u0631\u0645\u0632|\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631|\u0627\u0644\u062a\u062d\u0642\u0642|\u043f\u0430\u0440\u043e\u043b|\u043a\u043e\u0434",
    re.I)
# ... alone = not part of a word, a decimal, a time, a date, a source
# position ("x.dart:1080:33", "line 5108 pos 12") or a measure ("3000 ms").
_BARE_CODE = re.compile(
    r"(?<![A-Za-z0-9_#])(?<!%s)(?<!\d[.:,])(?<!\.dart:)(?<!line )(?<!pos )%s{4,8}"
    r"(?!%s|[A-Za-z0-9_]|[.:,]\d|-\d\d-\d\d| ?(?:ms|px|dp|s|m|km|kB|KB|MB|bytes)\b)" % (_D, _D, _D))
# A logcat line's own head (date, time, pid, tid, level) is kept as it is.
_LOGCAT_STAMP = re.compile(r"^\s*\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+\d+\s+\d+\s+[VDIWEF]\s")


def _name_kind(name):
    """'line', 'secret', 'plain' or None for a name before a value."""
    if _NAME_LINE.search(name):
        return "line"
    if re.sub(r"[_\-]", "", name).lower() in _PLAIN_NAMES:
        return "plain"
    if _NAME_SECRET.search(name) or _NAME_PART.search(name):
        return "secret"
    return None


def _readable(value):
    """A value a 'plain' name may show: an error-code word, a status."""
    return bool(_SNAKE.match(value) or _SHORT_PLAIN.match(value) or value in _CODE_WORDS)


def _mask_joined(m):
    return REDACTED if len(_HAS_DIGIT.findall(m.group(0))) >= 8 else m.group(0)


def _mask_spaced_code(m):
    value = m.group(0)
    digits = len(_HAS_DIGIT.findall(value))
    if not 4 <= digits <= 8 or _DATE.match(value) or ("." in value and re.search(r"\d{4}", value)):
        return value
    return REDACTED


def _close(text, pos):
    """The end of the bracket that opens at pos: its matching close, or
    the end of the line."""
    depth = 0
    for i in range(pos, len(text)):
        c = text[i]
        if c == "\n":
            return i
        if c in "{[(":
            depth += 1
        elif c in "}])":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def _mask_calls(text):
    """"OtpSession(id: ...)": the text of a secret type masked."""
    out, pos = [], 0
    while True:
        m = _CALL.search(text, pos)
        if not m:
            break
        words = _CAMEL.findall(m.group(1))
        end = _close(text, m.end() - 1)
        inner = text[m.end():end - 1] if text[end - 1:end] == ")" else text[m.end():end]
        if not words or words[-1].lower() not in _CALL_WORDS or not inner or _readable(inner):
            out.append(text[pos:m.end()])
            pos = m.end()
            continue
        out.append(text[pos:m.end()] + REDACTED)
        pos = m.end() + len(inner)
    out.append(text[pos:])
    return "".join(out)


def _mask_phrase(m):
    if _NOT_A_VALUE.match(m.group(3)) or m.group(3).startswith("["):
        return m.group(0)
    return m.group(1) + m.group(2) + REDACTED


def _mask_phrases(text):
    """French / Arabic / Russian secret words and their value."""
    return _PHRASE_CODE.sub(_mask_phrase, _PHRASE_LINE.sub(_mask_phrase, text))


def _mask_named(text):
    """`name: value` pairs: the value of a secret name masked."""
    out, pos = [], 0
    while True:
        m = _KEY.search(text, pos)
        if not m:
            break
        kind = _name_kind(m.group(1))
        if kind is None:
            out.append(text[pos:m.end(1)])
            pos = m.end(1)
            continue
        out.append(text[pos:m.end()])
        pos = m.end()
        if kind != "plain" and text[pos:pos + 1] in ("{", "["):
            # MF-1 round 2: an object or a list goes whole.
            out.append(REDACTED)
            pos = _close(text, pos)
            continue
        q = _VALUE_QUOTED.match(text, pos)
        if q:
            inner = next(i for i in (1, 2, 3) if q.group(i) is not None)
            keep = kind == "plain" and _readable(q.group(inner))
            out.append(text[pos:q.start(inner)] + (q.group(inner) if keep else REDACTED) + text[q.end(inner):q.end()])
            pos = q.end()
            continue
        q = _OPEN_QUOTE.match(text, pos)
        if q:
            out.append(q.group(0))
            pos = q.end()
        v = (_VALUE_LINE if kind == "line" or q else _VALUE_TOKEN).match(text, pos)
        if v and v.group(0):
            value = v.group(0)
            keep = not q and kind != "line" and (_SOURCE_REF.search(value) or (kind == "plain" and _readable(value)))
            out.append(value if keep else REDACTED)
            pos = v.end()
    out.append(text[pos:])
    return "".join(out)


def _mask_is(text):
    """"password is hunter2" (to the end of the line), "token is abc123"."""
    out, pos = [], 0
    while True:
        m = _KEY_IS.search(text, pos)
        if not m:
            break
        kind = _name_kind(m.group(1))
        out.append(text[pos:m.end()])
        pos = m.end()
        if kind is None or _NOT_A_VALUE.match(text, pos):
            continue
        v = (_VALUE_LINE if kind == "line" else _VALUE_TOKEN).match(text, pos)
        if not v or not v.group(0):
            continue
        value = v.group(0)
        if kind != "line" and (not _HAS_DIGIT.search(value) or _SHORT_PLAIN.match(value)
                               or _SOURCE_REF.search(value)):
            continue
        out.append(REDACTED)
        pos = v.end()
    out.append(text[pos:])
    return "".join(out)


def _mask_spaced(m):
    kind = _name_kind(m.group(1))
    value = m.group(3)
    if kind is None or _SHORT_PLAIN.match(value) or value.startswith("[") or _SOURCE_REF.search(value):
        return m.group(0)
    return m.group(1) + m.group(2) + REDACTED


def is_auth_text(text):
    """True when text talks about a code, a sign-in or a secret."""
    return bool(_AUTH_LINE.search(text) or _NAME_PART.search(text))


def mask_bare_codes(text):
    """Every 4-8 digit number standing alone in text masked."""
    return _BARE_CODE.sub(REDACTED, text)


def _mask_auth_line(line):
    return mask_bare_codes(line) if is_auth_text(line) else line


def mask_generic(text):
    """text with everything shaped like a phone number, a code, a token, a
    password or an e-mail address replaced by [REDACTED]."""
    text = str(text)
    m = _LOGCAT_STAMP.match(text)
    head, out = (text[:m.end()], text[m.end():]) if m else ("", text)
    out = _BEARER.sub(lambda b: "%s %s" % (b.group(1), REDACTED), out)
    out = _JWT.sub(REDACTED, out)
    out = _EMAIL.sub(REDACTED, out)
    out = _OPAQUE.sub(REDACTED, out)
    out = _BASE64.sub(REDACTED, out)
    # Numbers before names: "code=070/123 45 67" goes as one number, not as
    # a value "070/123" with the rest left behind.
    out = _PHONE_SHAPE.sub(REDACTED, out)
    out = _LONG_DIGITS.sub(REDACTED, out)
    out = _PHONE_JOINED.sub(_mask_joined, out)
    out = "\n".join(_SPACED_CODE.sub(_mask_spaced_code, line) if is_auth_text(line) else line
                     for line in out.split("\n"))
    out = _GLUED_CODE.sub(lambda g: g.group(1) + REDACTED, out)
    out = _mask_calls(out)
    out = _mask_phrases(out)
    out = _mask_named(out)
    out = _mask_is(out)
    out = _KEY_SPACE.sub(_mask_spaced, out)
    out = "\n".join(_mask_auth_line(line) for line in out.split("\n"))
    return head + out


# Country codes of the app's countries (lib/core/auth/phone_country.dart);
# others fall back to the whole number.
_COUNTRY_CODES = ("216", "33", "46")
# Separators the app, Android and people put between digits.
_SEP = r"[\s\-()./]*"
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
                return mask_generic(line[at + len(PREFIX):].strip())
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
    """Crash lines of logcat: the real ones first (Flutter, fatal, ANR,
    died), then at most NOISE_LINES of the phone's start-up noise, all
    within MAX_CRASH_LINES."""
    real, noise = [], []
    for path in _logcat_files(root):
        for line in _lines(path):
            if PREFIX in line:
                continue
            short = mask_generic(line.strip())[:300]
            if any(p.search(line) for p in CRASH_PATTERNS):
                if short not in real and len(real) < MAX_CRASH_LINES:
                    real.append(short)
            elif any(p.search(line) for p in NOISE_PATTERNS):
                if short not in noise and len(noise) < NOISE_LINES:
                    noise.append(short)
    room = max(0, MAX_CRASH_LINES - len(real))
    return real + noise[:room]


def _flutter_text(line):
    """The text of a flutter logcat line (head cut), or None for other tags."""
    m = _LOGCAT_HEAD.match(line.strip())
    return line.strip()[m.end():] if m else None


def flutter_error_blocks(root):
    """Every Flutter "EXCEPTION CAUGHT BY" block (up to MAX_FLUTTER_BLOCKS):
    its header, message lines and first BLOCK_FRAMES stack frames."""
    blocks = []
    for path in _logcat_files(root):
        current = None
        for line in _lines(path):
            text = _flutter_text(line)
            if text is None:
                text = line.strip() if FLUTTER_BLOCK_START.search(line) else None
                if text is None:
                    continue
            if FLUTTER_BLOCK_START.search(text):
                if len(blocks) >= MAX_FLUTTER_BLOCKS:
                    return _mask_block_codes(blocks)
                current = {"head": mask_generic(text)[:300], "message": [], "frames": [], "stack": False}
                blocks.append(current)
                continue
            if current is None:
                continue
            body = text.strip()
            if not body:
                continue
            if set(body) <= set("═╡╞ "):
                current = None  # the block's closing rule
                continue
            if _FRAME_RE.match(body):
                if len(current["frames"]) < BLOCK_FRAMES:
                    current["frames"].append(mask_generic(body)[:300])
                current["stack"] = True
                continue
            if body.startswith("When the exception was thrown"):
                current["stack"] = True
                continue
            if not current["stack"] and len(current["message"]) < BLOCK_MESSAGE_LINES:
                current["message"].append(mask_generic(body)[:300])
    return _mask_block_codes(blocks)


def _mask_block_codes(blocks):
    """FTL MF-1: in a block that talks about a code or a sign-in, a 4-8
    digit number standing alone is masked on every line of the block."""
    for b in blocks:
        if any(is_auth_text(line) for line in [b["head"]] + b["message"]):
            b["head"] = mask_bare_codes(b["head"])
            b["message"] = [mask_bare_codes(line) for line in b["message"]]
    return blocks


def app_exception_lines(root):
    """The harness's own "STEP app exception" lines (type, masked text;
    masked here again: this file is the last gate before the job log)."""
    out = []
    marker = PREFIX + "STEP app exception "
    for path in _logcat_files(root):
        for line in _lines(path):
            at = line.find(marker)
            if at >= 0:
                text = mask_generic(line[at + len(marker):].strip())[:500]
                if text not in out:
                    out.append(text)
    return out[:MAX_CRASH_LINES]


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


_BUILD_RE = re.compile(re.escape(PREFIX) + r"BUILD mode=(debug|profile|release)\b")
INDICATIVE = "indicative (debug build)"
# The frame rule of integration_test/staging/smooth_verdict.dart (the same
# numbers). Driver profile runs 45 / 46 (2026-11-22): at 40-80 frames the
# share of missed frames moved by 10-20 points from run to run, so over 20%
# is a WARN on profile; a FAIL needs a frame over 200 ms, or over 35% of at
# least 60 frames.
FREEZE_MS = 200
FAIL_MISSED = 0.35
FAIL_MIN_FRAMES = 60
WARN_MISSED = 0.20
NEAR_MISSED = 0.15
DEBUG_MIN_FRAMES = 10
SMOOTH_RULE = "FAIL: a frame > 200 ms or > 35% missed with >= 60 frames; WARN: > 20% missed"
OVER_WARN = "over the warn limit"


def _number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def judge_frames(frames, missed, worst_ms, mode):
    """'pass' / 'warn' / 'fail' for one screen change; any mode but debug is strict."""
    frames, missed, worst_ms = _number(frames), _number(missed), _number(worst_ms)
    ratio = missed / frames if frames > 0 else 0.0
    freeze = worst_ms > FREEZE_MS
    if mode == "debug":
        return "warn" if freeze or (frames >= DEBUG_MIN_FRAMES and ratio > WARN_MISSED) else "pass"
    if freeze or (frames >= FAIL_MIN_FRAMES and ratio > FAIL_MISSED):
        return "fail"
    return "warn" if ratio > WARN_MISSED else "pass"


def _row_mode(row):
    build = str(row.get("build") or "")
    return next((m for m in ("debug", "profile", "release") if build.startswith(m)), None)


def _row_judged(row):
    """The tool's own judgement of a transitions row, from its numbers."""
    return judge_frames(row.get("frames"), row.get("missed"), row.get("worstMs"), _row_mode(row))


def row_outcome(row):
    """The harness's SMOOTH outcome of a row; an older row is judged by its numbers."""
    said = str(row.get("smoothOutcome") or "").lower()
    return said if said in ("pass", "warn", "fail") else _row_judged(row)


def _share(row):
    frames, missed = _number(row.get("frames")), _number(row.get("missed"))
    return missed / frames if frames > 0 else 0.0


def near_limit_text(rows):
    """One line naming every screen change with 15% or more frames missed; None = none."""
    near = ["%s %d%% (%s/%s)" % (mask_generic(str(r.get("name", "?"))), round(_share(r) * 100),
                                r.get("missed"), r.get("frames"))
            for r in rows if isinstance(r, dict) and _share(r) >= NEAR_MISSED]
    if not near:
        return None
    return "Near the limit (15%% or more frames missed): %s" % ", ".join(near[:30])


def unfailed_rows(root):
    """Names of rows over the FAIL limit (by the tool's numbers) that have no FAIL line."""
    failed = set()
    for path in _logcat_files(root):
        for line in _lines(path):
            m = _CHECK_FAIL_RE.search(line)
            if m:
                failed.add(m.group(1))
    out = []
    for r in transitions_from(root):
        if isinstance(r, dict) and _row_judged(r) == "fail":
            name = str(r.get("name", "?"))
            if "TRANSITION:%s:SMOOTH" % name not in failed and name not in out:
                out.append(name)
    return out


def build_mode_from(root):
    """'debug' / 'profile' / 'release' from the harness line; None = not said."""
    for path in _logcat_files(root):
        for line in _lines(path):
            m = _BUILD_RE.search(line)
            if m:
                return m.group(1)
    return None


def build_mode_text(mode):
    if mode == "debug":
        return ("Build mode: debug (slow: the frame checks, SMOOTH, are %s and reported as WARN, "
                "not FAIL; every other check counts)" % INDICATIVE)
    if mode in ("profile", "release"):
        return "Build mode: %s (release speed: the frame checks, SMOOTH, count: %s)" % (mode, SMOOTH_RULE)
    return "Build mode: not reported (no MOVERA-TL BUILD line in logcat)"


_CHECK_WARN_RE = re.compile(re.escape(PREFIX) + r"CHECK (\S+) WARN\b")


def warned_from(root):
    """Ids of the CHECK ... WARN lines in logcat, in order, each once."""
    out = []
    for path in _logcat_files(root):
        for line in _lines(path):
            m = _CHECK_WARN_RE.search(line)
            if m and m.group(1) not in out:
                out.append(m.group(1))
    return out


def smooth_warns(root):
    """(smooth, wrong): WARN ids that are a SMOOTH check, and the rest (never allowed)."""
    ok, wrong = [], []
    for check in warned_from(root):
        (ok if check.endswith(":SMOOTH") else wrong).append(check)
    return ok, wrong


def warn_reason(root):
    """Why a SMOOTH WARN is not a FAIL, by the build that ran."""
    return INDICATIVE if build_mode_from(root) == "debug" else OVER_WARN


def transitions_text(rows):
    if not rows:
        return []
    out = ["", "### Screen changes (FAIL: a frame > 200 ms or > 35% missed frames with >= 60 frames, "
           "a map created again, a full-screen loader or blank frame, a failed call or exception; "
           "WARN: > 20% missed frames; debug build: frames are WARN only)", "",
           "| Change | Frames | Missed | Worst ms | p90 ms | Jank ms | GET reads | Maps re-created | Loader/blank "
           "| Errors | Result |",
           "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if not isinstance(r, dict):
            continue
        # The frames: FAIL, or a WARN (debug: indicative; profile: over 20% missed).
        frames_outcome = row_outcome(r)
        bad = [k for k, v in (("FREEZE", frames_outcome == "fail"), ("RELOAD", r.get("reload")),
                              ("ERRORS", r.get("errors"))) if v]
        result = "FAIL " + " ".join(bad) if bad else ""
        if frames_outcome == "warn":
            result += ("; " if result else "") + (
                "WARN FREEZE (indicative, debug build)" if _row_mode(r) == "debug"
                else "WARN FRAMES (over 20% missed, not a FAIL)")
        missed = r.get("missed")
        if _number(r.get("frames")) > 0:
            missed = "%s (%d%%)" % (missed, round(_share(r) * 100))
        errors = [mask_generic(str(e)) for e in list(r.get("failedCalls") or []) + list(r.get("exceptions") or [])]
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s/%s | %s | %s |" % (
            mask_generic(str(r.get("name", "?"))).replace("|", "/"), r.get("frames"), missed, r.get("worstMs"),
            r.get("p90Ms", "-"), r.get("jankMs", "-"), r.get("gets"), mask_generic(", ".join(str(m) for m in r.get("recreatedMaps") or [])) or "-",
            r.get("loaderSamples"),
            r.get("blankSamples"), "; ".join(str(e) for e in errors).replace("|", "/")[:200] or "-",
            result or "PASS"))
    build = next((r.get("build") for r in rows if isinstance(r, dict) and r.get("build")), None)
    if build:
        out += ["", "Frame numbers: %s." % mask_generic(str(build))]
    out += ["", "p90 and jank (the sum of ms over 16.7 of the missed frames) are shown only; "
            "they are not part of the verdict yet."]
    near = near_limit_text(rows)
    if near:
        out += ["", near]
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
    out = ["## Test Lab device checks (staging)", "", build_mode_text(build_mode_from(root)), ""]
    indicative, wrong_warns = smooth_warns(root)
    if indicative:
        why = INDICATIVE if build_mode_from(root) == "debug" else OVER_WARN + " (> 20% missed frames)"
        out += ["WARN: %d SMOOTH check(s) %s, not a FAIL: %s" % (
            len(indicative), why, mask_generic(", ".join(indicative[:30]))), ""]
    if wrong_warns:
        out += ["FAIL: %d WARN line(s) that are not a SMOOTH check: %s" % (
            len(wrong_warns), mask_generic(", ".join(wrong_warns[:20]))), ""]
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
            # FTL MF-1 (SF-2): the summary is the last gate for all it prints.
            detail = mask_generic(str(c.get("detail", ""))).replace("|", "/")[:limit]
            title = mask_generic(str(c.get("title") or "")).replace("|", "/")
            out.append("| %s %s | %s | %s |" % (
                mask_generic(str(c.get("id"))).replace("|", "/"), title,
                mask_generic(str(c.get("outcome", "")).upper()), detail))
        out += ["", "(from %s)" % source]
    elif not skipped:
        out.append("NOT CHECKED: no check results found (the test did not start or its output was not pulled).")
    out += transitions_text(transitions_from(root))
    out += ["", "JUnit: tests=%(tests)d failures=%(failures)d errors=%(errors)d skipped=%(skipped)d" % totals]
    if failed_cases:
        out.append("Failed JUnit cases: " + mask_generic(", ".join(failed_cases)))
    out += ["", SHARED_ACCOUNTS_NOTE]
    exceptions = app_exception_lines(root)
    if exceptions:
        out += ["", "App exceptions the test saw: %d" % len(exceptions), "```"]
        out += exceptions
        out.append("```")
    blocks = flutter_error_blocks(root)
    if blocks:
        out += ["", "Flutter errors in logcat (EXCEPTION CAUGHT BY): %d" % len(blocks), "```"]
        for b in blocks:
            out.append(b["head"])
            out += ["  " + m for m in b["message"]]
            out += ["  " + f for f in b["frames"]]
        out.append("```")
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


def verdict_reasons(root, rc, expected_build=""):
    """Why the device run did NOT pass; [] = passed. Never a value.

    expected_build: the build the workflow asked for ("debug" / "profile");
    empty = not compared.
    """
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
    _, wrong_warns = smooth_warns(root)
    if wrong_warns:
        reasons.append("%d WARN line(s), but WARN is only for SMOOTH: %s"
                       % (len(wrong_warns), ", ".join(wrong_warns[:20])))
    unfailed = unfailed_rows(root)
    if unfailed:
        reasons.append("%d screen change(s) over the FAIL limit without a FAIL line: %s (%s)"
                       % (len(unfailed), ", ".join(unfailed[:20]), SMOOTH_RULE))
    expected = str(expected_build or "").strip()
    if expected and not skipped:
        ran = build_mode_from(root)
        if ran != expected:
            reasons.append("build mode: asked for %s, the phone ran %s"
                           % (expected if expected in ("debug", "profile") else "an unknown mode",
                              ran or "not reported"))
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


def verdict(root, rc, expected_build=""):
    """The `verdict` command; returns an exit code."""
    reasons = verdict_reasons(root, rc, expected_build)
    indicative, _ = smooth_warns(root)
    if indicative:
        debug = build_mode_from(root) == "debug"
        print("::warning::%d SMOOTH check(s) %s, not a FAIL: %s. %s" % (
            len(indicative), warn_reason(root), mask_generic(", ".join(indicative[:30])),
            "Run with testlab_build=profile to judge the frames." if debug
            else "More than 20% of the frames missed 16.7 ms; see the screen changes table."))
    for reason in reasons:
        print("::error::Device checks did not pass: " + mask_generic(reason))
    if reasons:
        print("Device checks FAILED (%d reason(s)); see the summary above and the "
              "testlab-results artifact." % len(reasons))
        return 1
    mode = build_mode_from(root)
    print("Device checks passed on Test Lab (exit 0, JUnit tests, END line, no FAIL, outcome Passed; %s)."
          % ("debug build: SMOOTH %s" % INDICATIVE if mode == "debug"
             else "%s build: SMOOTH counts (%s)" % (mode, SMOOTH_RULE) if mode
             else "build mode not reported"))
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
        return verdict(root, os.environ.get("RC", ""), os.environ.get("TL_BUILD", ""))
    text = summary_text(root)
    print(text)
    step = os.environ.get("GITHUB_STEP_SUMMARY")
    if step:
        with open(step, "a", encoding="utf-8") as fh:
            fh.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
