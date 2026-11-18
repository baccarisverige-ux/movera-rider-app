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

/// MF-1 round 2: a phone number written with "_", "," or ":" between its
/// digit groups ("070_123_45_67", "+46:70:123:45:67"): it starts with + or
/// 0, the same separator each time, 4+ groups, 8+ digits. A time
/// ("07:58:01"), a size and a source position have fewer groups or no
/// lead 0.
final RegExp _phoneJoined = RegExp(
  '(?<!$_d)(?<![.:,_])(?:\\+|0)$_d{0,3}([,:_])$_d{2,4}(?:\\1$_d{2,4}){2,}'
  '(?!$_d|[.:,_]$_d)',
);

/// MF-1 round 2: a code written in digit groups ("482 913", "48 29 13",
/// "4 8 2 9 1 3", "48.29"), masked whole on a line about a code or a
/// sign-in: 4-8 digits in all. Not a date, not a decimal like "1080.0".
final RegExp _spacedCode = RegExp(
  '(?<![A-Za-z0-9_#+])(?<!$_d)(?<!$_d[.:,])$_d{1,4}'
  '(?:[ \\u00a0.\\-]{1,3}$_d{1,4})+(?!$_d|[A-Za-z0-9_]|[.:,]$_d)',
);
final RegExp _date = RegExp(r'^\d{4}-\d\d-\d\d$');
final RegExp _fourDigits = RegExp(r'\d{4}');

/// MF-1 round 2: a code glued to its name: "PIN4829", "OTP482913",
/// "code482913".
final RegExp _gluedCode = RegExp(
  '(?<![A-Za-z])((?:pin|otp|code|kod|sms)[_\\-]?)($_d{4,8})(?!$_d)',
  caseSensitive: false,
);

/// MF-1 round 2: a secret type's text, "OtpSession(id: ...)",
/// "Session(...)": the last word of the type name is a secret word.
final RegExp _call = RegExp(r'(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\(');
final RegExp _camel = RegExp(r'[A-Z]?[a-z]+|[A-Z]+(?![a-z])');
const Set<String> _callWords = {
  'session',
  'token',
  'tokens',
  'otp',
  'pin',
  'credential',
  'credentials',
  'secret',
  'password',
};

/// MF-1 round 2: the secret words of the three markets that are not one
/// Latin name: French, Arabic, Russian. A password to the end of the line,
/// a code one value.
const String _notLetter =
    r'(?<![A-Za-z\u00c0-\u024f\u0400-\u04ff\u0600-\u06ff])';
const String _phraseSep =
    r'(\s*[:=]\s*|\s+(?:est|\u00e4r|is|\u0647\u0648|\u0647\u064a)\s*[:=]?\s*)';
final RegExp _phraseLine = RegExp(
  '$_notLetter'
  r'(mot\s+de\s+passe|mdp|\u0643\u0644\u0645\u0629\s+(?:\u0627\u0644\u0645\u0631\u0648\u0631|\u0627\u0644\u0633\u0631)'
  r'|[\u041f\u043f]\u0430\u0440\u043e\u043b[\u044c\u044f])(?![A-Za-z\u0400-\u04ff\u0600-\u06ff])'
  '$_phraseSep'
  r'([^\n]+)',
);
final RegExp _phraseCode = RegExp(
  '$_notLetter'
  r'(code\s+de\s+(?:v[\u00e9e]rification|confirmation|validation)'
  r'|\u0631\u0645\u0632(?:\s+(?:\u0627\u0644\u062a\u062d\u0642\u0642|\u0627\u0644\u062a\u0623\u0643\u064a\u062f|\u0627\u0644\u062f\u062e\u0648\u0644|\u0627\u0644\u062a\u0641\u0639\u064a\u0644))?'
  r'|\u0627\u0644\u0631\u0645\u0632|[\u041a\u043a]\u043e\u0434(?:\s+\u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043d\u0438\u044f)?)'
  r'(?![A-Za-z\u0400-\u04ff\u0600-\u06ff])'
  '$_phraseSep'
  r'''([^\s"',;}&)]+)''',
);

/// "Bearer abc", "bearer:abc", "Basic = abc", and JWTs.
final RegExp _bearer = RegExp(
  r'\b(Bearer|Basic)(?:\s*[:=]\s*|\s+)[A-Za-z0-9\-._~+/=]+',
  caseSensitive: false,
);
final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)?',
);

/// An e-mail address (MF-1 round 2: also with a URL-coded "@", %40).
final RegExp _email = RegExp(
  r'[A-Za-z0-9._%+\-]+(?:@|%40)[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
);

/// A name and what follows it: `name: value`, `"name":"value"`,
/// `name=value`, `name => value`, `name -> value` (also inside an escaped
/// JSON text: \"name\":\"value\").
final RegExp _key = RegExp(
  r'''(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\\?["']?\s*(?:=>|->|[:=])\s*)''',
);

