/// FTL-H4 (Rules audits/impact/firebase-trip-run-2026-11-16.md, row 5):
/// the device run records an app error's TEXT, not only its type, so the
/// next diagnosis does not need the logcat artifact. The text goes to
/// logcat and summary.json, so every secret is masked first: the run's own
/// phone numbers and code ([known]), any phone-shaped number (with or
/// without its lead), session tokens, e-mail addresses and the value of a
/// code / token / password / session name. Plain Dart (unit tested in
/// test/device_suite/ftl_harness_test.dart).
///
/// FTL MF-1 (post-merge read, same record): the same rules as
/// tool/testlab_summary.py `mask_generic`, kept in step by ONE table for
/// both, tool/tests/mask_probes.json. Change both files together.
library;

const String masked = '[REDACTED]';

/// Between a phone number's digits: up to 3 of space (also no-break /
/// thin), dot, dash, slash, bracket: "070-123 45 67", "070 - 123",
/// "070/123", "+33 (0)6 12", "06.12.34.56.78".
const String _digitSep = r'[ \u00a0\u202f\u2009.\-/()]{0,3}';

/// A digit: also the Arabic and the full-width ones (the same set in
/// tool/testlab_summary.py).
const String _d = r'[0-9\u0660-\u0669\u06f0-\u06f9\uff10-\uff19]';

/// 8 or more digits, with or without a lead, also right after ":" or "."
/// ("tel:070", ":20 123 456", "12:070-123"); two numbers side by side go
/// as one. No colon or comma between the digits, so a time ("07:58:01"), a
/// source position ("x.dart:1080:33") and a size ("1080.0, 2400.0") stay.
final RegExp _phone = RegExp(
  '(?<!$_d)\\+?\\(?$_d(?:$_digitSep$_d){7,40}(?!$_d)',
);

/// Any plain run of 8 or more digits.
final RegExp _longDigits = RegExp('$_d{8,}');

/// "Bearer abc", "bearer:abc", "Basic = abc", and JWTs.
final RegExp _bearer = RegExp(
  r'\b(Bearer|Basic)(?:\s*[:=]\s*|\s+)[A-Za-z0-9\-._~+/=]+',
  caseSensitive: false,
);
final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)?',
);

/// An e-mail address.
final RegExp _email = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
);

/// A name and what follows it: `name: value`, `"name":"value"`,
/// `name=value`, `name => value`, `name -> value` (also inside an escaped
/// JSON text: \"name\":\"value\").
final RegExp _key = RegExp(
  r'''(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\\?["']?\s*(?:=>|->|[:=])\s*)''',
);

/// name + "is" / "was" + value, and name + space + value.
final RegExp _keyIs = RegExp(
  r'(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\s+(?:is|was|are|were)(?:\s*[:=]\s*|\s+))',
  caseSensitive: false,
);
final RegExp _keySpace = RegExp(
  r'''(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\s+)([^\s"',;}&)]*'''
  '$_d'
  r'''[^\s"',;}&)]*)''',
);

/// Names whose value is masked to the end of the value: the closing
/// quote, or the end of the line (a password may hold spaces and & , ; ) ).
final RegExp _nameLine = RegExp(
  r'passw(?:or)?d|passphrase|pwd|secret|authorization|cookie|l[o\u00f6]senord|^(?:pass|pw|psw|auth)$',
  caseSensitive: false,
);

/// Names whose value is one token (or a quoted text).
final RegExp _nameSecret = RegExp(
  r'token|api[_\-]?key|private[_\-]?key|access[_\-]?key|session|credential|signature|code',
  caseSensitive: false,
);

/// Short words that count only as a word of their own inside a name
/// ("pickupPin", "ride_pin", "otpCode", "sid", "PIN"), not as letters of a
/// longer word ("mapping", "inside", "spinner").
final RegExp _namePart = RegExp(
  r'(?:(?<![A-Za-z])(?:pin|Pin|PIN|otp|Otp|OTP|sid|Sid|SID|kod|Kod|KOD|sms|Sms|SMS)'
  r'|(?<=[a-z])(?:Pin|PIN|Otp|OTP|Sid|SID|Sms|SMS))(?![a-z])',
);

