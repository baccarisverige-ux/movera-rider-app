/// Finds the English words a Dart source file could put on screen without
/// going through the translations (owner 2026-10-28: no English-only text).
///
/// A small lexer: comments are skipped, string literals are read with their
/// interpolations (`$name`, `${...}`, nested strings) replaced by a blank,
/// and adjacent literals ('a ' 'b') are joined. Each literal is then judged
/// by its words and by the code just before and after it: log lines,
/// exceptions, map keys, `switch` patterns, comparisons and the like are
/// code, not text a person reads.
library;

class SourceLiteral {
  SourceLiteral(this.line, this.text, this.before, this.after);

  /// 1-based line of the literal's opening quote.
  final int line;

  /// The literal's characters, interpolations blanked.
  final String text;

  /// Up to 160 characters of code before the literal and 40 after it
  /// (strings and comments blanked).
  final String before;
  final String after;
}

/// Every string literal of [source].
List<SourceLiteral> literalsOf(String source) {
  final lexer = _Lexer(source)..run();
  final code = String.fromCharCodes(lexer.code);
  final out = <SourceLiteral>[];
  _Raw? pending;
  void flush() {
    final raw = pending;
    if (raw == null) return;
    pending = null;
    final start = raw.start;
    final end = raw.end;
    out.add(
      SourceLiteral(
        _lineOf(source, start),
        raw.text.toString(),
        code.substring(start - 160 < 0 ? 0 : start - 160, start),
        code.substring(end, end + 40 > code.length ? code.length : end + 40),
      ),
    );
  }

  for (final raw in lexer.literals) {
    final previous = pending;
    if (previous != null &&
        raw.start >= previous.end &&
        code.substring(previous.end, raw.start).trim().isEmpty &&
        raw.depth == previous.depth) {
      previous.text.write(raw.text);
      previous.end = raw.end;
      continue;
    }
    flush();
    pending = raw;
  }
  flush();
  return out;
}

int _lineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

class _Raw {
  _Raw(this.start, this.depth);
  final int start;
  final int depth;
  int end = 0;
  final StringBuffer text = StringBuffer();
}

class _Lexer {
  _Lexer(this.src);
  final String src;
  int i = 0;
  int depth = 0;
  final List<int> code = [];
  final List<_Raw> literals = [];

  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      code.add(src.codeUnitAt(k) == 0x0A ? 0x0A : 0x20);
    }
  }

  void run({bool untilBrace = false}) {
    var braces = 0;
    while (i < src.length) {
      final c = src[i];
      if (src.startsWith('//', i)) {
        final end = src.indexOf('\n', i);
        final stop = end < 0 ? src.length : end;
        blank(i, stop);
        i = stop;
      } else if (src.startsWith('/*', i)) {
        final from = i;
        var nest = 0;
        while (i < src.length) {
          if (src.startsWith('/*', i)) {
            nest++;
            i += 2;
          } else if (src.startsWith('*/', i)) {
            nest--;
            i += 2;
            if (nest == 0) break;
          } else {
            i++;
          }
        }
        blank(from, i);
      } else if (c == "'" ||
          c == '"' ||
          (c == 'r' &&
              i + 1 < src.length &&
              (src[i + 1] == "'" || src[i + 1] == '"') &&
              (i == 0 || !_isIdent(src.codeUnitAt(i - 1))))) {
        string();
      } else if (untilBrace && c == '{') {
        braces++;
        code.add(src.codeUnitAt(i));
        i++;
      } else if (untilBrace && c == '}') {
        if (braces == 0) return;
        braces--;
        code.add(src.codeUnitAt(i));
        i++;
      } else {
        code.add(src.codeUnitAt(i));
        i++;
      }
    }
  }

  void string() {
    final start = i;
    final raw = src[i] == 'r';
    if (raw) i++;
    final q = src[i];
    final triple = src.startsWith(q * 3, i);
    final quote = triple ? q * 3 : q;
    i += quote.length;
    final literal = _Raw(start, depth);
    literals.add(literal);
    while (i < src.length && !src.startsWith(quote, i)) {
      final c = src[i];
      if (!raw && c == r'\') {
        literal.text.write(i + 1 < src.length ? src[i + 1] : '');
        i += 2;
      } else if (!raw && src.startsWith(r'${', i)) {
        literal.text.write(' ');
        i += 2;
        depth++;
        final outer = code.length;
        run(untilBrace: true);
        depth--;
        i++; // the closing brace
        // Interpolated code is part of the literal, not code around it.
        code.length = outer;
      } else if (!raw && c == r'$') {
        literal.text.write(' ');
        i++;
        while (i < src.length && _isIdent(src.codeUnitAt(i))) {
          i++;
        }
      } else {
        literal.text.write(c);
        i++;
      }
    }
    i += quote.length;
    if (i > src.length) i = src.length;
    blank(start, i);
    literal.end = i;
  }
}

