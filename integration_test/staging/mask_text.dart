/// FTL-H4 (Rules audits/impact/firebase-trip-run-2026-11-16.md, row 5):
/// the device run records an app error's TEXT, not only its type, so the
/// next diagnosis does not need the logcat artifact. The text goes to
/// logcat and summary.json, so every secret is masked first: the run's own
/// phone numbers and code ([known]), any phone-shaped number (with or
/// without its lead), session tokens, e-mail addresses and `code=` /
/// `token:` / `password`-style values under any name. Plain Dart (unit
/// tested in test/device_suite/ftl_harness_test.dart). The same rules as
/// tool/testlab_summary.py `mask_generic`.
library;

const String masked = '[REDACTED]';

/// One space (also no-break and thin spaces), dot or dash.
const String _s = r'[    .\-]';

/// Between a number's digits: one separator, with a bracket before or
/// after it: "70 123", "(0)70", "(070) 123", "70-123".
const String _sep = '(?:$_s?\\(|\\)$_s?|$_s)?';

/// A phone number in any spelling, with or without its lead:
/// "+46 70 123 45 67", "0046701234567", "070-123 45 67", "(070) 123-45-67",
/// "+33 (0)6 12 34 56 78", "06.12.34.56.78", "20 123 456" (Tunisian: 8
/// digits, no trunk 0). 8-15 digits with single separators; a time
/// ("07:58:01"), a source position (":123:45") or a size ("1080.0, 2400.0")
/// does not match (no colon or comma between the digits).
final RegExp _phone = RegExp(
  '(?<![\\d.:])\\+?\\(?\\d(?:$_sep\\d){7,14}(?!\\d)',
);

/// Any plain run of 8 or more digits.
final RegExp _longDigits = RegExp(r'\d{8,}');

/// Bearer / Basic credentials and JWTs.
final RegExp _bearer = RegExp(
  r'\b(Bearer|Basic)\s+[A-Za-z0-9\-._~+/=]+',
  caseSensitive: false,
);
final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)?',
);

/// `code=1234`, `"token": "abc"`, `password: x`, `otp 123456`, and the
/// same under a longer name: `access_token=`, `idToken`, `client_secret`,
/// `newPassword`, `x-api-key:` ...
final RegExp _named = RegExp(
  r'''((?:[A-Za-z0-9_\-]*(?:token|password|passwd|pwd|secret|api[_\-]?key|authorization|otp)|\b(?:code|pin))\b["']?\s*[:=]?\s*["']?)([^\s"',;}&)]+)''',
  caseSensitive: false,
);

/// A 4-8 digit number shortly after "code" / "otp" / "pin" ("the code
/// was 482913").
final RegExp _codeNear = RegExp(
  r'(\b(?:code|otp|pin|kod)\b[^\d\n]{0,24})\d{4,8}(?!\d)',
  caseSensitive: false,
);

/// A long opaque value (32+ letters and digits, at least one digit): a
/// session token or key nobody named.
final RegExp _opaque = RegExp(r'(?=[A-Za-z_\-]*\d)[A-Za-z0-9_\-]{32,}');

/// An e-mail address.
final RegExp _email = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
);

/// [text] with every secret replaced by [masked]. [known] are the run's
/// own values (phone numbers in E.164, the sign-in code); each is masked
/// as written and, for a number, in any spelling with separators.
String maskText(String text, {Iterable<String> known = const <String>[]}) {
  var out = text;
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
          .join(r'[    \-().]{0,2}');
      out = out.replaceAll(RegExp(spaced), masked);
    }
  }
  out = out.replaceAllMapped(_bearer, (m) => '${m[1]} $masked');
  out = out.replaceAll(_jwt, masked);
  out = out.replaceAll(_email, masked);
  out = out.replaceAllMapped(_named, (m) => '${m[1]}$masked');
  out = out.replaceAllMapped(_codeNear, (m) => '${m[1]}$masked');
  out = out.replaceAll(_opaque, masked);
  out = out.replaceAll(_phone, masked);
  out = out.replaceAll(_longDigits, masked);
  return out;
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
