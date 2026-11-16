/// FTL-H4 (Rules audits/impact/firebase-trip-run-2026-11-16.md, row 5):
/// the device run records an app error's TEXT, not only its type, so the
/// next diagnosis does not need the logcat artifact. The text goes to
/// logcat and summary.json, so every secret is masked first: the run's own
/// phone numbers and code ([known]), any phone-shaped number, session
/// tokens and `code=` / `token:`-style values. Plain Dart (unit tested in
/// test/device_suite/ftl_harness_test.dart).
library;

const String masked = '[REDACTED]';

/// A phone number in any spelling: "+46 70 123 45 67", "0046701234567",
/// "070-123 45 67", "(070) 123-45-67". Starts with +, 00 or 0 and has 7-15
/// more digits; a time ("07:58:01") or a source position (":123:45") does
/// not match (no colon between the digits).
final RegExp _phone = RegExp(
  r'(?<![\w+])(?:\+|\(?0)\d(?:[ \-().]{0,2}\d){6,14}(?![\w])',
);

/// Any plain run of 9-15 digits (a number without its lead).
final RegExp _longDigits = RegExp(r'(?<!\w)\d{9,15}(?!\w)');

/// Bearer tokens and JWTs.
final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/=]+');
final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)?',
);

/// `code=1234`, `"token": "abc"`, `password: x`, `otp 123456` ...
final RegExp _named = RegExp(
  r'''(\b(?:code|otp|pin|token|accessToken|refreshToken|password|secret|apiKey|api_key|authorization)\b["']?\s*[:=]?\s*["']?)([^\s"',;}&)]+)''',
  caseSensitive: false,
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
    if (digits.length >= 8) {
      // The national part (last 9 digits) with any separators between.
      final tail = digits.substring(digits.length - 9);
      final spaced = tail.split('').map(RegExp.escape).join(r'[ \-().]{0,2}');
      out = out.replaceAll(RegExp(spaced), masked);
    }
  }
  out = out.replaceAll(_bearer, 'Bearer $masked');
  out = out.replaceAll(_jwt, masked);
  out = out.replaceAllMapped(_named, (m) => '${m[1]}$masked');
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