bool _isIdent(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F ||
    unit == 0x24;

final _word = RegExp(r"[A-Za-zÀ-ÿ]{2,}");
final _twoWords = RegExp(r"[A-Za-zÀ-ÿ]{2,}[\s,.!?:;·–—-]+[A-Za-zÀ-ÿ]{2,}");
final _capitalWord = RegExp(r"^\s*[A-Z][a-zà-ÿ]+");
final _token = RegExp(r"^[\w.\-/:@#%+?=&*<>|\[\](){}~^]+$");

/// Whether [text] reads as words: two words, or one capitalised word.
bool isProse(String text) {
  final t = text.trim();
  if (!_word.hasMatch(t)) return false;
  // A route, a JSON or JavaScript blob, a media query.
  if (RegExp(r'^[/({\[]').hasMatch(t)) return false;
  // A lowercase key with blanks where its interpolations were
  // (`ride-check-option-$id-$n`).
  if (RegExp(r'^[a-z0-9][a-z0-9_.\-]*[_.\-][a-z0-9_.\-\s]*$').hasMatch(t)) {
    return false;
  }
  final spaced = _twoWords.hasMatch(t) && t.contains(RegExp(r'\s'));
  if (spaced) return true;
  if (!_capitalWord.hasMatch(t)) return false;
  // One token: a name like `Cash`, not a path, file, key or wire value.
  if (_token.hasMatch(t) &&
      (t.contains('.') ||
          t.contains('/') ||
          t.contains('_') ||
          t.contains(':') ||
          RegExp(r'[a-z][A-Z]').hasMatch(t))) {
    return false;
  }
  return true;
}

final _codeBefore = <RegExp>[
  // Imports, parts, annotations, keys, patterns and formats.
  RegExp(r'\b(import|export|part|library)\s*$'),
  RegExp(r'@\w+\(\s*$'),
  RegExp(r'\b(Key|ValueKey|ObjectKey|PageStorageKey|GlobalObjectKey)\(\s*$'),
  RegExp(r'\b(RegExp|DateFormat|Uri\.\w+|Uri)\(\s*$'),
  RegExp(r'\bfontFamily:\s*$'),
  // Logs and diagnostics.
  RegExp(r'\b(\w*Log|log|logger|_log|developer)\.\w+\(\s*$'),
  RegExp(r'\b(debugPrint|print|log|_log|assert)\([^;]*$'),
  RegExp(r'\b(extra|tags|data|fields):\s*[{\[][^;]*$'),
  RegExp(r'\breason:\s*$'),
  // Errors and exceptions (what the UI shows is checked separately).
  RegExp(
    r'\b\w*(Error|Exception|Failure|Exceeded|Unavailable|Timeout)\w*(\.\w+)?\((\s*\w+:)?\s*$',
  ),
  RegExp(r'\b\w*(Error|Exception)\w*(\.\w+)?\([^;]*,\s*(\w+:)?\s*$'),
  RegExp(r'\bthrow\s+\w*\(?\s*$'),
  RegExp(r'\b(fail|FlutterError\.\w+|TimeoutException)\(\s*$'),
  RegExp(r'String toString\(\)\s*(=>|\{[^}]*return)\s*$'),
  // Comparisons and string checks: the literal is a value, not text.
  RegExp(r'(==|!=)\s*$'),
  RegExp(
    r'\.(startsWith|endsWith|contains|indexOf|split|replaceAll|replaceFirst|remove|containsKey|join|padLeft|padRight)\(\s*$',
  ),
  RegExp(r'\bcase\s*$'),
  RegExp(r'\[\s*$'),
  RegExp(r'\b(headers|header|h)\s*\[\s*$'),
  // Platform channels, storage and environment names.
  RegExp(
    r'\b(MethodChannel|EventChannel|BasicMessageChannel|fromEnvironment|getString|setString|getBool|setBool|getInt|setInt|remove)\(\s*$',
  ),
  RegExp(r'\b(js|globalContext)\.\w+\(\s*$'),
];

final _codeAfter = <RegExp>[
  // A map key or a named-argument-like key (`'Accept': ...`).
  RegExp(r'^\s*:(?!:)'),
  // A switch pattern (`'Cash' =>`, `'Cash' ||`).
  RegExp(r'^\s*(=>|\|\|)'),
  RegExp(r'^\s*(==|!=)'),
  RegExp(r'^\s*\]'),
];

bool _ternaryValue(String before) => RegExp(r'\?\s*$').hasMatch(before);

/// Whether the code around a literal makes it code rather than text.
bool isCodeContext(SourceLiteral literal) {
  final before = literal.before;
  for (final pattern in _codeBefore) {
    if (pattern.hasMatch(before)) return true;
  }
  if (_ternaryValue(before)) return false;
  for (final pattern in _codeAfter) {
    if (pattern.hasMatch(literal.after)) return true;
  }
  return false;
}

/// The literals of [source] that read as words outside a code context.
List<SourceLiteral> englishCandidates(String source) => [
  for (final literal in literalsOf(source))
    if (isProse(literal.text) && !isCodeContext(literal)) literal,
];