/// name + "is" / "was" + value, and name + space + value.
final RegExp _keyIs = RegExp(
  r'(?<![A-Za-z0-9_\-\u00c0-\u024f])([A-Za-z\u00c0-\u024f][A-Za-z0-9_\-\u00c0-\u024f]*)(\s+(?:is|was|are|were|\u00e4r|var|est|ist)(?:\s*[:=]\s*|\s+))',
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
  r'passw(?:or)?d|passphrase|pwd|secret|authorization|cookie|l[o\u00f6]senord|^(?:pass|pw|psw|auth)$|[_\-]auth$',
  caseSensitive: false,
);

/// Names whose value is one token (or a quoted text).
final RegExp _nameSecret = RegExp(
  r'token|api[_\-]?key|private[_\-]?key|access[_\-]?key|session|credential|signature|code|jwt|nonce|^key$|[_\-]key$',
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
  r'credential|mot de passe|\u0631\u0645\u0632|\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631|\u0627\u0644\u062a\u062d\u0642\u0642|\u043f\u0430\u0440\u043e\u043b|\u043a\u043e\u0434',
  caseSensitive: false,
);

/// ... alone = not part of a word, a decimal, a time, a date, a source
/// position ("x.dart:1080:33", "line 5108 pos 12") or a measure
/// ("3000 ms").
final RegExp _bareCode = RegExp(
  '(?<![A-Za-z0-9_#])(?<!$_d)'
  r'(?<!\d[.:,])(?<!\.dart:)(?<!line )(?<!pos )'
  '$_d{4,8}(?!$_d'
  r'|[A-Za-z0-9_]|[.:,]\d|-\d\d-\d\d| ?(?:ms|px|dp|s|m|km|kB|KB|MB|bytes)\b)',
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

String _maskJoined(Match m) =>
    _digit.allMatches(m[0]!).length >= 8 ? masked : m[0]!;

String _maskSpacedCode(Match m) {
  final value = m[0]!;
  final digits = _digit.allMatches(value).length;
  if (digits < 4 ||
      digits > 8 ||
      _date.hasMatch(value) ||
      (value.contains('.') && _fourDigits.hasMatch(value))) {
    return value;
  }
  return masked;
}

/// The end of the bracket that opens at [pos]: its matching close, or the
/// end of the line.
int _close(String text, int pos) {
  var depth = 0;
  for (var i = pos; i < text.length; i++) {
    final c = text[i];
    if (c == '\n') return i;
    if (c == '{' || c == '[' || c == '(') {
      depth++;
    } else if (c == '}' || c == ']' || c == ')') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return text.length;
}

/// "OtpSession(id: ...)": the text of a secret type masked.
String _maskCalls(String text) {
  final out = StringBuffer();
  var pos = 0;
  while (true) {
    final m = _next(_call, text, pos);
    if (m == null) break;
    final words = _camel.allMatches(m[1]!).map((w) => w[0]!).toList();
    final end = _close(text, m.end - 1);
    final inner = end > m.end && text[end - 1] == ')'
        ? text.substring(m.end, end - 1)
        : text.substring(m.end, end < m.end ? m.end : end);
    if (words.isEmpty ||
        !_callWords.contains(words.last.toLowerCase()) ||
        inner.isEmpty ||
        _readable(inner)) {
      out.write(text.substring(pos, m.end));
      pos = m.end;
      continue;
    }
    out
      ..write(text.substring(pos, m.end))
      ..write(masked);
    pos = m.end + inner.length;
  }
  out.write(text.substring(pos));
  return out.toString();
}

String _maskPhrase(Match m) {
  if (_notAValue.matchAsPrefix(m[3]!) != null || m[3]!.startsWith('[')) {
    return m[0]!;
  }
  return '${m[1]}${m[2]}$masked';
}

/// French / Arabic / Russian secret words and their value.
String _maskPhrases(String text) => text
    .replaceAllMapped(_phraseLine, _maskPhrase)
    .replaceAllMapped(_phraseCode, _maskPhrase);

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
    if (kind != 'plain' &&
        pos < text.length &&
        (text[pos] == '{' || text[pos] == '[')) {
      // MF-1 round 2: an object or a list goes whole.
      out.write(masked);
      pos = _close(text, pos);
      continue;
    }
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
  out = out.replaceAllMapped(_phoneJoined, _maskJoined);
  out = out
      .split('\n')
      .map(
        (line) => isAuthText(line)
            ? line.replaceAllMapped(_spacedCode, _maskSpacedCode)
            : line,
      )
      .join('\n');
  out = out.replaceAllMapped(_gluedCode, (g) => '${g[1]}$masked');
  out = _maskCalls(out);
  out = _maskPhrases(out);
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