/// Names that carry an error / status / country code: a readable value
/// stays.
const Set<String> _plainNames = {
  'code',
  'errorcode',
  'errcode',
  'statuscode',
  'httpcode',
  'responsecode',
  'exitcode',
  'resultcode',
  'reasoncode',
  'countrycode',
  'languagecode',
  'currencycode',
  'localecode',
  'keycode',
};

/// One-word error codes; a snake_case word ("invalid_body") is readable
/// too.
const Set<String> _codeWords = {
  'ok',
  'error',
  'unauthorized',
  'unauthenticated',
  'forbidden',
  'conflict',
  'invalid',
  'expired',
  'timeout',
  'unavailable',
  'internal',
  'unknown',
  'cancelled',
  'canceled',
  'failed',
  'denied',
  'blocked',
  'missing',
  'duplicate',
  'null',
  'none',
};
final RegExp _snake = RegExp(r'^[a-z]+(?:_[a-z]+)+$');
final RegExp _shortPlain = RegExp(r'^(?:[0-9]{1,3}|[A-Za-z]{2,3})$');
final RegExp _valueQuoted = RegExp(
  r"""\\"((?:[^\\\n]|\\(?!"))*)\\"|"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'""",
);
final RegExp _valueToken = RegExp(r'''[^\s"',;}&)]+''');

/// A quote that opens a value and is never closed (a cut line).
final RegExp _openQuote = RegExp(r'''\\?["']''');
final RegExp _valueLine = RegExp(r'[^\n]*');

/// A source position is no secret: "EnterCode:file:///b/lib/x.dart:120:14".
final RegExp _sourceRef = RegExp(
  r'^(?:file:|package:|dart:)|\.dart(?::\d+){0,2}\)?$',
);

/// "password is required": not a value.
final RegExp _notAValue = RegExp(
  r'(?:required|missing|invalid|incorrect|wrong|too|empty|not|null|weak|short|long|'
  r'expired|blank|the|a|an|no|set|needed|mandatory)\b',
  caseSensitive: false,
);

/// A long opaque value (32+ letters and digits, at least one digit), and
/// base64 with + or / (24+, with a digit, a capital and a small letter) or
/// with = padding.
final RegExp _opaque = RegExp(r'(?=[A-Za-z_\-]*\d)[A-Za-z0-9_\-]{32,}');
final RegExp _base64 = RegExp(
  r'(?<![A-Za-z0-9+/])(?:(?=[A-Za-z0-9+/]*\d)(?=[A-Za-z0-9+/]*[A-Z])(?=[A-Za-z0-9+/]*[a-z])'
  r'(?:(?=[A-Za-z0-9]*[+/])[A-Za-z0-9+/]{24,}={0,2}|[A-Za-z0-9+/]{16,}={1,2})(?![A-Za-z0-9+/=]))',
);

/// A line that talks about a code, a sign-in or a secret: every 4-8 digit
/// number standing alone on it is masked ("482913 is your code").
final RegExp _authLine = RegExp(
  r'code|kod|verif|passw|passphrase|l[o\u00f6]senord|token|secret|api[_\-]?key|sign[ _\-]?in|log[ _\-]?in|auth|'
  r'credential',
  caseSensitive: false,
);

/// ... alone = not part of a word, a decimal, a time, a date, a source
/// position ("x.dart:1080:33", "line 5108 pos 12") or a measure
/// ("3000 ms").
final RegExp _bareCode = RegExp(
  '(?<![A-Za-z0-9_#])(?<!$_d)'
  r'(?<!\d[.:,])(?<!line )(?<!pos )'
  '$_d{4,8}(?!$_d'
  r'|[A-Za-z0-9_]|[.:,]\d|:|-\d\d-\d\d| ?(?:ms|px|dp|s|m|km|kB|KB|MB|bytes)\b)',
);

