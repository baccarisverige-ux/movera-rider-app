import 'dart:convert';

/// Turns the lines of a Server-Sent Events body into the JSON objects of
/// its `data:` lines (contract §4: one JSON event per `data:`, `id:` is the
/// sequence, comments are heartbeats). One parser per connection.
class SseEventParser {
  final StringBuffer _data = StringBuffer();
  String? _id;

  /// The last `id:` the stream sent (the `Last-Event-ID` of a reconnect).
  String? get lastId => _id;

  /// The event that [line] completes, or null.
  Map<String, Object?>? add(String line) {
    if (line.isEmpty) {
      final text = _data.toString();
      _data.clear();
      if (text.isEmpty) return null;
      try {
        final decoded = jsonDecode(text);
        return decoded is Map ? Map<String, Object?>.from(decoded) : null;
      } on FormatException {
        return null;
      }
    }
    if (line.startsWith(':')) return null;
    if (line.startsWith('id:')) {
      final id = line.substring(3).trim();
      if (id.isNotEmpty) _id = id;
      return null;
    }
    if (line.startsWith('data:')) {
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(line.substring(5).trimLeft());
    }
    return null;
  }
}