/// A logcat line's own head (date, time, pid, tid, level) is kept as it is.
final RegExp _logcatStamp = RegExp(
  r'^\s*\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+\d+\s+\d+\s+[VDIWEF]\s',
);
final RegExp _digit = RegExp(_d);
final RegExp _nameJoin = RegExp(r'[_\-]');

/// 'line', 'secret', 'plain' or null for a name before a value.
String? _nameKind(String name) {
  if (_nameLine.hasMatch(name)) return 'line';
  if (_plainNames.contains(name.replaceAll(_nameJoin, '').toLowerCase())) {
    return 'plain';
  }
  if (_nameSecret.hasMatch(name) || _namePart.hasMatch(name)) return 'secret';
  return null;
}

/// A value a 'plain' name may show: an error-code word, a status.
bool _readable(String value) =>
    _snake.hasMatch(value) ||
    _shortPlain.hasMatch(value) ||
    _codeWords.contains(value);

RegExpMatch? _next(RegExp re, String text, int from) {
  for (final m in re.allMatches(text, from)) {
    return m;
  }
  return null;
}

/// `name: value` pairs: the value of a secret name masked.
String _maskNamed(String text) {
  final out = StringBuffer();
  var pos = 0;
  while (true) {
    final m = _next(_key, text, pos);
    if (m == null) break;
    final kind = _nameKind(m[1]!);
    final nameEnd = m.start + m[1]!.length;
    if (kind == null) {
      out.write(text.substring(pos, nameEnd));
      pos = nameEnd;
      continue;
    }
    out.write(text.substring(pos, m.end));
    pos = m.end;
    final q = _valueQuoted.matchAsPrefix(text, pos);
    if (q != null) {
      final inner = q[1] ?? q[2] ?? q[3] ?? '';
      // The quote marks: 2 characters each for \" , else 1.
      final quote = q[1] != null ? 2 : 1;
      final keep = kind == 'plain' && _readable(inner);
      out
        ..write(text.substring(pos, pos + quote))
        ..write(keep ? inner : masked)
        ..write(text.substring(q.end - quote, q.end));
      pos = q.end;
      continue;
    }
    final open = _openQuote.matchAsPrefix(text, pos);
    if (open != null) {
      out.write(open[0]);
      pos = open.end;
    }
    final v = (kind == 'line' || open != null ? _valueLine : _valueToken)
        .matchAsPrefix(text, pos);
    final value = v?[0] ?? '';
    if (value.isNotEmpty) {
      final keep =
          open == null &&
          kind != 'line' &&
          (_sourceRef.hasMatch(value) || (kind == 'plain' && _readable(value)));
      out.write(keep ? value : masked);
      pos = v!.end;
    }
  }
  out.write(text.substring(pos));
  return out.toString();
}

/// "password is hunter2" (to the end of the line), "token is abc123".
String _maskIs(String text) {
  final out = StringBuffer();
  var pos = 0;
  while (true) {
    final m = _next(_keyIs, text, pos);
    if (m == null) break;
    final kind = _nameKind(m[1]!);
    out.write(text.substring(pos, m.end));
    pos = m.end;
    if (kind == null || _notAValue.matchAsPrefix(text, pos) != null) continue;
    final v = (kind == 'line' ? _valueLine : _valueToken).matchAsPrefix(
      text,
      pos,
    );
    final value = v?[0] ?? '';
    if (value.isEmpty) continue;
    if (kind != 'line' &&
        (!_digit.hasMatch(value) ||
            _shortPlain.hasMatch(value) ||
            _sourceRef.hasMatch(value))) {
      continue;
    }
    out.write(masked);
    pos = v!.end;
  }
  out.write(text.substring(pos));
  return out.toString();
}

String _maskSpaced(Match m) {
  final value = m[3]!;
  if (_nameKind(m[1]!) == null ||
      _shortPlain.hasMatch(value) ||
      value.startsWith('[') ||
      _sourceRef.hasMatch(value)) {
    return m[0]!;
  }
  return '${m[1]}${m[2]}$masked';
}

/// True when [text] talks about a code, a sign-in or a secret.
bool isAuthText(String text) =>
    _authLine.hasMatch(text) || _namePart.hasMatch(text);

/// Every 4-8 digit number standing alone in [text] masked.
String maskBareCodes(String text) => text.replaceAll(_bareCode, masked);

/// [text] with every secret replaced by [masked]. [known] are the run's
/// own values (phone numbers in E.164, the sign-in code); each is masked
/// as written and, for a number, in any spelling with separators.
String maskText(String text, {Iterable<String> known = const <String>[]}) {
  final stamp = _logcatStamp.firstMatch(text);
  final head = stamp == null ? '' : text.substring(0, stamp.end);
  var out = stamp == null ? text : text.substring(stamp.end);
  final values = <String>{
    for (final k in known)
      if (k.trim().length >= 4) k.trim(),
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final v in values) {
    out = out.replaceAll(v, masked);
    final digits = v.replaceAll(RegExp(r'\D'), '');
    // The national part (the last 9, then the last 8 digits: Tunisian
    // numbers have 8) with any separators between.
    for (final n in const [9, 8]) {
      if (digits.length < n) continue;
      final tail = digits.substring(digits.length - n);
      final spaced = tail
          .split('')
          .map(RegExp.escape)
          .join(r'[ \u00a0\u202f\u2009\-()./]{0,3}');
      out = out.replaceAll(RegExp(spaced), masked);
    }
  }
  out = out.replaceAllMapped(_bearer, (m) => '${m[1]} $masked');
  out = out.replaceAll(_jwt, masked);
  out = out.replaceAll(_email, masked);
  out = out.replaceAll(_opaque, masked);
  out = out.replaceAll(_base64, masked);
  // Numbers before names: "code=070/123 45 67" goes as one number, not as
  // a value "070/123" with the rest left behind.
  out = out.replaceAll(_phone, masked);
  out = out.replaceAll(_longDigits, masked);
  out = _maskNamed(out);
  out = _maskIs(out);
  out = out.replaceAllMapped(_keySpace, _maskSpaced);
  out = out
      .split('\n')
      .map((line) => isAuthText(line) ? maskBareCodes(line) : line)
      .join('\n');
  return head + out;
}

/// One app error as the run records it: type, the first lines of the
/// message (masked, at most [maxChars]) and the first [frames] stack
/// frames. Used for the "STEP app exception" logcat line and the
/// transitions table's Errors column.
String exceptionText(
  Object exception, {
  String? library,
  StackTrace? stack,
  Iterable<String> known = const <String>[],
  int maxChars = 300,
  int frames = 3,
}) {
  final type = exception.runtimeType.toString();
  var message = maskText(
    exception.toString().replaceAll(RegExp(r'\s+'), ' ').trim(),
    known: known,
  );
  // FTL MF-1: a sign-in error's type names the topic ("OtpException"),
  // so a bare 4-8 digit number in its message is masked too.
  if (isAuthText(type) || isAuthText(library ?? '')) {
    message = maskBareCodes(message);
  }
  if (message.length > maxChars) {
    message = '${message.substring(0, maxChars)}...';
  }
  final top = <String>[
    if (stack != null)
      for (final line in stack.toString().split('\n'))
        if (line.trim().isNotEmpty) line.trim().replaceAll(RegExp(r'\s+'), ' '),
  ].take(frames).map((f) => maskText(f, known: known)).toList();
  return '$type (${library ?? 'no library'}): $message'
      '${top.isEmpty ? '' : ' @ ${top.join(' | ')}'}';
}
